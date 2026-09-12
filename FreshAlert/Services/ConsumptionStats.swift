import Foundation

/// Zeitraum der Auswertung.
enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case days30
    case days90
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days30: return "30 Tage"
        case .days90: return "90 Tage"
        case .all:    return "Alles"
        }
    }

    /// Länge in Tagen, `nil` bei "Alles".
    var days: Int? {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .all:    return nil
        }
    }

    /// Schlusshalbsatz für die Zeile unter der großen Zahl.
    var sentenceSuffix: String {
        switch self {
        case .days30: return "in den letzten 30 Tagen"
        case .days90: return "in den letzten 90 Tagen"
        case .all:    return "insgesamt"
        }
    }
}

/// Verbraucht gegen weggeworfen, gezählt in Exemplaren.
struct ConsumptionSummary: Equatable {
    var consumed: Int = 0
    var discarded: Int = 0

    var total: Int { consumed + discarded }

    /// Anteil der verbrauchten Exemplare in Prozent, `nil` ohne Sätze.
    var rescueRate: Double? {
        guard total > 0 else { return nil }
        return Double(consumed) / Double(total) * 100
    }
}

/// Ein Name mit einer Anzahl: Produkt oder Lagerort in der Verlustliste.
struct NamedCount: Equatable, Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

/// Eine Woche im Diagramm.
struct WeekBucket: Equatable, Identifiable {
    let weekStart: Date
    let consumed: Int
    let discarded: Int
    var id: Date { weekStart }
}

/// Alles, was die Statistikansicht für einen Zeitraum braucht.
struct ConsumptionReport: Equatable {
    let period: StatsPeriod
    let current: ConsumptionSummary
    let previous: ConsumptionSummary
    /// Unterschied der Rettungsquote in Prozentpunkten gegenüber dem
    /// Vorzeitraum. `nil`, wenn einer der beiden Zeiträume leer ist.
    let rateChange: Double?
    let topLosses: [NamedCount]
    let worstLocation: NamedCount?
    /// Im Schnitt so viele Tage vor Ablauf verbraucht, gewichtet nach
    /// Exemplaren. Negativ heißt: im Schnitt erst nach Ablauf.
    let averageDaysBeforeExpiry: Double?
    let weeks: [WeekBucket]

    var isEmpty: Bool { current.total == 0 }
}

/// Reine Auswertung über eine Liste von Sätzen. Keine Datenbank, kein
/// SwiftUI, damit jeder Schritt einzeln testbar bleibt.
enum ConsumptionStats {
    /// So viele Wochen zeigt das Diagramm höchstens, sonst wird es unlesbar.
    static let maxWeeks = 26
    static let topLossCount = 3

    // MARK: - Zeitraum

