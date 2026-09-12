import SwiftUI
import SwiftData
import UIKit

struct AddFoodItemView: View {
    /// Ein Formular für beides: Anlegen (nach Scan oder von Hand) und
    /// Bearbeiten eines bestehenden Produkts.
    enum Mode {
        case create(barcode: String)
        case edit(FoodItem)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject private var store: StoreManager

    let mode: Mode

    private var barcode: String {
        switch mode {
        case .create(let barcode): return barcode
        case .edit(let item): return item.barcode
        }
    }

    private var editingItem: FoodItem? {
        if case .edit(let item) = mode { return item }
        return nil
    }

    private var isEditMode: Bool { editingItem != nil }

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var imageURL: String = ""
    /// Bewusst ohne Vorbelegung: Nik soll das Datum aktiv wählen, sonst landet
    /// jedes Produkt mit "1 Monat" im Bestand.
    @State private var expiryDate: Date? = nil
    @State private var quantity: Int = 1
    @State private var selectedLocation: StorageLocation? = nil
    @State private var useCustomReminder = false
    @State private var customReminderDays: Int = 7
    @State private var isLoadingProduct: Bool
    @State private var isEditingProduct: Bool
    @State private var capturedImageData: Data?
    @State private var photoSource: PhotoSource?
    @State private var showImageSourceDialog = false
    @State private var showPaywall = false
    @State private var isSaving = false
    /// Keine der Produktdatenbanken kennt den Barcode: Nachtragen anbieten.
    @State private var productNotFound = false
    @State private var showContributeSheet = false
    @FocusState private var focusedField: Field?

    /// Zuletzt gewählter Lagerort, als UUID-String. Leer heißt "noch nie gespeichert",
    /// `noLocationMarker` heißt "zuletzt bewusst Ohne Ort".
    @AppStorage("lastStorageLocationID") private var lastStorageLocationID: String = ""

    enum Field { case name, brand }

