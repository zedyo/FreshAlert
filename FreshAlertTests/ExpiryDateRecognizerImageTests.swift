import XCTest
import UIKit
@testable import FreshAlert

/// Prüft die Texterkennung selbst, nicht nur den Parser: ein im Code gemaltes
/// Etikett geht durch Vision und muss als Haltbarkeitsdatum herauskommen.
/// Schlägt das hier fehl, liegt der Fehler in der Erkennung, nicht an der Kamera.
final class ExpiryDateRecognizerImageTests: XCTestCase {

    /// Fester Bezugstag, damit der Plausibilitätsfilter (heute −10 bis +20 Jahre)
    /// den Test nicht irgendwann von allein rot werden lässt.
    private let referenz: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 13
        return ExpiryDateParser.calendar.date(from: components)!
    }()

    // MARK: - Bild bauen

    /// Weißer Grund, schwarzer Text, zentriert.
    private func etikett(
        _ text: String,
        size: CGSize = CGSize(width: 900, height: 300),
        schriftgroesse: CGFloat = 110
    ) throws -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let bild = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let absatz = NSMutableParagraphStyle()
            absatz.alignment = .center
            let attribute: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: schriftgroesse, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: absatz,
            ]
            let zeile = NSAttributedString(string: text, attributes: attribute)
            let gemessen = zeile.boundingRect(
                with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            zeile.draw(
                with: CGRect(
                    x: 0,
                    y: (size.height - gemessen.height) / 2,
                    width: size.width,
                    height: gemessen.height
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        return try XCTUnwrap(bild.cgImage, "Das gerenderte Bild hat kein CGImage")
    }

    // MARK: - Tests

    /// Der Kernfall: großes, aufrechtes "MHD 12.10.2026".
    func testErkenntMhdAufWeissemGrund() async throws {
        let bild = try etikett("MHD 12.10.2026")
        let treffer = try await ExpiryDateRecognizer.candidates(in: bild, now: referenz)

        XCTAssertFalse(treffer.isEmpty, "Vision hat im Testbild gar kein Datum gefunden")
        let erwartet = try XCTUnwrap(
            ExpiryDateParser.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))
        )
        XCTAssertEqual(
            treffer.first?.date,
            erwartet,
            "Bester Vorschlag war \(treffer.map(\.rawText))"
        )
    }

    /// Zwei Zeilen, wie auf einem echten Deckel. Der Parser muss trotzdem das
    /// Haltbarkeitsdatum vorn haben.
    func testErkenntZweizeiligesEtikett() async throws {
        let bild = try etikett(
            "mindestens haltbar bis\n12.10.2026",
            size: CGSize(width: 900, height: 420),
            schriftgroesse: 86
        )
        let treffer = try await ExpiryDateRecognizer.candidates(in: bild, now: referenz)

        let erwartet = try XCTUnwrap(
            ExpiryDateParser.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))
        )
        XCTAssertEqual(treffer.first?.date, erwartet, "Erkannt: \(treffer.map(\.rawText))")
    }

    /// Dasselbe Bild um 90 Grad gedreht, mit passender Orientierungsangabe.
    /// Das ist genau der Weg, den die Kamera nimmt, wenn die Verbindung das
    /// Bild nicht selbst drehen kann.
    func testErkenntGedrehtesBildMitOrientierung() async throws {
        let aufrecht = try etikett("MHD 12.10.2026")
        let gedreht = try quer(aufrecht)

        let treffer = try await ExpiryDateRecognizer.candidates(
            in: gedreht,
            orientation: .right,
            now: referenz
        )
        let erwartet = try XCTUnwrap(
            ExpiryDateParser.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))
        )
        XCTAssertEqual(treffer.first?.date, erwartet, "Erkannt: \(treffer.map(\.rawText))")
    }

    /// Kleine Schrift, wie auf einer Folie: ungefähr 4 % der Bildhöhe.
    /// Fällt das hier durch, ist die minimale Texthöhe das Problem.
    func testErkenntKleineSchrift() async throws {
        let bild = try etikett(
            "MHD 12.10.2026",
            size: CGSize(width: 1920, height: 1080),
            schriftgroesse: 44
        )
        let treffer = try await ExpiryDateRecognizer.candidates(in: bild, now: referenz)

        let erwartet = try XCTUnwrap(
            ExpiryDateParser.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))
        )
        XCTAssertEqual(treffer.first?.date, erwartet, "Erkannt: \(treffer.map(\.rawText))")
    }

    // MARK: - Hilfen

    /// Dreht ein Bild so, wie die Kamera es liefert: gegen den Uhrzeigersinn,
    /// also muss es zum Anzeigen um 90 Grad im Uhrzeigersinn zurück. Genau das
    /// bedeutet `CGImagePropertyOrientation.right`.
    /// Gezeichnet wird über `UIImage.draw`, weil `CGContext.draw` im
    /// UIKit-Kontext das Bild zusätzlich spiegeln würde.
    private func quer(_ bild: CGImage) throws -> CGImage {
        let breite = bild.height
        let hoehe = bild.width
        let aufrecht = UIImage(cgImage: bild)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: breite, height: hoehe))
        let gedreht = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: 0, y: CGFloat(hoehe))
            cg.rotate(by: -.pi / 2)
            aufrecht.draw(in: CGRect(x: 0, y: 0, width: CGFloat(hoehe), height: CGFloat(breite)))
        }
        return try XCTUnwrap(gedreht.cgImage, "Das gedrehte Bild hat kein CGImage")
    }
}
