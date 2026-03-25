import Foundation
import SwiftData
import SwiftUI

@Model
final class FoodItem {
    @Attribute(.unique) var id: UUID
    var barcode: String
    var name: String
    var brand: String
    var imageURL: String
    @Attribute(.externalStorage) var imageData: Data?
    var expiryDate: Date
    var quantity: Int
    var storageLocation: StorageLocation?
    var customReminderDays: Int?
    var notificationIdentifiers: [String]
    var isOfflineEntry: Bool
    var addedAt: Date

    init(
        id: UUID = UUID(),
        barcode: String = "",
        name: String,
        brand: String = "",
        imageURL: String = "",
        imageData: Data? = nil,
        expiryDate: Date,
        quantity: Int = 1,
        storageLocation: StorageLocation? = nil,
        customReminderDays: Int? = nil,
        notificationIdentifiers: [String] = [],
        isOfflineEntry: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.imageURL = imageURL
        self.imageData = imageData
        self.expiryDate = expiryDate
        self.quantity = quantity
        self.storageLocation = storageLocation
        self.customReminderDays = customReminderDays
        self.notificationIdentifiers = notificationIdentifiers
        self.isOfflineEntry = isOfflineEntry
        self.addedAt = addedAt
    }

    var daysUntilExpiry: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: expiryDate)
        ).day ?? 0
    }

    var expiryStatus: ExpiryStatus {
        switch daysUntilExpiry {
        case ..<0:  return .expired
        case 0...3: return .critical
        case 4...7: return .warning
        default:    return .good
        }
    }

    var expiryLabel: String {
        switch daysUntilExpiry {
        case ..<0:  return "Abgelaufen"
        case 0:     return "Läuft heute ab"
        case 1:     return "Läuft morgen ab"
        default:    return "Noch \(daysUntilExpiry) Tage"
        }
    }
}

enum ExpiryStatus {
    case good, warning, critical, expired

    var color: Color {
        switch self {
        case .good:     return Color(red: 0.2, green: 0.78, blue: 0.2)
        case .warning:  return .orange
        case .critical: return .red
        case .expired:  return Color(.systemGray)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .good:     return Color(red: 0.2, green: 0.78, blue: 0.2).opacity(0.12)
        case .warning:  return Color.orange.opacity(0.12)
        case .critical: return Color.red.opacity(0.12)
        case .expired:  return Color(.systemGray5)
        }
    }

    var iconName: String {
        switch self {
        case .good:     return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.circle.fill"
        case .expired:  return "xmark.circle.fill"
        }
    }
}
