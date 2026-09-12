import SwiftUI
import SwiftData
import UserNotifications

// First-launch setup wizard. Explains the app and lets the user pick the
// storage locations to start with. Shown only when no locations exist yet.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let onFinish: () -> Void

    @State private var page = 0
    // Alle Standardorte vorausgewählt, nur "Keller" nicht: den hat nicht jeder.
    @State private var selectedTemplates: Set<Int> = Set(
        StorageLocation.defaultTemplates.indices.filter {
            StorageLocation.defaultTemplates[$0].name != "Keller"
        }
    )
    @State private var notificationsGranted = false
    @State private var isRequestingNotifications = false

    private let lastPage = 4

    var body: some View {
        VStack(spacing: 0) {
            skipBar

            TabView(selection: $page) {
                infoPage(
                    icon: "leaf.circle.fill",
                    title: "Willkommen bei FreshAlert",
                    text: "Behalte den Überblick über deine Lebensmittel – und wirf nie wieder etwas weg, weil du es vergessen hast."
                ).tag(0)

                infoPage(
                    icon: "barcode.viewfinder",
                    title: "Schnell erfasst",
                    text: "Scanne den Barcode eines Produkts. Name, Marke und Bild werden automatisch geladen. Kein Barcode? Trag das Produkt einfach manuell ein."
                ).tag(1)

                reminderPage.tag(2)

                locationPage.tag(3)

                infoPage(
                    icon: "checkmark.circle.fill",
                    title: "Alles bereit!",
                    text: "Du kannst jetzt dein erstes Produkt hinzufügen. Lagerorte und Erinnerungen lassen sich jederzeit in den Einstellungen anpassen."
                ).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            primaryButton
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
        .task { await loadNotificationStatus() }
    }

    // MARK: - Bars

    private var skipBar: some View {
        HStack {
            Spacer()
            if page < lastPage {
                Button("Überspringen") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(height: 44)
    }

    private var primaryButton: some View {
        Button {
            if page < lastPage {
                withAnimation { page += 1 }
            } else {
                finish()
            }
        } label: {
            Text(page < lastPage ? "Weiter" : "Los geht’s")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.freshGreen)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Pages

    private func infoPage(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 88))
                .foregroundStyle(Color.freshGreen)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // Seite 3: Erinnerungen erklären und die Berechtigung per Knopf holen,
    // nicht automatisch beim Weiterblättern. "Weiter" geht auch ohne.
    private var reminderPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 88))
                .foregroundStyle(Color.freshGreen)
            Text("Rechtzeitig erinnert")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("FreshAlert benachrichtigt dich, bevor etwas abläuft. Wische ein Produkt nach links, sobald du es verbraucht hast.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            notificationButton

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var notificationButton: some View {
        if notificationsGranted {
            Label("Erinnerungen aktiv", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.freshGreen)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(Color.freshGreen.opacity(0.12))
                .clipShape(Capsule())
        } else {
            Button {
                Task { await requestNotifications() }
            } label: {
                Label("Erinnerungen aktivieren", systemImage: "bell.fill")
                    .font(.headline)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.freshGreen)
            .disabled(isRequestingNotifications)
        }
    }

    private var locationPage: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.freshGreen)
                    .padding(.top, 24)
                Text("Deine Lagerorte")
                    .font(.title.bold())
                Text("Wo bewahrst du Lebensmittel auf? Wähle aus – du kannst später jederzeit weitere hinzufügen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 8) {
                    ForEach(Array(StorageLocation.defaultTemplates.enumerated()), id: \.offset) { index, template in
                        templateRow(index: index, template: template)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func templateRow(index: Int, template: StorageLocationTemplate) -> some View {
        let isSelected = selectedTemplates.contains(index)
        let color = Color(hex: template.colorHex) ?? .freshGreen
        return Button {
            if isSelected { selectedTemplates.remove(index) }
            else { selectedTemplates.insert(index) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: template.iconName)
                        .font(.title3)
                        .foregroundStyle(color)
                }
                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.freshGreen : Color(.systemGray3))
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notifications

    private func loadNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsGranted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    private func requestNotifications() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        notificationsGranted = await NotificationService.shared.requestPermission()
    }

    // MARK: - Finish

    /// Legt die gewählten Lagerorte an. Beim Überspringen gilt die Vorauswahl.
    private func finish() {
        var sortOrder = 0
        for (index, template) in StorageLocation.defaultTemplates.enumerated() {
            guard selectedTemplates.contains(index) else { continue }
            modelContext.insert(
                StorageLocation(
                    name: template.name,
                    iconName: template.iconName,
                    colorHex: template.colorHex,
                    sortOrder: sortOrder
                )
            )
            sortOrder += 1
        }
        try? modelContext.save()
        onFinish()
    }
}