    init(barcode: String) {
        self.init(mode: .create(barcode: barcode))
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let barcode):
            _isLoadingProduct = State(initialValue: !barcode.isEmpty)
            _isEditingProduct = State(initialValue: barcode.isEmpty)
        case .edit(let item):
            _isLoadingProduct = State(initialValue: false)
            _isEditingProduct = State(initialValue: true)
            _name = State(initialValue: item.name)
            _brand = State(initialValue: item.brand)
            _imageURL = State(initialValue: item.imageURL)
            _capturedImageData = State(initialValue: item.imageData)
            _expiryDate = State(initialValue: item.expiryDate)
            _quantity = State(initialValue: item.quantity)
            _selectedLocation = State(initialValue: item.storageLocation)
            _useCustomReminder = State(initialValue: item.customReminderDays != nil)
            _customReminderDays = State(initialValue: item.customReminderDays ?? 7)
        }
    }

    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    private let quickExpiry: [(label: String, days: Int)] = [
        ("3 Tage", 3), ("1 Woche", 7), ("2 Wochen", 14),
        ("1 Monat", 30), ("3 Monate", 90), ("6 Monate", 180), ("1 Jahr", 365)
    ]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && expiryDate != nil && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    productInfoHeader
                    if productNotFound, let contributeURL {
                        contributeRow(url: contributeURL)
                    }
                } header: {
                    Text("Produkt")
                }

                if !locations.isEmpty {
                    Section {
                        locationChipRow
                    } header: {
                        Text("Lagerort")
                    }
                }

                Section {
                    Stepper("Menge: \(quantity)", value: $quantity, in: 1...99)
                } header: {
                    Text("Menge")
                }

                Section {
                    quickExpiryRow
                    expiryResultRow
                    DatePicker(
                        "Anderes Datum",
                        selection: datePickerBinding,
                        in: datePickerRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(Color.freshGreen)
                } header: {
                    Text("Haltbar bis")
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

                if !isEditMode && !viewModel.isOnline {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash").foregroundStyle(.orange)
                            Text("Offline gespeichert, Produktinfos werden beim nächsten Online-Gang ergänzt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            // Kurz, weil "Neues Produkt" neben "Abbrechen" und "Speichern"
            // auf dem iPhone abgeschnitten wird. Der Abschnitt darunter heißt "Produkt".
            .navigationTitle(isEditMode ? "Bearbeiten" : "Neu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Speichern") { saveItem() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .task { await loadProduct() }
            .onAppear { preselectLastLocation() }
            .interactiveDismissDisabled(isEditMode)
            .sheet(isPresented: $showPaywall) { PaywallView() }
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
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .brand }
                    TextField("Marke (optional)", text: $brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
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
            if capturedImageData != nil || !imageURL.isEmpty {
                // Entfernt auch die Bild-URL, sonst taucht das alte Bild
                // aus Open Food Facts gleich wieder auf.
                Button("Foto entfernen", role: .destructive) {
                    capturedImageData = nil
                    imageURL = ""
                }
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

    // MARK: - Lagerort
    private var locationChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                locationChip(title: "Ohne Ort", icon: "questionmark", tint: .secondary,
                             isSelected: selectedLocation == nil) {
                    selectedLocation = nil
                }
                ForEach(locations) { loc in
                    locationChip(title: loc.name, icon: loc.iconName, tint: loc.color,
                                 isSelected: selectedLocation?.id == loc.id) {
                        selectedLocation = loc
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func locationChip(title: String, icon: String, tint: Color,
                              isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.25)) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(isSelected ? .bold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(isSelected ? tint : Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Haltbar bis
    private var quickExpiryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickExpiry, id: \.days) { option in
                    let targetDate = Self.dateFromToday(days: option.days)
                    let isSelected = expiryDate.map { Calendar.current.isDate($0, inSameDayAs: targetDate) } ?? false
                    Button {
                        withAnimation(.spring(response: 0.25)) { expiryDate = targetDate }
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(isSelected ? Color.freshGreen : Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(isSelected ? Color.freshGreen : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var expiryResultRow: some View {
        if let date = expiryDate {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.freshGreen)
                Text("Haltbar bis \(Self.longDateString(date))")
                    .font(.subheadline.weight(.medium))
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                Text("Bitte Datum wählen")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.orange)
        }
    }

    /// Der DatePicker braucht ein nicht optionales Datum. Solange nichts
    /// gewählt ist, zeigt er heute, schreibt aber erst beim Ändern zurück.
    /// Beim Anlegen nur ab heute. Beim Bearbeiten darf ein abgelaufenes
    /// Produkt sein altes Datum behalten, sonst springt der Picker auf heute.
    private var datePickerRange: PartialRangeFrom<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        if let existing = editingItem?.expiryDate, existing < today {
            return Calendar.current.startOfDay(for: existing)...
        }
        return today...
    }

    private var datePickerBinding: Binding<Date> {
        Binding(
            get: { expiryDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { expiryDate = $0 }
        )
    }

    private static func dateFromToday(days: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: days, to: today) ?? today
    }

    /// "Fr, 15.09.2026"
    private static func longDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EE, dd.MM.yyyy"
        return f.string(from: date).replacingOccurrences(of: ".,", with: ",")
    }

    /// "15.09."
    private static func shortDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM."
        return f.string(from: date)
    }

    // MARK: - Actions
    private func beginEditing() {
        withAnimation(.spring(response: 0.25)) { isEditingProduct = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focusedField = .name }
    }

    /// Vorbelegung des Lagerorts:
    /// - zuletzt gewählter Ort, falls er noch existiert
    /// - "none": Nik hat zuletzt bewusst "Ohne Ort" gewählt, das bleibt so
    /// - leer (allererstes Produkt): "Kühlschrank", sonst der erste Ort, sonst "Ohne Ort"
    private func preselectLastLocation() {
        guard !isEditMode, selectedLocation == nil else { return }
        if lastStorageLocationID == Self.noLocationMarker { return }
        if let id = UUID(uuidString: lastStorageLocationID),
           let last = locations.first(where: { $0.id == id }) {
            selectedLocation = last
            return
        }
        selectedLocation = locations.first { $0.name.caseInsensitiveCompare("Kühlschrank") == .orderedSame }
            ?? locations.first
    }

    /// Wert in `lastStorageLocationID`, wenn zuletzt bewusst ohne Ort gespeichert wurde.
    /// Unterscheidet "noch nie gespeichert" (leer) von "Ohne Ort gewählt".
    private static let noLocationMarker = "none"

    private func loadProduct() async {
        // Bearbeiten: alles ist schon da, nichts nachladen, kein Fokus-Sprung.
        guard !isEditMode else { return }
        // Manuelles Anlegen: Name ist leer, also direkt ins Namensfeld springen.
        guard !barcode.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focusedField = .name }
            return
        }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        // Offline oder Produkt unbekannt: Nik füllt die Felder selbst aus.
        guard viewModel.isOnline else { beginEditing(); return }
        switch await viewModel.lookupProduct(barcode: barcode) {
        case .found(let info):
            name     = info.name
            brand    = info.brand
            imageURL = info.imageURL ?? ""
        case .notFound:
            productNotFound = true
            beginEditing()
        case .unavailable:
            beginEditing()
        }
    }

    private var contributeURL: URL? {
        guard !isEditMode, !barcode.isEmpty else { return nil }
        return Legal.openFoodFactsContributeURL(barcode: barcode)
    }

    /// Dezente Zeile unter dem Produktkopf, wenn der Barcode nirgends bekannt ist.
    private func contributeRow(url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
            Text("Nicht in Open Food Facts. Nachtragen hilft allen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Nachtragen") { showContributeSheet = true }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(Color.freshGreen)
        }
        .sheet(isPresented: $showContributeSheet) {
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    private func saveItem() {
        guard !trimmedName.isEmpty, let expiryDate else { return }
        guard !isSaving else { return }
        if let item = editingItem {
            saveEdits(to: item, expiryDate: expiryDate)
            return
        }
        if !store.isPro {
            let count = (try? modelContext.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
            if count >= StoreManager.freeLimit {
                showPaywall = true
                return
            }
        }
        let item = FoodItem(
            barcode: barcode,
            name: trimmedName,
            brand: brand,
            imageURL: imageURL,
            imageData: capturedImageData,
            expiryDate: expiryDate,
            quantity: quantity,
            storageLocation: selectedLocation,
            customReminderDays: useCustomReminder ? customReminderDays : nil,
            isOfflineEntry: !viewModel.isOnline
        )
        // Speichern ist sofort erledigt, der Bilddownload und die Erinnerungen
        // laufen im Hintergrund weiter. Vorher wartete der Sheet bis zu 60 s auf
        // das Bild, und ein zweiter Tipp erzeugte ein Duplikat.
        isSaving = true
        lastStorageLocationID = selectedLocation?.id.uuidString ?? Self.noLocationMarker
        viewModel.addFoodItem(item)
        viewModel.showToast("\(trimmedName) gespeichert, haltbar bis \(Self.shortDateString(expiryDate))")
        Feedback.itemSaved()
        dismiss()
    }

    /// Schreibt die Felder ins bestehende Produkt. `updateFoodItem` plant die
    /// Erinnerungen neu, das deckt geändertes Datum und geänderte Erinnerung ab.
    private func saveEdits(to item: FoodItem, expiryDate: Date) {
        isSaving = true
        item.name = trimmedName
        item.brand = brand.trimmingCharacters(in: .whitespaces)
        item.imageURL = imageURL
        item.imageData = capturedImageData
        item.expiryDate = expiryDate
        item.quantity = quantity
        item.storageLocation = selectedLocation
        item.customReminderDays = useCustomReminder ? customReminderDays : nil
        Task { await viewModel.updateFoodItem(item) }
        viewModel.showToast("\(trimmedName) gespeichert, haltbar bis \(Self.shortDateString(expiryDate))")
        Feedback.itemSaved()
        dismiss()
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
