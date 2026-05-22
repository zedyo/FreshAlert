import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Query private var locations: [StorageLocation]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var selectedTab = 0
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Übersicht", systemImage: "house.fill")
                }
                .tag(0)

            BarcodeScannerView()
                .tabItem {
                    Label("Scannen", systemImage: "barcode.viewfinder")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(Color.freshGreen)
        .onAppear {
            if viewModel.scanRequested {
                selectedTab = 1
                viewModel.scanRequested = false
            }
            resolveOnboarding()
        }
        .onChange(of: viewModel.scanRequested) { _, requested in
            guard requested else { return }
            selectedTab = 1
            viewModel.scanRequested = false
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
    }

    // Show the wizard only on a true first launch: onboarding never completed
    // and no storage locations exist yet. Existing users (who already have
    // locations from earlier versions) are silently marked as onboarded.
    private func resolveOnboarding() {
        guard !hasCompletedOnboarding else { return }
        if locations.isEmpty {
            showOnboarding = true
        } else {
            hasCompletedOnboarding = true
        }
    }
}
