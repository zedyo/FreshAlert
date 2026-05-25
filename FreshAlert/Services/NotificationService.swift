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

    /// Geplante Notifications, deren `itemId` nicht mehr im Datenbestand existiert —
    /// daraus Name + Ablaufdatum rekonstruieren, damit der Nutzer verlorene Produkte
    /// wiederherstellen kann (Hauptursache: stiller SwiftData-Verlust).
    func findOrphanedNotifications(existingIDs: Set<UUID>) async -> [OrphanedNotification] {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        var byID: [UUID: OrphanAggregate] = [:]

        for request in pending {
            guard let idStr = request.content.userInfo["itemId"] as? String,
                  let itemID = UUID(uuidString: idStr),
                  !existingIDs.contains(itemID),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger else { continue }

            var agg = byID[itemID] ?? OrphanAggregate()
            agg.identifiers.append(request.identifier)
            let body = request.content.body

            if request.identifier.hasPrefix("freshalert-expiry-"),
               let range = body.range(of: " läuft heute ab.") {
                // Body: "<name> läuft heute ab. ..." — Ablaufdatum = Triggertag.
                agg.name = String(body[..<range.lowerBound])
                if let date = Calendar.current.date(from: trigger.dateComponents) {
                    agg.expiryDate = Calendar.current.startOfDay(for: date)
                }
            } else if request.identifier.hasPrefix("freshalert-reminder-"),
                      let prefixRange = body.range(of: " läuft in "),
                      let suffixRange = body.range(of: " ab.", range: prefixRange.upperBound..<body.endIndex) {
                // Body: "<name> läuft in N Tag(en) ab." — Ablaufdatum = Trigger + N Tage.
                if agg.name == nil {
                    agg.name = String(body[..<prefixRange.lowerBound])
                }
                let middle = body[prefixRange.upperBound..<suffixRange.lowerBound]
                if agg.expiryDate == nil,
                   let daysStr = middle.split(separator: " ").first,
                   let n = Int(daysStr),
                   let triggerDate = Calendar.current.date(from: trigger.dateComponents),
                   let expiry = Calendar.current.date(byAdding: .day, value: n, to: triggerDate) {
                    agg.expiryDate = Calendar.current.startOfDay(for: expiry)
                }
            }
            byID[itemID] = agg
        }

        return byID.compactMap { id, agg in
            guard let name = agg.name?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty,
                  let expiry = agg.expiryDate else { return nil }
            return OrphanedNotification(
                itemID: id,
                name: name,
                expiryDate: expiry,
                notificationIdentifiers: agg.identifiers
            )
        }
        .sorted { $0.expiryDate < $1.expiryDate }
    }

    func cancelNotifications(withIdentifiers ids: [String]) {
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

struct OrphanedNotification: Identifiable, Hashable {
    let itemID: UUID
    let name: String
    let expiryDate: Date
    let notificationIdentifiers: [String]
    var id: UUID { itemID }
}

private struct OrphanAggregate {
    var name: String?
    var expiryDate: Date?
    var identifiers: [String] = []
}
