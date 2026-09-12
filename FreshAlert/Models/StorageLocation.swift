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

    /// Alle Vorlagen mit fertigem Icon und Farbe, in der Reihenfolge der
    /// Vorlagenliste beim Anlegen eines Lagerorts. Die ersten fünf sind die
    /// Standardorte aus dem Onboarding (`defaultTemplates`).
    static let allTemplates: [StorageLocationTemplate] = [
        .init(name: "Kühlschrank",    iconName: "thermometer.snowflake", colorHex: "#5AC8FA"),
        .init(name: "Tiefkühler",     iconName: "snowflake",             colorHex: "#007AFF"),
        .init(name: "Vorratsschrank", iconName: "cabinet",               colorHex: "#FF9500"),
        .init(name: "Keller",         iconName: "building.columns",      colorHex: "#8E8E93"),
        .init(name: "Obstkorb",       iconName: "basket",                colorHex: "#FF3B30"),
        .init(name: "Gewürzregal",    iconName: "flame",                 colorHex: "#FF9500"),
        .init(name: "Getränke",       iconName: "waterbottle",           colorHex: "#5AC8FA"),
        .init(name: "Brotkasten",     iconName: "basket.fill",           colorHex: "#FFCC00"),
        .init(name: "Büro",           iconName: "briefcase",             colorHex: "#8E8E93"),
        .init(name: "Auto",           iconName: "car",                   colorHex: "#007AFF"),
        .init(name: "Camping",        iconName: "tent",                  colorHex: "#34C759"),
        .init(name: "Medikamente",    iconName: "pills",                 colorHex: "#FF3B30"),
        .init(name: "Tierfutter",     iconName: "pawprint",              colorHex: "#AF52DE"),
        .init(name: "Baby",           iconName: "teddybear",             colorHex: "#FF2D55"),
    ]

    /// Single source of truth for the suggested storage locations,
    /// used by the onboarding wizard and the `defaultLocations` factory.
    static let defaultTemplates: [StorageLocationTemplate] = Array(allTemplates.prefix(5))

    /// Icon und Farbe aus dem Namen eines eigenen Orts: "Kühlbox" bekommt das
    /// Thermometer in Blau, "Bierkeller" die Säulen, alles Unbekannte die Box.
    /// Umlaute und ae/oe/ue-Schreibweisen zählen gleich.
    static func suggestion(forName name: String) -> (iconName: String, colorHex: String) {
        let n = name.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
        let words = n.split(whereSeparator: { !$0.isLetter }).map(String.init)
        // Reihenfolge zählt: "Tiefkühler" enthält auch "kühl". "eis" nur am
        // Wortanfang, sonst wird die Speisekammer zum Gefrierfach.
        let rules: [(keys: [String], wordStart: Bool, iconName: String, colorHex: String)] = [
            (["gefrier", "tief"],                false, "snowflake",             "#007AFF"),
            (["eis"],                            true,  "snowflake",             "#007AFF"),
            (["kuhl", "kuehl"],                  false, "thermometer.snowflake", "#5AC8FA"),
            (["keller"],                         false, "building.columns",      "#8E8E93"),
            (["obst"],                           false, "basket",                "#FF3B30"),
            (["getrank", "getraenk", "flasche"], false, "waterbottle",           "#5AC8FA"),
            (["gewurz", "gewuerz"],              false, "flame",                 "#FF9500"),
            (["brot"],                           false, "basket.fill",           "#FFCC00"),
        ]
        for rule in rules {
            let hit = rule.keys.contains { key in
                rule.wordStart ? words.contains { $0.hasPrefix(key) } : n.contains(key)
            }
            if hit { return (rule.iconName, rule.colorHex) }
        }
        return ("archivebox", "#34C759")
    }

    static var defaultLocations: [StorageLocation] {
        defaultTemplates.enumerated().map { index, t in
            StorageLocation(name: t.name, iconName: t.iconName, colorHex: t.colorHex, sortOrder: index)
        }
    }
}

struct StorageLocationTemplate {
    let name: String
    let iconName: String
    let colorHex: String
}

// MARK: - Brand Color
extension Color {
    /// FreshAlert brand green — the single source of truth for the app's accent.
    static let freshGreen = Color(red: 0.2, green: 0.78, blue: 0.2)
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
