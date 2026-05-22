import SwiftUI
import SwiftData

@main
struct FreshAlertApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let modelContainer: ModelContainer
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let schema = Schema([FoodItem.self, StorageLocation.self])
            let config = ModelConfiguration("FreshAlert", schema: schema)
            let container = try ModelContainer(for: schema, configurations: config)
            modelContainer = container
            _appViewModel = StateObject(
                wrappedValue: AppViewModel(modelContext: container.mainContext)
            )
        } catch {
            fatalError("SwiftData Container konnte nicht erstellt werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environmentObject(appViewModel)
                .task {
                    await NotificationService.shared.requestPermission()
                    appViewModel.updateWidgetSnapshot()
                    appViewModel.purgeOrphanedImageData()
                    await appViewModel.cacheImagesForExistingItems()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appViewModel.processPendingWidgetDecrements()
                if AppDelegate.pendingShortcutType == "com.freshalert.app.scan" {
                    AppDelegate.pendingShortcutType = nil
                    NotificationCenter.default.post(name: .openScannerTab, object: nil)
                }
            }
        }
    }
}
