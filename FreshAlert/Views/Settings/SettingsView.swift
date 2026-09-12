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
    @AppStorage("reminderHour") private var reminderHour: Int = 9
    @AppStorage("reminderMinute") private var reminderMinute: Int = 0
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
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
                } footer: {
                    if viewModel.pendingSyncCount > 0 {
                        Text("Produkte, die ohne Netz angelegt wurden und ihre Daten von Open Food Facts noch nachladen.")
                    }
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
                    NavigationLink {
                        RemindersOverviewView()
                    } label: {
                        Label("Erinnerungen", systemImage: "calendar.badge.clock")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Vorlauf", systemImage: "clock")
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
                        ) { editing in
                            // Beim Loslassen neu planen, nicht bei jedem Schritt.
                            if !editing { viewModel.scheduleReminderReplan() }
                        }
                        .tint(Color.freshGreen)
                        .accessibilityLabel("Vorlauf in Tagen")
                        .accessibilityValue("\(globalReminderDays) \(globalReminderDays == 1 ? "Tag" : "Tage")")
                        Text("FreshAlert meldet sich \(globalReminderDays) \(globalReminderDays == 1 ? "Tag" : "Tage") vor dem Haltbarkeitsdatum, um \(reminderTimeText). Gilt für alle Produkte ohne eigene Einstellung.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker(
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    ) {
                        Label("Uhrzeit", systemImage: "alarm")
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
                    Link(destination: Legal.openFoodFactsURL) {
                        LabeledContent("Produktdaten: Open Food Facts", value: "ODbL")
                    }
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

    private var reminderTimeText: String {
        ReminderTimeFormatting.string(hour: reminderHour, minute: reminderMinute)
    }

    /// Uhrzeit als Date für den DatePicker, gespeichert werden nur Stunde und Minute.
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let hour = components.hour ?? 9
                let minute = components.minute ?? 0
                guard hour != reminderHour || minute != reminderMinute else { return }
                reminderHour = hour
                reminderMinute = minute
                viewModel.scheduleReminderReplan()
            }
        )
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
