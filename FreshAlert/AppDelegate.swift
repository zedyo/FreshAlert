import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Only ever touched on the main thread (scene delegate callbacks and
    // .main-queue notification observers), so opting out of actor isolation
    // is safe and avoids Sendable-closure warnings.
    nonisolated(unsafe) static var pendingShortcutType: String?

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
