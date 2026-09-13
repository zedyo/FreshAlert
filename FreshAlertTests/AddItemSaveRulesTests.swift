import XCTest
@testable import FreshAlert

/// Speichern-Knopf und "übernehmen und speichern" im Datum-Scanner teilen dieselben Regeln.
final class AddItemSaveRulesTests: XCTestCase {

    // MARK: canSave

    func testSpeichernMitNameUndDatum() {
        XCTAssertTrue(AddItemSaveRules.canSave(name: "Naturjoghurt", hasExpiryDate: true, isSaving: false))
    }

    func testOhneNameKeinSpeichern() {
        XCTAssertFalse(AddItemSaveRules.canSave(name: "", hasExpiryDate: true, isSaving: false))
    }

    func testNurLeerzeichenZaehlenNichtAlsName() {
        XCTAssertFalse(AddItemSaveRules.canSave(name: "   ", hasExpiryDate: true, isSaving: false))
    }

    func testOhneDatumKeinSpeichern() {
        XCTAssertFalse(AddItemSaveRules.canSave(name: "Milch", hasExpiryDate: false, isSaving: false))
    }

    func testWaehrendDesSpeichernsKeinZweitesMal() {
        XCTAssertFalse(AddItemSaveRules.canSave(name: "Milch", hasExpiryDate: true, isSaving: true))
    }

    // MARK: offersSaveAfterDateScan

    func testSchnellspeichernBeimAnlegenMitName() {
        XCTAssertTrue(AddItemSaveRules.offersSaveAfterDateScan(isEditMode: false, name: "Milch", isSaving: false))
    }

    func testKeinSchnellspeichernBeimBearbeiten() {
        XCTAssertFalse(AddItemSaveRules.offersSaveAfterDateScan(isEditMode: true, name: "Milch", isSaving: false))
    }

    func testKeinSchnellspeichernOhneName() {
        XCTAssertFalse(AddItemSaveRules.offersSaveAfterDateScan(isEditMode: false, name: " ", isSaving: false))
    }

    func testKeinSchnellspeichernWaehrendDesSpeicherns() {
        XCTAssertFalse(AddItemSaveRules.offersSaveAfterDateScan(isEditMode: false, name: "Milch", isSaving: true))
    }

    /// Das gescannte Datum ersetzt das fehlende, sonst gelten dieselben Regeln wie beim Knopf.
    func testSchnellspeichernEntsprichtSpeichernMitDatum() {
        for name in ["", " ", "Käse"] {
            for isSaving in [false, true] {
                XCTAssertEqual(
                    AddItemSaveRules.offersSaveAfterDateScan(isEditMode: false, name: name, isSaving: isSaving),
                    AddItemSaveRules.canSave(name: name, hasExpiryDate: true, isSaving: isSaving)
                )
            }
        }
    }
}
