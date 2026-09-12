import XCTest
@testable import FreshAlert

/// Icon und Farbe aus dem Namen eines eigenen Lagerorts.
final class StorageLocationSuggestionTests: XCTestCase {

    private func icon(_ name: String) -> String {
        StorageLocation.suggestion(forName: name).iconName
    }

    func testKeywordsPickIcon() {
        XCTAssertEqual(icon("Kühlbox"), "thermometer.snowflake")
        XCTAssertEqual(icon("kuehlbox"), "thermometer.snowflake")
        XCTAssertEqual(icon("Gefrierfach"), "snowflake")
        XCTAssertEqual(icon("Eisfach"), "snowflake")
        XCTAssertEqual(icon("Bierkeller"), "building.columns")
        XCTAssertEqual(icon("Obstschale"), "basket")
        XCTAssertEqual(icon("Getränkekiste"), "waterbottle")
        XCTAssertEqual(icon("Flaschenregal"), "waterbottle")
        XCTAssertEqual(icon("Gewürzschublade"), "flame")
        XCTAssertEqual(icon("Brotdose"), "basket.fill")
    }

    func testTiefkuehlerIsFreezerNotFridge() {
        XCTAssertEqual(icon("Tiefkühltruhe"), "snowflake")
    }

    func testSpeisekammerIsNotAFreezer() {
        XCTAssertEqual(icon("Speisekammer"), "archivebox")
    }

    func testUnknownNameGetsGreenBox() {
        let s = StorageLocation.suggestion(forName: "Garage")
        XCTAssertEqual(s.iconName, "archivebox")
        XCTAssertEqual(s.colorHex, "#34C759")
    }

    func testFridgeColorIsBlue() {
        XCTAssertEqual(StorageLocation.suggestion(forName: "Kühlschrank").colorHex, "#5AC8FA")
    }

    func testTemplatesAreUniqueAndStartWithDefaults() {
        let names = StorageLocation.allTemplates.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names.count, 14)
        XCTAssertEqual(StorageLocation.defaultTemplates.map(\.name),
                       ["Kühlschrank", "Tiefkühler", "Vorratsschrank", "Keller", "Obstkorb"])
    }
}
