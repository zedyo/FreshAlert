import XCTest
@testable import FreshAlert

/// Der Planer ist eine reine Funktion, die Tests laufen mit festem Kalender
/// und festem "jetzt" (Montag, 14.09.2026, 08:00, Europe/Berlin).
final class ReminderDigestPlannerTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    private lazy var planner = ReminderDigestPlanner(calendar: calendar)
    private lazy var today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
    private lazy var now = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: today)!

    // MARK: - Hilfen

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func product(_ name: String, expiresIn days: Int, custom: Int? = nil) -> ReminderProduct {
        ReminderProduct(name: name, expiryDate: day(days), customReminderDays: custom)
    }

    private func plan(
        _ products: [ReminderProduct],
        now: Date? = nil,
        lead: Int = 7,
        hour: Int = 9,
        minute: Int = 0
    ) -> [PlannedReminder] {
        planner.plan(products: products, now: now ?? self.now, globalReminderDays: lead, hour: hour, minute: minute)
    }

    // MARK: - Gruppierung
    // Jedes Produkt taucht zweimal auf: am Meldetag (Vorlauf) und am Ablauftag
    // ("Heute läuft ab"), jeweils in der Tagesmitteilung des Tages.

    func testGroupsProductsOfSameDayIntoOneReminder() {
        let result = plan([
            product("Milch", expiresIn: 10),
            product("Joghurt", expiresIn: 10),
            product("Käse", expiresIn: 12)
        ])
        XCTAssertEqual(result.map(\.day), [day(3), day(5), day(10), day(12)])
        XCTAssertEqual(result[0].productCount, 2)
        XCTAssertEqual(result[0].identifier, "freshalert.daily.2026-09-17")
        XCTAssertEqual(result[1].productCount, 1)
        XCTAssertEqual(result[2].expiringToday.map(\.name), ["Joghurt", "Milch"])
        XCTAssertEqual(result[3].expiringToday.map(\.name), ["Käse"])
    }

    func testFireDateUsesConfiguredTime() {
        let result = plan([product("Milch", expiresIn: 10)], hour: 18, minute: 30)
        let components = calendar.dateComponents([.hour, .minute], from: result[0].fireDate)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 30)
    }

    func testNoEmptyDays() {
        let result = plan([
            product("A", expiresIn: 9),
            product("B", expiresIn: 20)
        ])
        XCTAssertEqual(result.map(\.day), [day(2), day(9), day(13), day(20)])
    }

    // MARK: - Texte

    func testSingularAndPluralTitles() {
        XCTAssertEqual(plan([product("Milch", expiresIn: 10)])[0].title, "1 Produkt läuft bald ab")
        XCTAssertEqual(
            plan([product("Milch", expiresIn: 10), product("Joghurt", expiresIn: 10)])[0].title,
            "2 Produkte laufen bald ab"
        )
        XCTAssertEqual(plan([product("Milch", expiresIn: 1)], lead: 0)[0].title, "1 Produkt läuft heute ab")
    }

    func testBodyListsUpToThreeNamesThenCountsTheRest() {
        let names = ["Milch", "Joghurt", "Butter", "Quark", "Sahne"]
        let result = plan(names.map { product($0, expiresIn: 8) })
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(
            result[0].body,
            "Butter (in 7 Tagen), Joghurt (in 7 Tagen), Milch (in 7 Tagen) und 2 weitere"
        )
    }

    func testBodyMentionsSingleRemainingProduct() {
        let result = plan(["A", "B", "C", "D"].map { product($0, expiresIn: 8) })
        XCTAssertTrue(result[0].body.hasSuffix("und 1 weiteres"))
    }

    func testRemainingLabels() {
        XCTAssertEqual(plan([product("Milch", expiresIn: 1)], lead: 1)[0].body, "Milch (morgen)")
        XCTAssertEqual(plan([product("Milch", expiresIn: 3)], lead: 3)[0].body, "Milch (in 3 Tagen)")
    }

    func testExpiryDayIsListedInSameReminder() {
        let result = plan([
            product("Milch", expiresIn: 3),
            product("Brot", expiresIn: 0)
        ], lead: 3)
        XCTAssertEqual(result.map(\.day), [today, day(3)])
        XCTAssertEqual(result[0].upcoming.map(\.name), ["Milch"])
        XCTAssertEqual(result[0].expiringToday.map(\.name), ["Brot"])
        XCTAssertEqual(result[0].body, "Milch (in 3 Tagen)\nHeute läuft ab: Brot")
    }

    // MARK: - Meldetag in der Vergangenheit

    func testPastReminderDayMovesToNextSlot() {
        // Vorlauf 7, Ablauf in 3 Tagen: Meldetag wäre vor 4 Tagen, also heute (08:00 liegt vor 09:00).
        let result = plan([product("Milch", expiresIn: 3)])
        XCTAssertEqual(result.map(\.day), [today, day(3)])
        XCTAssertEqual(result[1].body, "Heute läuft ab: Milch")
        XCTAssertEqual(result[0].body, "Milch (in 3 Tagen)")
    }

    func testAfterTodaysSlotNextSlotIsTomorrow() {
        let lateNow = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let result = plan([product("Milch", expiresIn: 3)], now: lateNow)
        XCTAssertEqual(result.map(\.day), [day(1), day(3)])
        XCTAssertEqual(result[0].body, "Milch (in 2 Tagen)")
    }

    func testExpiredProductsAreIgnored() {
        XCTAssertTrue(plan([product("Alt", expiresIn: -1)]).isEmpty)
        // Läuft heute ab, aber das Sendefenster von heute ist schon vorbei.
        let lateNow = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        XCTAssertTrue(plan([product("Heute", expiresIn: 0)], now: lateNow).isEmpty)
    }

    // MARK: - Limit

    func testAtMostThirtyReminders() {
        let products = (1...80).map { product("P\($0)", expiresIn: $0, custom: 0) }
        let result = plan(products)
        XCTAssertEqual(result.count, ReminderDigestPlanner.maxRequests)
        XCTAssertLessThanOrEqual(result.count, 30)
        XCTAssertEqual(result.last?.day, day(30))
    }

    func testProductsBeyondHorizonAreNotPlannedYet() {
        XCTAssertTrue(plan([product("Spät", expiresIn: 60)]).isEmpty)
    }

    // MARK: - Eigene Vorlaufzeit

    func testCustomLeadBeatsGlobalLead() {
        let result = plan([
            product("Eigen", expiresIn: 10, custom: 2),
            product("Global", expiresIn: 10)
        ])
        XCTAssertEqual(result.map(\.day), [day(3), day(8), day(10)])
        XCTAssertEqual(result[0].upcoming.map(\.name), ["Global"])
        XCTAssertEqual(result[1].upcoming.map(\.name), ["Eigen"])
        XCTAssertEqual(result[2].expiringToday.count, 2)
    }

    // MARK: - Darstellung

    func testDayLabels() {
        XCTAssertEqual(planner.dayLabel(for: today, now: now), "Heute")
        XCTAssertEqual(planner.dayLabel(for: day(1), now: now), "Morgen")
        XCTAssertEqual(planner.dayLabel(for: day(2), now: now), "Mi, 16.09.")
    }

    func testTimeFormatting() {
        XCTAssertEqual(ReminderTimeFormatting.string(hour: 9, minute: 0), "9:00")
        XCTAssertEqual(ReminderTimeFormatting.string(hour: 18, minute: 5), "18:05")
    }
}
