import XCTest
import SwiftUI
@testable import FreshAlert

// Unit tests for expiry label logic and ExpiryStatus.
// Run via Product → Test in Xcode (⌘U).
final class ExpiryLabelTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(daysOffset: Int) -> FoodItem {
        let date = Calendar.current.date(byAdding: .day, value: daysOffset, to: Calendar.current.startOfDay(for: Date()))!
        return FoodItem(name: "Test", expiryDate: date)
    }

    // MARK: - expiryLabel

    func testExpiredSingleDay() {
        XCTAssertEqual(makeItem(daysOffset: -1).expiryLabel, "Abgelaufen · 1 Tag")
    }

    func testExpiredMultipleDays() {
        XCTAssertEqual(makeItem(daysOffset: -5).expiryLabel, "Abgelaufen · 5 Tage")
    }

    func testToday() {
        XCTAssertEqual(makeItem(daysOffset: 0).expiryLabel, "Heute verbrauchen")
    }

    func testTomorrow() {
        XCTAssertEqual(makeItem(daysOffset: 1).expiryLabel, "Morgen")
    }

    func testFutureDays() {
        XCTAssertEqual(makeItem(daysOffset: 10).expiryLabel, "Noch 10 Tage")
    }

    // MARK: - expiryStatus

    func testStatusExpired() {
        XCTAssertEqual(makeItem(daysOffset: -1).expiryStatus, .expired)
    }

    func testStatusCriticalToday() {
        XCTAssertEqual(makeItem(daysOffset: 0).expiryStatus, .critical)
    }

    func testStatusCritical3Days() {
        XCTAssertEqual(makeItem(daysOffset: 3).expiryStatus, .critical)
    }

    func testStatusWarning() {
        XCTAssertEqual(makeItem(daysOffset: 5).expiryStatus, .warning)
    }

    func testStatusGood() {
        XCTAssertEqual(makeItem(daysOffset: 14).expiryStatus, .good)
    }
}

// MARK: - WidgetFoodItem expiry label tests

final class WidgetExpiryLabelTests: XCTestCase {

    private func makeWidget(daysOffset: Int) -> WidgetFoodItem {
        let date = Calendar.current.date(byAdding: .day, value: daysOffset, to: Calendar.current.startOfDay(for: Date()))!
        return WidgetFoodItem(id: UUID(), name: "Test", brand: "", expiryDate: date, quantity: 1, locationName: nil, locationIconName: nil)
    }

    func testExpiredLabel() {
        XCTAssertEqual(makeWidget(daysOffset: -3).expiryLabel, "Abl. 3 T.")
    }

    func testTodayLabel() {
        XCTAssertEqual(makeWidget(daysOffset: 0).expiryLabel, "Heute verwenden")
    }

    func testTomorrowLabel() {
        XCTAssertEqual(makeWidget(daysOffset: 1).expiryLabel, "Morgen")
    }

    func testFutureLabel() {
        XCTAssertEqual(makeWidget(daysOffset: 7).expiryLabel, "Noch 7 T.")
    }
}

// MARK: - daysUntilExpiry

final class DaysUntilExpiryTests: XCTestCase {

    private func makeItem(daysOffset: Int) -> FoodItem {
        let date = Calendar.current.date(byAdding: .day, value: daysOffset, to: Calendar.current.startOfDay(for: Date()))!
        return FoodItem(name: "Test", expiryDate: date)
    }

    func testToday() {
        XCTAssertEqual(makeItem(daysOffset: 0).daysUntilExpiry, 0)
    }

    func testPast() {
        XCTAssertEqual(makeItem(daysOffset: -4).daysUntilExpiry, -4)
    }

    func testFuture() {
        XCTAssertEqual(makeItem(daysOffset: 30).daysUntilExpiry, 30)
    }

    func testIgnoresTimeOfDay() {
        // An expiry later today must still count as 0 days.
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date())!
        XCTAssertEqual(FoodItem(name: "Test", expiryDate: endOfDay).daysUntilExpiry, 0)
    }
}

// MARK: - Color(hex:)

final class ColorHexTests: XCTestCase {

    func testValidHexWithHash() {
        XCTAssertNotNil(Color(hex: "#FF9500"))
    }

    func testValidHexWithoutHash() {
        XCTAssertNotNil(Color(hex: "34C759"))
    }

    func testInvalidLength() {
        XCTAssertNil(Color(hex: "#FFF"))
    }

    func testNonHexCharacters() {
        XCTAssertNil(Color(hex: "#ZZZZZZ"))
    }

    func testEmptyString() {
        XCTAssertNil(Color(hex: ""))
    }
}

// MARK: - StorageLocation defaults

final class StorageLocationTests: XCTestCase {

    func testDefaultLocationCount() {
        XCTAssertEqual(StorageLocation.defaultLocations.count, 5)
    }

    func testDefaultSortOrdersAreSequential() {
        let orders = StorageLocation.defaultLocations.map(\.sortOrder)
        XCTAssertEqual(orders, Array(0..<orders.count))
    }

    func testDefaultLocationsHaveNamesAndIcons() {
        for loc in StorageLocation.defaultLocations {
            XCTAssertFalse(loc.name.isEmpty)
            XCTAssertFalse(loc.iconName.isEmpty)
        }
    }
}
