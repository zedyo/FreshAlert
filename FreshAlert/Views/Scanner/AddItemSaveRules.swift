import Foundation

/// Wann das Produktformular gespeichert werden darf. Eine Stelle für den
/// Speichern-Knopf und für "übernehmen und speichern" im Datum-Scanner,
/// damit beide Wege dieselben Regeln haben.
enum AddItemSaveRules {
    /// Name (ohne Leerzeichen) nicht leer, Datum gewählt, kein Speichern im Gange.
    static func canSave(name: String, hasExpiryDate: Bool, isSaving: Bool) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && hasExpiryDate && !isSaving
    }

    /// Bietet der Datum-Scanner "übernehmen und speichern" an? Nur beim Anlegen,
    /// und nur, wenn das Formular mit dem gescannten Datum speicherbar wäre.
    static func offersSaveAfterDateScan(isEditMode: Bool, name: String, isSaving: Bool) -> Bool {
        !isEditMode && canSave(name: name, hasExpiryDate: true, isSaving: isSaving)
    }
}
