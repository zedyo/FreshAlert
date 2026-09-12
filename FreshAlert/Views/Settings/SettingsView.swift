import SwiftUI
import SwiftData
import StoreKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject private var store: StoreManager
    @State private var itemCount: Int = 0
    @State private var showManageSubscriptions = false
    @State private var showPaywall = false
    @State private var restoreMessage: String?
    @AppStorage("globalReminderDays") private var globalReminderDays: Int = 7
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showRescheduleConfirm = false
    @State private var showRescheduleDone = false
    @ObservedObject private var environment = AppEnvironmentObserver.shared

    var body: some View {
        NavigationStack {
            Form {
                // Status
                Section {
                    HStack {
                        Label("Netzwerk", systemImage: viewModel.isOnline ? "wifi" : "wifi.slash")
                        Spacer()
                        Text(viewModel.isOnline ? "Online" : "Offline")
                            .foregroundStyle(viewModel.isOnline ? .green : .orange)
                            .font(.subheadline)
                    }
                    if viewModel.pendingSyncCount > 0 {
                        HStack {
                            Label("Ausstehende Syncs", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            Text("\(viewModel.pendingSyncCount)")
                                .foregroundStyle(.orange).font(.subheadline.bold())
                        }
                    }
                } header: {
                    Text("Status")
                }

                // Verwaltung
                Section {
                    NavigationLink {
                        StorageLocationsView()
                    } label: {
                        Label("Lagerorte verwalten", systemImage: "archivebox.fill")
                    }
                } header: {
                    Text("Verwaltung")
                }

                // Notifications
                Section {
                    HStack {
                        Label("Benachrichtigungen", systemImage: "bell")
                        Spacer()
                        notifStatusBadge
                    }
                    if notifStatus == .denied {
                        Button {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        } label: {
                            Label("In Einstellungen aktivieren", systemImage: "arrow.up.right")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Erinnerung", systemImage: "clock")
                            Spacer()
                            Text("\(globalReminderDays) \(globalReminderDays == 1 ? "Tag" : "Tage") vorher")
                                .foregroundStyle(.secondary).font(.subheadline)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(globalReminderDays) },
                                set: { globalReminderDays = Int($0) }
                            ),
                            in: 1...30, step: 1
                        )
                        .tint(Color.freshGreen)
                        HStack {
                            Text("1 Tag"); Spacer(); Text("30 Tage")
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button {
                        showRescheduleConfirm = true
                    } label: {
                        Label("Alle Erinnerungen neu planen", systemImage: "arrow.clockwise")
                    }
                    .confirmationDialog(
                        "Alle Erinnerungen werden neu geplant mit dem globalen Wert (\(globalReminderDays) Tage).",
                        isPresented: $showRescheduleConfirm
                    ) {
                        Button("Neu planen") {
                            Task {
                                await viewModel.rescheduleAllNotifications()
                                showRescheduleDone = true
                            }
                        }
                        Button("Abbrechen", role: .cancel) {}
                    }
                    .alert("Erledigt", isPresented: $showRescheduleDone) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Alle Erinnerungen wurden neu eingeplant.")
                    }
                } header: {
                    Text("Benachrichtigungen")
                }

                // FreshAlert Pro
                Section {
                    HStack {
                        Label("Status", systemImage: store.isPro ? "checkmark.seal.fill" : "seal")
                        Spacer()
                        Text(store.isPro ? "Pro aktiv" : "\(itemCount) von \(StoreManager.freeLimit) kostenlosen Produkten")
                            .foregroundStyle(store.isPro ? .green : .secondary)
                            .font(.subheadline)
                    }
                    if !store.isPro {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Pro freischalten", systemImage: "sparkles")
                        }
                    }
                    Button {
                        Task {
                            await store.restorePurchases()
                            restoreMessage = store.isPro
                                ? "Dein Kauf wurde wiederhergestellt."
                                : "Kein Kauf für diese Apple-ID gefunden."
                        }
                    } label: {
                        Label("Kauf wiederherstellen", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(store.isPurchasing)
                    if store.hasActiveSubscription {
                        Button {
                            showManageSubscriptions = true
                        } label: {
                            Label("Abo verwalten", systemImage: "creditcard")
                        }
                    }
                } header: {
                    Text("FreshAlert Pro")
                }

                // About
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                    LabeledContent("Produktdaten", value: "Open Food Facts")
                    LabeledContent("Minimales iOS", value: "iOS 17.0")
                    Link(destination: Legal.privacyPolicyURL) {
                        Label("Datenschutzerklärung", systemImage: "hand.raised")
                    }
                    Link(destination: Legal.termsOfUseURL) {
                        Label("Nutzungsbedingungen", systemImage: "doc.text")
                    }
                    Link(destination: Legal.supportURL) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Über FreshAlert")
                }

                // Entwickler (nur Debug und TestFlight, nie App Store)
                if environment.isDeveloperMenuAvailable {
                    Section {
                        NavigationLink {
                            DeveloperMenuView()
                        } label: {
                            Label("Entwicklermenü", systemImage: "hammer")
                        }
                    } header: {
                        Text("Entwickler")
                    } footer: {
                        Text("Nur in TestFlight- und Debug-Builds sichtbar.")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .task {
                await loadNotifStatus()
                await environment.refresh()
            }
            .onAppear { refreshItemCount() }
            .sheet(isPresented: $showPaywall, onDismiss: { refreshItemCount() }) {
                PaywallView(reason: .fromSettings)
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .alert("Kauf wiederherstellen", isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var notifStatusBadge: some View {
        switch notifStatus {
        case .authorized, .provisional:
            Text("Aktiv").foregroundStyle(.green).font(.subheadline)
        case .denied:
            Text("Blockiert").foregroundStyle(.red).font(.subheadline)
        default:
            Text("Nicht erteilt").foregroundStyle(.secondary).font(.subheadline)
        }
    }

    private func refreshItemCount() {
        itemCount = (try? modelContext.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
    }

    private func loadNotifStatus() async {
        notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
