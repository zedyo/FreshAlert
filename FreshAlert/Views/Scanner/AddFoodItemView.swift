import SwiftUI
import SwiftData

struct AddFoodItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: AppViewModel

    let barcode: String

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var imageURL: String = ""
    @State private var expiryDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var quantity: Int = 1
    @State private var selectedLocation: StorageLocation? = nil
    @State private var useCustomReminder = false
    @State private var customReminderDays: Int = 7
    @State private var isLoadingProduct: Bool
    @State private var productNotFound = false

    init(barcode: String) {
        self.barcode = barcode
        _isLoadingProduct = State(initialValue: !barcode.isEmpty)
    }
    @State private var showLocationPicker = false

    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    private let quickExpiry: [(label: String, days: Int)] = [
        ("3 Tage", 3), ("1 Woche", 7), ("2 Wochen", 14),
        ("1 Monat", 30), ("3 Monate", 90), ("6 Monate", 180), ("1 Jahr", 365)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    productInfoHeader
                } header: {
                    Text("Produkt")
                }

                Section {
                    TextField("Produktname *", text: $name)
                    TextField("Marke (optional)", text: $brand)
                } header: {
                    Text("Details")
                }

                // Menge ABOVE Ablaufdatum
                Section {
                    Stepper("Menge: \(quantity)", value: $quantity, in: 1...99)
                } header: {
                    Text("Menge")
                }

                Section {
                    quickExpiryRow
                    DatePicker(
                        "Mindesthaltbarkeitsdatum",
                        selection: $expiryDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(Color(red: 0.2, green: 0.78, blue: 0.2))
                } header: {
                    Text("Ablaufdatum")
                }

                if !locations.isEmpty {
                    Section {
                        Picker("Lagerort", selection: $selectedLocation) {
                            Label("Kein Ort", systemImage: "questionmark").tag(StorageLocation?.none)
                            ForEach(locations) { loc in
                                Label(loc.name, systemImage: loc.iconName)
                                    .tag(StorageLocation?.some(loc))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text("Lagerort")
                    }
                }

                Section {
                    Toggle("Individuelle Erinnerung", isOn: $useCustomReminder.animation())
                    if useCustomReminder {
                        Stepper(
                            "\(customReminderDays) \(customReminderDays == 1 ? "Tag" : "Tage") vorher",
                            value: $customReminderDays, in: 1...30
                        )
                    } else {
                        Text("Global: \(viewModel.globalReminderDays) Tage vorher")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } header: {
                    Text("Erinnerung")
                }

                if !viewModel.isOnline {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash").foregroundStyle(.orange)
                            Text("Offline gespeichert – Produktinfos werden beim nächsten Online-Gang ergänzt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Produkt hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Speichern") { saveItem() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { await loadProduct() }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerSheet(locations: locations) { chosen in
                    performSave(location: chosen)
                }
            }
        }
    }

    // MARK: - Product Info Header
    private var productInfoHeader: some View {
        HStack(spacing: 12) {
            if !imageURL.isEmpty, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        productPlaceholder
                    }
                }
            } else {
                productPlaceholder
            }

            VStack(alignment: .leading, spacing: 4) {
                if barcode.isEmpty {
                    Text("Produktdaten manuell eingeben")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if isLoadingProduct {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("Produkt wird gesucht …")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if productNotFound {
                    Text("Produkt nicht gefunden")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Bitte Namen manuell eingeben.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    Text(name.isEmpty ? "Unbekannt" : name)
                        .font(.subheadline.weight(.semibold))
                    if !brand.isEmpty {
                        Text(brand).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !barcode.isEmpty {
                    Text("Barcode: \(barcode)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var productPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .frame(width: 64, height: 64)
            .overlay(Image(systemName: barcode.isEmpty ? "pencil" : "barcode").foregroundStyle(.secondary))
    }

    // MARK: - Quick Expiry
    private var quickExpiryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickExpiry, id: \.days) { option in
                    let targetDate = Calendar.current.date(byAdding: .day, value: option.days, to: Date()) ?? Date()
                    let isSelected = Calendar.current.isDate(expiryDate, inSameDayAs: targetDate)
                    Button {
                        withAnimation(.spring(response: 0.25)) { expiryDate = targetDate }
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(isSelected
                                ? Color(red: 0.2, green: 0.78, blue: 0.2)
                                : Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions
    private func loadProduct() async {
        guard !barcode.isEmpty else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        guard viewModel.isOnline else { productNotFound = true; return }
        if let info = await viewModel.fetchProductInfo(barcode: barcode) {
            name     = info.name
            brand    = info.brand
            imageURL = info.imageURL ?? ""
        } else {
            productNotFound = true
        }
    }

    private func saveItem() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // If no location chosen and locations exist → show picker
        if selectedLocation == nil && !locations.isEmpty {
            showLocationPicker = true
            return
        }
        performSave(location: selectedLocation)
    }

    private func performSave(location: StorageLocation?) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let item = FoodItem(
            barcode: barcode,
            name: trimmedName,
            brand: brand,
            imageURL: imageURL,
            expiryDate: expiryDate,
            quantity: quantity,
            storageLocation: location,
            customReminderDays: useCustomReminder ? customReminderDays : nil,
            isOfflineEntry: !viewModel.isOnline
        )
        Task {
            await viewModel.addFoodItem(item)
            dismiss()
        }
    }
}

// MARK: - Location Picker Sheet
struct LocationPickerSheet: View {
    let locations: [StorageLocation]
    let onSelect: (StorageLocation?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(locations) { loc in
                        Button {
                            onSelect(loc)
                            dismiss()
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(loc.color.opacity(0.15))
                                        .frame(width: 64, height: 64)
                                    Image(systemName: loc.iconName)
                                        .font(.title2)
                                        .foregroundStyle(loc.color)
                                }
                                Text(loc.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Wo lagerst du das?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ohne Ort") {
                        onSelect(nil)
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
