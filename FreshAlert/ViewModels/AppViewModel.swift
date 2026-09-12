import Foundation
import SwiftData
import SwiftUI
import UIKit
import Network
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    private let modelContext: ModelContext
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.freshalert.network")

    @Published var isOnline: Bool = true
    @Published var pendingSyncCount: Int = 0
    @Published var isLoadingProduct: Bool = false
    @Published var toastMessage: String?
    @Published var toastAction: ToastAction?
    /// Zweiter Knopf im Toast, heute nur "Weggeworfen" nach dem Löschen.
    @Published var toastSecondaryAction: ToastAction?
    @Published var scanRequested: Bool = false
    @Published var selectedTab: Int = 0
    /// Von einer angetippten Mitteilung gesetzt, die Übersicht wertet es aus.
    @Published var pendingDashboardFilter: DashboardFilter?

    /// Schnappschuss des zuletzt entfernten Produkts, für "Rückgängig".
    /// Verfällt nach `undoWindow` Sekunden oder beim nächsten Entfernen.
    private var lastRemovedSnapshot: RemovedItemSnapshot?
    /// Der beim Entfernen geschriebene Statistiksatz, damit "Rückgängig" ihn mitnimmt.
    private var lastRemovedRecord: ConsumptionRecord?
    private var undoExpiryTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private let undoWindow: TimeInterval = 6

    @AppStorage("globalReminderDays") var globalReminderDays: Int = 7
    @AppStorage("reminderHour") var reminderHour: Int = 9
    @AppStorage("reminderMinute") var reminderMinute: Int = 0

    private var replanTask: Task<Void, Never>?
    private let replanDebounce: Duration = .milliseconds(500)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupNetwork()
        setupQuickActionObserver()
    }

    private func setupQuickActionObserver() {
        let center = NotificationCenter.default
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            if AppDelegate.pendingShortcutType == "com.freshalert.app.scan" {
                AppDelegate.pendingShortcutType = nil
                Task { @MainActor in self.scanRequested = true }
            }
        }
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main, using: handler
        )
        center.addObserver(
            forName: .openScannerTab,
            object: nil, queue: .main, using: handler
        )
    }

    // MARK: - Network
    private func setupNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if wasOffline && self.isOnline {
                    await self.syncOfflineEntries()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Food Items CRUD
    /// Legt das Produkt sofort an. Erinnerungen, Sync und Bilddownload folgen
    /// im Hintergrund, damit der aufrufende Sheet nicht darauf warten muss.
    func addFoodItem(_ item: FoodItem) {
        modelContext.insert(item)
        try? modelContext.save()
        updatePendingCount()
        updateWidgetSnapshot()

        scheduleReminderReplan()

        Task { @MainActor in
            if item.isOfflineEntry && isOnline {
                await syncItem(item)
            } else if !item.imageURL.isEmpty && item.imageData == nil {
                await downloadAndCacheImage(for: item)
            }
        }
    }

    /// Löscht das Produkt und bietet 6 Sekunden lang "Rückgängig" an.
    /// Im selben Toast fragt "Weggeworfen" nach, ob es in den Müll ging.
    /// Kein Antippen heißt: nur gelöscht, kein Satz für die Statistik.
    func deleteFoodItem(_ item: FoodItem) {
        remove(item, toast: "\(item.name) gelöscht", offerDiscarded: true)
    }

    func updateFoodItem(_ item: FoodItem) async {
        try? modelContext.save()
        updateWidgetSnapshot()
        scheduleReminderReplan()
    }

    /// Verbraucht ein Exemplar. Bei Menge 1 wird das Produkt entfernt,
    /// mit "Rückgängig" statt Nachfrage.
    /// Ein abgelaufenes Produkt zählt trotzdem als verbraucht: gegessen ist gegessen.
    func decrementQuantity(_ item: FoodItem) {
        if item.quantity > 1 {
            item.quantity -= 1
            modelContext.insert(makeRecord(for: item, outcome: .consumed))
        } else {
            // Der Satz muss stehen, solange das Produkt noch da ist.
            remove(
                item,
                toast: "\(item.name) verbraucht",
                record: makeRecord(for: item, outcome: .consumed)
            )
            return
        }
        try? modelContext.save()
        updateWidgetSnapshot()
    }

    // MARK: - Statistik

    /// Ein Satz für die Statistik, aus dem Produkt heraus gebaut. Der Lagerort
    /// wandert als Name hinein, damit ein späteres Löschen nichts kaputt macht.
    private func makeRecord(
        for item: FoodItem, outcome: ConsumptionOutcome, quantity: Int = 1
    ) -> ConsumptionRecord {
        ConsumptionRecord(
            productName: item.name,
            brand: item.brand,
            barcode: item.barcode,
            storageLocationName: item.storageLocation?.name ?? "",
            quantity: quantity,
            outcome: outcome,
            expiryDate: item.expiryDate
        )
    }

    /// "Weggeworfen" im Toast nach dem Löschen: trägt den Verlust nach.
    /// "Rückgängig" bleibt danach erreichbar und nimmt den Satz wieder mit.
    func markLastRemovalDiscarded() {
        guard let snapshot = lastRemovedSnapshot, lastRemovedRecord == nil else { return }
        let record = ConsumptionRecord(
            productName: snapshot.name,
            brand: snapshot.brand,
            barcode: snapshot.barcode,
            storageLocationName: snapshot.storageLocation?.name ?? "",
            quantity: snapshot.quantity,
            outcome: .discarded,
            expiryDate: snapshot.expiryDate
        )
        modelContext.insert(record)
        try? modelContext.save()
        lastRemovedRecord = record
        startUndoWindow()
        showToast(
            "\(snapshot.name) weggeworfen",
            actionTitle: "Rückgängig",
            handler: { [weak self] in self?.undoLastRemoval() }
        )
    }

    // MARK: - Entfernen mit Undo

    private func remove(
        _ item: FoodItem,
        toast message: String,
        record: ConsumptionRecord? = nil,
        offerDiscarded: Bool = false
    ) {
        lastRemovedSnapshot = RemovedItemSnapshot(item)
        lastRemovedRecord = record
        if let record { modelContext.insert(record) }
        // Explicitly nil out external storage before deletion so SwiftData
        // releases the image file on disk immediately during the same save.
        item.imageData = nil
        modelContext.delete(item)
        try? modelContext.save()
        updatePendingCount()
        updateWidgetSnapshot()
        scheduleReminderReplan()

        startUndoWindow()
        showToast(
            message,
            actionTitle: "Rückgängig",
            secondaryTitle: offerDiscarded ? "Weggeworfen" : nil,
            secondaryHandler: offerDiscarded ? { [weak self] in self?.markLastRemovalDiscarded() } : nil,
            handler: { [weak self] in self?.undoLastRemoval() }
        )
    }

    /// Startet das Zeitfenster neu, in dem "Rückgängig" noch etwas findet.
    private func startUndoWindow() {
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.undoWindow ?? 6))
            guard !Task.isCancelled else { return }
            self?.lastRemovedSnapshot = nil
            self?.lastRemovedRecord = nil
        }
    }

    /// Stellt das zuletzt entfernte Produkt aus dem Schnappschuss wieder her.
    func undoLastRemoval() {
        guard let snapshot = lastRemovedSnapshot else { return }
        lastRemovedSnapshot = nil
        // Der Vorgang hat nie stattgefunden, also auch kein Satz darüber.
        if let record = lastRemovedRecord {
            modelContext.delete(record)
            lastRemovedRecord = nil
        }
        undoExpiryTask?.cancel()
        dismissToast()

        let item = snapshot.makeItem()
        modelContext.insert(item)
        try? modelContext.save()
        updatePendingCount()
        updateWidgetSnapshot()
        scheduleReminderReplan()
    }

    // MARK: - Toast

    func showToast(
        _ message: String,
        actionTitle: String? = nil,
        secondaryTitle: String? = nil,
        secondaryHandler: (() -> Void)? = nil,
        handler: (() -> Void)? = nil
    ) {
        toastDismissTask?.cancel()
        toastMessage = message
        if let actionTitle, let handler {
            toastAction = ToastAction(title: actionTitle, handler: handler)
        } else {
            toastAction = nil
        }
        if let secondaryTitle, let secondaryHandler {
            toastSecondaryAction = ToastAction(title: secondaryTitle, handler: secondaryHandler)
        } else {
            toastSecondaryAction = nil
        }
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismissToast()
        }
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toastMessage = nil
        toastAction = nil
        toastSecondaryAction = nil
    }

    /// Für Dubletten beim Scannen: statt eines zweiten Eintrags nur die Menge erhöhen.
    func incrementQuantity(_ item: FoodItem) {
        item.quantity += 1
        try? modelContext.save()
        updateWidgetSnapshot()
        showToast("\(item.name): jetzt \(item.quantity)×")
    }

    // MARK: - Widget Data
    func updateWidgetSnapshot() {
        let descriptor = FetchDescriptor<FoodItem>(
            sortBy: [SortDescriptor(\.expiryDate, order: .forward)]
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        let widgetItems = items.prefix(20).map { item in
            WidgetFoodItem(
                id: item.id,
                name: item.name,
                brand: item.brand,
                expiryDate: item.expiryDate,
                quantity: item.quantity,
                locationName: item.storageLocation?.name,
                locationIconName: item.storageLocation?.iconName
            )
        }
        WidgetDataStore.saveItems(Array(widgetItems))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func processPendingWidgetDecrements() {
        let pending = WidgetDataStore.loadPendingDecrements()
        guard !pending.isEmpty else { return }
        WidgetDataStore.clearPendingDecrements()
        for id in pending {
            let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })
            if let item = try? modelContext.fetch(descriptor).first {
                decrementQuantity(item)
            }
        }
    }

    // MARK: - Product Fetch
    /// Offline und Netzfehler landen in `.unavailable` (Offline-Pfad), ein Barcode,
    /// den keine der drei Datenbanken kennt, in `.notFound` (Nachtragen anbieten).
    func lookupProduct(barcode: String) async -> ProductLookup {
        guard isOnline else { return .unavailable }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            return .found(try await OpenFoodFactsService.shared.fetchProduct(barcode: barcode))
        } catch let error as OFFError where error.isProductNotFound {
            return .notFound
        } catch {
            return .unavailable
        }
    }

    // MARK: - Offline Sync
    private func syncOfflineEntries() async {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.isOfflineEntry }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        for item in items {
            await syncItem(item)
        }
        updatePendingCount()
        if !items.isEmpty {
            showToast("\(items.count) Produkte synchronisiert")
        }
    }

    private func syncItem(_ item: FoodItem) async {
        guard !item.barcode.isEmpty else {
            item.isOfflineEntry = false
            try? modelContext.save()
            return
        }
        if case .found(let info) = await lookupProduct(barcode: item.barcode) {
            if item.name.isEmpty { item.name = info.name }
            if item.brand.isEmpty { item.brand = info.brand }
            if item.imageURL.isEmpty, let url = info.imageURL { item.imageURL = url }
        }
        item.isOfflineEntry = false
        try? modelContext.save()
        if !item.imageURL.isEmpty && item.imageData == nil {
            await downloadAndCacheImage(for: item)
        }
    }

    // Downloads the product image once and stores it in SwiftData (@externalStorage).
    // After this, the image is shown from local storage and never fetched again.
    // Intern statt privat: TestDataSeeder nutzt denselben Weg.
    func downloadAndCacheImage(for item: FoodItem) async {
        guard let url = URL(string: item.imageURL) else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty else { return }
        item.imageData = data
        try? modelContext.save()
    }

    // Back-fills imageData for existing items that only have a URL stored.
    func cacheImagesForExistingItems() async {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { !$0.imageURL.isEmpty && $0.imageData == nil }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        for item in items {
            await downloadAndCacheImage(for: item)
        }
    }

    private func updatePendingCount() {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.isOfflineEntry }
        )
        pendingSyncCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Erinnerungen

    /// Plant alle Tagesmitteilungen sofort neu (alle `freshalert.*`-Requests
    /// weg, dann der frische Plan aus dem aktuellen Bestand).
    func rescheduleAllNotifications() async {
        replanTask?.cancel()
        replanTask = nil
        let items = (try? modelContext.fetch(FetchDescriptor<FoodItem>())) ?? []
        await NotificationService.shared.rescheduleAll(items: items)
    }

    /// Neuplanen mit 0,5 s Verzögerung: mehrere Änderungen kurz nacheinander
    /// (Scannen, Undo, Regler) lösen nur einen Lauf aus.
    func scheduleReminderReplan() {
        replanTask?.cancel()
        replanTask = Task { [weak self] in
            try? await Task.sleep(for: self?.replanDebounce ?? .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            await self.rescheduleAllNotifications()
        }
    }

    /// Der aktuelle Plan, ohne iOS anzufassen (Übersichtsseite, Entwicklermenü).
    func plannedReminders(now: Date = Date()) -> [PlannedReminder] {
        let items = (try? modelContext.fetch(FetchDescriptor<FoodItem>())) ?? []
        return NotificationService.plan(for: items, now: now)
    }
}

