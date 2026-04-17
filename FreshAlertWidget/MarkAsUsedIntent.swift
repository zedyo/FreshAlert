import AppIntents
import WidgetKit

struct MarkAsUsedIntent: AppIntent {
    static var title: LocalizedStringResource = "Als verwendet markieren"
    static var description = IntentDescription("Markiert ein Produkt als verwendet und vermindert die Menge um 1.")

    @Parameter(title: "Produkt-ID")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: itemID) {
            WidgetDataStore.queueDecrement(id: id)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
