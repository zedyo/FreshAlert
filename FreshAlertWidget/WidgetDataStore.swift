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
        case ..<0:  return "Abgelaufen"
        case 0:     return "Heute"
        case 1:     return "Morgen"
        default:    return "Noch \(daysUntilExpiry) T."
        }
    }
}

enum WidgetDataStore {
    static let itemsKey = "widgetFoodItems"
    static let pendingDecrementsKey = "widgetPendingDecrements"

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
}
