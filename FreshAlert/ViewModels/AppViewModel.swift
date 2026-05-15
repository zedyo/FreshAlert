import Foundation
import SwiftData
import SwiftUI
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

    @AppStorage("globalReminderDays") var globalReminderDays: Int = 7

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupNetwork()
        insertDefaultLocationsIfNeeded()
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

    // MARK: - Default Locations
    private func insertDefaultLocationsIfNeeded() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<StorageLocation>())) ?? 0
        guard count == 0 else { return }
        StorageLocation.defaultLocations.forEach { modelContext.insert($0) }
        try? modelContext.save()
    }

    // MARK: - Food Items CRUD
    func addFoodItem(_ item: FoodItem) async {
        modelContext.insert(item)
        let days = item.customReminderDays ?? globalReminderDays
        item.notificationIdentifiers = await NotificationService.shared
            .scheduleNotifications(for: item, reminderDays: days)
        try? modelContext.save()
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
        modelContext.delete(item)
        try? modelContext.save()
        updatePendingCount()
        updateWidgetSnapshot()
    }

    func updateFoodItem(_ item: FoodItem) async {
        let days = item.customReminderDays ?? globalReminderDays
        item.notificationIdentifiers = await NotificationService.shared
            .scheduleNotifications(for: item, reminderDays: days)
        try? modelContext.save()
        updateWidgetSnapshot()
    }

    func decrementQuantity(_ item: FoodItem) {
        if item.quantity > 1 {
            item.quantity -= 1
        } else {
            deleteFoodItem(item)
            return
        }
        try? modelContext.save()
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
    private func downloadAndCacheImage(for item: FoodItem) async {
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
