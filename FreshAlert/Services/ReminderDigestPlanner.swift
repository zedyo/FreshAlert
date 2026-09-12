import Foundation

/// Ein Produkt, so weit der Planer es kennt. Bewusst ein einfaches Struct,
/// damit der Planer ohne SwiftData testbar bleibt.
struct ReminderProduct: Equatable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let expiryDate: Date
    let customReminderDays: Int?

    init(id: UUID = UUID(), name: String, expiryDate: Date, customReminderDays: Int? = nil) {
        self.id = id
        self.name = name
        self.expiryDate = expiryDate
        self.customReminderDays = customReminderDays
    }
}

/// Eine geplante Tagesmitteilung: ein Kalendertag, eine Mitteilung.
struct PlannedReminder: Equatable, Identifiable {
    /// Tagesbeginn des Meldetags.
    let day: Date
    /// Meldetag plus eingestellte Uhrzeit, der Auslösezeitpunkt.
    let fireDate: Date
    let identifier: String
    let title: String
    let body: String
    /// Produkte, deren Vorlauf an diesem Tag erreicht ist (laufen später ab).
    let upcoming: [ReminderProduct]
    /// Produkte, die genau an diesem Tag ablaufen.
    let expiringToday: [ReminderProduct]

    var id: String { identifier }
    var allProducts: [ReminderProduct] { upcoming + expiringToday }
    var productCount: Int { upcoming.count + expiringToday.count }
}

/// Fasst alle Erinnerungen zu höchstens einer Mitteilung je Kalendertag
/// zusammen. Reine Funktion: kein UNUserNotificationCenter, kein SwiftData.
///
/// Regeln:
/// - Meldetag = Haltbar-bis minus Vorlauf (eigener Wert schlägt den globalen).
/// - Liegt der Meldetag schon hinter dem nächsten Sendefenster, rutscht das
///   Produkt in die nächste Tagesmitteilung, solange es nicht abgelaufen ist.
/// - Am Haltbar-bis-Tag selbst steht das Produkt im Abschnitt "Heute läuft ab"
///   derselben Tagesmitteilung, es gibt keine zweite Mitteilung.
/// - Nur Tage mit Produkten, nur die nächsten `horizonDays` Tage, höchstens
///   `maxRequests` Mitteilungen (Schutzabstand zum iOS-Limit von 64).
struct ReminderDigestPlanner {
    static let identifierPrefix = "freshalert."
    static let dailyIdentifierPrefix = "freshalert.daily."
    static let maxRequests = 30
    static let horizonDays = 30
    static let namesInBody = 3

    var calendar: Calendar = .current

    // MARK: - Planen

    func plan(
        products: [ReminderProduct],
        now: Date = Date(),
        globalReminderDays: Int,
        hour: Int,
        minute: Int
    ) -> [PlannedReminder] {
        let today = calendar.startOfDay(for: now)
        guard let todaySlot = fireDate(on: today, hour: hour, minute: minute),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let horizonEnd = calendar.date(byAdding: .day, value: Self.horizonDays, to: today)
        else { return [] }

        // Das nächste Sendefenster: heute, falls die Uhrzeit noch kommt, sonst morgen.
        let firstSlotDay = now < todaySlot ? today : tomorrow

        var upcomingByDay: [Date: [ReminderProduct]] = [:]
        var expiringByDay: [Date: [ReminderProduct]] = [:]

        for product in products {
            let expiryDay = calendar.startOfDay(for: product.expiryDate)
            // Abgelaufen vor dem nächsten Sendefenster: nichts mehr zu melden.
            guard expiryDay >= firstSlotDay else { continue }

            if expiryDay <= horizonEnd {
                expiringByDay[expiryDay, default: []].append(product)
            }

            let lead = max(0, product.customReminderDays ?? globalReminderDays)
            guard let reminderDay = calendar.date(byAdding: .day, value: -lead, to: expiryDay) else { continue }
            let effectiveDay = max(reminderDay, firstSlotDay)
            // Fällt der Meldetag auf den Ablauftag, reicht der Abschnitt "Heute läuft ab".
            guard effectiveDay < expiryDay, effectiveDay <= horizonEnd else { continue }
            upcomingByDay[effectiveDay, default: []].append(product)
        }

        let days = Set(upcomingByDay.keys).union(expiringByDay.keys).sorted()
        var planned: [PlannedReminder] = []
        for day in days.prefix(Self.maxRequests) {
            guard let fire = fireDate(on: day, hour: hour, minute: minute) else { continue }
            let upcoming = (upcomingByDay[day] ?? []).sorted(by: Self.byExpiryThenName)
            let expiring = (expiringByDay[day] ?? []).sorted(by: Self.byExpiryThenName)
            planned.append(
                PlannedReminder(
                    day: day,
                    fireDate: fire,
                    identifier: identifier(for: day),
                    title: title(upcomingCount: upcoming.count, expiringCount: expiring.count),
                    body: body(day: day, upcoming: upcoming, expiringToday: expiring),
                    upcoming: upcoming,
                    expiringToday: expiring
                )
            )
        }
        return planned
    }

