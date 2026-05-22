import SwiftUI
import SwiftData
import UIKit

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
    @State private var isEditingProduct: Bool
    @State private var capturedImageData: Data?
    @State private var photoSource: PhotoSource?
    @State private var showImageSourceDialog = false
    @FocusState private var focusedField: Field?

    enum Field { case name, brand }

    init(barcode: String) {
        self.barcode = barcode
        _isLoadingProduct = State(initialValue: !barcode.isEmpty)
        _isEditingProduct = State(initialValue: barcode.isEmpty)
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
                    .tint(Color.freshGreen)
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
            productImageView

            VStack(alignment: .leading, spacing: 4) {
                if isLoadingProduct {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("Produkt wird gesucht …")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if isEditingProduct {
                    TextField("Produktname *", text: $name)
                        .font(.subheadline.weight(.semibold))
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .brand }
                    TextField("Marke (optional)", text: $brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .focused($focusedField, equals: .brand)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                } else {
                    HStack(spacing: 4) {
                        Text(name.isEmpty ? "Unbekannt" : name)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if !brand.isEmpty {
                        Text(brand).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !barcode.isEmpty {
                    Text("Barcode: \(barcode)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isLoadingProduct else { return }
                beginEditing()
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Produktfoto", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Foto aufnehmen") { photoSource = .camera }
            }
            Button("Aus Mediathek wählen") { photoSource = .library }
            if capturedImageData != nil {
                Button("Foto entfernen", role: .destructive) { capturedImageData = nil }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(item: $photoSource) { source in
            ImagePicker(sourceType: source.uiSourceType) { data in
                capturedImageData = data
            }
        }
    }

    // The image slot. In edit mode it is tappable to take or pick a photo.
    private var productImageView: some View {
        imageContent
            .overlay(alignment: .bottomTrailing) {
                if isEditingProduct && !isLoadingProduct {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.freshGreen, in: Circle())
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 5, y: 5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isLoadingProduct else { return }
                if isEditingProduct {
                    showImageSourceDialog = true
                } else {
                    beginEditing()
                }
            }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let data = capturedImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if !imageURL.isEmpty, let url = URL(string: imageURL) {
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
    }

    private var productPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .frame(width: 64, height: 64)
            .overlay(
                Image(systemName: isEditingProduct ? "camera" : (barcode.isEmpty ? "pencil" : "barcode"))
                    .foregroundStyle(.secondary)
            )
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
                                ? Color.freshGreen
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
    private func beginEditing() {
        withAnimation(.spring(response: 0.25)) { isEditingProduct = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focusedField = .name }
    }

    private func loadProduct() async {
        guard !barcode.isEmpty else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        // Offline or product not found → let the user fill in details manually.
        guard viewModel.isOnline else { beginEditing(); return }
        if let info = await viewModel.fetchProductInfo(barcode: barcode) {
            name     = info.name
            brand    = info.brand
            imageURL = info.imageURL ?? ""
        } else {
            beginEditing()
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
            imageData: capturedImageData,
            expiryDate: expiryDate,
            quantity: quantity,
            storageLocation: location,
            customReminderDays: useCustomReminder ? customReminderDays : nil,
            isOfflineEntry: !viewModel.isOnline
        )
        Task {
            await viewModel.addFoodItem(item)
            Feedback.itemSaved()
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

// MARK: - Photo Capture

enum PhotoSource: Identifiable {
    case camera, library
    var id: Self { self }
    var uiSourceType: UIImagePickerController.SourceType {
        self == .camera ? .camera : .photoLibrary
    }
}

// Wraps UIImagePickerController for taking a photo or picking one from the
// library. The picked image is downscaled and handed back as JPEG data.
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = Self.downscaled(image).jpegData(compressionQuality: 0.7) {
                parent.onImagePicked(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        private static func downscaled(_ image: UIImage, maxDimension: CGFloat = 1200) -> UIImage {
            let longest = max(image.size.width, image.size.height)
            guard longest > maxDimension else { return image }
            let scale = maxDimension / longest
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
    }
}
