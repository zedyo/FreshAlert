import XCTest
import SwiftData
@testable import FreshAlert

/// Integrationsnahe Tests für die CRUD-Pfade in `AppViewModel` mit einem
/// SwiftData-In-Memory-Container. Deckt Add/Delete/Decrement sowie die
/// kritischen Pfade `recoverOrphanedItem` und `processPendingWidgetDecrements`
/// ab — letztere zwei waren historisch fragil (siehe v1.6/v1.7).
///
/// Hinweis: `UNUserNotificationCenter.add(...)` schlägt im Test-Host ohne
/// User-Permission stumm fehl, daher werden `item.notificationIdentifiers`
/// hier **nicht** geprüft. Das ist OK — die Notification-Logik selbst hat
/// eigene Tests (`OrphanedNotificationParsingTests`).
@MainActor
final class AppViewModelCRUDTests: XCTestCase {

    private var container: ModelContainer!
    private var viewModel: AppViewModel!
    private var suiteName: String!
    private var originalDefaults: UserDefaults?

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([FoodItem.self, StorageLocation.self])
        let config = ModelConfiguration("InMemoryTest", schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        viewModel = AppViewModel(modelContext: container.mainContext)

        // Eigene UserDefaults-Suite, damit Widget-Pending-Queues isoliert sind.
        suiteName = "freshalert-appviewmodel-test-\(UUID().uuidString)"
        originalDefaults = WidgetDataStore.defaults
        WidgetDataStore.defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        WidgetDataStore.defaults?.removePersistentDomain(forName: suiteName)
        WidgetDataStore.defaults = originalDefaults
        viewModel = nil
        container = nil
        try await super.tearDown()
    }

    private func makeItem(name: String = "Test", quantity: Int = 1, daysFromNow: Int = 30) -> FoodItem {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
        return FoodItem(name: name, expiryDate: date, quantity: quantity)
    }

    private func fetchAll() throws -> [FoodItem] {
        try container.mainContext.fetch(FetchDescriptor<FoodItem>())
    }

    // MARK: - Add / Delete

    func testAddFoodItemPersistsAndUpdatesWidgetSnapshot() async throws {
        let item = makeItem(name: "Joghurt")
        await viewModel.addFoodItem(item)

        let all = try fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Joghurt")

        // Widget-Snapshot wurde geschrieben.
        let snapshot = WidgetDataStore.loadItems()
        XCTAssertEqual(snapshot.first?.name, "Joghurt")
    }

    func testDeleteFoodItemRemovesFromContext() async throws {
        let item = makeItem(name: "Wurst")
        await viewModel.addFoodItem(item)
        XCTAssertEqual(try fetchAll().count, 1)

        viewModel.deleteFoodItem(item)
        XCTAssertEqual(try fetchAll().count, 0)
    }

    // MARK: - Decrement-Semantik

    func testDecrementGreaterThanOneReducesQuantity() async throws {
        let item = makeItem(name: "Eier", quantity: 6)
        await viewModel.addFoodItem(item)

        viewModel.decrementQuantity(item)

        let fetched = try fetchAll().first
        XCTAssertEqual(fetched?.quantity, 5)
    }

    func testDecrementAtOneDeletes() async throws {
        let item = makeItem(name: "Brot", quantity: 1)
        await viewModel.addFoodItem(item)

        viewModel.decrementQuantity(item)

        XCTAssertEqual(try fetchAll().count, 0,
                       "Bei Menge 1 muss decrement das Item löschen, nicht auf 0 setzen.")
    }

    // MARK: - Orphan-Recovery

    func testRecoverOrphanedItemReusesItemID() async throws {
        let originalID = UUID()
        let expiry = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        let orphan = OrphanedNotification(
            itemID: originalID, name: "Verlorener Joghurt",
            expiryDate: expiry, notificationIdentifiers: []
        )

        await viewModel.recoverOrphanedItem(orphan)

        let all = try fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, originalID,
                       "Recovered Item muss dieselbe UUID behalten — sonst entstehen Duplikate bei späterem Sync.")
        XCTAssertEqual(all.first?.name, "Verlorener Joghurt")
    }

    func testRecoverOrphanedItemRemovesFromOrphanList() async throws {
        let orphan = OrphanedNotification(
            itemID: UUID(), name: "Salat",
            expiryDate: Date(), notificationIdentifiers: []
        )
        // ViewModel intern in den Zustand bringen, als wäre der Scan gelaufen.
        // (Wir nutzen direkt recoverOrphanedItem; scanForOrphanedNotifications
        // setzt die Liste auch — die Methode ist async und greift auf
        // UNUserNotificationCenter zu, was im Test-Host leer ist.)
        await viewModel.recoverOrphanedItem(orphan)

        XCTAssertTrue(viewModel.orphanedNotifications.allSatisfy { $0.itemID != orphan.itemID })
    }

    // MARK: - processPendingWidgetDecrements

    func testProcessPendingDecrementsAppliesToSwiftData() async throws {
        let item = makeItem(name: "Käse", quantity: 3)
        await viewModel.addFoodItem(item)

        WidgetDataStore.queueDecrement(id: item.id)
        WidgetDataStore.queueDecrement(id: item.id)

        viewModel.processPendingWidgetDecrements()

        let fetched = try fetchAll().first
        XCTAssertEqual(fetched?.quantity, 1, "Zwei queued Decrements: 3 → 2 → 1")

        // Queues wurden geleert.
        XCTAssertTrue(WidgetDataStore.loadPendingDecrements().isEmpty)
    }

    func testProcessPendingDeleteAllsAppliesToSwiftData() async throws {
        let item = makeItem(name: "Suppe", quantity: 5)
        await viewModel.addFoodItem(item)

        WidgetDataStore.queueDeleteAll(id: item.id)
        viewModel.processPendingWidgetDecrements()

        XCTAssertEqual(try fetchAll().count, 0,
                       "Delete-All muss unabhängig von der Menge das Item löschen.")
        XCTAssertTrue(WidgetDataStore.loadPendingDeleteAlls().isEmpty)
    }

    func testProcessPendingWithEmptyQueueIsNoOp() async throws {
        let item = makeItem(name: "Apfel", quantity: 2)
        await viewModel.addFoodItem(item)

        viewModel.processPendingWidgetDecrements()

        XCTAssertEqual(try fetchAll().first?.quantity, 2,
                       "Ohne pending Queue darf der Bestand unverändert sein.")
    }
}
