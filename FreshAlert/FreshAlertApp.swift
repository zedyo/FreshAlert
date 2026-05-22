import SwiftUI
import SwiftData

@main
struct FreshAlertApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let modelContainer: ModelContainer
    @StateObject private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

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
                    // On a fresh install the notification prompt is deferred to
                    // the onboarding wizard (after the reminder step is explained).
                    if hasCompletedOnboarding {
                        await NotificationService.shared.requestPermission()
                    }
                    appViewModel.updateWidgetSnapshot()
                    appViewModel.purgeOrphanedImageData()
                    await appViewModel.cacheImagesForExistingItems()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appViewModel.processPendingWidgetDecrements()
            }
        }
    }
}
