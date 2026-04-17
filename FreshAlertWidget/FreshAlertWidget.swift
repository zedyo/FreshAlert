import WidgetKit
import SwiftUI

// MARK: - Timeline

struct FreshAlertEntry: TimelineEntry {
    let date: Date
    let items: [WidgetFoodItem]
}

struct FreshAlertTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FreshAlertEntry {
        FreshAlertEntry(date: Date(), items: Self.sampleItems)
    }

    func getSnapshot(in context: Context, completion: @escaping (FreshAlertEntry) -> Void) {
        let items = WidgetDataStore.loadItems()
        completion(FreshAlertEntry(date: Date(), items: items.isEmpty ? Self.sampleItems : items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FreshAlertEntry>) -> Void) {
        let items = WidgetDataStore.loadItems()
        let entry = FreshAlertEntry(date: Date(), items: items)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    static var sampleItems: [WidgetFoodItem] = [
        WidgetFoodItem(id: UUID(), name: "Milch", brand: "Landliebe",
                       expiryDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                       quantity: 1, locationName: "Kühlschrank", locationIconName: "thermometer.snowflake"),
        WidgetFoodItem(id: UUID(), name: "Joghurt", brand: "Müller",
                       expiryDate: Date(), quantity: 2,
                       locationName: "Kühlschrank", locationIconName: "thermometer.snowflake"),
        WidgetFoodItem(id: UUID(), name: "Käse", brand: "Arla",
                       expiryDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())!,
                       quantity: 1, locationName: nil, locationIconName: nil),
        WidgetFoodItem(id: UUID(), name: "Butter", brand: "",
                       expiryDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())!,
                       quantity: 1, locationName: "Kühlschrank", locationIconName: "thermometer.snowflake"),
        WidgetFoodItem(id: UUID(), name: "Orangensaft", brand: "Tropicana",
                       expiryDate: Calendar.current.date(byAdding: .day, value: 12, to: Date())!,
                       quantity: 3, locationName: "Kühlschrank", locationIconName: "thermometer.snowflake"),
    ]
}

// MARK: - Widget View

struct FreshAlertWidgetEntryView: View {
    let entry: FreshAlertEntry

    // Expired first, then soonest, max 10
    var displayItems: [WidgetFoodItem] {
        Array(entry.items.sorted { $0.expiryDate < $1.expiryDate }.prefix(10))
    }

    var body: some View {
        if displayItems.isEmpty {
            emptyView
        } else {
            largeView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: WidgetDataStore.defaults == nil ? "exclamationmark.triangle" : "cart.badge.checkmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(WidgetDataStore.defaults == nil ? "App Group nicht konfiguriert" : "Keine Produkte")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if WidgetDataStore.defaults == nil {
                Text("In Xcode: beide Targets → Signing & Capabilities → App Groups → group.com.freshalert.app")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill, for: .widget)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "refrigerator.fill")
                    .foregroundStyle(Color(red: 0.36, green: 0.68, blue: 0.89))
                    .font(.subheadline.weight(.semibold))
                Text("FreshAlert")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(displayItems.count) Produkte")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 7)

            Divider().padding(.horizontal, 14)

            ForEach(Array(displayItems.enumerated()), id: \.element.id) { idx, item in
                itemRow(item)
                if idx < displayItems.count - 1 {
                    Divider()
                        .padding(.leading, 30)
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(.fill, for: .widget)
    }

    private func itemRow(_ item: WidgetFoodItem) -> some View {
        let days = item.daysUntilExpiry
        let statusColor: Color = days < 0 ? Color(.systemGray) : days <= 1 ? .red : days <= 7 ? .orange : Color(red: 0.2, green: 0.78, blue: 0.2)

        return HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if item.quantity > 1 {
                    Text("\(item.quantity)×")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(item.expiryLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())

            Button(intent: MarkAsUsedIntent(itemID: item.id.uuidString)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}

// MARK: - Widget Configuration

struct FreshAlertWidget: Widget {
    let kind = "FreshAlertWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FreshAlertTimelineProvider()) { entry in
            FreshAlertWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("FreshAlert")
        .description("Die 10 nächsten ablaufenden Produkte auf einen Blick.")
        .supportedFamilies([.systemLarge])
    }
}
