import UserNotifications
import Foundation

/// Plant die Erinnerungen als Tagesmitteilungen: eine Mitteilung je Kalendertag,
/// höchstens 30 auf einmal (iOS hält 64 pro App). Die eigentliche Logik steckt
/// in `ReminderDigestPlanner`, hier passiert nur das Sprechen mit iOS.
@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    static let reminderHourKey = "reminderHour"
    static let reminderMinuteKey = "reminderMinute"
    static let globalReminderDaysKey = "globalReminderDays"
    static let defaultReminderHour = 9
    static let defaultReminderMinute = 0
    static let defaultGlobalReminderDays = 7

    /// Alle Mitteilungen dieser App tragen dieses Präfix, auch die alten
    /// Einzelmitteilungen ("freshalert-reminder-…"), damit sie beim Neuplanen mitverschwinden.
    private static let legacyPrefix = "freshalert"

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    // MARK: - Planen

    /// Die aktuellen Einstellungen aus den UserDefaults.
    static var settings: (reminderDays: Int, hour: Int, minute: Int) {
        let defaults = UserDefaults.standard
        let days = defaults.object(forKey: globalReminderDaysKey) as? Int ?? defaultGlobalReminderDays
        let hour = defaults.object(forKey: reminderHourKey) as? Int ?? defaultReminderHour
        let minute = defaults.object(forKey: reminderMinuteKey) as? Int ?? defaultReminderMinute
        return (max(1, min(30, days)), max(0, min(23, hour)), max(0, min(59, minute)))
    }

    static func products(from items: [FoodItem]) -> [ReminderProduct] {
        items.map {
            ReminderProduct(
                id: $0.id,
                name: $0.name,
                expiryDate: $0.expiryDate,
                customReminderDays: $0.customReminderDays
            )
        }
    }

    /// Berechnet den Plan, ohne etwas bei iOS anzumelden (für die Übersichtsseite).
    static func plan(for items: [FoodItem], now: Date = Date()) -> [PlannedReminder] {
        let settings = Self.settings
        return ReminderDigestPlanner().plan(
            products: products(from: items),
            now: now,
            globalReminderDays: settings.reminderDays,
            hour: settings.hour,
            minute: settings.minute
        )
    }

    /// Löscht alle `freshalert.*`-Requests und plant die Tagesmitteilungen neu.
    /// Gibt den Plan zurück, den iOS jetzt kennt.
    @discardableResult
    func rescheduleAll(items: [FoodItem], now: Date = Date()) async -> [PlannedReminder] {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.legacyPrefix) }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }

        let planned = Self.plan(for: items, now: now)
        let calendar = Calendar.current
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "freshalert.daily"
            content.userInfo = [
                "kind": "daily",
                "day": reminder.identifier,
                "productCount": reminder.productCount
            ]
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(
                UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            )
        }
        return planned
    }
}
