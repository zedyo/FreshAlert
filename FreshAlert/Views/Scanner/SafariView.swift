import SwiftUI
import SafariServices

/// Öffnet eine Webseite im In-App-Browser, z.B. das Nachtragen-Formular von
/// Open Food Facts. Als Sheet mit `.ignoresSafeArea()` verwenden.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
