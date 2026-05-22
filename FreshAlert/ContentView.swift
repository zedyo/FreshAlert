import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedTab = 0

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
        .tint(Color(red: 0.2, green: 0.78, blue: 0.2))
        .onAppear {
            if viewModel.scanRequested {
                selectedTab = 1
                viewModel.scanRequested = false
            }
        }
        .onChange(of: viewModel.scanRequested) { _, requested in
            guard requested else { return }
            selectedTab = 1
            viewModel.scanRequested = false
        }
    }
}
