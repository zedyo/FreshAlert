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
    @State private var isSearchPresented = false

    enum FilterOption {
        case all, expiringSoon, expired
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
                // Interactive stat cards (replace filter chips)
                if !allItems.isEmpty {
                    Section {
                        statsRow
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }

                // Location chips
                if !locations.isEmpty {
                    Section {
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
            // Hidden by default — appears only when search icon tapped
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .automatic,
                prompt: "Produkt suchen …"
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        if viewModel.pendingSyncCount > 0 { syncBadge }
                        Button {
                            withAnimation { isSearchPresented.toggle() }
                        } label: {
                            Image(systemName: isSearchPresented ? "xmark.circle.fill" : "magnifyingglass")
                                .foregroundStyle(isSearchPresented ? Color.secondary : Color.primary)
                        }
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
            InteractiveStatCard(
                value: "\(allItems.count)",
                label: "Produkte",
                icon: "cart.fill",
                color: .blue,
                isSelected: selectedFilter == .all
            ) {
                withAnimation(.spring(response: 0.3)) { selectedFilter = .all }
            }
            InteractiveStatCard(
                value: "\(expiringThisWeek)",
                label: "Bald ablaufend",
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                isSelected: selectedFilter == .expiringSoon
            ) {
                withAnimation(.spring(response: 0.3)) { selectedFilter = .expiringSoon }
            }
            InteractiveStatCard(
                value: "\(expiredCount)",
                label: "Abgelaufen",
                icon: "xmark.circle.fill",
                color: .red,
                isSelected: selectedFilter == .expired
            ) {
                withAnimation(.spring(response: 0.3)) { selectedFilter = .expired }
            }
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

struct InteractiveStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(isSelected ? .white : color)
                        .font(.caption)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? color : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
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
