import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Lädt Beispieldaten aus `TestData/*.json` in die Datenbank und setzt die App
/// auf Wunsch komplett zurück. Zwei Datensätze: `testprodukte` (50 Produkte,
/// gemischte Daten, auch abgelaufene) zum Entwickeln und `screenshotprodukte`
/// (14 deutsche Alltagsprodukte, nichts abgelaufen) für die Store-Bilder.
/// Nur über das Entwicklermenü und die Launch-Argumente `-seedTestData`
/// beziehungsweise `-seedScreenshotData` erreichbar.
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

    /// Der Entwickler-Datensatz.
    nonisolated static let defaultFileName = "testprodukte"
    /// Der kuratierte Datensatz für die App-Store-Bilder.
    nonisolated static let screenshotFileName = "screenshotprodukte"

    static func loadProducts(from fileName: String = defaultFileName) -> [TestProduct] {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TestDataFile.self, from: data)
        else { return [] }
        return file.produkte
    }

    static var productCount: Int { loadProducts().count }
    static var screenshotProductCount: Int { loadProducts(from: screenshotFileName).count }

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
    static func seed(
        into context: ModelContext,
        viewModel: AppViewModel,
        fileName: String = defaultFileName
    ) async -> Int {
        let products = loadProducts(from: fileName)
        guard !products.isEmpty else {
            viewModel.showToast("Testdaten nicht gefunden")
            return 0
        }

        // Vor der Dublettenprüfung: die Statistik soll auch dann etwas zeigen,
        // wenn die Produkte schon in der Datenbank stehen.
        seedConsumptionRecords(into: context, products: products)

        return await insert(
            products,
            into: context,
            viewModel: viewModel,
            successToast: { "\($0) Testprodukte geladen" },
            nothingNewToast: "Alle Testprodukte sind schon da"
        )
    }

    /// Legt die noch fehlenden Produkte an, plant Erinnerungen und wartet, bis
    /// alle Bilder da sind. Gemeinsamer Teil beider Datensätze.
    private static func insert(
        _ products: [TestProduct],
        into context: ModelContext,
        viewModel: AppViewModel,
        successToast: (Int) -> String,
        nothingNewToast: String
    ) async -> Int {
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
            viewModel.showToast(nothingNewToast)
            return 0
        }

        // Sofort statt mit Verzögerung, damit das Entwicklermenü den Zähler gleich richtig zeigt.
        await viewModel.rescheduleAllNotifications()
        viewModel.showToast(successToast(newItems.count))

        await downloadImages(for: newItems, viewModel: viewModel)
        return newItems.count
    }

    // MARK: - Screenshot-Daten

    /// Die Lagerorte der Store-Bilder, in dieser Reihenfolge.
    private static let screenshotLocations = ["Kühlschrank", "Tiefkühler", "Vorratsschrank", "Obstkorb"]

    /// Räumt die Datenbank leer und legt den kuratierten Datensatz an:
    /// 14 Produkte mit Bild, keines abgelaufen, vier Lagerorte und eine
    /// Verbrauchshistorie mit guter Quote. Kehrt erst zurück, wenn alle
    /// Bilder geladen sind, sonst zeigen die Bilder graue Platzhalter.
    /// Das Onboarding bleibt abgehakt, anders als bei `resetApp`.
    @discardableResult
    static func seedScreenshotData(into context: ModelContext, viewModel: AppViewModel) async -> Int {
        let products = loadProducts(from: screenshotFileName)
        guard !products.isEmpty else {
            viewModel.showToast("Screenshot-Daten nicht gefunden")
            return 0
        }

        clearDatabase(in: context, viewModel: viewModel)

        // Erst die Orte in fester Reihenfolge, damit die Chips in der Übersicht
        // immer gleich liegen. Die JSON-Daten nutzen drei davon.
        var locations: [StorageLocation] = []
        for name in screenshotLocations {
            _ = locationNamed(name, in: &locations, context: context)
        }
        try? context.save()

        seedScreenshotConsumptionRecords(into: context, products: products)

        return await insert(
            products,
            into: context,
            viewModel: viewModel,
            successToast: { "\($0) Screenshot-Produkte geladen" },
            nothingNewToast: "Screenshot-Produkte sind schon da"
        )
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

    /// 70 Sätze über die letzten 90 Tage für die Store-Bilder: sechs Verluste,
    /// also rund 92 Prozent gerettet, gleichmäßig über die Wochen verteilt und
    /// über die Lagerorte gemischt. Zwei der Verluste liegen in den letzten
    /// 30 Tagen, damit auch der voreingestellte Zeitraum eine echte Quote zeigt.
    /// Weggeworfen wird, was im Kühlschrank üblicherweise schlecht wird.
    @discardableResult
    static func seedScreenshotConsumptionRecords(
        into context: ModelContext, products: [TestProduct]
    ) -> Int {
        guard !products.isEmpty else { return 0 }
        // Feste Folge, damit zwei Läufe dasselbe Bild ergeben.
        var random = SeededGenerator(seed: 20_260_912)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let total = 70
        let losses = [
            (name: "Salatgurke", ort: "Kühlschrank"),
            (name: "Strauchtomaten", ort: "Obstkorb"),
            (name: "Eisbergsalat", ort: "Kühlschrank"),
        ]

        // Sechs Verluste, bewusst überwiegend im älteren Zeitraum: die letzten
        // 30 Tage (Index bis etwa 22) sollen besser dastehen als die 60 davor,
        // damit die Statistik einen Fortschritt zeigt statt eines Rückschritts.
        let lossIndices: Set<Int> = [17, 33, 41, 49, 57, 65]

        var created = 0
        var lossIndex = 0
        for index in 0..<total {
            let discarded = lossIndices.contains(index)
            // Gleichmäßig über 89 Tage, nie heute (sonst läge ein Satz in der Zukunft).
            let daysAgo = 1 + (index * 88) / (total - 1)
            let hour = Int.random(in: 8...20, using: &random)
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let recordedAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            else { continue }

            let pick = products[Int.random(in: 0..<products.count, using: &random)]
            let loss = losses[lossIndex % losses.count]
            let lossProduct = products.first { $0.name == loss.name }
            if discarded { lossIndex += 1 }

            // Verbraucht: ein paar Tage vor dem Datum. Weggeworfen: danach.
            let offset = discarded
                ? -Int.random(in: 0...4, using: &random)
                : Int.random(in: 1...8, using: &random)
            let expiry = calendar.date(byAdding: .day, value: offset, to: day) ?? day

            let record = ConsumptionRecord(
                productName: discarded ? loss.name : pick.name,
                brand: discarded ? (lossProduct?.marke ?? "") : pick.marke,
                barcode: discarded ? (lossProduct?.barcode ?? "") : pick.barcode,
                storageLocationName: discarded ? loss.ort : pick.ort,
                // Verluste bleiben Einzelstücke, sonst drückt die Menge die Quote.
                quantity: discarded ? 1 : (Int.random(in: 1...10, using: &random) > 8 ? 2 : 1),
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
        clearDatabase(in: context, viewModel: viewModel)
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        viewModel.showToast("App zurückgesetzt. Beim nächsten Start kommt das Onboarding.")
    }

    /// Produkte, Lagerorte, Verbrauchssätze, Mitteilungen und Widget-Daten weg.
    /// Das Onboarding-Flag bleibt, darum kümmert sich der Aufrufer.
    private static func clearDatabase(in context: ModelContext, viewModel: AppViewModel) {
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

        // Zeigt sonst auf einen gelöschten Lagerort.
        UserDefaults.standard.removeObject(forKey: "lastStorageLocationID")

        viewModel.pendingSyncCount = 0
    }
}