    // MARK: - Texte

    func title(upcomingCount: Int, expiringCount: Int) -> String {
        let total = upcomingCount + expiringCount
        if upcomingCount == 0 {
            return total == 1 ? "1 Produkt läuft heute ab" : "\(total) Produkte laufen heute ab"
        }
        return total == 1 ? "1 Produkt läuft bald ab" : "\(total) Produkte laufen bald ab"
    }

    func body(day: Date, upcoming: [ReminderProduct], expiringToday: [ReminderProduct]) -> String {
        var lines: [String] = []
        if !upcoming.isEmpty {
            let names = upcoming.map { "\($0.name) (\(remainingLabel(from: day, to: $0.expiryDate)))" }
            lines.append(Self.join(names))
        }
        if !expiringToday.isEmpty {
            lines.append("Heute läuft ab: " + Self.join(expiringToday.map(\.name)))
        }
        return lines.joined(separator: "\n")
    }

    /// "morgen", "in 3 Tagen", relativ zum Meldetag.
    func remainingLabel(from day: Date, to expiryDate: Date) -> String {
        let days = daysBetween(day, calendar.startOfDay(for: expiryDate))
        switch days {
        case ...0: return "heute"
        case 1:    return "morgen"
        default:   return "in \(days) Tagen"
        }
    }

    /// Bis zu drei Namen, danach "und n weitere".
    static func join(_ names: [String]) -> String {
        let shown = names.prefix(namesInBody).joined(separator: ", ")
        let rest = names.count - namesInBody
        guard rest > 0 else { return shown }
        return "\(shown) und \(rest) \(rest == 1 ? "weiteres" : "weitere")"
    }

    func identifier(for day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%@%04d-%02d-%02d",
            Self.dailyIdentifierPrefix, components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }

    /// "Heute", "Morgen", sonst "Mi, 16.09.", relativ zu `now`.
    func dayLabel(for day: Date, now: Date = Date()) -> String {
        switch daysBetween(now, day) {
        case 0: return "Heute"
        case 1: return "Morgen"
        default:
            let components = calendar.dateComponents([.weekday, .day, .month], from: day)
            let weekday = Self.weekdayNames[((components.weekday ?? 1) - 1 + 7) % 7]
            return String(format: "%@, %02d.%02d.", weekday, components.day ?? 0, components.month ?? 0)
        }
    }

    private static let weekdayNames = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    // MARK: - Hilfen

    func fireDate(on day: Date, hour: Int, minute: Int) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    func daysBetween(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    private static func byExpiryThenName(_ a: ReminderProduct, _ b: ReminderProduct) -> Bool {
        if a.expiryDate != b.expiryDate { return a.expiryDate < b.expiryDate }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// Uhrzeit-Darstellung wie "9:00" und "18:30", ohne führende Null.
enum ReminderTimeFormatting {
    static func string(hour: Int, minute: Int) -> String {
        String(format: "%d:%02d", hour, minute)
    }
}
