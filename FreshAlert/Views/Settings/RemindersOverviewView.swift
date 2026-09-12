import SwiftUI
import SwiftData

/// Zeigt, wann FreshAlert sich meldet: eine Tagesmitteilung je Kalendertag,
/// gruppiert wie der Planer sie tatsächlich bei iOS anmeldet. Nur Anzeige,
/// die Zeilen sind kein Tipp-Ziel.
struct RemindersOverviewView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Query(sort: \FoodItem.expiryDate) private var items: [FoodItem]
    @AppStorage("globalReminderDays") private var globalReminderDays: Int = 7
    @AppStorage("reminderHour") private var reminderHour: Int = 9
    @AppStorage("reminderMinute") private var reminderMinute: Int = 0

    private let planner = ReminderDigestPlanner()
    private let now = Date()

    private var plan: [PlannedReminder] {
        planner.plan(
            products: NotificationService.products(from: items),
            now: now,
            globalReminderDays: globalReminderDays,
            hour: reminderHour,
            minute: reminderMinute
        )
    }

    private var itemsByID: [UUID: FoodItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var expiredItems: [FoodItem] {
        items.filter { $0.daysUntilExpiry < 0 }
    }

    private var timeText: String {
        ReminderTimeFormatting.string(hour: reminderHour, minute: reminderMinute)
    }

    private var leadText: String {
        "\(globalReminderDays) \(globalReminderDays == 1 ? "Tag" : "Tage")"
    }

    var body: some View {
        Group {
            if plan.isEmpty && expiredItems.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Erinnerungen", systemImage: "bell.slash")
                } description: {
                    Text("Sobald du Produkte anlegst, siehst du hier, wann FreshAlert sich meldet.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        let plan = self.plan
        let byID = itemsByID
        return List {
            Section {
                if let next = plan.first {
                    Text("Nächste Mitteilung: \(planner.dayLabel(for: next.day, now: now)), \(timeText), \(next.productCount) \(next.productCount == 1 ? "Produkt" : "Produkte")")
                        .font(.headline)
                } else {
                    Text("Keine Mitteilung in den nächsten \(ReminderDigestPlanner.horizonDays) Tagen")
                        .font(.headline)
                }
                LabeledContent("Uhrzeit", value: timeText)
                LabeledContent("Vorlauf", value: "\(leadText) vorher")
            }

            if !expiredItems.isEmpty {
                Section {
                    ForEach(expiredItems) { item in
                        row(for: item)
                    }
                } header: {
                    Text("Abgelaufen").foregroundStyle(.red)
                }
            }

            ForEach(plan) { reminder in
                Section {
                    ForEach(reminder.allProducts) { product in
                        if let item = byID[product.id] {
                            row(for: item)
                        }
                    }
                } header: {
                    Text(planner.dayLabel(for: reminder.day, now: now))
                } footer: {
                    if reminder.id == plan.last?.id {
                        Text("Erinnerungen gelten für alle Produkte, \(leadText) vorher. Eigene Vorlaufzeit setzt du beim Bearbeiten eines Produkts.")
                    }
                }
            }
        }
    }

    private func row(for item: FoodItem) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.expiryLabel)
                    .font(.caption)
                    .foregroundStyle(item.expiryStatus.color)
            }
            Spacer()
            leadBadge(for: item)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func thumbnail(for item: FoodItem) -> some View {
        Group {
            if let data = item.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.storageLocation?.iconName ?? "carrot")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func leadBadge(for item: FoodItem) -> some View {
        if let custom = item.customReminderDays {
            HStack(spacing: 3) {
                Image(systemName: "bell.badge")
                Text("\(custom) T.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Eigene Vorlaufzeit: \(custom) \(custom == 1 ? "Tag" : "Tage")")
        } else {
            Image(systemName: "bell")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Standardvorlauf")
        }
    }
}
