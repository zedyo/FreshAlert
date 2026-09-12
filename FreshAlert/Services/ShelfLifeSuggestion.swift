import Foundation

/// Typische Restlaufzeit einer Produktgruppe, ab Kaufdatum und ab dem Öffnen.
struct ShelfLife: Equatable {
    /// Kategorie-Tag aus Open Food Facts, etwa `en:yogurts`.
    let tag: String
    /// Deutscher Name für die Zeile im Formular, etwa "Joghurt".
    let label: String
    let unopenedDays: Int
    let openedDays: Int
}

/// Schlägt aus den Kategorien eines Produkts eine Haltbarkeit vor.
/// Reine Tabelle, keine Netzanfrage, nichts wird automatisch gesetzt.
enum ShelfLifeSuggestion {

    /// Von allgemein nach spezifisch sortiert. Trifft mehr als ein Tag, gewinnt
    /// der spezifischste, also der weiter unten stehende Eintrag. Die Werte sind
    /// Erfahrungswerte für ungekühlten Einkauf in Deutschland, bewusst eher
    /// vorsichtig: ein Vorschlag, kein Versprechen.
    static let table: [ShelfLife] = [
        // Sehr allgemeine Gruppen
        ShelfLife(tag: "en:plant-based-foods", label: "Pflanzliches Produkt", unopenedDays: 30, openedDays: 7),
        ShelfLife(tag: "en:beverages", label: "Getränk", unopenedDays: 180, openedDays: 5),
        ShelfLife(tag: "en:dried-products", label: "Trockenware", unopenedDays: 365, openedDays: 120),
        ShelfLife(tag: "en:canned-foods", label: "Konserve", unopenedDays: 540, openedDays: 3),
        ShelfLife(tag: "en:frozen-foods", label: "Tiefkühlware", unopenedDays: 270, openedDays: 30),
        ShelfLife(tag: "en:snacks", label: "Snack", unopenedDays: 120, openedDays: 14),
        ShelfLife(tag: "en:cereals-and-potatoes", label: "Getreideprodukt", unopenedDays: 240, openedDays: 60),
        ShelfLife(tag: "en:fruits-and-vegetables", label: "Obst und Gemüse", unopenedDays: 8, openedDays: 4),
        ShelfLife(tag: "en:dairies", label: "Milchprodukt", unopenedDays: 14, openedDays: 4),
        ShelfLife(tag: "en:meats", label: "Fleisch", unopenedDays: 6, openedDays: 2),
        ShelfLife(tag: "en:seafood", label: "Meeresfrüchte", unopenedDays: 3, openedDays: 1),
        ShelfLife(tag: "en:condiments", label: "Würzmittel", unopenedDays: 300, openedDays: 45),
        ShelfLife(tag: "en:spreads", label: "Aufstrich", unopenedDays: 180, openedDays: 21),
        ShelfLife(tag: "en:desserts", label: "Dessert", unopenedDays: 21, openedDays: 2),

        // Mittlere Ebene
        ShelfLife(tag: "en:sweet-snacks", label: "Süßigkeit", unopenedDays: 150, openedDays: 21),
        ShelfLife(tag: "en:salty-snacks", label: "Knabberzeug", unopenedDays: 90, openedDays: 7),
        ShelfLife(tag: "en:chocolates", label: "Schokolade", unopenedDays: 300, openedDays: 30),
        ShelfLife(tag: "en:biscuits", label: "Kekse", unopenedDays: 150, openedDays: 14),
        ShelfLife(tag: "en:breakfast-cereals", label: "Müsli", unopenedDays: 180, openedDays: 45),
        ShelfLife(tag: "en:pastas", label: "Nudeln", unopenedDays: 540, openedDays: 180),
        ShelfLife(tag: "en:rice", label: "Reis", unopenedDays: 540, openedDays: 180),
        ShelfLife(tag: "en:rices", label: "Reis", unopenedDays: 540, openedDays: 180),
        ShelfLife(tag: "en:flours", label: "Mehl", unopenedDays: 300, openedDays: 120),
        ShelfLife(tag: "en:breads", label: "Brot", unopenedDays: 5, openedDays: 3),
        ShelfLife(tag: "en:milks", label: "Milch", unopenedDays: 9, openedDays: 3),
        ShelfLife(tag: "en:fermented-milk-products", label: "Sauermilchprodukt", unopenedDays: 18, openedDays: 5),
        ShelfLife(tag: "en:creams", label: "Sahne", unopenedDays: 14, openedDays: 3),
        ShelfLife(tag: "en:butters", label: "Butter", unopenedDays: 40, openedDays: 21),
        ShelfLife(tag: "en:cheeses", label: "Käse", unopenedDays: 21, openedDays: 7),
        ShelfLife(tag: "en:eggs", label: "Eier", unopenedDays: 24, openedDays: 14),
        ShelfLife(tag: "en:fresh-meats", label: "Frischfleisch", unopenedDays: 3, openedDays: 1),
        ShelfLife(tag: "en:prepared-meats", label: "Wurstware", unopenedDays: 12, openedDays: 4),
        ShelfLife(tag: "en:sausages", label: "Würstchen", unopenedDays: 12, openedDays: 4),
        ShelfLife(tag: "en:hams", label: "Schinken", unopenedDays: 14, openedDays: 5),
        ShelfLife(tag: "en:fish", label: "Fisch", unopenedDays: 2, openedDays: 1),
        ShelfLife(tag: "en:fishes", label: "Fisch", unopenedDays: 2, openedDays: 1),
        ShelfLife(tag: "en:fresh-fruits", label: "Obst", unopenedDays: 7, openedDays: 3),
        ShelfLife(tag: "en:fresh-vegetables", label: "Gemüse", unopenedDays: 8, openedDays: 4),
        ShelfLife(tag: "en:salads", label: "Salat", unopenedDays: 4, openedDays: 2),
        ShelfLife(tag: "en:fruit-juices", label: "Saft", unopenedDays: 90, openedDays: 4),
        ShelfLife(tag: "en:waters", label: "Wasser", unopenedDays: 365, openedDays: 30),
        ShelfLife(tag: "en:sodas", label: "Limonade", unopenedDays: 270, openedDays: 5),
        ShelfLife(tag: "en:beers", label: "Bier", unopenedDays: 210, openedDays: 1),
        ShelfLife(tag: "en:wines", label: "Wein", unopenedDays: 1095, openedDays: 3),
        ShelfLife(tag: "en:coffees", label: "Kaffee", unopenedDays: 365, openedDays: 90),
        ShelfLife(tag: "en:teas", label: "Tee", unopenedDays: 540, openedDays: 180),
        ShelfLife(tag: "en:sauces", label: "Soße", unopenedDays: 300, openedDays: 30),
        ShelfLife(tag: "en:jams", label: "Marmelade", unopenedDays: 540, openedDays: 30),
        ShelfLife(tag: "en:honeys", label: "Honig", unopenedDays: 1095, openedDays: 365),
        ShelfLife(tag: "en:vegetable-oils", label: "Öl", unopenedDays: 540, openedDays: 120),
        ShelfLife(tag: "en:plant-based-milk-alternatives", label: "Pflanzendrink", unopenedDays: 180, openedDays: 5),
        ShelfLife(tag: "en:tofu", label: "Tofu", unopenedDays: 21, openedDays: 3),
        ShelfLife(tag: "en:ice-creams", label: "Eiscreme", unopenedDays: 270, openedDays: 30),

        // Spezifische Gruppen, gewinnen gegen alles darüber
        ShelfLife(tag: "en:yogurts", label: "Joghurt", unopenedDays: 16, openedDays: 3),
        ShelfLife(tag: "en:fresh-cheeses", label: "Frischkäse", unopenedDays: 14, openedDays: 7),
        ShelfLife(tag: "en:hard-cheeses", label: "Hartkäse", unopenedDays: 45, openedDays: 21),
        ShelfLife(tag: "en:mozzarella", label: "Mozzarella", unopenedDays: 21, openedDays: 3),
        ShelfLife(tag: "en:minced-meats", label: "Hackfleisch", unopenedDays: 2, openedDays: 1),
        ShelfLife(tag: "en:smoked-fishes", label: "Räucherfisch", unopenedDays: 14, openedDays: 3),
        ShelfLife(tag: "en:canned-fishes", label: "Fischkonserve", unopenedDays: 730, openedDays: 2),
        ShelfLife(tag: "en:ketchup", label: "Ketchup", unopenedDays: 365, openedDays: 60),
        ShelfLife(tag: "en:mustards", label: "Senf", unopenedDays: 365, openedDays: 90),
        ShelfLife(tag: "en:mayonnaises", label: "Mayonnaise", unopenedDays: 180, openedDays: 21),
    ]

