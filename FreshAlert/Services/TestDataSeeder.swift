import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Lädt die 50 Testprodukte aus `TestData/testprodukte.json` in die Datenbank
/// und setzt die App auf Wunsch komplett zurück. Nur über das Entwicklermenü
/// und das Launch-Argument `-seedTestData` erreichbar.
@MainActor
enum TestDataSeeder {
    struct TestProduct: Decodable {
        let barcode: String
        let name: String
        let marke: String
        let bildURL: String
        let ort: String
        let menge: Int
        let haltbarInTagen: Int
    }

    private struct TestDataFile: Decodable {
        let stand: String
        let quelle: String
        let produkte: [TestProduct]
    }

    private static let maxParallelDownloads = 4

    static func loadProducts() -> [TestProduct] {
        guard let url = Bundle.main.url(forResource: "testprodukte", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TestDataFile.self, from: data)
        else { return [] }
        return file.produkte
    }

    static var productCount: Int { loadProducts().count }

    static func isDatabaseEmpty(_ context: ModelContext) -> Bool {
        let items = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        let locations = (try? context.fetchCount(FetchDescriptor<StorageLocation>())) ?? 0
        return items == 0 && locations == 0
    }

    // MARK: - Seed

    /// Legt für jeden Eintrag ein FoodItem an, überspringt vorhandene Barcodes,
    /// plant Erinnerungen und lädt die Bilder nach (höchstens 4 parallel).
    /// Gibt die Zahl der neu angelegten Produkte zurück.
    @discardableResult
    static func seed(into context: ModelContext, viewModel: AppViewModel) async -> Int {
        let products = loadProducts()
        guard !products.isEmpty else {
            viewModel.showToast("Testdaten nicht gefunden")
            return 0
        }

        let existingBarcodes = Set(
            ((try? context.fetch(FetchDescriptor<FoodItem>())) ?? []).map(\.barcode)
        )
        var locations = (try? context.fetch(
            FetchDescriptor<StorageLocation>(sortBy: [SortDescriptor(\.sortOrder)])
        )) ?? []

        let today = Calendar.current.startOfDay(for: Date())
        var newItems: [FoodItem] = []

        for product in products where !existingBarcodes.contains(product.barcode) {
            let location = locationNamed(product.ort, in: &locations, context: context)
            let expiry = Calendar.current.date(byAdding: .day, value: product.haltbarInTagen, to: today) ?? today
            let item = FoodItem(
                barcode: product.barcode,
                name: product.name,
                brand: product.marke,
                imageURL: product.bildURL,
                imageData: nil,
                expiryDate: expiry,
                quantity: max(1, product.menge),
                storageLocation: location
            )
            context.insert(item)
            newItems.append(item)
        }
        try? context.save()
        viewModel.updateWidgetSnapshot()

        guard !newItems.isEmpty else {
            viewModel.showToast("Alle Testprodukte sind schon da")
            return 0
        }

        // Erinnerungen wie in AppViewModel.addFoodItem, nur gebündelt.
        for item in newItems {
            let days = item.customReminderDays ?? viewModel.globalReminderDays
            item.notificationIdentifiers = await NotificationService.shared
                .scheduleNotifications(for: item, reminderDays: days)
        }
        try? context.save()
        viewModel.showToast("\(newItems.count) Testprodukte geladen")

        await downloadImages(for: newItems, viewModel: viewModel)
        return newItems.count
    }

    private static func locationNamed(
        _ name: String,
        in locations: inout [StorageLocation],
        context: ModelContext
    ) -> StorageLocation {
        if let existing = locations.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let template = StorageLocation.defaultTemplates.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        let location = StorageLocation(
            name: name,
            iconName: template?.iconName ?? "archivebox",
            colorHex: template?.colorHex ?? "#34C759",
            sortOrder: (locations.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(location)
        locations.append(location)
        return location
    }

    /// Gleitendes Fenster: nie mehr als `maxParallelDownloads` Bilder gleichzeitig.
    private static func downloadImages(for items: [FoodItem], viewModel: AppViewModel) async {
        let pending = items.filter { !$0.imageURL.isEmpty && $0.imageData == nil }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = pending.makeIterator()
            var running = 0
            while running < maxParallelDownloads, let item = iterator.next() {
                group.addTask { @MainActor in await viewModel.downloadAndCacheImage(for: item) }
                running += 1
            }
            while await group.next() != nil {
                if let item = iterator.next() {
                    group.addTask { @MainActor in await viewModel.downloadAndCacheImage(for: item) }
                }
            }
        }
    }

    // MARK: - Löschen

    /// Löscht alle Produkte samt Erinnerungen. Lagerorte bleiben.
    static func deleteAllItems(in context: ModelContext, viewModel: AppViewModel) {
        let items = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        for item in items {
            NotificationService.shared.cancelNotifications(for: item)
            item.imageData = nil
            context.delete(item)
        }
        try? context.save()
        viewModel.pendingSyncCount = 0
        viewModel.updateWidgetSnapshot()
        viewModel.showToast("\(items.count) Produkte gelöscht")
    }

    /// Setzt die App auf den Zustand nach der Erstinstallation zurück:
    /// Produkte, Lagerorte, Mitteilungen, Widget-Daten und Onboarding-Flag.
    static func resetApp(in context: ModelContext, viewModel: AppViewModel) {
        let items = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        for item in items {
            item.imageData = nil
            context.delete(item)
        }
        let locations = (try? context.fetch(FetchDescriptor<StorageLocation>())) ?? []
        for location in locations {
            context.delete(location)
        }
        try? context.save()

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        WidgetDataStore.saveItems([])
        WidgetDataStore.clearPendingDecrements()
        WidgetCenter.shared.reloadAllTimelines()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "lastStorageLocationID")

        viewModel.pendingSyncCount = 0
        viewModel.showToast("App zurückgesetzt. Beim nächsten Start kommt das Onboarding.")
    }
}
