import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @AppStorage("globalReminderDays") private var globalReminderDays: Int = 7
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showRescheduleConfirm = false
    @State private var showRescheduleDone = false

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

                // Wiederherstellung verlorener Produkte
                if !viewModel.orphanedNotifications.isEmpty {
                    Section {
                        ForEach(viewModel.orphanedNotifications) { orphan in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(orphan.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("Ablauf: \(orphan.expiryDate, format: .dateTime.day().month().year())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Button {
                                        Task { await viewModel.recoverOrphanedItem(orphan) }
                                    } label: {
                                        Label("Wiederherstellen", systemImage: "arrow.uturn.backward.circle.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color.freshGreen)
                                    Button {
                                        viewModel.dismissOrphanedItem(orphan)
                                    } label: {
                                        Label("Verwerfen", systemImage: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        }
                        if viewModel.orphanedNotifications.count > 1 {
                            Button(role: .destructive) {
                                viewModel.dismissAllOrphanedNotifications()
                            } label: {
                                Label("Alle verwerfen", systemImage: "trash")
                            }
                        }
                    } header: {
                        Label("Vermisste Produkte (\(viewModel.orphanedNotifications.count))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("Diese Produkte sind aus der Liste verschwunden, ihre Erinnerungen sind aber noch geplant. Wiederherstellen legt Name + Ablaufdatum neu an (andere Felder bleiben leer).")
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

                // About
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                    LabeledContent("Produktdaten", value: "Open Food Facts")
                    LabeledContent("Minimales iOS", value: "iOS 17.0")
                } header: {
                    Text("Über FreshAlert")
                }
            }
            .navigationTitle("Einstellungen")
            .task { await loadNotifStatus() }
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
