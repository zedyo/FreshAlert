import Foundation

let freshalertAppGroupID = "group.com.freshalert.app"

struct WidgetFoodItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let brand: String
    let expiryDate: Date
    var quantity: Int
    let locationName: String?
    let locationIconName: String?

    var daysUntilExpiry: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: expiryDate)
        ).day ?? 0
    }

    var expiryLabel: String {
        switch daysUntilExpiry {
        case ..<0:
            return "Abl. \(abs(daysUntilExpiry)) T."
        case 0:     return "Heute verwenden"
        case 1:     return "Morgen"
        default:    return "Noch \(daysUntilExpiry) T."
        }
    }
}

enum WidgetDataStore {
    static let itemsKey = "widgetFoodItems"
    static let pendingDecrementsKey = "widgetPendingDecrements"
    static let pendingDeleteAllsKey = "widgetPendingDeleteAlls"

    static var defaults: UserDefaults? { UserDefaults(suiteName: freshalertAppGroupID) }

    static func saveItems(_ items: [WidgetFoodItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults?.set(data, forKey: itemsKey)
    }

    static func loadItems() -> [WidgetFoodItem] {
        guard let data = defaults?.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode([WidgetFoodItem].self, from: data)
        else { return [] }
        return items
    }

    static func queueDecrement(id: UUID) {
        // Optimistic UI: update the snapshot immediately
        var items = loadItems()
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if items[idx].quantity > 1 {
                items[idx].quantity -= 1
            } else {
                items.remove(at: idx)
            }
            saveItems(items)
        }
        // Queue so the main app can apply the change to SwiftData
        var pending = loadPendingDecrements()
        pending.append(id)
        if let data = try? JSONEncoder().encode(pending) {
            defaults?.set(data, forKey: pendingDecrementsKey)
        }
    }

    static func loadPendingDecrements() -> [UUID] {
        guard let data = defaults?.data(forKey: pendingDecrementsKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else { return [] }
        return ids
    }

    static func clearPendingDecrements() {
        defaults?.removeObject(forKey: pendingDecrementsKey)
    }

    /// "Alle verbraucht" aus einer Push-Notification: das gesamte Item entfernen,
    /// nicht nur die Menge dekrementieren. Optimistisch aus dem Snapshot
    /// streichen; das App-eigene Persistieren passiert beim nächsten Start.
    ///
    /// **Dedupe-Politik (bewusst unterschiedlich zur Decrement-Queue):**
    /// Delete-All ist idempotent — Mehrfach-Taps auf dieselbe Mitteilung sollen
    /// nicht doppelt verarbeitet werden. Decrement-Queue dedupet **nicht**:
    /// dort ist jeder Tap ein realer Verbrauch, n Taps = n Dekremente.
    static func queueDeleteAll(id: UUID) {
        var items = loadItems()
        items.removeAll { $0.id == id }
        saveItems(items)

        var pending = loadPendingDeleteAlls()
        guard !pending.contains(id) else { return }
        pending.append(id)
        if let data = try? JSONEncoder().encode(pending) {
            defaults?.set(data, forKey: pendingDeleteAllsKey)
        }
    }

    static func loadPendingDeleteAlls() -> [UUID] {
        guard let data = defaults?.data(forKey: pendingDeleteAllsKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else { return [] }
        return ids
    }

    static func clearPendingDeleteAlls() {
        defaults?.removeObject(forKey: pendingDeleteAllsKey)
    }
}
