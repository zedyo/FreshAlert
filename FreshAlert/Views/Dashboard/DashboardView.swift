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
    /// Chip "Ohne Ort": nur Produkte ohne Lagerort. Schließt `selectedLocationID` aus.
    @State private var filterWithoutLocation = false
    @State private var showReminders = false

    enum FilterOption {
        case all, expiringSoon, expired
    }

    /// Gibt es mindestens ein Produkt ohne Lagerort? Steuert den Chip "Ohne Ort".
    private var hasItemsWithoutLocation: Bool {
        allItems.contains { $0.storageLocation == nil }
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
        if filterWithoutLocation {
            items = items.filter { $0.storageLocation == nil }
        } else if let locID = selectedLocationID {
            items = items.filter { $0.storageLocation?.id == locID }
        }
        return items
    }

    var expiringThisWeek: Int { allItems.filter { $0.daysUntilExpiry >= 0 && $0.daysUntilExpiry <= 7 }.count }
    var expiredCount: Int     { allItems.filter { $0.daysUntilExpiry < 0 }.count }
    /// Heute fällig oder schon abgelaufen: die Zahl an der Glocke.
    var dueCount: Int         { allItems.filter { $0.daysUntilExpiry <= 0 }.count }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                // Interactive stat cards
                if !allItems.isEmpty {
                    Section {
                        statsRow
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .id("firstSection")
                }

                // Location chips (erst, wenn es Produkte gibt)
                if !locations.isEmpty && !allItems.isEmpty {
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
                                        Feedback.itemUsed()
                                    } label: {
                                        Label(
                                            item.quantity > 1 ? "1 verbraucht" : "Verbraucht",
                                            systemImage: "checkmark.circle.fill"
                                        )
                                    }
                                    .tint(Color.freshGreen)
                                }
                                // Kein Alert: "Rückgängig" im Toast deckt Fehlgriffe ab.
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.deleteFoodItem(item)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        viewModel.decrementQuantity(item)
                                        Feedback.itemUsed()
                                    } label: {
                                        Label(
                                            item.quantity > 1 ? "1 verbraucht" : "Verbraucht",
                                            systemImage: "checkmark.circle"
                                        )
                                    }
                                    Button(role: .destructive) {
                                        viewModel.deleteFoodItem(item)
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
            .searchableIf(!allItems.isEmpty, text: $searchText, prompt: "Produkt suchen …")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if viewModel.pendingSyncCount > 0 { syncBadge }
                        reminderBell
                    }
                }
            }
            .sheet(isPresented: $showReminders) {
                NavigationStack {
                    RemindersOverviewView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Fertig") { showReminders = false }
                            }
                        }
                }
            }
            .task {
                proxy.scrollTo("firstSection", anchor: .top)
            }
            .onAppear { applyPendingFilter() }
            .onChange(of: viewModel.pendingDashboardFilter) { _, _ in applyPendingFilter() }
            // Letztes Produkt ohne Ort zugeordnet: Chip verschwindet, Filter zurück auf "Alle Orte".
            .onChange(of: hasItemsWithoutLocation) { _, stillAny in
                if !stillAny && filterWithoutLocation {
                    withAnimation { filterWithoutLocation = false }
                }
            }
            } // ScrollViewReader
        }
    }

    /// Von einer angetippten Mitteilung vorgemerkt: Kachel "Bald ablaufend" setzen,
    /// dann das Feld leeren. Nicht im View-Update zurücksetzen, sonst warnt SwiftUI.
    private func applyPendingFilter() {
        guard let pending = viewModel.pendingDashboardFilter else { return }
        switch pending {
        case .expiringSoon:
            withAnimation(.spring(response: 0.3)) { selectedFilter = .expiringSoon }
        }
        DispatchQueue.main.async { viewModel.pendingDashboardFilter = nil }
    }

    // MARK: - Subviews

    private var reminderBell: some View {
        Button {
            showReminders = true
        } label: {
            Image(systemName: "bell")
                .font(.body)
                .overlay(alignment: .topTrailing) {
                    if dueCount > 0 {
                        Text(dueCount > 99 ? "99+" : "\(dueCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .accessibilityLabel(
            dueCount == 0
                ? "Erinnerungen"
                : "Erinnerungen, \(dueCount) \(dueCount == 1 ? "Produkt" : "Produkte") heute fällig oder abgelaufen"
        )
    }

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
                FilterChip(title: "Alle Orte", isSelected: selectedLocationID == nil && !filterWithoutLocation) {
                    withAnimation {
                        selectedLocationID = nil
                        filterWithoutLocation = false
                    }
                }
                ForEach(locations) { loc in
                    LocationChip(location: loc, isSelected: selectedLocationID == loc.id && !filterWithoutLocation) {
                        withAnimation {
                            selectedLocationID = loc.id
                            filterWithoutLocation = false
                        }
                    }
                }
                if hasItemsWithoutLocation {
                    NoLocationChip(isSelected: filterWithoutLocation) {
                        withAnimation {
                            selectedLocationID = nil
                            filterWithoutLocation = true
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if allItems.isEmpty {
            // Noch gar nichts erfasst: direkt zum Scanner führen.
            VStack(spacing: 16) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                Text("Noch keine Produkte")
                    .font(.title3.weight(.semibold))
                Text("Scanne den Barcode eines Produkts, FreshAlert erinnert dich, bevor es abläuft.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    viewModel.selectedTab = 1
                } label: {
                    Label("Ersten Barcode scannen", systemImage: "barcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.freshGreen)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.horizontal, 32)
        } else {
            // Es gibt Produkte, aber Suche oder Filter treffen nichts.
            VStack(spacing: 16) {
                Image(systemName: searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                Text("Keine Ergebnisse")
                    .font(.title3.weight(.semibold))
                Text(searchText.isEmpty
                     ? "In dieser Auswahl gibt es gerade nichts."
                     : "Versuche einen anderen Suchbegriff.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.horizontal, 32)
        }
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

private extension View {
    /// Suchfeld nur zeigen, wenn es etwas zu suchen gibt.
    @ViewBuilder
    func searchableIf(_ condition: Bool, text: Binding<String>, prompt: String) -> some View {
        if condition {
            searchable(text: text, placement: .automatic, prompt: prompt)
        } else {
            self
        }
    }
}

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
                .background(isSelected ? Color.freshGreen : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Grauer Chip ganz rechts: filtert auf Produkte ohne Lagerort.
struct NoLocationChip: View {
    let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle").font(.caption)
                Text("Ohne Ort").font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? Color(.systemGray) : Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
