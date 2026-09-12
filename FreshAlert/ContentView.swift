import SwiftUI
import SwiftData
import UIKit
import AudioToolbox

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Query private var locations: [StorageLocation]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
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
        // Über der TabView, damit der Toast auf jedem Tab sichtbar ist,
        // auch im Scanner, wo man nach dem Speichern landet.
        .overlay(alignment: .bottom) {
            if let message = viewModel.toastMessage {
                ToastView(
                    message: message,
                    action: viewModel.toastAction,
                    secondaryAction: viewModel.toastSecondaryAction
                ) {
                    viewModel.dismissToast()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: viewModel.toastMessage)
        .onChange(of: viewModel.selectedTab) { _, _ in
            Feedback.tabChanged()
        }
        .onAppear {
            if viewModel.scanRequested {
                viewModel.selectedTab = 1
                viewModel.scanRequested = false
            }
            resolveOnboarding()
        }
        .onChange(of: viewModel.scanRequested) { _, requested in
            guard requested else { return }
            viewModel.selectedTab = 1
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

// MARK: - Toast

/// Kurze Meldung unten über der Tab-Leiste, optional mit ein oder zwei
/// Aktionsknöpfen ("Rückgängig", "Weggeworfen"). Verschwindet von selbst,
/// siehe AppViewModel.showToast.
struct ToastView: View {
    let message: String
    let action: ToastAction?
    var secondaryAction: ToastAction? = nil
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                // In der Mitte kürzen: bei langen Produktnamen bleibt sonst
                // neben zwei Knöpfen nichts vom "gelöscht" übrig.
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let action {
                Button(action.title) {
                    action.handler()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.freshGreen)
                .buttonStyle(.plain)
                if let secondaryAction {
                    Button(secondaryAction.title) {
                        secondaryAction.handler()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Meldung schließen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.darkGray).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

// MARK: - Feedback

// Subtle sound + haptic feedback. System sounds honor the ringer switch,
// so the audio stays discreet and is silent when the phone is muted.
enum Feedback {
    static func tabChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func scanSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1057)
    }

    static func itemSaved() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1057)
    }

    static func itemUsed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AudioServicesPlaySystemSound(1104)
    }
}
