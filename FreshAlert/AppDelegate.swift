import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var pendingShortcutType: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            Self.pendingShortcutType = shortcut.type
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Self.pendingShortcutType = shortcutItem.type
        completionHandler(true)
    }
}

extension Notification.Name {
    static let openScannerTab = Notification.Name("com.freshalert.openScannerTab")
}
