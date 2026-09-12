import XCTest
@testable import FreshAlert

/// Der Haltbarkeitsvorschlag aus den Open-Food-Facts-Kategorien.
final class ShelfLifeSuggestionTests: XCTestCase {

    func testSpezifischsterTagGewinnt() throws {
        let tags = ["en:dairies", "en:fermented-milk-products", "en:yogurts"]
        let suggestion = try XCTUnwrap(ShelfLifeSuggestion.suggestion(for: tags))
        XCTAssertEqual(suggestion.label, "Joghurt")
        XCTAssertEqual(suggestion.tag, "en:yogurts")
    }

    func testSpezifischsterTagGewinntAuchInUmgekehrterReihenfolge() throws {
        let tags = ["en:yogurts", "en:fermented-milk-products", "en:dairies"]
        let suggestion = try XCTUnwrap(ShelfLifeSuggestion.suggestion(for: tags))
        XCTAssertEqual(suggestion.tag, "en:yogurts")
    }

    func testHartkaeseGewinntGegenKaese() throws {
        let tags = ["en:dairies", "en:cheeses", "en:hard-cheeses"]
        XCTAssertEqual(try XCTUnwrap(ShelfLifeSuggestion.suggestion(for: tags)).label, "Hartkäse")
    }

    func testAllgemeinerTagBleibtWennNichtsSpezifischeresDaIst() throws {
        XCTAssertEqual(try XCTUnwrap(ShelfLifeSuggestion.suggestion(for: ["en:dairies"])).label, "Milchprodukt")
    }

    func testGrossschreibungUndLeerzeichenStoerenNicht() throws {
        XCTAssertEqual(try XCTUnwrap(ShelfLifeSuggestion.suggestion(for: [" EN:Yogurts "])).tag, "en:yogurts")
    }

    // MARK: Ohne Treffer

    func testUnbekannterTagGibtKeinenVorschlag() {
        XCTAssertNil(ShelfLifeSuggestion.suggestion(for: ["en:einhornfutter", "de:quatsch"]))
    }

    func testLeereListeGibtKeinenVorschlag() {
        XCTAssertNil(ShelfLifeSuggestion.suggestion(for: []))
    }

    // MARK: Tabelle

    func testTabelleIstGrossGenug() {
        XCTAssertGreaterThanOrEqual(ShelfLifeSuggestion.table.count, 25)
    }

    func testJederTagKommtNurEinmalVor() {
        let tags = ShelfLifeSuggestion.table.map(\.tag)
        XCTAssertEqual(Set(tags).count, tags.count)
    }

    func testAlleTagsSindOpenFoodFactsTags() {
        for entry in ShelfLifeSuggestion.table {
            XCTAssertTrue(entry.tag.hasPrefix("en:"), "\(entry.tag) sieht nicht wie ein OFF-Tag aus")
            XCTAssertEqual(entry.tag, entry.tag.lowercased())
        }
    }

    func testGeoeffnetHaeltImmerKuerzerAlsUngeoeffnet() {
        for entry in ShelfLifeSuggestion.table {
            XCTAssertLessThan(entry.openedDays, entry.unopenedDays, "\(entry.tag)")
            XCTAssertGreaterThan(entry.openedDays, 0, "\(entry.tag)")
        }
    }

    // MARK: Texte und Datum

    func testSatzFuerJoghurt() throws {
        let joghurt = try XCTUnwrap(ShelfLifeSuggestion.suggestion(for: ["en:yogurts"]))
        XCTAssertEqual(ShelfLifeSuggestion.sentence(for: joghurt), "Joghurt hält meist etwa 2 Wochen")
        XCTAssertEqual(ShelfLifeSuggestion.openedSentence(for: joghurt), "Geöffnet meist etwa 3 Tage")
    }

    func testDauertext() {
        XCTAssertEqual(ShelfLifeSuggestion.durationText(days: 1), "einen Tag")
        XCTAssertEqual(ShelfLifeSuggestion.durationText(days: 3), "3 Tage")
        XCTAssertEqual(ShelfLifeSuggestion.durationText(days: 14), "2 Wochen")
        XCTAssertEqual(ShelfLifeSuggestion.durationText(days: 60), "2 Monate")
        XCTAssertEqual(ShelfLifeSuggestion.durationText(days: 365), "ein Jahr")
        XCTAssertEqual(ShelfLifeSuggestion.durationText(days: 1095), "3 Jahre")
    }

    func testVorgeschlagenesDatumLiegtAmTagesanfang() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let basis = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 18))!
        let ziel = ShelfLifeSuggestion.date(addingDays: 16, to: basis, calendar: calendar)
        XCTAssertEqual(ziel, calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!)
    }
}
