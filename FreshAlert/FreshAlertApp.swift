import SwiftUI
import SwiftData

@main
struct FreshAlertApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let modelContainer: ModelContainer
    @StateObject private var appViewModel: AppViewModel
    @StateObject private var storeManager = StoreManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Launch-Argument `-seedTestData` (Simulator): leere Datenbank mit Testprodukten füllen.
    private let shouldSeedTestData: Bool

    init() {
        do {
            let schema = Schema([FoodItem.self, StorageLocation.self, ConsumptionRecord.self])
            let config = ModelConfiguration("FreshAlert", schema: schema)
            let container = try ModelContainer(for: schema, configurations: config)
            modelContainer = container
            let viewModel = AppViewModel(modelContext: container.mainContext)
            _appViewModel = StateObject(wrappedValue: viewModel)
            // Für den Tipp auf eine Mitteilung (AppDelegate leitet in die Übersicht).
            AppDelegate.viewModel = viewModel
            let seedRequested = AppEnvironment.hasLaunchArgument(AppEnvironment.seedTestDataArgument)
                && TestDataSeeder.isDatabaseEmpty(container.mainContext)
            shouldSeedTestData = seedRequested
            if seedRequested {
                // Vor dem ersten Rendern, sonst zeigt ContentView das Onboarding.
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        } catch {
            fatalError("SwiftData Container konnte nicht erstellt werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environmentObject(appViewModel)
                .environmentObject(storeManager)
                .task {
                    AppDelegate.viewModel = appViewModel
                    // Testdaten zuerst, damit die Übersicht sofort voll ist. Die
                    // Erinnerungen werden nach der Berechtigungsfrage neu geplant.
                    if shouldSeedTestData {
                        await TestDataSeeder.seed(
                            into: modelContainer.mainContext, viewModel: appViewModel
                        )
                    }
                    // On a fresh install the notification prompt is deferred to
                    // the onboarding wizard (after the reminder step is explained).
                    if hasCompletedOnboarding {
                        await NotificationService.shared.requestPermission()
                    }
                    // Ein frischer Plan bei jedem Start: Uhrzeit oder Bestand können sich
                    // geändert haben, alte Einzelmitteilungen verschwinden dabei.
                    await appViewModel.rescheduleAllNotifications()
                    appViewModel.updateWidgetSnapshot()
                    await appViewModel.cacheImagesForExistingItems()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appViewModel.processPendingWidgetDecrements()
                appViewModel.scheduleReminderReplan()
            }
        }
    }
}