/// Filter, den die Übersicht nach dem Tipp auf eine Mitteilung anwendet.
enum DashboardFilter: Equatable {
    case expiringSoon
}

/// Ergebnis einer Barcode-Suche in den Produktdatenbanken.
enum ProductLookup {
    case found(ProductInfo)
    case notFound
    case unavailable
}

// MARK: - Hilfstypen

struct ToastAction {
    let title: String
    let handler: () -> Void
}

/// Alle Felder eines FoodItem, damit es nach dem Löschen wiederhergestellt
/// werden kann. Der Lagerort bleibt als Referenz erhalten, er wird nicht gelöscht.
struct RemovedItemSnapshot {
    let id: UUID
    let barcode: String
    let name: String
    let brand: String
    let imageURL: String
    let imageData: Data?
    let expiryDate: Date
    let quantity: Int
    let storageLocation: StorageLocation?
    let customReminderDays: Int?
    let isOfflineEntry: Bool
    let addedAt: Date

    init(_ item: FoodItem) {
        id = item.id
        barcode = item.barcode
        name = item.name
        brand = item.brand
        imageURL = item.imageURL
        imageData = item.imageData
        expiryDate = item.expiryDate
        quantity = item.quantity
        storageLocation = item.storageLocation
        customReminderDays = item.customReminderDays
        isOfflineEntry = item.isOfflineEntry
        addedAt = item.addedAt
    }

    func makeItem() -> FoodItem {
        FoodItem(
            id: id,
            barcode: barcode,
            name: name,
            brand: brand,
            imageURL: imageURL,
            imageData: imageData,
            expiryDate: expiryDate,
            quantity: quantity,
            storageLocation: storageLocation,
            customReminderDays: customReminderDays,
            isOfflineEntry: isOfflineEntry,
            addedAt: addedAt
        )
    }
}
