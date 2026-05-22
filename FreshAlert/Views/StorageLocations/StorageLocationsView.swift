import SwiftUI
import SwiftData

struct StorageLocationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    @State private var showAddSheet = false
    @State private var locationToEdit: StorageLocation?
    @State private var locationToDelete: StorageLocation?
    @State private var showSimpleDeleteAlert = false
    @State private var showItemsWarningAlert = false

    var body: some View {
        Group {
            if locations.isEmpty {
                emptyState
            } else {
                locationList
            }
        }
        .navigationTitle("Lagerorte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddStorageLocationView(existingCount: locations.count)
        }
        .sheet(item: $locationToEdit) { loc in
            AddStorageLocationView(editingLocation: loc, existingCount: locations.count)
        }
        // Simple delete (no items affected)
        .alert("Lagerort löschen?", isPresented: $showSimpleDeleteAlert, presenting: locationToDelete) { loc in
            Button("Löschen", role: .destructive) { delete(loc) }
            Button("Abbrechen", role: .cancel) {}
        } message: { loc in
            Text("\"\(loc.name)\" wird gelöscht.")
        }
        // Delete with items warning
        .alert("Lagerort hat noch Produkte", isPresented: $showItemsWarningAlert, presenting: locationToDelete) { loc in
            Button("Abbrechen", role: .cancel) {}
            Button("Trotzdem löschen", role: .destructive) { delete(loc) }
        } message: { loc in
            let count = loc.foodItems.count
            let produktWort = count == 1 ? "Produkt" : "Produkte"
            Text(
                "\"\(loc.name)\" enthält noch \(count) \(produktWort). " +
                "Diese Produkte werden nicht gelöscht, sind aber danach ohne Lagerort gespeichert."
            )
        }
    }

    private var locationList: some View {
        List {
            ForEach(locations) { loc in
                LocationRow(location: loc)
                    .contentShape(Rectangle())
                    .onTapGesture { locationToEdit = loc }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            locationToDelete = loc
                            if loc.foodItems.isEmpty {
                                showSimpleDeleteAlert = true
                            } else {
                                showItemsWarningAlert = true
                            }
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        Button {
                            locationToEdit = loc
                        } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }
            .onMove { from, to in
                var arr = locations
                arr.move(fromOffsets: from, toOffset: to)
                for (index, loc) in arr.enumerated() { loc.sortOrder = index }
                try? modelContext.save()
            }
        }
        .listStyle(.insetGrouped)
        .toolbar { EditButton() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Keine Lagerorte")
                .font(.title3.bold())
            Text("Erstelle Orte wie Kühlschrank, Tiefkühler oder Vorratsschrank.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Ersten Ort erstellen") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.freshGreen)
        }
        .padding()
    }

    private func delete(_ location: StorageLocation) {
        modelContext.delete(location)
        try? modelContext.save()
    }
}

struct LocationRow: View {
    let location: StorageLocation
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(location.color.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: location.iconName)
                    .font(.title3)
                    .foregroundStyle(location.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name).font(.subheadline.weight(.semibold))
                let count = location.foodItems.count
                Text(count == 0 ? "Keine Produkte" : "\(count) \(count == 1 ? "Produkt" : "Produkte")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
