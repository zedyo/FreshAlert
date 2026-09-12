import Foundation

/// Öffentliche Rechtstexte der App. Eine Stelle für alle Links, damit Paywall
/// und Einstellungen nie auseinanderlaufen.
///
/// TODO(Nik): `privacyPolicyURL` und `supportURL` auf die eigene Domain umstellen,
/// sobald die Seite gehostet ist. Die Interimsadresse zeigt auf den Entwurf im Repo.
enum Legal {
    /// Datenschutzerklärung. Pflicht für den App Store (Richtlinie 5.1.1).
    static let privacyPolicyURL = URL(string: "https://github.com/zedyo/FreshAlert/blob/main/docs/PRIVACY_POLICY.md")!

    /// Apples Standard-EULA, gilt für alle Apps ohne eigene Nutzungsbedingungen.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Support-Adresse. Wird auch im App Store Connect als Support-URL hinterlegt.
    static let supportURL = URL(string: "https://github.com/zedyo/FreshAlert/issues")!

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
