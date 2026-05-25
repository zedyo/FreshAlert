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
    @Published var scanRequested: Bool = false
    @Published private(set) var orphanedNotifications: [OrphanedNotification] = []

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
    func addFoodItem(_ item: FoodItem) async {
        modelContext.insert(item)
        let days = item.customReminderDays ?? globalReminderDays
        item.notificationIdentifiers = await NotificationService.shared
            .scheduleNotifications(for: item, reminderDays: days)
        saveContext()
        updatePendingCount()
        updateWidgetSnapshot()

        if item.isOfflineEntry && isOnline {
            await syncItem(item)
        } else if !item.imageURL.isEmpty && item.imageData == nil {
            await downloadAndCacheImage(for: item)
        }
    }

    func deleteFoodItem(_ item: FoodItem) {
        NotificationService.shared.cancelNotifications(for: item)
        // Explicitly nil out external storage before deletion so SwiftData
        // releases the image file on disk immediately during the same save.
        item.imageData = nil
        modelContext.delete(item)
        saveContext()
        updatePendingCount()
        updateWidgetSnapshot()
    }

    func updateFoodItem(_ item: FoodItem) async {
        let days = item.customReminderDays ?? globalReminderDays
        item.notificationIdentifiers = await NotificationService.shared
            .scheduleNotifications(for: item, reminderDays: days)
        saveContext()
        updateWidgetSnapshot()
    }

    func decrementQuantity(_ item: FoodItem) {
        if item.quantity > 1 {
            item.quantity -= 1
        } else {
            deleteFoodItem(item)
            return
        }
        saveContext()
        updateWidgetSnapshot()
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
            toastMessage = "\(items.count) Einträge synchronisiert"
        }
    }

    private func syncItem(_ item: FoodItem) async {
        guard !item.barcode.isEmpty else {
            item.isOfflineEntry = false
            saveContext()
            return
        }
        if let info = await fetchProductInfo(barcode: item.barcode) {
            if item.name.isEmpty { item.name = info.name }
            if item.brand.isEmpty { item.brand = info.brand }
            if item.imageURL.isEmpty, let url = info.imageURL { item.imageURL = url }
        }
        item.isOfflineEntry = false
        saveContext()
        if !item.imageURL.isEmpty && item.imageData == nil {
            await downloadAndCacheImage(for: item)
        }
    }

    // Downloads the product image once and stores it in SwiftData (@externalStorage).
    // After this, the image is shown from local storage and never fetched again.
    private func downloadAndCacheImage(for item: FoodItem) async {
        guard let url = URL(string: item.imageURL) else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty else { return }
        item.imageData = data
        saveContext()
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
        saveContext("rescheduleAllNotifications")
    }

    // MARK: - Persistence
    /// Speichert den ModelContext und meldet Fehler, statt sie zu verschlucken.
    /// Stille Save-Fehler waren mit verlorener Sicht auf Produkte verbunden.
    @discardableResult
    func saveContext(_ context: String = #function) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            print("[FreshAlert] SwiftData-Save fehlgeschlagen in \(context): \(error)")
            toastMessage = "Speichern fehlgeschlagen – bitte erneut versuchen."
            return false
        }
    }

    // MARK: - Orphaned Notifications Recovery
    /// Sucht geplante Notifications, deren Produkt nicht mehr im Datenbestand ist
    /// (z. B. nach stillem SwiftData-Verlust). Werden in den Einstellungen zur
    /// Wiederherstellung angeboten.
    func scanForOrphanedNotifications() async {
        let allItems = (try? modelContext.fetch(FetchDescriptor<FoodItem>())) ?? []
        let existing = Set(allItems.map { $0.id })
        orphanedNotifications = await NotificationService.shared
            .findOrphanedNotifications(existingIDs: existing)
    }

    /// Stellt ein verlorenes Produkt aus den Notification-Daten wieder her
    /// (Name + Ablaufdatum). Andere Felder bleiben leer und können vom Nutzer
    /// nachträglich ergänzt werden. Die alten Notifs werden gecancelt und neu
    /// geplant – mit derselben itemID, damit nichts doppelt auftaucht.
    func recoverOrphanedItem(_ orphan: OrphanedNotification) async {
        NotificationService.shared.cancelNotifications(
            withIdentifiers: orphan.notificationIdentifiers
        )
        let item = FoodItem(
            id: orphan.itemID,
            name: orphan.name,
            expiryDate: orphan.expiryDate
        )
        modelContext.insert(item)
        let days = item.customReminderDays ?? globalReminderDays
        item.notificationIdentifiers = await NotificationService.shared
            .scheduleNotifications(for: item, reminderDays: days)
        saveContext()
        orphanedNotifications.removeAll { $0.itemID == orphan.itemID }
        updateWidgetSnapshot()
    }

    /// Verwirft ein verwaistes Produkt: cancelt die geplanten Notifs ohne es
    /// wiederherzustellen. Wird gebraucht, wenn das Produkt vom Nutzer
    /// tatsächlich aus der Liste entfernt werden sollte.
    func dismissOrphanedItem(_ orphan: OrphanedNotification) {
        NotificationService.shared.cancelNotifications(
            withIdentifiers: orphan.notificationIdentifiers
        )
        orphanedNotifications.removeAll { $0.itemID == orphan.itemID }
    }

    func dismissAllOrphanedNotifications() {
        let ids = orphanedNotifications.flatMap { $0.notificationIdentifiers }
        NotificationService.shared.cancelNotifications(withIdentifiers: ids)
        orphanedNotifications.removeAll()
    }
}
