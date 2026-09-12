import SwiftUI
import SwiftData

struct FoodItemCardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let item: FoodItem
    @State private var showDetail = false
    @State private var showLocationPicker = false
    @State private var showEdit = false
    /// Aktion aus dem Detail-Sheet, die erst nach dessen Schließen läuft.
    @State private var pendingAction: FoodItemDetailAction?

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM."
        return f
    }()

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
                    } else {
                        // Kein Ort: Tipp auf die Zeile öffnet die Schnellzuordnung,
                        // der Rest der Karte führt weiter ins Detail.
                        Button {
                            showLocationPicker = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "questionmark.circle")
                                    .font(.caption2)
                                Text("Kein Lagerort")
                                    .font(.caption)
                            }
                            .foregroundStyle(.orange)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kein Lagerort, Ort zuordnen")
                    }

                    HStack(spacing: 6) {
                        Image(systemName: item.expiryStatus.iconName)
                            .font(.caption)
                        Text(item.expiryLabel)
                            .font(.caption.weight(.medium))
                        Text(Self.shortDate.string(from: item.expiryDate))
                            .font(.caption)
                            .opacity(0.75)
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
                        Text("\(item.quantity)×")
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
        .sheet(isPresented: $showDetail, onDismiss: handleDetailDismiss) {
            FoodItemDetailView(item: item) { action in
                // Erst das Sheet schließen, dann handeln: sonst rendert das
                // Sheet ein gelöschtes @Model und die App stürzt ab.
                pendingAction = action
            }
        }
        .sheet(isPresented: $showEdit) {
            AddFoodItemView(mode: .edit(item))
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationQuickPickSheet(item: item)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
    }

    private func handleDetailDismiss() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        let item = self.item
        switch action {
        case .delete:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                viewModel.deleteFoodItem(item)
            }
        case .consume:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                viewModel.decrementQuantity(item)
                Feedback.itemUsed()
            }
        case .edit:
            // Kurz warten, bis die Schließanimation durch ist, sonst
            // verschluckt SwiftUI das zweite Sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showEdit = true
            }
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

// MARK: - Schnellzuordnung Lagerort
/// Kleines Sheet unter der Karte: ein Tipp auf einen Ort speichert sofort.
struct LocationQuickPickSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: AppViewModel
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]
    let item: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wo liegt \(item.name)?")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Tippe auf einen Ort, das Produkt wird sofort zugeordnet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if locations.isEmpty {
                Text("Noch keine Lagerorte angelegt. Unter Einstellungen kannst du welche erstellen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(locations) { loc in
                            Button {
                                assign(loc)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: loc.iconName)
                                        .font(.caption.weight(.semibold))
                                    Text(loc.name)
                                        .font(.caption.weight(.regular))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(loc.color)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(loc.color.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assign(_ loc: StorageLocation) {
        item.storageLocation = loc
        Task { await viewModel.updateFoodItem(item) }
        viewModel.showToast("\(item.name) liegt jetzt im \(loc.name)")
        Feedback.itemSaved()
        dismiss()
    }
}

// MARK: - Detail Sheet

/// Was nach dem Schließen des Detail-Sheets im Parent passieren soll.
/// Entfernen und Bearbeiten laufen erst nach dem Dismiss, sonst rendert das
/// Sheet ein gelöschtes @Model oder zwei Sheets kollidieren.
enum FoodItemDetailAction {
    case delete
    case consume
    case edit
}

struct FoodItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: AppViewModel
    let item: FoodItem
    /// Wird vor dem Schließen aufgerufen. Der Parent führt die Aktion nach dem
    /// Dismiss aus (Löschen, Verbrauchen bei Menge 1, Formular öffnen).
    let onAction: (FoodItemDetailAction) -> Void

    @State private var showDeleteConfirmation = false
    @State private var showDetails = false

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM."
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    actionRow
                    detailsGroup
                    deleteButton
                }
                .padding()
            }
            .navigationTitle("Produkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Kopf

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            productImage

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.brand.isEmpty {
                    Text(item.brand)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                locationChip

                statusPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var productImage: some View {
        if let data = item.imageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if !item.imageURL.isEmpty, let url = URL(string: item.imageURL) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    imagePlaceholder
                }
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemGray5))
            .frame(width: 110, height: 110)
            .overlay(
                Image(systemName: "camera")
                    .font(.title)
                    .foregroundStyle(.secondary)
            )
    }

    @ViewBuilder
    private var locationChip: some View {
        if let loc = item.storageLocation {
            HStack(spacing: 5) {
                Image(systemName: loc.iconName)
                    .font(.caption.weight(.semibold))
                Text(loc.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(loc.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(loc.color.opacity(0.15))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                Text("Kein Lagerort")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: item.expiryStatus.iconName)
                .font(.caption)
            Text("\(item.expiryLabel), \(Self.shortDate.string(from: item.expiryDate))")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(item.expiryStatus.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(item.expiryStatus.backgroundColor)
        .clipShape(Capsule())
    }

    // MARK: Aktionen

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                consume()
            } label: {
                Label(item.quantity > 1 ? "1 verbraucht" : "Verbraucht",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.freshGreen)

            quantityControl

            Button {
                onAction(.edit)
                dismiss()
            } label: {
                Text("Bearbeiten")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private var quantityControl: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.decrementQuantity(item)
                Feedback.itemUsed()
            } label: {
                Image(systemName: "minus")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 36, height: 44)
            }
            .disabled(item.quantity <= 1)
            .accessibilityLabel("Menge verringern")

            Text("\(item.quantity)×")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 30)

            Button {
                viewModel.incrementQuantity(item)
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("Menge erhöhen")
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Bei Menge > 1 nur eins abziehen, das Sheet bleibt offen. Bei Menge 1
    /// verschwindet das Produkt: erst schließen, der Parent entfernt es danach.
    private func consume() {
        if item.quantity > 1 {
            viewModel.decrementQuantity(item)
            Feedback.itemUsed()
        } else {
            onAction(.consume)
            dismiss()
        }
    }

    // MARK: Details

    private var detailsGroup: some View {
        DisclosureGroup("Details", isExpanded: $showDetails) {
            VStack(spacing: 0) {
                detailRow("Erinnerung", value: reminderValue)
                Divider().padding(.leading, 16)
                detailRow("Hinzugefügt", value: item.addedAt.formatted(date: .abbreviated, time: .omitted))
                if !item.barcode.isEmpty {
                    Divider().padding(.leading, 16)
                    detailRow("Barcode", value: item.barcode, monospaced: true)
                }
                if item.isOfflineEntry {
                    Divider().padding(.leading, 16)
                    detailRow("Sync", value: "Offline, wartet auf Sync", color: .orange)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
        }
        .font(.subheadline.weight(.medium))
        .tint(.primary)
    }

    private func detailRow(_ label: String, value: String,
                           color: Color = .primary, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .subheadline.monospaced() : .subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var reminderValue: String {
        if let days = item.customReminderDays {
            return "\(reminderText(days)) (eigene)"
        }
        return "\(reminderText(viewModel.globalReminderDays)) (Standard)"
    }

    private func reminderText(_ days: Int) -> String {
        "\(days) \(days == 1 ? "Tag" : "Tage") vorher"
    }

    // MARK: Löschen

    private var deleteButton: some View {
        Button("Produkt löschen") {
            showDeleteConfirmation = true
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
        .confirmationDialog(
            "\(item.name) löschen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Produkt löschen", role: .destructive) {
                onAction(.delete)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}
