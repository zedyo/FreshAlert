import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Only ever touched on the main thread (scene delegate callbacks and
    // .main-queue notification observers), so opting out of actor isolation
    // is safe and avoids Sendable-closure warnings.
    nonisolated(unsafe) static var pendingShortcutType: String?

    /// Wird von `FreshAlertApp` beim Start gesetzt. Über diese Referenz leitet
    /// ein Tipp auf eine Mitteilung in die Übersicht weiter.
    nonisolated(unsafe) static weak var viewModel: AppViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Im Vordergrund trotzdem Banner und Ton zeigen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Tipp auf eine Mitteilung: Übersicht öffnen und "läuft bald ab" vormerken.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier.hasPrefix(ReminderDigestPlanner.identifierPrefix)
        else { return }
        await MainActor.run {
            guard let viewModel = AppDelegate.viewModel else { return }
            viewModel.selectedTab = 0
            viewModel.pendingDashboardFilter = .expiringSoon
        }
    }
}

// In SwiftUI scene-based apps Home Screen quick actions are delivered to the
// scene delegate, never to UIApplicationDelegate. Cold launch arrives via
// connectionOptions, warm launch via windowScene(_:performActionFor:).
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            AppDelegate.pendingShortcutType = shortcutItem.type
            NotificationCenter.default.post(name: .openScannerTab, object: nil)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        AppDelegate.pendingShortcutType = shortcutItem.type
        NotificationCenter.default.post(name: .openScannerTab, object: nil)
        completionHandler(true)
    }
}

extension Notification.Name {
    static let openScannerTab = Notification.Name("com.freshalert.openScannerTab")
}
