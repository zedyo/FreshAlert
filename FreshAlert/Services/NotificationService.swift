import UserNotifications
import Foundation

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// Schedules reminder + expiry-day notifications. Returns notification identifiers.
    func scheduleNotifications(for item: FoodItem, reminderDays: Int) async -> [String] {
        // Cancel existing first
        cancelNotifications(for: item)

        var identifiers: [String] = []

        // 1. Reminder notification (X days before expiry)
        if let reminderDate = Calendar.current.date(
            byAdding: .day, value: -reminderDays, to: item.expiryDate
        ), reminderDate > Date() {
            let id = "freshalert-reminder-\(item.id.uuidString)"
            let content = UNMutableNotificationContent()
            content.title = "FreshAlert – Bald ablaufend"
            content.body = "\(item.name) läuft in \(reminderDays) \(reminderDays == 1 ? "Tag" : "Tagen") ab."
            content.sound = .default
            content.userInfo = ["itemId": item.id.uuidString]

            var components = Calendar.current.dateComponents([.year, .month, .day], from: reminderDate)
            components.hour = 9
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            if let _ = try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            ) { identifiers.append(id) }
        }

        // 2. Expiry-day notification
        if item.expiryDate > Date() {
            let id = "freshalert-expiry-\(item.id.uuidString)"
            let content = UNMutableNotificationContent()
            content.title = "FreshAlert – Heute ablaufend!"
            content.body = "\(item.name) läuft heute ab. Verwende es noch heute!"
            content.sound = .default
            content.userInfo = ["itemId": item.id.uuidString]

            var components = Calendar.current.dateComponents([.year, .month, .day], from: item.expiryDate)
            components.hour = 8
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            if let _ = try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            ) { identifiers.append(id) }
        }

        return identifiers
    }

    func cancelNotifications(for item: FoodItem) {
        guard !item.notificationIdentifiers.isEmpty else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: item.notificationIdentifiers)
    }
}
