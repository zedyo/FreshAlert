import Foundation

/// Öffentliche Rechtstexte der App. Eine Stelle für alle Links, damit Paywall
/// und Einstellungen nie auseinanderlaufen.
///
/// Die Seiten liegen auf freshalert.nseel.me (Cloudflare Pages). Kontaktadresse für
/// Kunden ist `supportEmail`.
enum Legal {
    /// Datenschutzerklärung. Pflicht für den App Store (Richtlinie 5.1.1).
    static let privacyPolicyURL = URL(string: "https://freshalert.nseel.me/datenschutz")!

    /// Apples Standard-EULA, gilt für alle Apps ohne eigene Nutzungsbedingungen.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Support-Seite. Wird auch im App Store Connect als Support-URL hinterlegt.
    static let supportURL = URL(string: "https://freshalert.nseel.me/support")!

    /// Kontaktadresse für Kunden. Steht auch im User-Agent der Anfragen an Open Food Facts.
    static let supportEmail = "freshalert@nseel.me"

    /// Quelle der Produktdaten, Lizenz ODbL. Die Nennung in den Einstellungen ist Pflicht.
    static let openFoodFactsURL = URL(string: "https://openfoodfacts.org")!

    /// Formular zum Nachtragen eines unbekannten Barcodes bei Open Food Facts.
    static func openFoodFactsContributeURL(barcode: String) -> URL? {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/product.pl")
        components?.queryItems = [
            URLQueryItem(name: "type", value: "add"),
            URLQueryItem(name: "code", value: barcode),
        ]
        return components?.url
    }
}
