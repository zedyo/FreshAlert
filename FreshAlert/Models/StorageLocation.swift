import Foundation
import SwiftData
import SwiftUI

@Model
final class StorageLocation {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var sortOrder: Int

    @Relationship(deleteRule: .nullify, inverse: \FoodItem.storageLocation)
    var foodItems: [FoodItem]

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "archivebox",
        colorHex: String = "#34C759",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.foodItems = []
    }

    var color: Color {
        Color(hex: colorHex) ?? .green
    }

    static var defaultLocations: [StorageLocation] {
        [
            StorageLocation(name: "Kühlschrank",    iconName: "thermometer.snowflake", colorHex: "#5AC8FA", sortOrder: 0),
            StorageLocation(name: "Tiefkühler",     iconName: "snowflake",             colorHex: "#007AFF", sortOrder: 1),
            StorageLocation(name: "Vorratsschrank", iconName: "cabinet",               colorHex: "#FF9500", sortOrder: 2),
            StorageLocation(name: "Keller",         iconName: "building.columns",      colorHex: "#8E8E93", sortOrder: 3),
            StorageLocation(name: "Obstkorb",       iconName: "basket",                colorHex: "#FF3B30", sortOrder: 4),
        ]
    }
}

// MARK: - Color Hex Extension
extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }

    var toHex: String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return "#34C759" }
        return String(format: "#%02X%02X%02X",
            Int(components[0] * 255),
            Int(components[1] * 255),
            Int(components[2] * 255))
    }
}