    /// Tag auf Position in `table`. Die Position ist zugleich die Spezifität.
    private static let ranks: [String: Int] = {
        var ranks: [String: Int] = [:]
        for (index, entry) in table.enumerated() { ranks[entry.tag] = index }
        return ranks
    }()

    /// Der spezifischste Treffer aus `categories_tags`. `nil`, wenn die App
    /// keine der Kategorien kennt: dann gibt es einfach keinen Vorschlag.
    static func suggestion(for tags: [String]) -> ShelfLife? {
        var best: (rank: Int, entry: ShelfLife)?
        for tag in tags {
            let key = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let rank = ranks[key] else { continue }
            if let current = best, current.rank > rank { continue }
            best = (rank, table[rank])
        }
        return best?.entry
    }

    // MARK: - Texte

    /// "2 Wochen", "3 Tage", "einen Monat"
    static func durationText(days: Int) -> String {
        switch days {
        case ..<1:    return "weniger als einen Tag"
        case 1:       return "einen Tag"
        case 2...13:  return "\(days) Tage"
        case 14...59:
            let weeks = Int((Double(days) / 7).rounded())
            return weeks == 1 ? "eine Woche" : "\(weeks) Wochen"
        case 60...364:
            let months = Int((Double(days) / 30.4).rounded())
            return months == 1 ? "einen Monat" : "\(months) Monate"
        default:
            let years = Int((Double(days) / 365).rounded())
            return years <= 1 ? "ein Jahr" : "\(years) Jahre"
        }
    }

    /// "Joghurt hält meist etwa 2 Wochen"
    static func sentence(for shelfLife: ShelfLife) -> String {
        "\(shelfLife.label) hält meist etwa \(durationText(days: shelfLife.unopenedDays))"
    }

    /// "Geöffnet meist etwa 3 Tage"
    static func openedSentence(for shelfLife: ShelfLife) -> String {
        "Geöffnet meist etwa \(durationText(days: shelfLife.openedDays))"
    }

    /// Vorgeschlagenes Datum, immer auf den Tagesanfang gelegt.
    static func date(addingDays days: Int, to base: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: base)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }
}
