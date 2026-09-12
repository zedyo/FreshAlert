import XCTest
@testable import FreshAlert

/// Die Auswertung ist eine reine Funktion über eine Liste von Sätzen.
/// Alle Tests laufen mit festem Kalender und festem "jetzt"
/// (Samstag, 12.09.2026, 12:00, Europe/Berlin).
final class ConsumptionStatsTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }()

    private lazy var now = calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)
    )!

    // MARK: - Hilfen

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: now)!
    }

    private func record(
        _ name: String = "Milch",
        outcome: ConsumptionOutcome = .consumed,
        daysAgo: Int = 1,
        quantity: Int = 1,
        location: String = "Kühlschrank",
        expiryInDays: Int = 2
    ) -> ConsumptionRecord {
        record(
            name,
            outcome: outcome,
            at: date(daysAgo: daysAgo),
            quantity: quantity,
            location: location,
            expiryInDays: expiryInDays
        )
    }

    /// `expiryInDays` zählt ab dem Vorgang: positiv heißt vor dem Ablauf verbraucht.
    private func record(
        _ name: String,
        outcome: ConsumptionOutcome,
        at recordedAt: Date,
        quantity: Int = 1,
        location: String = "Kühlschrank",
        expiryInDays: Int = 2
    ) -> ConsumptionRecord {
        ConsumptionRecord(
            productName: name,
            storageLocationName: location,
            quantity: quantity,
            outcome: outcome,
            recordedAt: recordedAt,
            expiryDate: calendar.date(byAdding: .day, value: expiryInDays, to: recordedAt)!,
            calendar: calendar
        )
    }

    private func report(
        _ records: [ConsumptionRecord], period: StatsPeriod = .days30
    ) -> ConsumptionReport {
        ConsumptionStats.report(for: records, period: period, now: now, calendar: calendar)
    }

    // MARK: - Leere Liste

    func testEmptyListHasNoRate() {
        let result = report([])
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.current.rescueRate)
        XCTAssertNil(result.rateChange)
        XCTAssertNil(result.worstLocation)
        XCTAssertNil(result.averageDaysBeforeExpiry)
        XCTAssertTrue(result.topLosses.isEmpty)
        XCTAssertEqual(result.current.total, 0)
    }

    func testRateCountsExemplarsNotRecords() {
        // 8 verbraucht (einer davon doppelt), 2 weggeworfen: 80 Prozent.
        var records = (0..<7).map { _ in record() }
        records.append(record(quantity: 2))
        records.append(record(outcome: .discarded))
        records.append(record(outcome: .discarded))
        let result = report(records)
        XCTAssertEqual(result.current.consumed, 9)
        XCTAssertEqual(result.current.discarded, 2)
        XCTAssertEqual(result.current.rescueRate ?? 0, 81.81, accuracy: 0.01)
    }

    // MARK: - Zeitraumgrenzen

    func testPeriodBoundaryIsInclusive() {
        let start = calendar.date(byAdding: .day, value: -30, to: now)!
        let onBoundary = record("Grenze", outcome: .consumed, at: start)
        let justBefore = record(
            "Davor", outcome: .consumed, at: start.addingTimeInterval(-1)
        )
        let atNow = record("Jetzt", outcome: .consumed, at: now)

        let current = ConsumptionStats.records(
            [onBoundary, justBefore, atNow], in: .days30, now: now, calendar: calendar
        )
        XCTAssertEqual(current.map(\.productName).sorted(), ["Grenze", "Jetzt"])

        let previous = ConsumptionStats.previousRecords(
            [onBoundary, justBefore, atNow], in: .days30, now: now, calendar: calendar
        )
        XCTAssertEqual(previous.map(\.productName), ["Davor"])
    }

    func testNinetyDaysSeesMoreThanThirty() {
        let records = [record(daysAgo: 10), record(daysAgo: 60), record(daysAgo: 200)]
        XCTAssertEqual(report(records, period: .days30).current.total, 1)
        XCTAssertEqual(report(records, period: .days90).current.total, 2)
        XCTAssertEqual(report(records, period: .all).current.total, 3)
    }

    func testAllPeriodHasNoPreviousPeriod() {
        let result = report([record(daysAgo: 5), record(daysAgo: 200)], period: .all)
        XCTAssertEqual(result.previous.total, 0)
        XCTAssertNil(result.rateChange)
    }

    // MARK: - Vergleich zum Vorzeitraum

    func testRateChangeAgainstPreviousPeriod() {
        // Jetzt: 8 von 10 gerettet (80 %). Davor: 6 von 10 (60 %). Also +20 Punkte.
        var records = (0..<8).map { _ in record(daysAgo: 5) }
        records += (0..<2).map { _ in record(outcome: .discarded, daysAgo: 5) }
        records += (0..<6).map { _ in record(daysAgo: 40) }
        records += (0..<4).map { _ in record(outcome: .discarded, daysAgo: 40) }

        let result = report(records)
        XCTAssertEqual(result.current.rescueRate ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(result.previous.rescueRate ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(result.rateChange ?? 0, 20, accuracy: 0.001)
    }

    func testRateChangeIsNilWithoutPreviousRecords() {
        let result = report([record(daysAgo: 3)])
        XCTAssertNil(result.rateChange)
        XCTAssertEqual(result.current.rescueRate ?? 0, 100, accuracy: 0.001)
    }

    // MARK: - Top-Verluste

    func testTopLossesAreSortedAndCapped() {
        var records = (0..<4).map { _ in record("Joghurt", outcome: .discarded, daysAgo: 3) }
        records += (0..<3).map { _ in record("Salat", outcome: .discarded, daysAgo: 4) }
        records.append(record("Käse", outcome: .discarded, daysAgo: 5, quantity: 2))
        records.append(record("Brot", outcome: .discarded, daysAgo: 6))
        // Verbrauchtes zählt hier nicht mit, auch nicht in Massen.
        records += (0..<20).map { _ in record("Milch", daysAgo: 2) }

        let result = report(records)
        XCTAssertEqual(result.topLosses.count, 3)
        XCTAssertEqual(result.topLosses.map(\.name), ["Joghurt", "Salat", "Käse"])
        XCTAssertEqual(result.topLosses.map(\.count), [4, 3, 2])
    }

    func testTopLossesIgnoreRecordsOutsidePeriod() {
        let records = [
            record("Alt", outcome: .discarded, daysAgo: 80),
            record("Neu", outcome: .discarded, daysAgo: 2)
        ]
        XCTAssertEqual(report(records).topLosses.map(\.name), ["Neu"])
        XCTAssertEqual(report(records, period: .days90).topLosses.count, 2)
    }

    // MARK: - Lagerort

    func testWorstLocationCountsOnlyLosses() {
        var records = [
            record(outcome: .discarded, daysAgo: 2, location: "Kühlschrank"),
            record(outcome: .discarded, daysAgo: 3, location: "Kühlschrank"),
            record(outcome: .discarded, daysAgo: 4, location: "Keller")
        ]
        // Viel Verbrauchtes im Keller kippt das Ergebnis nicht.
        records += (0..<10).map { _ in record(daysAgo: 5, location: "Keller") }

        let worst = report(records).worstLocation
        XCTAssertEqual(worst?.name, "Kühlschrank")
        XCTAssertEqual(worst?.count, 2)
    }

    func testWorstLocationSkipsRecordsWithoutLocation() {
        let records = [
            record(outcome: .discarded, daysAgo: 2, location: ""),
            record(outcome: .discarded, daysAgo: 3, location: ""),
            record(outcome: .discarded, daysAgo: 4, location: "Obstkorb")
        ]
        XCTAssertEqual(report(records).worstLocation?.name, "Obstkorb")
    }

    // MARK: - Tage vor Ablauf

    func testAverageDaysBeforeExpiry() {
        let records = [
            record(daysAgo: 2, expiryInDays: 4),
            record(daysAgo: 3, expiryInDays: 2),
            // Weggeworfenes zählt nicht mit.
            record(outcome: .discarded, daysAgo: 4, expiryInDays: -10)
        ]
        XCTAssertEqual(report(records).averageDaysBeforeExpiry ?? 0, 3, accuracy: 0.001)
    }

    func testAverageIsNegativeWhenEatenAfterExpiry() {
        let result = report([record(daysAgo: 2, expiryInDays: -3)])
        XCTAssertEqual(result.averageDaysBeforeExpiry ?? 0, -3, accuracy: 0.001)
    }

    // MARK: - Wochen

    func testWeeksCoverThePeriodWithoutGaps() {
        let weeks = report([record(daysAgo: 2), record(outcome: .discarded, daysAgo: 20)]).weeks
        XCTAssertGreaterThanOrEqual(weeks.count, 5)
        XCTAssertEqual(weeks.map(\.weekStart), weeks.map(\.weekStart).sorted())
        XCTAssertEqual(weeks.reduce(0) { $0 + $1.consumed }, 1)
        XCTAssertEqual(weeks.reduce(0) { $0 + $1.discarded }, 1)
        // Montag als Wochenanfang, wie im deutschen Kalender.
        for week in weeks {
            XCTAssertEqual(calendar.component(.weekday, from: week.weekStart), 2)
        }
    }

    func testWeeksAreCapped() {
        let records = (0..<40).map { record(daysAgo: $0 * 7 + 1) }
        let weeks = report(records, period: .all).weeks
        XCTAssertEqual(weeks.count, ConsumptionStats.maxWeeks)
    }
}
