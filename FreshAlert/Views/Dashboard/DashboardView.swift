import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: AppViewModel
    @Query(sort: \FoodItem.expiryDate, order: .forward) private var allItems: [FoodItem]
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all
    @State private var selectedLocationID: UUID?
    @State private var itemToDelete: FoodItem?
    @State private var showDeleteAlert = false

    enum FilterOption: String, CaseIterable {
        case all          = "Alle"
        case expiringSoon = "Bald ablaufend"
        case expired      = "Abgelaufen"
    }

    var filteredItems: [FoodItem] {
        var items = allItems
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.brand.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch selectedFilter {
        case .all: break
        case .expiringSoon: items = items.filter { $0.daysUntilExpiry >= 0 && $0.daysUntilExpiry <= 7 }
        case .expired:      items = items.filter { $0.daysUntilExpiry < 0 }
        }
        if let locID = selectedLocationID {
            items = items.filter { $0.storageLocation?.id == locID }
        }
        return items
    }

    var expiringThisWeek: Int { allItems.filter { $0.daysUntilExpiry >= 0 && $0.daysUntilExpiry <= 7 }.count }
    var expiredCount: Int     { allItems.filter { $0.daysUntilExpiry < 0 }.count }

    var body: some View {
        NavigationStack {
            List {
                // Stats
                if !allItems.isEmpty {
                    Section {
                        statsRow
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }

                // Filter + Location chips
                Section {
                    filterBar
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init())
                    if !locations.isEmpty {
                        locationBar
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init())
                    }
                }

                // Items
                if filteredItems.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(filteredItems) { item in
                            FoodItemCardView(item: item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                // Swipe LEFT → trailing → "Verwendet"
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        viewModel.decrementQuantity(item)
                                    } label: {
                                        Label(
                                            item.quantity > 1 ? "1 verwendet" : "Verwendet",
                                            systemImage: "checkmark.circle.fill"
                                        )
                                    }
                                    .tint(Color(red: 0.2, green: 0.78, blue: 0.2))
                                }
                                // Swipe RIGHT → leading → Löschen
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        viewModel.decrementQuantity(item)
                                    } label: {
                                        Label(
                                            item.quantity > 1 ? "1 Exemplar verbraucht" : "Als verwendet markieren",
                                            systemImage: "checkmark.circle"
                                        )
                                    }
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FreshAlert")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Produkt suchen …")
            .toolbar {
                if viewModel.pendingSyncCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        syncBadge
                    }
                }
            }
            .alert("Produkt löschen?", isPresented: $showDeleteAlert, presenting: itemToDelete) { item in
                Button("Löschen", role: .destructive) { viewModel.deleteFoodItem(item) }
                Button("Abbrechen", role: .cancel) {}
            } message: { item in
                Text("\"\(item.name)\" wird aus der Liste entfernt.")
            }
        }
    }

    // MARK: - Subviews

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(allItems.count)",       label: "Produkte",       icon: "cart.fill",                    color: .blue)
            StatCard(value: "\(expiringThisWeek)",     label: "Bald ablaufend", icon: "exclamationmark.triangle.fill", color: .orange)
            StatCard(value: "\(expiredCount)",         label: "Abgelaufen",     icon: "xmark.circle.fill",            color: .red)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    FilterChip(title: option.rawValue, isSelected: selectedFilter == option) {
                        withAnimation(.spring(response: 0.3)) { selectedFilter = option }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var locationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "Alle Orte", isSelected: selectedLocationID == nil) {
                    withAnimation { selectedLocationID = nil }
                }
                ForEach(locations) { loc in
                    LocationChip(location: loc, isSelected: selectedLocationID == loc.id) {
                        withAnimation { selectedLocationID = loc.id }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: searchText.isEmpty ? "cart.badge.plus" : "magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "Noch keine Produkte" : "Keine Ergebnisse")
                .font(.title3.weight(.semibold))
            Text(searchText.isEmpty
                 ? "Scanne einen Barcode unter \"Scannen\" um zu beginnen."
                 : "Versuche einen anderen Suchbegriff.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 32)
    }

    private var syncBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
            Text("\(viewModel.pendingSyncCount)").font(.caption.bold())
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Helper Components

struct StatCard: View {
    let value: String; let label: String; let icon: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Image(systemName: icon).foregroundStyle(color).font(.caption); Spacer() }
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FilterChip: View {
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isSelected ? Color(red: 0.2, green: 0.78, blue: 0.2) : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LocationChip: View {
    let location: StorageLocation; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: location.iconName).font(.caption)
                Text(location.name).font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? location.color : Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
