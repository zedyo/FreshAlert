import XCTest
import UserNotifications
@testable import FreshAlert

/// Unit-Tests für `OrphanedNotificationParser` — die Logik hinter der
/// „Vermisste Produkte"-Wiederherstellung. Wichtig, weil das Parsing
/// historisch fragil war (Body-Text-Zerlegung mit deutschen Substrings).
/// Seit v1.7.3 liest der Parser strukturierte `userInfo`-Werte; das
/// Body-Parsing bleibt als Fallback für Pre-1.8-Notifications testbar.
final class OrphanedNotificationParsingTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Helpers

    /// Baut einen `UNNotificationRequest` mit dem Datums-Trigger der
    /// jeweiligen Notification-Art und optional strukturierten userInfo-Feldern.
    private func makeRequest(
        identifier: String,
        body: String,
        triggerDate: Date,
        itemID: UUID,
        itemName: String? = nil,
        expiryDate: Date? = nil
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.body = body
        var info: [AnyHashable: Any] = ["itemId": itemID.uuidString]
        if let itemName { info["itemName"] = itemName }
        if let expiryDate { info["expiryDate"] = expiryDate.timeIntervalSince1970 }
        content.userInfo = info

        // Reminder-Notifs feuern um 9:00, Expiry-Notifs um 8:00 — für die
        // Tests reicht (Jahr, Monat, Tag) + Stunde, wie der Produktiv-Code.
        var comps = calendar.dateComponents([.year, .month, .day], from: triggerDate)
        comps.hour = identifier.hasPrefix("freshalert-expiry-") ? 8 : 9
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - userInfo-Pfad (Primärweg ab v1.7.3)

    func testStructuredUserInfoIsUsedForNameAndDate() {
        let id = UUID()
        let expiry = makeDate(year: 2026, month: 7, day: 1)
        let req = makeRequest(
            identifier: "freshalert-expiry-\(id.uuidString)",
            body: "irgendein Body — egal, wenn userInfo da ist",
            triggerDate: expiry,
            itemID: id,
            itemName: "Joghurt",
            expiryDate: expiry
        )

        let result = OrphanedNotificationParser.aggregate(
            [req], existingIDs: [], calendar: calendar
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Joghurt")
        XCTAssertEqual(result.first?.expiryDate, calendar.startOfDay(for: expiry))
    }

    // MARK: - Body-Fallback (Pre-1.8-Notifications ohne userInfo)

    func testFallbackParsesExpiryBodyWhenUserInfoMissing() {
        let id = UUID()
        let expiry = makeDate(year: 2026, month: 6, day: 15)
        let req = makeRequest(
            identifier: "freshalert-expiry-\(id.uuidString)",
            body: "Apfelmus läuft heute ab. Verwende es noch heute!",
            triggerDate: expiry,
            itemID: id
        )

        let result = OrphanedNotificationParser.aggregate(
            [req], existingIDs: [], calendar: calendar
        )

        XCTAssertEqual(result.first?.name, "Apfelmus")
        XCTAssertEqual(result.first?.expiryDate, calendar.startOfDay(for: expiry))
    }

    func testFallbackParsesReminderBody() {
        let id = UUID()
        let triggerDay = makeDate(year: 2026, month: 6, day: 1)
        let req = makeRequest(
            identifier: "freshalert-reminder-\(id.uuidString)",
            body: "Joghurt läuft in 7 Tagen ab.",
            triggerDate: triggerDay,
            itemID: id
        )

        let result = OrphanedNotificationParser.aggregate(
            [req], existingIDs: [], calendar: calendar
        )

        XCTAssertEqual(result.first?.name, "Joghurt")
        // Reminder triggert 7 Tage VOR dem Ablauf → Ablauf = Trigger + 7.
        XCTAssertEqual(
            result.first?.expiryDate,
            calendar.startOfDay(for: makeDate(year: 2026, month: 6, day: 8))
        )
    }

    func testFallbackParsesSingleDayReminderBody() {
        let id = UUID()
        let triggerDay = makeDate(year: 2026, month: 6, day: 1)
        let req = makeRequest(
            identifier: "freshalert-reminder-\(id.uuidString)",
            body: "Käse läuft in 1 Tag ab.",
            triggerDate: triggerDay,
            itemID: id
        )

        let result = OrphanedNotificationParser.aggregate(
            [req], existingIDs: [], calendar: calendar
        )

        XCTAssertEqual(result.first?.name, "Käse")
        XCTAssertEqual(
            result.first?.expiryDate,
            calendar.startOfDay(for: makeDate(year: 2026, month: 6, day: 2))
        )
    }

    // MARK: - Existierende IDs überspringen

    func testExistingIDsAreSkipped() {
        let id = UUID()
        let expiry = makeDate(year: 2026, month: 7, day: 1)
        let req = makeRequest(
            identifier: "freshalert-expiry-\(id.uuidString)",
            body: "Salat läuft heute ab. Verwende es noch heute!",
            triggerDate: expiry,
            itemID: id,
            itemName: "Salat",
            expiryDate: expiry
        )

        let result = OrphanedNotificationParser.aggregate(
            [req], existingIDs: [id], calendar: calendar
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Reminder + Expiry aggregieren zu EINEM Orphan

    func testReminderAndExpiryOfSameItemAggregate() {
        let id = UUID()
        let expiry = makeDate(year: 2026, month: 6, day: 8)
        let reminderTrigger = makeDate(year: 2026, month: 6, day: 1)

        let reminder = makeRequest(
            identifier: "freshalert-reminder-\(id.uuidString)",
            body: "Milch läuft in 7 Tagen ab.",
            triggerDate: reminderTrigger,
            itemID: id
        )
        let expiryReq = makeRequest(
            identifier: "freshalert-expiry-\(id.uuidString)",
            body: "Milch läuft heute ab. Verwende es noch heute!",
            triggerDate: expiry,
            itemID: id
        )

        let result = OrphanedNotificationParser.aggregate(
            [reminder, expiryReq], existingIDs: [], calendar: calendar
        )

        XCTAssertEqual(result.count, 1, "Ein Item → ein Orphan, beide Notifs zusammengefasst")
        XCTAssertEqual(result.first?.notificationIdentifiers.count, 2)
        XCTAssertEqual(result.first?.name, "Milch")
        XCTAssertEqual(result.first?.expiryDate, calendar.startOfDay(for: expiry))
    }

    // MARK: - Kaputte Bodies werden ignoriert

    func testMalformedBodyWithoutUserInfoYieldsNoOrphan() {
        let id = UUID()
        let req = makeRequest(
            identifier: "freshalert-expiry-\(id.uuidString)",
            body: "irgendein zerstörter Body ohne erkennbare Marker",
            triggerDate: makeDate(year: 2026, month: 6, day: 1),
            itemID: id
        )

        let result = OrphanedNotificationParser.aggregate(
            [req], existingIDs: [], calendar: calendar
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testRequestWithoutItemIdIsIgnored() {
        let content = UNMutableNotificationContent()
        content.body = "Foo läuft heute ab. ..."
        content.userInfo = [:] // kein itemId
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: "freshalert-expiry-x", content: content, trigger: trigger)

        let result = OrphanedNotificationParser.aggregate(
            [req], existingIDs: [], calendar: calendar
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Sortierung

    func testOrphansAreSortedByExpiryDateAscending() {
        let earlyID = UUID()
        let lateID  = UUID()
        let early   = makeDate(year: 2026, month: 6, day: 1)
        let late    = makeDate(year: 2026, month: 7, day: 1)

        let earlyReq = makeRequest(
            identifier: "freshalert-expiry-\(earlyID.uuidString)",
            body: "A läuft heute ab. ...", triggerDate: early, itemID: earlyID,
            itemName: "A", expiryDate: early
        )
        let lateReq = makeRequest(
            identifier: "freshalert-expiry-\(lateID.uuidString)",
            body: "B läuft heute ab. ...", triggerDate: late, itemID: lateID,
            itemName: "B", expiryDate: late
        )

        let result = OrphanedNotificationParser.aggregate(
            [lateReq, earlyReq], existingIDs: [], calendar: calendar
        )

        XCTAssertEqual(result.map(\.name), ["A", "B"])
    }
}
