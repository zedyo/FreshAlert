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
    @Published var scanRequested: Bool = false
    @Published var selectedTab: Int = 0

    /// Schnappschuss des zuletzt entfernten Produkts, für "Rückgängig".
    /// Verfällt nach `undoWindow` Sekunden oder beim nächsten Entfernen.
    private var lastRemovedSnapshot: RemovedItemSnapshot?
    private var undoExpiryTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private let undoWindow: TimeInterval = 6

    @AppStorage("globalReminderDays") var globalReminderDays: Int = 7

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

        Task { @MainActor in
            let days = item.customReminderDays ?? globalReminderDays
            item.notificationIdentifiers = await NotificationService.shared
                .scheduleNotifications(for: item, reminderDays: days)
            try? modelContext.save()

            if item.isOfflineEntry && isOnline {
                await syncItem(item)
            } else if !item.imageURL.isEmpty && item.imageData == nil {
                await downloadAndCacheImage(for: item)
            }
        }
    }

    /// Löscht das Produkt und bietet 6 Sekunden lang "Rückgängig" an.
    func deleteFoodItem(_ item: FoodItem) {
        remove(item, toast: "\(item.name) gelöscht")
    }

    func updateFoodItem(_ item: FoodItem) async {
        let days = item.customReminderDays ?? globalReminderDays
        item.notificationIdentifiers = await NotificationService.shared
            .scheduleNotifications(for: item, reminderDays: days)
        try? modelContext.save()
        updateWidgetSnapshot()
    }

    /// Verbraucht ein Exemplar. Bei Menge 1 wird das Produkt entfernt,
    /// mit "Rückgängig" statt Nachfrage.
    func decrementQuantity(_ item: FoodItem) {
        if item.quantity > 1 {
            item.quantity -= 1
        } else {
            remove(item, toast: "\(item.name) verbraucht")
            return
        }
        try? modelContext.save()
        updateWidgetSnapshot()
    }

    // MARK: - Entfernen mit Undo

    private func remove(_ item: FoodItem, toast message: String) {
        lastRemovedSnapshot = RemovedItemSnapshot(item)
        NotificationService.shared.cancelNotifications(for: item)
        // Explicitly nil out external storage before deletion so SwiftData
        // releases the image file on disk immediately during the same save.
        item.imageData = nil
        modelContext.delete(item)
        try? modelContext.save()
        updatePendingCount()
        updateWidgetSnapshot()

        undoExpiryTask?.cancel()
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.undoWindow ?? 6))
            guard !Task.isCancelled else { return }
            self?.lastRemovedSnapshot = nil
        }
        showToast(message, actionTitle: "Rückgängig") { [weak self] in
            self?.undoLastRemoval()
        }
    }

    /// Stellt das zuletzt entfernte Produkt aus dem Schnappschuss wieder her.
    func undoLastRemoval() {
        guard let snapshot = lastRemovedSnapshot else { return }
        lastRemovedSnapshot = nil
        undoExpiryTask?.cancel()
        dismissToast()

        let item = snapshot.makeItem()
        modelContext.insert(item)
        try? modelContext.save()
        updatePendingCount()
        updateWidgetSnapshot()

        Task { @MainActor in
            let days = item.customReminderDays ?? globalReminderDays
            item.notificationIdentifiers = await NotificationService.shared
                .scheduleNotifications(for: item, reminderDays: days)
            try? modelContext.save()
        }
    }

    // MARK: - Toast

    func showToast(_ message: String, actionTitle: String? = nil, handler: (() -> Void)? = nil) {
        toastDismissTask?.cancel()
        toastMessage = message
        if let actionTitle, let handler {
            toastAction = ToastAction(title: actionTitle, handler: handler)
        } else {
            toastAction = nil
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
    func fetchProductInfo(barcode: String) async -> ProductInfo? {
        guard isOnline else { return nil }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            return try await OpenFoodFactsService.shared.fetchProduct(barcode: barcode)
        } catch {
            return nil
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
        if let info = await fetchProductInfo(barcode: item.barcode) {
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

    // MARK: - Reschedule All
    func rescheduleAllNotifications() async {
        let items = (try? modelContext.fetch(FetchDescriptor<FoodItem>())) ?? []
        for item in items {
            let days = item.customReminderDays ?? globalReminderDays
            item.notificationIdentifiers = await NotificationService.shared
                .scheduleNotifications(for: item, reminderDays: days)
        }
        try? modelContext.save()
    }
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