    /// Beginn des Zeitraums, `nil` bei "Alles".
    static func periodStart(
        _ period: StatsPeriod, now: Date, calendar: Calendar = .current
    ) -> Date? {
        guard let days = period.days else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: now)
    }

    /// Sätze im Zeitraum. Die Grenze selbst zählt noch dazu.
    static func records(
        _ records: [ConsumptionRecord],
        in period: StatsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ConsumptionRecord] {
        guard let start = periodStart(period, now: now, calendar: calendar) else { return records }
        return records.filter { $0.recordedAt >= start && $0.recordedAt <= now }
    }

    /// Sätze aus dem gleich langen Zeitraum davor. Bei "Alles" immer leer.
    static func previousRecords(
        _ records: [ConsumptionRecord],
        in period: StatsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ConsumptionRecord] {
        guard let days = period.days,
              let start = periodStart(period, now: now, calendar: calendar),
              let previousStart = calendar.date(byAdding: .day, value: -days, to: start)
        else { return [] }
        return records.filter { $0.recordedAt >= previousStart && $0.recordedAt < start }
    }

    // MARK: - Kennzahlen

    static func summary(of records: [ConsumptionRecord]) -> ConsumptionSummary {
        var summary = ConsumptionSummary()
        for record in records {
            switch record.outcome {
            case .consumed:  summary.consumed += record.quantity
            case .discarded: summary.discarded += record.quantity
            }
        }
        return summary
    }

    /// Die am häufigsten weggeworfenen Produkte, das größte zuerst.
    /// Gleichstand nach Namen, damit die Liste stabil bleibt.
    static func topLosses(
        in records: [ConsumptionRecord], limit: Int = topLossCount
    ) -> [NamedCount] {
        Array(counts(in: records, key: \.productName).prefix(limit))
    }

    /// Der Lagerort mit den meisten weggeworfenen Exemplaren. Sätze ohne
    /// Lagerort zählen nicht mit, sonst gewinnt "kein Ort" die Liste.
    static func worstLocation(in records: [ConsumptionRecord]) -> NamedCount? {
        counts(in: records, key: \.storageLocationName).first
    }

    /// Im Schnitt so viele Tage vor Ablauf verbraucht, `nil` ohne verbrauchte Sätze.
    static func averageDaysBeforeExpiry(in records: [ConsumptionRecord]) -> Double? {
        let consumed = records.filter { $0.outcome == .consumed }
        let exemplars = consumed.reduce(0) { $0 + $1.quantity }
        guard exemplars > 0 else { return nil }
        let sum = consumed.reduce(0) { $0 + (-$1.daysEarlyOrLate * $1.quantity) }
        return Double(sum) / Double(exemplars)
    }

    private static func counts(
        in records: [ConsumptionRecord], key: KeyPath<ConsumptionRecord, String>
    ) -> [NamedCount] {
        var totals: [String: Int] = [:]
        for record in records where record.outcome == .discarded {
            let name = record[keyPath: key].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            totals[name, default: 0] += record.quantity
        }
        return totals
            .map { NamedCount(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name < $1.name
            }
    }

    // MARK: - Wochen

    /// Eine Zeile je Woche, auch für Wochen ohne Sätze, damit das Diagramm
    /// keine Lücken zeigt. Höchstens `maxWeeks` Wochen, die jüngsten.
    static func weeks(
        for records: [ConsumptionRecord],
        in period: StatsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeekBucket] {
        var consumed: [Date: Int] = [:]
        var discarded: [Date: Int] = [:]
        for record in records {
            let week = weekStart(of: record.recordedAt, calendar: calendar)
            switch record.outcome {
            case .consumed:  consumed[week, default: 0] += record.quantity
            case .discarded: discarded[week, default: 0] += record.quantity
            }
        }

        let last = weekStart(of: now, calendar: calendar)
        let earliestRecord = records.map(\.recordedAt).min()
        let rangeStart: Date = {
            if let start = periodStart(period, now: now, calendar: calendar) {
                return weekStart(of: start, calendar: calendar)
            }
            return weekStart(of: earliestRecord ?? now, calendar: calendar)
        }()

        var buckets: [WeekBucket] = []
        var cursor = min(rangeStart, last)
        while cursor <= last {
            buckets.append(
                WeekBucket(
                    weekStart: cursor,
                    consumed: consumed[cursor] ?? 0,
                    discarded: discarded[cursor] ?? 0
                )
            )
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor),
                  next > cursor
            else { break }
            cursor = next
        }
        return buckets.count > maxWeeks ? Array(buckets.suffix(maxWeeks)) : buckets
    }

    static func weekStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    // MARK: - Gesamtbericht

    static func report(
        for allRecords: [ConsumptionRecord],
        period: StatsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ConsumptionReport {
        let current = records(allRecords, in: period, now: now, calendar: calendar)
        let previous = previousRecords(allRecords, in: period, now: now, calendar: calendar)
        let currentSummary = summary(of: current)
        let previousSummary = summary(of: previous)

        var rateChange: Double?
        if let now = currentSummary.rescueRate, let before = previousSummary.rescueRate {
            rateChange = now - before
        }

        return ConsumptionReport(
            period: period,
            current: currentSummary,
            previous: previousSummary,
            rateChange: rateChange,
            topLosses: topLosses(in: current),
            worstLocation: worstLocation(in: current),
            averageDaysBeforeExpiry: averageDaysBeforeExpiry(in: current),
            weeks: weeks(for: current, in: period, now: now, calendar: calendar)
        )
    }
}
