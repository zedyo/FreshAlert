import Foundation
import SwiftData
import SwiftUI
import Network

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

        if item.isOfflineEntry && isOnline {
            await syncItem(item)
        }
    }

    func deleteFoodItem(_ item: FoodItem) {
        NotificationService.shared.cancelNotifications(for: item)
        modelContext.delete(item)
        try? modelContext.save()
        updatePendingCount()
    }

    func updateFoodItem(_ item: FoodItem) async {
        let days = item.customReminderDays ?? globalReminderDays
        item.notificationIdentifiers = await NotificationService.shared
            .scheduleNotifications(for: item, reminderDays: days)
        try? modelContext.save()
    }

    func decrementQuantity(_ item: FoodItem) {
        if item.quantity > 1 {
            item.quantity -= 1
        } else {
            deleteFoodItem(item)
        }
        try? modelContext.save()
    }

    // MARK: - Product Fetch
    func fetchProductInfo(barcode: String) async -> ProductInfo? {
        guard isOnline else { return nil }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            return try await OpenFoodFactsService.shared.fetchProduct(barcode: barcode)
        } catch OFFError.productNotFound {
            return nil
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
