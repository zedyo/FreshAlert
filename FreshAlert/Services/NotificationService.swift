import UserNotifications
import Foundation
import os

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    private static let logger = Logger(subsystem: "com.freshalert.app", category: "notifications")

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// Quick-Action-Kategorien für die Push-Notifications. Müssen einmal beim
    /// App-Start registriert werden, damit das System die Buttons anzeigen kann
    /// – auch wenn die App selbst nicht läuft.
    func registerCategories() {
        let singleUsed = UNNotificationAction(
            identifier: NotificationActionID.markUsedSingle,
            title: "Verbraucht",
            options: []
        )
        let multiOne = UNNotificationAction(
            identifier: NotificationActionID.markUsedOne,
            title: "1 verbraucht",
            options: []
        )
        let multiAll = UNNotificationAction(
            identifier: NotificationActionID.markUsedAll,
            title: "Alle verbraucht",
            options: [.destructive]
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationCategoryID.single,
                actions: [singleUsed],
                intentIdentifiers: [], options: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategoryID.multi,
                actions: [multiOne, multiAll],
                intentIdentifiers: [], options: []
            )
        ])
    }

    /// Schedules reminder + expiry-day notifications. Returns notification identifiers.
    func scheduleNotifications(for item: FoodItem, reminderDays: Int) async -> [String] {
        // Cancel existing first
        cancelNotifications(for: item)

        var identifiers: [String] = []
        let categoryID = item.quantity > 1
            ? NotificationCategoryID.multi
            : NotificationCategoryID.single

        // Strukturierte userInfo: itemId + itemName + expiryDate. Wird vom
        // Orphan-Parser primär gelesen — Body-Parsing ist nur Fallback für
        // Alt-Notifications aus Versionen vor 1.8.
        let baseUserInfo: [AnyHashable: Any] = [
            NotificationUserInfoKey.itemID: item.id.uuidString,
            NotificationUserInfoKey.itemName: item.name,
            NotificationUserInfoKey.expiryDate: item.expiryDate.timeIntervalSince1970
        ]

        // 1. Reminder notification (X days before expiry)
        if let reminderDate = Calendar.current.date(
            byAdding: .day, value: -reminderDays, to: item.expiryDate
        ), reminderDate > Date() {
            let id = "freshalert-reminder-\(item.id.uuidString)"
            let content = UNMutableNotificationContent()
            content.title = "FreshAlert – Bald ablaufend"
            content.body = "\(item.name) läuft in \(reminderDays) \(reminderDays == 1 ? "Tag" : "Tagen") ab."
            content.sound = .default
            content.userInfo = baseUserInfo
            content.categoryIdentifier = categoryID

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
            content.userInfo = baseUserInfo
            content.categoryIdentifier = categoryID

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
        return OrphanedNotificationParser.aggregate(pending, existingIDs: existingIDs)
    }

    func cancelNotifications(withIdentifiers ids: [String]) {
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Shared types

struct OrphanedNotification: Identifiable, Hashable {
    let itemID: UUID
    let name: String
    let expiryDate: Date
    let notificationIdentifiers: [String]
    var id: UUID { itemID }
}

enum NotificationCategoryID {
    static let single = "freshalert-single"
    static let multi  = "freshalert-multi"
}

enum NotificationActionID {
    static let markUsedSingle = "freshalert-mark-used-single"
    static let markUsedOne    = "freshalert-mark-used-one"
    static let markUsedAll    = "freshalert-mark-used-all"
}

enum NotificationUserInfoKey {
    static let itemID     = "itemId"
    static let itemName   = "itemName"
    static let expiryDate = "expiryDate"
}

// MARK: - Pure parser (testbar ohne UNUserNotificationCenter)

/// Rein funktionale Aggregation pending Notifications zu Waisen. Liest primär
/// strukturierte `userInfo`-Felder (ab v1.8); fällt auf Body-String-Parsing
/// zurück für Alt-Notifications. Pure → direkt unit-testbar.
enum OrphanedNotificationParser {
    static func aggregate(
        _ requests: [UNNotificationRequest],
        existingIDs: Set<UUID>,
        calendar: Calendar = .current
    ) -> [OrphanedNotification] {
        var byID: [UUID: Aggregate] = [:]

        for request in requests {
            let userInfo = request.content.userInfo
            guard let idStr = userInfo[NotificationUserInfoKey.itemID] as? String,
                  let itemID = UUID(uuidString: idStr),
                  !existingIDs.contains(itemID) else { continue }

            var agg = byID[itemID] ?? Aggregate()
            agg.identifiers.append(request.identifier)

            // Primärpfad: strukturierte userInfo (v1.8+).
            if agg.name == nil, let name = userInfo[NotificationUserInfoKey.itemName] as? String {
                agg.name = name
            }
            if agg.expiryDate == nil,
               let ts = userInfo[NotificationUserInfoKey.expiryDate] as? TimeInterval {
                agg.expiryDate = calendar.startOfDay(for: Date(timeIntervalSince1970: ts))
            }

            // Fallback: Body-Parsing für Alt-Notifications, sofern userInfo
            // unvollständig war. Entfernbar, sobald keine Pre-1.8-Notifs mehr
            // im Umlauf sein können (typisch nach Ablauf des längsten
            // globalen Reminders + Restlaufzeit, also realistisch 1.9 oder später).
            if agg.name == nil || agg.expiryDate == nil,
               let trigger = request.trigger as? UNCalendarNotificationTrigger {
                parseFromBody(
                    request: request,
                    trigger: trigger,
                    into: &agg,
                    calendar: calendar
                )
            }

            byID[itemID] = agg
        }

        return byID.compactMap { itemID, agg in
            guard let name = agg.name?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty,
                  let expiry = agg.expiryDate else { return nil }
            return OrphanedNotification(
                itemID: itemID,
                name: name,
                expiryDate: expiry,
                notificationIdentifiers: agg.identifiers
            )
        }
        .sorted { $0.expiryDate < $1.expiryDate }
    }

    private static func parseFromBody(
        request: UNNotificationRequest,
        trigger: UNCalendarNotificationTrigger,
        into agg: inout Aggregate,
        calendar: Calendar
    ) {
        let body = request.content.body
        if request.identifier.hasPrefix("freshalert-expiry-"),
           let range = body.range(of: " läuft heute ab.") {
            // Body: "<name> läuft heute ab. ..." — Ablaufdatum = Triggertag.
            if agg.name == nil {
                agg.name = String(body[..<range.lowerBound])
            }
            if agg.expiryDate == nil, let date = calendar.date(from: trigger.dateComponents) {
                agg.expiryDate = calendar.startOfDay(for: date)
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
               let triggerDate = calendar.date(from: trigger.dateComponents),
               let expiry = calendar.date(byAdding: .day, value: n, to: triggerDate) {
                agg.expiryDate = calendar.startOfDay(for: expiry)
            }
        }
    }

    fileprivate struct Aggregate {
        var name: String?
        var expiryDate: Date?
        var identifiers: [String] = []
    }
}
