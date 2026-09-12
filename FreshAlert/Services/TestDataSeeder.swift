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

        // Vor der Dublettenprüfung: die Statistik soll auch dann etwas zeigen,
        // wenn die Produkte schon in der Datenbank stehen.
        seedConsumptionRecords(into: context, products: products)

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

        // Sofort statt mit Verzögerung, damit das Entwicklermenü den Zähler gleich richtig zeigt.
        await viewModel.rescheduleAllNotifications()
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

    // MARK: - Statistik

    /// Rund 60 Sätze der letzten 90 Tage, ungefähr 80 zu 20 verbraucht gegen
    /// weggeworfen, verteilt über Wochen und Lagerorte. Läuft nur, solange
    /// noch kein Satz in der Datenbank steht.
    @discardableResult
    static func seedConsumptionRecords(
        into context: ModelContext, products: [TestProduct]? = nil
    ) -> Int {
        let existing = (try? context.fetchCount(FetchDescriptor<ConsumptionRecord>())) ?? 0
        guard existing == 0 else { return 0 }
        let pool = products ?? loadProducts()
        guard !pool.isEmpty else { return 0 }

        // Feste Folge, damit zwei Läufe dasselbe Bild ergeben.
        var random = SeededGenerator(seed: 20_260_912)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Ein paar Dauerkandidaten, damit "Woran es liegt" nicht aus lauter
        // Einzelfällen besteht.
        let lossFavourites = Array(pool.shuffled(using: &random).prefix(4))

        var created = 0
        for index in 0..<60 {
            // Jeder fünfte Satz ist ein Verlust: ergibt die 80-zu-20-Quote.
            let discarded = index % 5 == 0
            let product = discarded
                ? lossFavourites[Int.random(in: 0..<lossFavourites.count, using: &random)]
                : pool[Int.random(in: 0..<pool.count, using: &random)]

            let daysAgo = Int.random(in: 0...89, using: &random)
            let hour = Int.random(in: 8...20, using: &random)
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let recordedAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            else { continue }

            // Verbraucht: kurz vor dem Datum. Weggeworfen: kurz danach.
            let offset = discarded
                ? -Int.random(in: 0...5, using: &random)
                : Int.random(in: 1...8, using: &random)
            let expiry = calendar.date(byAdding: .day, value: offset, to: day) ?? day

            let record = ConsumptionRecord(
                productName: product.name,
                brand: product.marke,
                barcode: product.barcode,
                storageLocationName: product.ort,
                quantity: Int.random(in: 1...10, using: &random) > 8 ? 2 : 1,
                outcome: discarded ? .discarded : .consumed,
                recordedAt: recordedAt,
                expiryDate: expiry
            )
            context.insert(record)
            created += 1
        }
        try? context.save()
        return created
    }

    /// Linearer Kongruenzgenerator, reicht für Testdaten und bleibt reproduzierbar.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    // MARK: - Löschen

    /// Löscht alle Produkte samt Erinnerungen. Lagerorte bleiben.
    static func deleteAllItems(in context: ModelContext, viewModel: AppViewModel) async {
        let items = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        for item in items {
            item.imageData = nil
            context.delete(item)
        }
        try? context.save()
        viewModel.pendingSyncCount = 0
        viewModel.updateWidgetSnapshot()
        await viewModel.rescheduleAllNotifications()
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
        let records = (try? context.fetch(FetchDescriptor<ConsumptionRecord>())) ?? []
        for record in records {
            context.delete(record)
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
