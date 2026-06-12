import XCTest
@testable import FreshAlert

/// Unit-Tests für `WidgetDataStore` — die App-Group-Queue zwischen Widget /
/// Push-Notification-Actions und App-Persistierung. Wir setzen die statische
/// `defaults`-Property auf eine eigene Test-Suite, damit die Tests sich nicht
/// gegenseitig sehen und keine produktiven Werte beeinflussen.
final class WidgetDataStoreTests: XCTestCase {

    private var suiteName: String!
    private var originalDefaults: UserDefaults?

    override func setUp() {
        super.setUp()
        suiteName = "freshalert-test-\(UUID().uuidString)"
        originalDefaults = WidgetDataStore.defaults
        WidgetDataStore.defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        WidgetDataStore.defaults?.removePersistentDomain(forName: suiteName)
        WidgetDataStore.defaults = originalDefaults
        super.tearDown()
    }

    // MARK: - Decrement-Queue: behält Duplikate (gewollt — n Taps = n Verbräuche)

    func testDecrementQueueKeepsDuplicates() {
        let id = UUID()
        WidgetDataStore.queueDecrement(id: id)
        WidgetDataStore.queueDecrement(id: id)
        WidgetDataStore.queueDecrement(id: id)

        let pending = WidgetDataStore.loadPendingDecrements()
        XCTAssertEqual(pending.count, 3,
                       "Decrement-Queue darf NICHT dedupen — jeder Tap ist ein realer Verbrauch.")
        XCTAssertTrue(pending.allSatisfy { $0 == id })
    }

    // MARK: - Delete-All-Queue: dedupet (idempotent)

    func testDeleteAllQueueDedupes() {
        let id = UUID()
        WidgetDataStore.queueDeleteAll(id: id)
        WidgetDataStore.queueDeleteAll(id: id)
        WidgetDataStore.queueDeleteAll(id: id)

        let pending = WidgetDataStore.loadPendingDeleteAlls()
        XCTAssertEqual(pending, [id],
                       "Delete-All-Queue muss dedupen — Mehrfach-Tap auf dieselbe Mitteilung darf nicht mehrfach verarbeitet werden.")
    }

    func testDeleteAllQueueKeepsDistinctIDs() {
        let a = UUID()
        let b = UUID()
        WidgetDataStore.queueDeleteAll(id: a)
        WidgetDataStore.queueDeleteAll(id: b)
        WidgetDataStore.queueDeleteAll(id: a) // Duplikat von a

        let pending = WidgetDataStore.loadPendingDeleteAlls()
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.contains(a))
        XCTAssertTrue(pending.contains(b))
    }

    // MARK: - Optimistisches Snapshot-Update

    func testQueueDecrementOptimisticallyReducesQuantity() {
        let id = UUID()
        let item = WidgetFoodItem(
            id: id, name: "Joghurt", brand: "", expiryDate: Date(),
            quantity: 3, locationName: nil, locationIconName: nil
        )
        WidgetDataStore.saveItems([item])

        WidgetDataStore.queueDecrement(id: id)

        XCTAssertEqual(WidgetDataStore.loadItems().first?.quantity, 2)
    }

    func testQueueDecrementRemovesItemAtQuantityOne() {
        let id = UUID()
        let item = WidgetFoodItem(
            id: id, name: "Joghurt", brand: "", expiryDate: Date(),
            quantity: 1, locationName: nil, locationIconName: nil
        )
        WidgetDataStore.saveItems([item])

        WidgetDataStore.queueDecrement(id: id)

        XCTAssertTrue(WidgetDataStore.loadItems().isEmpty,
                      "Bei Menge 1 muss der Decrement das Item aus dem Snapshot entfernen.")
    }

    func testQueueDeleteAllRemovesItemRegardlessOfQuantity() {
        let id = UUID()
        let item = WidgetFoodItem(
            id: id, name: "Käse", brand: "", expiryDate: Date(),
            quantity: 5, locationName: nil, locationIconName: nil
        )
        WidgetDataStore.saveItems([item])

        WidgetDataStore.queueDeleteAll(id: id)

        XCTAssertTrue(WidgetDataStore.loadItems().isEmpty)
    }

    // MARK: - Roundtrips

    func testItemsRoundtrip() {
        let items = (0..<3).map { i in
            WidgetFoodItem(
                id: UUID(), name: "Item \(i)", brand: "",
                expiryDate: Date(), quantity: i + 1,
                locationName: nil, locationIconName: nil
            )
        }
        WidgetDataStore.saveItems(items)
        let loaded = WidgetDataStore.loadItems()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.name), ["Item 0", "Item 1", "Item 2"])
    }

    func testClearDecrementsAndDeleteAllsAreIndependent() {
        let a = UUID()
        let b = UUID()
        WidgetDataStore.queueDecrement(id: a)
        WidgetDataStore.queueDeleteAll(id: b)

        WidgetDataStore.clearPendingDecrements()

        XCTAssertTrue(WidgetDataStore.loadPendingDecrements().isEmpty)
        XCTAssertEqual(WidgetDataStore.loadPendingDeleteAlls(), [b],
                       "clearPendingDecrements() darf die Delete-All-Queue nicht anfassen.")
    }
}
