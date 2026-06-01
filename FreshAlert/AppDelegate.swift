import UIKit
import UserNotifications
import WidgetKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Only ever touched on the main thread (scene delegate callbacks and
    // .main-queue notification observers), so opting out of actor isolation
    // is safe and avoids Sendable-closure warnings.
    nonisolated(unsafe) static var pendingShortcutType: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task { @MainActor in NotificationService.shared.registerCategories() }
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

    // Notification im Vordergrund trotzdem als Banner zeigen, damit die
    // Quick-Action-Buttons auch dort sichtbar sind.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Quick-Action-Antworten: Item-ID aus userInfo holen, je nach Aktion
    // dekrementieren oder komplett verbrauchen. Nutzt den App-Group-Queue
    // (gleicher Mechanismus wie das Widget), damit auch ohne App-Start die
    // Anzeige stimmt und die Daten beim nächsten Start nachgezogen werden.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let idStr = userInfo["itemId"] as? String,
              let id = UUID(uuidString: idStr) else { return }

        switch response.actionIdentifier {
        case NotificationActionID.markUsedSingle,
             NotificationActionID.markUsedAll:
            // Item ist faktisch weg → beide Notifs cancellen, Delete-All queuen.
            let toCancel = [
                "freshalert-reminder-\(id.uuidString)",
                "freshalert-expiry-\(id.uuidString)"
            ]
            center.removePendingNotificationRequests(withIdentifiers: toCancel)
            center.removeDeliveredNotifications(withIdentifiers: toCancel)
            WidgetDataStore.queueDeleteAll(id: id)
        case NotificationActionID.markUsedOne:
            // Restmenge bleibt mit gleichem Ablauf → Notifs nicht antasten.
            WidgetDataStore.queueDecrement(id: id)
        default:
            // Standard-Tap (kein Action-Button) → keine Mutation.
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
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
