import SwiftUI
import SwiftData
import StoreKit
import UserNotifications

/// Entwicklermenü, nur in Debug- und TestFlight-Builds erreichbar
/// (siehe `AppEnvironment.isDeveloperMenuAvailable`).
struct DeveloperMenuView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var store: StoreManager
    @ObservedObject private var environment = AppEnvironmentObserver.shared

    @State private var entitlements: [EntitlementRow] = []
    @State private var isSyncingPurchases = false
    @State private var purchaseMessage: String?
    @State private var showManageSubscriptions = false
    @State private var pendingRequests: [PendingReminder] = []
    @State private var isWorking = false
    @State private var showDeleteItemsConfirm = false
    @State private var showResetConfirm = false
    @State private var showScreenshotConfirm = false

    private static let maxPendingNotifications = 64
    private let productCount = TestDataSeeder.productCount
    private let screenshotProductCount = TestDataSeeder.screenshotProductCount

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    "Umgebung",
                    value: "\(environment.environmentName), Version \(AppEnvironment.versionDescription)"
                )
            }

            purchaseSections

            Section {
                Button {
                    runSeed()
                } label: {
                    Label("\(productCount) Testprodukte laden", systemImage: "square.and.arrow.down")
                }
                Button {
                    showScreenshotConfirm = true
                } label: {
                    Label("Screenshot-Daten laden", systemImage: "camera.viewfinder")
                }
                .confirmationDialog(
                    "Bestand durch die Screenshot-Daten ersetzen? Produkte, Lagerorte und Statistik werden vorher gelöscht.",
                    isPresented: $showScreenshotConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Ersetzen", role: .destructive) {
                        runSeed(fileName: TestDataSeeder.screenshotFileName)
                    }
                    Button("Abbrechen", role: .cancel) {}
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
                        Task {
                            await TestDataSeeder.deleteAllItems(in: modelContext, viewModel: viewModel)
                            await loadPendingRequests()
                        }
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
                Text("Die Screenshot-Daten ersetzen den Bestand durch \(screenshotProductCount) kuratierte Produkte für die App-Store-Bilder. Zurücksetzen löscht Produkte, Lagerorte, Erinnerungen und Widget-Daten. Beim nächsten Start kommt das Onboarding.")
            }
            .disabled(isWorking)

            Section {
                if pendingRequests.isEmpty {
                    Text("Keine geplanten Erinnerungen")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingRequests) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                                .font(.subheadline.weight(.medium))
                            Text(reminder.body)
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
                Text("Eine Tagesmitteilung je Kalendertag, höchstens \(ReminderDigestPlanner.maxRequests). iOS hält höchstens \(Self.maxPendingNotifications) geplante Mitteilungen pro App.")
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
            store.applyEntitlements()
            await loadEntitlements()
            await loadPendingRequests()
        }
        .refreshable {
            await loadEntitlements()
            await loadPendingRequests()
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .onChange(of: showManageSubscriptions) { _, isShown in
            guard !isShown else { return }
            Task {
                await store.refreshPurchaseStatus()
                await loadEntitlements()
            }
        }
    }

    // MARK: - Käufe testen

    @ViewBuilder
    private var purchaseSections: some View {
        Section {
            if entitlements.isEmpty {
                Text("Keine aktiven Käufe")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entitlements) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(row.productID) · \(row.typeText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(row.details, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button {
                Task { await reloadPurchases() }
            } label: {
                Label("Käufe neu laden", systemImage: "arrow.clockwise")
            }
            .disabled(isSyncingPurchases)
            if let purchaseMessage {
                Text(purchaseMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Käufe testen")
        } footer: {
            Text("Aktive Käufe laut StoreKit. „Käufe neu laden“ gleicht mit dem App Store ab und fragt dabei eventuell nach der Apple-ID.")
        }

        Section {
            Toggle("Als Gratis-Nutzer anzeigen", isOn: $store.simulatesFreeUser)
            LabeledContent("Pro in der App", value: proStatusText)
        } footer: {
            Text("Nur in diesem Build und nur auf diesem Gerät: Die App behandelt dich wie einen Gratis-Nutzer, mit Limit von \(StoreManager.freeLimit) Produkten und Paywall. Der echte Kauf bleibt bestehen. Apples Kaufdialog kann deshalb melden, dass du das Produkt schon gekauft hast oder das Abo bereits aktiv ist.")
        }

        Section {
            Button {
                showManageSubscriptions = true
            } label: {
                Label("Abo bei Apple verwalten", systemImage: "creditcard")
            }
        } footer: {
            Text("Hier lässt sich das TestFlight-Abo kündigen und nach dem Ablauf neu abschließen. In TestFlight verlängern sich Abos deutlich schneller als im App Store, ein Jahresabo läuft dort nach kurzer Zeit ab. Der Einmalkauf lässt sich nicht zurücknehmen.")
        }
    }

    private var proStatusText: String {
        if store.isPro { return "Pro" }
        return store.hasProEntitlement ? "Gratis (simuliert)" : "Gratis"
    }

    private func reloadPurchases() async {
        guard !isSyncingPurchases else { return }
        isSyncingPurchases = true
        purchaseMessage = nil
        do {
            try await store.syncPurchases()
            purchaseMessage = "Käufe neu geladen."
        } catch StoreKitError.userCancelled {
            purchaseMessage = "Abgebrochen."
        } catch {
            purchaseMessage = "Neu laden fehlgeschlagen: \(error.localizedDescription)"
        }
        await loadEntitlements()
        isSyncingPurchases = false
    }

    private func loadEntitlements() async {
        var rows: [EntitlementRow] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            let transaction: StoreKit.Transaction
            let isVerified: Bool
            switch result {
            case .verified(let tx):
                transaction = tx
                isVerified = true
            case .unverified(let tx, _):
                transaction = tx
                isVerified = false
            }
            var willAutoRenew: Bool?
            if transaction.productType == .autoRenewable,
               let status = await transaction.subscriptionStatus,
               case .verified(let renewalInfo) = status.renewalInfo {
                willAutoRenew = renewalInfo.willAutoRenew
            }
            let name = store.products.first { $0.id == transaction.productID }?.displayName
            rows.append(EntitlementRow(
                transaction: transaction,
                name: name,
                isVerified: isVerified,
                willAutoRenew: willAutoRenew
            ))
        }
        entitlements = rows.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private func runSeed(fileName: String = TestDataSeeder.defaultFileName) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            if fileName == TestDataSeeder.screenshotFileName {
                await TestDataSeeder.seedScreenshotData(into: modelContext, viewModel: viewModel)
            } else {
                await TestDataSeeder.seed(into: modelContext, viewModel: viewModel, fileName: fileName)
            }
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

private struct EntitlementRow: Identifiable {
    let id: UInt64
    let productID: String
    let name: String
    let typeText: String
    let purchaseDate: Date
    let details: [String]

    init(transaction: StoreKit.Transaction, name: String?, isVerified: Bool, willAutoRenew: Bool?) {
        id = transaction.id
        productID = transaction.productID
        self.name = name ?? transaction.productID
        purchaseDate = transaction.purchaseDate

        switch transaction.productType {
        case .autoRenewable: typeText = "Abo"
        case .nonConsumable: typeText = "Einmalkauf"
        case .nonRenewable: typeText = "Abo ohne Verlängerung"
        case .consumable: typeText = "Verbrauchsartikel"
        default: typeText = "Unbekannter Typ"
        }

        let environmentText: String
        switch transaction.environment {
        case .sandbox: environmentText = "Sandbox"
        case .xcode: environmentText = "Xcode"
        case .production: environmentText = "Production"
        default: environmentText = transaction.environment.rawValue
        }

        var lines = [
            "Gekauft: \(transaction.purchaseDate.formatted(date: .abbreviated, time: .shortened))"
        ]
        if let expiration = transaction.expirationDate {
            lines.append("Läuft ab: \(expiration.formatted(date: .abbreviated, time: .shortened))")
        }
        if let willAutoRenew {
            lines.append(willAutoRenew ? "Verlängert sich automatisch" : "Gekündigt, verlängert sich nicht")
        }
        lines.append("Umgebung: \(environmentText)")
        if let revocation = transaction.revocationDate {
            lines.append("Widerrufen: \(revocation.formatted(date: .abbreviated, time: .shortened))")
        }
        if !isVerified {
            lines.append("Nicht verifiziert")
        }
        details = lines
    }
}

private struct PendingReminder: Identifiable {
    let id: String
    let title: String
    let body: String
    let date: Date?

    init(_ request: UNNotificationRequest) {
        id = request.identifier
        title = request.content.title
        body = request.content.body
        date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }

    var dateText: String {
        guard let date else { return "Ohne Datum" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
