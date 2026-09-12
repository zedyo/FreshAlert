import SwiftUI
import SwiftData
import UserNotifications

/// Entwicklermenü, nur in Debug- und TestFlight-Builds erreichbar
/// (siehe `AppEnvironment.isDeveloperMenuAvailable`).
struct DeveloperMenuView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var environment = AppEnvironmentObserver.shared

    @State private var pendingRequests: [PendingReminder] = []
    @State private var isWorking = false
    @State private var showDeleteItemsConfirm = false
    @State private var showResetConfirm = false

    private static let maxPendingNotifications = 64
    private let productCount = TestDataSeeder.productCount

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    "Umgebung",
                    value: "\(environment.environmentName), Version \(AppEnvironment.versionDescription)"
                )
            }

            Section {
                Button {
                    runSeed()
                } label: {
                    Label("\(productCount) Testprodukte laden", systemImage: "square.and.arrow.down")
                }
                Button {
                    showDeleteItemsConfirm = true
                } label: {
                    Label("Alle Produkte löschen", systemImage: "trash")
                }
                .confirmationDialog(
                    "Alle Produkte löschen? Die Lagerorte bleiben erhalten.",
                    isPresented: $showDeleteItemsConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Produkte löschen", role: .destructive) {
                        TestDataSeeder.deleteAllItems(in: modelContext, viewModel: viewModel)
                        Task { await loadPendingRequests() }
                    }
                    Button("Abbrechen", role: .cancel) {}
                }
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("App zurücksetzen", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
                .confirmationDialog(
                    "Alles löschen? Das lässt sich nicht rückgängig machen.",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Alles löschen", role: .destructive) {
                        TestDataSeeder.resetApp(in: modelContext, viewModel: viewModel)
                        Task { await loadPendingRequests() }
                    }
                    Button("Abbrechen", role: .cancel) {}
                }
            } header: {
                Text("Testdaten")
            } footer: {
                Text("Zurücksetzen löscht Produkte, Lagerorte, Erinnerungen und Widget-Daten. Beim nächsten Start kommt das Onboarding.")
            }
            .disabled(isWorking)

            Section {
                if pendingRequests.isEmpty {
                    Text("Keine geplanten Erinnerungen")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingRequests) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.productName)
                                .font(.subheadline.weight(.medium))
                            Text(reminder.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(reminder.dateText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Geplante Erinnerungen (\(pendingRequests.count) von \(Self.maxPendingNotifications))")
            } footer: {
                Text("iOS hält höchstens \(Self.maxPendingNotifications) geplante Mitteilungen pro App, die frühesten zuerst.")
            }
        }
        .navigationTitle("Entwicklermenü")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking {
                ProgressView("Testprodukte werden geladen …")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            await environment.refresh()
            await loadPendingRequests()
        }
        .refreshable { await loadPendingRequests() }
    }

    private func runSeed() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await TestDataSeeder.seed(into: modelContext, viewModel: viewModel)
            await loadPendingRequests()
            isWorking = false
        }
    }

    private func loadPendingRequests() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingRequests = requests
            .map(PendingReminder.init)
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}

private struct PendingReminder: Identifiable {
    let id: String
    let title: String
    let productName: String
    let date: Date?

    init(_ request: UNNotificationRequest) {
        id = request.identifier
        title = request.content.title
        date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        let body = request.content.body
        if let range = body.range(of: " läuft ") {
            productName = String(body[..<range.lowerBound])
        } else {
            productName = body
        }
    }

    var dateText: String {
        guard let date else { return "Ohne Datum" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
