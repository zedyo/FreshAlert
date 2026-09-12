import SwiftUI
import SwiftData

struct AddStorageLocationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var editingLocation: StorageLocation? = nil
    let existingCount: Int

    /// Für die Vorlagenliste: was es schon gibt, wird ausgegraut.
    @Query(sort: \StorageLocation.sortOrder) private var locations: [StorageLocation]

    @State private var name: String = ""
    @State private var selectedIcon: String = "archivebox"
    @State private var selectedColor: Color = Color.freshGreen
    @State private var iconSearchText: String = ""
    @State private var showCustomize = false
    /// Sobald Nik selbst Icon oder Farbe gewählt hat, schlägt der Name nichts mehr vor.
    @State private var userChoseIcon = false
    @State private var userChoseColor = false

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
            "waterbottle", "takeoutbag.and.cup.and.straw", "birthday.cake", "carrot"
        ]),
        ("Ort & Gebäude", [
            "building.columns", "house", "house.fill", "building",
            "building.2", "door.garage.closed", "car", "tent"
        ]),
        ("Körbe & Behälter", [
            "basket", "basket.fill", "bag", "bag.fill",
            "backpack", "briefcase", "cart", "cart.fill", "cylinder"
        ]),
        ("Natur & Lebensmittel", [
            "leaf", "leaf.fill", "tree", "sun.max",
            "drop", "flame", "bolt"
        ]),
        ("Haushalt & Familie", [
            "pills", "cross.case", "pawprint", "dog", "cat",
            "stroller", "teddybear"
        ])
    ]

    /// Deutsche Stichwörter für die Icon-Suche. Ein Stichwort trifft alle
    /// Symbole in seiner Liste, zusätzlich zur Suche im Symbolnamen selbst.
    private static let keywordTable: [String: [String]] = [
        "kühl":    ["thermometer.snowflake", "snowflake", "thermometer.medium", "refrigerator", "air.conditioner.horizontal"],
        "kuehl":   ["thermometer.snowflake", "snowflake", "thermometer.medium", "refrigerator", "air.conditioner.horizontal"],
        "kalt":    ["thermometer.snowflake", "snowflake", "thermometer.medium", "refrigerator", "air.conditioner.horizontal"],
        "gefrier": ["snowflake", "thermometer.snowflake", "refrigerator"],
        "tief":    ["snowflake", "thermometer.snowflake", "refrigerator"],
        "eis":     ["snowflake", "thermometer.snowflake"],
        "schrank": ["cabinet", "cabinet.fill", "refrigerator", "archivebox", "archivebox.fill"],
        "regal":   ["cabinet", "cabinet.fill", "tray", "tray.fill", "shippingbox", "shippingbox.fill"],
        "vorrat":  ["cabinet", "cabinet.fill", "archivebox", "archivebox.fill", "shippingbox", "shippingbox.fill"],
        "keller":  ["building.columns", "house", "house.fill", "archivebox", "archivebox.fill"],
        "obst":    ["basket", "basket.fill", "carrot", "leaf", "leaf.fill", "tree"],
        "gemüse":  ["carrot", "basket", "basket.fill", "leaf", "leaf.fill"],
        "gemuese": ["carrot", "basket", "basket.fill", "leaf", "leaf.fill"],
        "korb":    ["basket", "basket.fill", "cart", "cart.fill"],
        "getränk": ["wineglass", "mug", "cup.and.saucer", "waterbottle", "takeoutbag.and.cup.and.straw"],
        "getraenk": ["wineglass", "mug", "cup.and.saucer", "waterbottle", "takeoutbag.and.cup.and.straw"],
        "flasche": ["waterbottle", "wineglass", "cylinder"],
        "wasser":  ["waterbottle", "drop"],
        "wein":    ["wineglass", "cylinder"],
        "bier":    ["mug", "waterbottle", "cylinder"],
        "kaffee":  ["cup.and.saucer", "mug"],
        "tee":     ["cup.and.saucer", "mug"],
        "gewürz":  ["flame", "leaf", "leaf.fill", "cylinder"],
        "gewuerz": ["flame", "leaf", "leaf.fill", "cylinder"],
        "brot":    ["fork.knife", "birthday.cake", "basket", "basket.fill"],
        "kuchen":  ["birthday.cake", "fork.knife"],
        "küche":   ["fork.knife", "cup.and.saucer", "mug", "wineglass", "birthday.cake"],
        "kueche":  ["fork.knife", "cup.and.saucer", "mug", "wineglass", "birthday.cake"],
        "büro":    ["briefcase", "building", "building.2", "tray", "tray.fill"],
        "buero":   ["briefcase", "building", "building.2", "tray", "tray.fill"],
        "arbeit":  ["briefcase", "building", "building.2"],
        "auto":    ["car", "door.garage.closed"],
        "garage":  ["door.garage.closed", "car"],
        "camping": ["tent", "backpack", "flame"],
        "zelt":    ["tent"],
        "tasche":  ["bag", "bag.fill", "backpack", "briefcase"],
        "rucksack": ["backpack"],
        "box":     ["shippingbox", "shippingbox.fill", "archivebox", "archivebox.fill", "tray", "tray.fill"],
        "kiste":   ["shippingbox", "shippingbox.fill", "archivebox", "archivebox.fill"],
        "karton":  ["shippingbox", "shippingbox.fill"],
        "garten":  ["leaf", "leaf.fill", "tree", "sun.max", "drop", "carrot"],
        "balkon":  ["sun.max", "leaf", "leaf.fill", "house"],
        "haus":    ["house", "house.fill", "building", "building.2"],
        "wohnung": ["house", "house.fill", "building", "building.2"],
        "medizin": ["pills", "cross.case"],
        "apotheke": ["pills", "cross.case"],
        "tablette": ["pills"],
        "tier":    ["pawprint", "dog", "cat"],
        "hund":    ["dog", "pawprint"],
        "katze":   ["cat", "pawprint"],
        "futter":  ["pawprint", "dog", "cat", "shippingbox"],
        "baby":    ["stroller", "teddybear"],
        "kind":    ["stroller", "teddybear"],
        "feuer":   ["flame"],
        "grill":   ["flame"],
        "sonne":   ["sun.max"],
        "strom":   ["bolt"],
    ]

    /// Kleinschreibung und Umlaute vereinheitlichen, damit "Kühl" und "kuhl" dasselbe finden.
    private static func normalized(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
    }

    /// Symbolname → normalisierte deutsche Stichwörter, aus `keywordTable` umgedreht.
    private static let keywordsBySymbol: [String: [String]] = {
        var result: [String: [String]] = [:]
        for (keyword, symbols) in keywordTable {
            let key = normalized(keyword)
            for symbol in symbols {
                result[symbol, default: []].append(key)
            }
        }
        return result
    }()

    private var filteredGroups: [(category: String, icons: [String])] {
        let q = Self.normalized(iconSearchText.trimmingCharacters(in: .whitespaces))
        if q.isEmpty { return iconGroups }
        return iconGroups.compactMap { group in
            let icons = group.icons.filter { icon in
                icon.contains(q)
                    || (Self.keywordsBySymbol[icon] ?? []).contains { $0.contains(q) }
            }
            return icons.isEmpty ? nil : (group.category, icons)
        }
    }

    private let colors: [(name: String, color: Color)] = [
        ("Frischgrün", Color.freshGreen),
        ("Hellblau",   Color(hex: "#5AC8FA") ?? .cyan),
        ("Blau",       Color(hex: "#007AFF") ?? .blue),
        ("Orange",     Color(hex: "#FF9500") ?? .orange),
        ("Rot",        Color(hex: "#FF3B30") ?? .red),
        ("Pink",       Color(hex: "#FF2D55") ?? .pink),
        ("Lila",       Color(hex: "#AF52DE") ?? .purple),
        ("Grau",       Color(hex: "#8E8E93") ?? .gray),
        ("Grün",       Color(hex: "#34C759") ?? .green),
        ("Gelb",       Color(hex: "#FFCC00") ?? .yellow),
    ]

    var isEditing: Bool { editingLocation != nil }

    var body: some View {
        NavigationStack {
            Form {
                if isEditing {
                    previewSection
                    Section("Name") {
                        TextField("z.B. Kühlschrank", text: $name)
                    }
                    Section("Farbe") { colorGrid }
                    Section("Icon") { iconPicker }
                } else {
                    templatesSection
                    customSection
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
            .onChange(of: name) { _, newName in
                guard !isEditing else { return }
                applySuggestion(for: newName)
            }
        }
    }

    // MARK: - Abschnitte

    private var previewSection: some View {
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
    }

    /// Fertige Orte mit Icon und Farbe. Ein Tipp legt sofort an und schließt.
    private var templatesSection: some View {
        Section {
            ForEach(StorageLocation.allTemplates, id: \.name) { template in
                let exists = locationExists(named: template.name)
                let color = Color(hex: template.colorHex) ?? .green
                Button {
                    create(name: template.name, iconName: template.iconName, colorHex: template.colorHex)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(color.opacity(0.18))
                                .frame(width: 40, height: 40)
                            Image(systemName: template.iconName)
                                .font(.body)
                                .foregroundStyle(color)
                        }
                        Text(template.name)
                            .foregroundStyle(exists ? .secondary : .primary)
                        Spacer()
                        if exists {
                            Text("vorhanden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(exists ? 0.6 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(exists)
                .accessibilityLabel(exists ? "\(template.name), vorhanden" : template.name)
            }
        } header: {
            Text("Vorlagen")
        }
    }

    /// Eigener Name, Icon und Farbe kommen aus dem Namen, "Anpassen" klappt die Auswahl auf.
    private var customSection: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selectedColor.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: selectedIcon)
                        .font(.body)
                        .foregroundStyle(selectedColor)
                }
                .accessibilityHidden(true)
                TextField("Name, z.B. Garage", text: $name)
                    .submitLabel(.done)
                    .onSubmit { save() }
            }
            DisclosureGroup("Anpassen", isExpanded: $showCustomize) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Farbe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    colorGrid
                    Text("Icon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    iconPicker
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Eigener Ort")
        } footer: {
            Text("Icon und Farbe wählt FreshAlert passend zum Namen, du kannst sie unter „Anpassen“ ändern.")
        }
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 12) {
            ForEach(colors.indices, id: \.self) { i in
                let entry = colors[i]
                let isSelected = selectedColor == entry.color
                Button {
                    selectedColor = entry.color
                    userChoseColor = true
                } label: {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: 3)
                                .opacity(isSelected ? 1 : 0)
                        )
                        .shadow(color: entry.color.opacity(0.5), radius: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var iconPicker: some View {
        TextField("Icon suchen, z.B. Kühl, Korb, Keller …", text: $iconSearchText)
            .autocorrectionDisabled()

        if filteredGroups.isEmpty {
            Text("Kein Icon zu „\(iconSearchText)“ gefunden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

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
                            userChoseIcon = true
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
                        .accessibilityLabel(icon)
                        .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Logik

    private func locationExists(named candidate: String) -> Bool {
        locations.contains { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }
    }

    private func applySuggestion(for newName: String) {
        let suggestion = StorageLocation.suggestion(forName: newName)
        if !userChoseIcon { selectedIcon = suggestion.iconName }
        if !userChoseColor, let color = Color(hex: suggestion.colorHex) { selectedColor = color }
    }

    private func create(name: String, iconName: String, colorHex: String) {
        let loc = StorageLocation(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            sortOrder: existingCount
        )
        modelContext.insert(loc)
        try? modelContext.save()
        dismiss()
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
            try? modelContext.save()
            dismiss()
        } else {
            create(name: trimmed, iconName: selectedIcon, colorHex: hexColor)
        }
    }
}
