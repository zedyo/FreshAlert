import Foundation
import SwiftData

/// Was mit einem Exemplar passiert ist.
enum ConsumptionOutcome: String, Codable, CaseIterable, Sendable {
    case consumed
    case discarded
}

/// Ein Satz je Vorgang: ein oder mehrere Exemplare eines Produkts wurden
/// verbraucht oder weggeworfen. Bewusst ohne Referenz auf FoodItem oder
/// StorageLocation, denn beide dürfen gelöscht werden, ohne dass die
/// Statistik Lücken bekommt. Deshalb stehen hier Kopien der Namen.
@Model
final class ConsumptionRecord {
    @Attribute(.unique) var id: UUID
    var productName: String
    var brand: String
    var barcode: String
    /// Platz für eine Kategorie, sobald Produkte eine tragen. Bis dahin leer.
    var categoryTag: String?
    /// Name statt Referenz. Leer, wenn das Produkt keinen Lagerort hatte.
    var storageLocationName: String
    /// Wie viele Exemplare dieser Vorgang betrifft.
    var quantity: Int
    /// `ConsumptionOutcome` als String abgelegt, das hält Abfragen einfach.
    var outcomeRaw: String
    var recordedAt: Date
    var expiryDate: Date
    /// Negativ: vor dem Haltbarkeitsdatum, positiv: danach.
    var daysEarlyOrLate: Int

    init(
        id: UUID = UUID(),
        productName: String,
        brand: String = "",
        barcode: String = "",
        categoryTag: String? = nil,
        storageLocationName: String = "",
        quantity: Int = 1,
        outcome: ConsumptionOutcome,
        recordedAt: Date = Date(),
        expiryDate: Date,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.productName = productName
        self.brand = brand
        self.barcode = barcode
        self.categoryTag = categoryTag
        self.storageLocationName = storageLocationName
        self.quantity = max(1, quantity)
        self.outcomeRaw = outcome.rawValue
        self.recordedAt = recordedAt
        self.expiryDate = expiryDate
        self.daysEarlyOrLate = Self.daysEarlyOrLate(
            expiryDate: expiryDate, recordedAt: recordedAt, calendar: calendar
        )
    }

    var outcome: ConsumptionOutcome {
        get { ConsumptionOutcome(rawValue: outcomeRaw) ?? .consumed }
        set { outcomeRaw = newValue.rawValue }
    }

    /// Ganze Tage zwischen Haltbarkeitsdatum und Vorgang.
    static func daysEarlyOrLate(
        expiryDate: Date, recordedAt: Date, calendar: Calendar = .current
    ) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: expiryDate),
            to: calendar.startOfDay(for: recordedAt)
        ).day ?? 0
    }
}
