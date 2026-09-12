import Foundation
import StoreKit

/// Erkennt, in welcher Umgebung die App läuft. Das Entwicklermenü ist nur in
/// Debug- und TestFlight-Builds erreichbar, nie im App Store.
enum AppEnvironment {
    static let developerMenuArgument = "-developerMenu"
    static let seedTestDataArgument = "-seedTestData"
    static let seedScreenshotDataArgument = "-seedScreenshotData"

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func hasLaunchArgument(_ name: String) -> Bool {
        CommandLine.arguments.contains(name)
    }

    /// Synchrone Heuristik: TestFlight-Builds tragen einen Sandbox-Beleg.
    static var hasSandboxReceipt: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// App-Store-Builds tragen einen Produktionsbeleg namens "receipt".
    static var hasProductionReceipt: Bool {
        guard let url = Bundle.main.appStoreReceiptURL, url.lastPathComponent == "receipt" else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Nur wenn weder Sandbox- noch Produktionsbeleg vorliegen, lohnt die
    /// StoreKit-Abfrage. Sonst könnte `AppTransaction.shared` eine
    /// Apple-Account-Anmeldung auslösen (im Simulator sicher, im Store möglich).
    static var needsTransactionCheck: Bool {
        !isDebugBuild && !hasSandboxReceipt && !hasProductionReceipt
    }

    /// Wird von `AppEnvironmentObserver.refresh()` über StoreKit 2 nachgezogen,
    /// falls die Beleg-Heuristik nichts liefert.
    static var isSandboxTransaction = false

    static var isTestFlight: Bool {
        !isDebugBuild && (hasSandboxReceipt || isSandboxTransaction)
    }

    static var isDeveloperMenuAvailable: Bool {
        isDebugBuild || hasLaunchArgument(developerMenuArgument) || isTestFlight
    }

    static var environmentName: String {
        if isDebugBuild { return "Debug" }
        if isTestFlight { return "TestFlight" }
        return "App Store"
    }

    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Beobachtbare Fassung für SwiftUI. `refresh()` fragt StoreKit 2 nach der
/// Umgebung der App-Transaktion und aktualisiert die Flags, damit die
/// Einstellungen den Abschnitt nachziehen, wenn die Beleg-Heuristik fehlschlägt.
@MainActor
final class AppEnvironmentObserver: ObservableObject {
    static let shared = AppEnvironmentObserver()

    @Published private(set) var isDeveloperMenuAvailable = AppEnvironment.isDeveloperMenuAvailable
    @Published private(set) var environmentName = AppEnvironment.environmentName

    private var hasRefreshed = false

    private init() {}

    func refresh() async {
        guard !hasRefreshed else { return }
        hasRefreshed = true
        if AppEnvironment.needsTransactionCheck,
           case .verified(let transaction) = try? await AppTransaction.shared,
           transaction.environment == .sandbox {
            AppEnvironment.isSandboxTransaction = true
        }
        isDeveloperMenuAvailable = AppEnvironment.isDeveloperMenuAvailable
        environmentName = AppEnvironment.environmentName
    }
}
