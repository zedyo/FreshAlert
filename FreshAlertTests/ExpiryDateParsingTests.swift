import XCTest
@testable import FreshAlert

/// Das Parsen der erkannten Textzeilen. Reine Funktion, ohne Kamera und ohne Vision.
final class ExpiryDateParsingTests: XCTestCase {

    /// Fester Bezugstag, damit "Zukunft" und "Vergangenheit" prüfbar sind.
    private let heute = ExpiryDateParsingTests.tag(2026, 9, 12)

    private static func tag(_ year: Int, _ month: Int, _ day: Int) -> Date {
        ExpiryDateParser.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func erstes(_ text: String, confidence: Float = 1) throws -> ExpiryDateCandidate {
        let candidates = ExpiryDateParser.candidates(in: text, confidence: confidence, now: heute)
        return try XCTUnwrap(candidates.first, "kein Datum in \"\(text)\"")
    }

    // MARK: Formate auf deutschen Verpackungen

    func testPunktFormatMitVierstelligemJahr() throws {
        XCTAssertEqual(try erstes("12.10.2026").date, Self.tag(2026, 10, 12))
    }

    func testPunktFormatMitZweistelligemJahr() throws {
        XCTAssertEqual(try erstes("12.10.26").date, Self.tag(2026, 10, 12))
    }

    func testSchraegstrichFormat() throws {
        XCTAssertEqual(try erstes("12/10/2026").date, Self.tag(2026, 10, 12))
    }

    func testBindestrichFormat() throws {
        XCTAssertEqual(try erstes("12-10-2026").date, Self.tag(2026, 10, 12))
    }

    func testMhdVorDemDatum() throws {
        XCTAssertEqual(try erstes("MHD 12.10.26").date, Self.tag(2026, 10, 12))
    }

    func testMindestensHaltbarBis() throws {
        XCTAssertEqual(try erstes("mindestens haltbar bis 12.10.2026").date, Self.tag(2026, 10, 12))
    }

    func testVerbrauchenBis() throws {
        XCTAssertEqual(try erstes("verbrauchen bis 12.10.26").date, Self.tag(2026, 10, 12))
    }

    func testMonatsnameMitPunkt() throws {
        XCTAssertEqual(try erstes("12. Okt 2026").date, Self.tag(2026, 10, 12))
    }

    func testMonatsnameInGrossbuchstaben() throws {
        XCTAssertEqual(try erstes("12 OKT 26").date, Self.tag(2026, 10, 12))
    }

    func testAusgeschriebenerMonatsname() throws {
        XCTAssertEqual(try erstes("12. Dezember 2026").date, Self.tag(2026, 12, 12))
    }

    func testMonatsnameMitUmlaut() throws {
        XCTAssertEqual(try erstes("03. März 2027").date, Self.tag(2027, 3, 3))
    }

    /// Deutsche Lesart: Tag vor Monat, nicht amerikanisch.
    func testTagVorMonat() throws {
        XCTAssertEqual(try erstes("05.11.2026").date, Self.tag(2026, 11, 5))
    }

    // MARK: Nur Monat und Jahr

    func testNurMonatUndJahrWirdLetzterTagDesMonats() throws {
        XCTAssertEqual(try erstes("10.2026").date, Self.tag(2026, 10, 31))
    }

    func testNurMonatUndJahrMitSchraegstrich() throws {
        XCTAssertEqual(try erstes("10/26").date, Self.tag(2026, 10, 31))
    }

    func testNurMonatUndJahrKenntSchaltjahr() throws {
        XCTAssertEqual(try erstes("02.2028").date, Self.tag(2028, 2, 29))
    }

    func testMonatsnameOhneTagWirdLetzterTagDesMonats() throws {
        XCTAssertEqual(try erstes("MHD Okt 2026").date, Self.tag(2026, 10, 31))
    }

    /// Ein vollständiges Datum darf nicht zusätzlich als Monat und Jahr durchgehen.
    func testVollstaendigesDatumErzeugtNurEinenKandidaten() {
        let candidates = ExpiryDateParser.candidates(in: "12.10.2026", now: heute)
        XCTAssertEqual(candidates.count, 1)
    }

    // MARK: Reihenfolge

    func testVergangenheitStehtHinten() throws {
        let lines = [
            RecognizedTextLine("Hergestellt 01.03.2026"),
            RecognizedTextLine("MHD 12.10.2026"),
        ]
        let candidates = ExpiryDateParser.candidates(in: lines, now: heute)
        XCTAssertEqual(candidates.first?.date, Self.tag(2026, 10, 12))
        XCTAssertEqual(candidates.last?.date, Self.tag(2026, 3, 1))
    }

    func testNaechstesZukunftsdatumZuerst() throws {
        let lines = [
            RecognizedTextLine("12.12.2027"),
            RecognizedTextLine("01.10.2026"),
            RecognizedTextLine("20.09.2026"),
        ]
        let dates = ExpiryDateParser.candidates(in: lines, now: heute).map(\.date)
        XCTAssertEqual(dates, [
            Self.tag(2026, 9, 20), Self.tag(2026, 10, 1), Self.tag(2027, 12, 12),
        ])
    }

    func testHeuteZaehltNichtAlsVergangenheit() throws {
        let lines = [RecognizedTextLine("01.01.2026"), RecognizedTextLine("12.09.2026")]
        let candidates = ExpiryDateParser.candidates(in: lines, now: heute)
        XCTAssertEqual(candidates.first?.date, heute)
    }

    // MARK: Rohtext und Konfidenz

    func testRohtextIstDieGefundeneStelle() throws {
        XCTAssertEqual(try erstes("MHD 12.10.26").rawText, "12.10.26")
    }

    func testHinweisWortHebtDieKonfidenz() throws {
        let mitHinweis = try erstes("MHD 12.10.2026", confidence: 0.7)
        let ohneHinweis = try erstes("12.10.2026", confidence: 0.7)
        XCTAssertGreaterThan(mitHinweis.confidence, ohneHinweis.confidence)
    }

    func testHerstelldatumSenktDieKonfidenz() throws {
        let hergestellt = try erstes("Hergestellt am 12.10.2026", confidence: 0.9)
        let neutral = try erstes("12.10.2026", confidence: 0.9)
        XCTAssertLessThan(hergestellt.confidence, neutral.confidence)
    }

    func testDoppeltesDatumErscheintNurEinmal() {
        let lines = [RecognizedTextLine("12.10.2026"), RecognizedTextLine("MHD 12.10.2026")]
        XCTAssertEqual(ExpiryDateParser.candidates(in: lines, now: heute).count, 1)
    }

    // MARK: Was kein Datum ist

    func testChargennummerIstKeinDatum() {
        XCTAssertTrue(ExpiryDateParser.candidates(in: "Charge L4711 25", now: heute).isEmpty)
        XCTAssertTrue(ExpiryDateParser.candidates(in: "Lot 123456", now: heute).isEmpty)
        XCTAssertTrue(ExpiryDateParser.candidates(in: "Inhalt 500 g", now: heute).isEmpty)
    }

    func testUnmoeglichesDatumWirdVerworfen() {
        XCTAssertTrue(ExpiryDateParser.candidates(in: "45.13.2026", now: heute).isEmpty)
    }

    func testLaengstVergangenesJahrWirdVerworfen() {
        XCTAssertTrue(ExpiryDateParser.candidates(in: "12.10.1999", now: heute).isEmpty)
    }
}
