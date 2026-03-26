import SwiftUI

struct FoodItemCardView: View {
    let item: FoodItem
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 12) {
                // Product Image
                productImage

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !item.brand.isEmpty {
                        Text(item.brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let loc = item.storageLocation {
                        HStack(spacing: 3) {
                            Image(systemName: loc.iconName)
                                .font(.caption2)
                            Text(loc.name)
                                .font(.caption)
                        }
                        .foregroundStyle(loc.color)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: item.expiryStatus.iconName)
                            .font(.caption)
                        Text(item.expiryLabel)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(item.expiryStatus.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.expiryStatus.backgroundColor)
                    .clipShape(Capsule())
                }

                Spacer()

                // Quantity badge + chevron
                VStack(alignment: .trailing, spacing: 8) {
                    if item.quantity > 1 {
                        Text("x\(item.quantity)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray2))
                            .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(item.expiryStatus.color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            FoodItemDetailView(item: item)
        }
    }

    @ViewBuilder
    private var productImage: some View {
        if let data = item.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if !item.imageURL.isEmpty, let url = URL(string: item.imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .frame(width: 62, height: 62)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Detail Sheet
struct FoodItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: AppViewModel
    let item: FoodItem

    @State private var editMode = false
    @State private var editedName: String = ""
    @State private var editedExpiryDate: Date = Date()
    @State private var editedQuantity: Int = 1
    @State private var editedReminderDays: Int? = nil
    @State private var editedLocation: StorageLocation? = nil

    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image
                    productImageHeader

                    // Info cards
                    infoSection

                    // Danger zone
                    dangerSection
                }
                .padding()
            }
            .navigationTitle(editMode ? "Bearbeiten" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editMode ? "Speichern" : "Bearbeiten") {
                        if editMode { saveEdits() }
                        else { startEditing() }
                        editMode.toggle()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var productImageHeader: some View {
        Group {
            if let data = item.imageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if !item.imageURL.isEmpty, let url = URL(string: item.imageURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(spacing: 12) {
            if editMode {
                // Editable fields
                LabeledContent("Name") {
                    TextField("Produktname", text: $editedName)
                        .multilineTextAlignment(.trailing)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                DatePicker("MHD", selection: $editedExpiryDate, displayedComponents: .date)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Stepper("Menge: \(editedQuantity)", value: $editedQuantity, in: 1...99)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Picker("Lagerort", selection: $editedLocation) {
                    Text("Kein Ort").tag(StorageLocation?.none)
                    ForEach(locations) { loc in
                        Text(loc.name).tag(StorageLocation?.some(loc))
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Individuelle Erinnerung", isOn: Binding(
                        get: { editedReminderDays != nil },
                        set: { if $0 { editedReminderDays = 7 } else { editedReminderDays = nil } }
                    ))
                    if let days = editedReminderDays {
                        Stepper("\(days) \(days == 1 ? "Tag" : "Tage") vorher",
                                value: Binding(get: { days }, set: { editedReminderDays = $0 }),
                                in: 1...30)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            } else {
                // Read-only
                DetailRow(label: "MHD", value: item.expiryDate.formatted(date: .long, time: .omitted))
                DetailRow(label: "Status", value: item.expiryLabel, color: item.expiryStatus.color)
                DetailRow(label: "Menge", value: "\(item.quantity)x")
                if !item.brand.isEmpty {
                    DetailRow(label: "Marke", value: item.brand)
                }
                if let loc = item.storageLocation {
                    DetailRow(label: "Lagerort", value: loc.name)
                }
                if let reminder = item.customReminderDays {
                    DetailRow(label: "Erinnerung", value: "\(reminder) Tage vorher")
                } else {
                    DetailRow(label: "Erinnerung", value: "Global (\(viewModel.globalReminderDays) Tage)")
                }
                DetailRow(label: "Hinzugefügt", value: item.addedAt.formatted(date: .abbreviated, time: .omitted))
                if item.isOfflineEntry {
                    DetailRow(label: "Status", value: "Offline – warte auf Sync", color: .orange)
                }
            }
        }
    }

    private var dangerSection: some View {
        Button(role: .destructive) {
            viewModel.deleteFoodItem(item)
            dismiss()
        } label: {
            Label("Produkt löschen", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func startEditing() {
        editedName = item.name
        editedExpiryDate = item.expiryDate
        editedQuantity = item.quantity
        editedReminderDays = item.customReminderDays
        editedLocation = item.storageLocation
    }

    private func saveEdits() {
        item.name = editedName
        item.expiryDate = editedExpiryDate
        item.quantity = editedQuantity
        item.customReminderDays = editedReminderDays
        item.storageLocation = editedLocation
        Task { await viewModel.updateFoodItem(item) }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
