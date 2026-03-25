import SwiftUI
import SwiftData

struct AddStorageLocationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var editingLocation: StorageLocation? = nil
    let existingCount: Int

    @State private var name: String = ""
    @State private var selectedIcon: String = "archivebox"
    @State private var selectedColor: Color = Color(red: 0.2, green: 0.78, blue: 0.2)
    @State private var iconSearchText: String = ""

    // SF Symbols for storage locations
    private let iconGroups: [(category: String, icons: [String])] = [
        ("Kühlschränke & Gefrieren", [
            "thermometer.snowflake", "snowflake", "thermometer.medium",
            "refrigerator", "air.conditioner.horizontal"
        ]),
        ("Schrank & Regal", [
            "cabinet", "cabinet.fill", "shippingbox", "shippingbox.fill",
            "archivebox", "archivebox.fill", "tray", "tray.fill"
        ]),
        ("Küche", [
            "fork.knife", "cup.and.saucer", "mug", "wineglass",
            "takeoutbag.and.cup.and.straw", "birthday.cake"
        ]),
        ("Ort & Gebäude", [
            "building.columns", "house", "house.fill", "building",
            "building.2", "carport", "garage"
        ]),
        ("Körbe & Behälter", [
            "basket", "basket.fill", "bag", "bag.fill",
            "cart", "cart.fill", "cylinder"
        ]),
        ("Natur & Lebensmittel", [
            "leaf", "leaf.fill", "tree", "sun.max",
            "drop", "flame", "bolt"
        ])
    ]

    private var allIcons: [String] { iconGroups.flatMap(\.icons) }
    private var filteredGroups: [(category: String, icons: [String])] {
        if iconSearchText.isEmpty { return iconGroups }
        let q = iconSearchText.lowercased()
        return iconGroups.compactMap { group in
            let icons = group.icons.filter { $0.contains(q) }
            return icons.isEmpty ? nil : (group.category, icons)
        }
    }

    private let colors: [Color] = [
        Color(red: 0.2, green: 0.78, blue: 0.2),
        Color(hex: "#5AC8FA") ?? .cyan,
        Color(hex: "#007AFF") ?? .blue,
        Color(hex: "#FF9500") ?? .orange,
        Color(hex: "#FF3B30") ?? .red,
        Color(hex: "#FF2D55") ?? .pink,
        Color(hex: "#AF52DE") ?? .purple,
        Color(hex: "#8E8E93") ?? .gray,
        Color(hex: "#34C759") ?? .green,
        Color(hex: "#FFCC00") ?? .yellow,
    ]

    var isEditing: Bool { editingLocation != nil }

    var body: some View {
        NavigationStack {
            Form {
                // Preview
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(selectedColor.opacity(0.18))
                                    .frame(width: 72, height: 72)
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 32))
                                    .foregroundStyle(selectedColor)
                            }
                            Text(name.isEmpty ? "Name" : name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // Name
                Section("Name") {
                    TextField("z.B. Kühlschrank", text: $name)
                }

                // Color
                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 12) {
                        ForEach(colors.indices, id: \.self) { i in
                            let c = colors[i]
                            Circle()
                                .fill(c)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 3)
                                        .opacity(selectedColor == c ? 1 : 0)
                                )
                                .shadow(color: c.opacity(0.5), radius: 4)
                                .onTapGesture { selectedColor = c }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Icon
                Section {
                    TextField("Icon suchen …", text: $iconSearchText)
                        .autocorrectionDisabled()

                    ForEach(filteredGroups, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 10) {
                                ForEach(group.icons, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedIcon == icon
                                                      ? selectedColor.opacity(0.2)
                                                      : Color(.systemGray6))
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .strokeBorder(selectedIcon == icon ? selectedColor : .clear, lineWidth: 2)
                                                )
                                            Image(systemName: icon)
                                                .font(.title3)
                                                .foregroundStyle(selectedIcon == icon ? selectedColor : .primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Icon")
                }
            }
            .navigationTitle(isEditing ? "Ort bearbeiten" : "Neuer Lagerort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Speichern" : "Erstellen") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { prefillIfEditing() }
        }
    }

    private func prefillIfEditing() {
        guard let loc = editingLocation else { return }
        name = loc.name
        selectedIcon = loc.iconName
        selectedColor = loc.color
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let hexColor = selectedColor.toHex

        if let loc = editingLocation {
            loc.name = trimmed
            loc.iconName = selectedIcon
            loc.colorHex = hexColor
        } else {
            let loc = StorageLocation(
                name: trimmed,
                iconName: selectedIcon,
                colorHex: hexColor,
                sortOrder: existingCount
            )
            modelContext.insert(loc)
        }
        try? modelContext.save()
        dismiss()
    }
}
