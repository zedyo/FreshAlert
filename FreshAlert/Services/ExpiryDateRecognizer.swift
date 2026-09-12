import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Vision

// MARK: - Ergebnistypen

/// Ein Datum, das im Etikettentext gefunden wurde.
/// `rawText` ist die Stelle, die zu diesem Datum geführt hat ("12.10.26"),
/// `confidence` die Konfidenz der Texterkennung, angepasst um Hinweise aus der
/// Zeile (MHD oder "haltbar bis" zählen mehr, Herstelldatum weniger).
struct ExpiryDateCandidate: Equatable {
    let date: Date
    let rawText: String
    let confidence: Float
}

/// Eine erkannte Textzeile. Trennt das Parsen von der Bilderkennung: der Parser
/// bekommt nur Text und Konfidenz und ist damit ohne Kamera testbar.
struct RecognizedTextLine: Equatable {
    let text: String
    let confidence: Float

    init(_ text: String, confidence: Float = 1) {
        self.text = text
        self.confidence = min(1, max(0, confidence))
    }
}

// MARK: - Parser (rein, testbar)

/// Findet Haltbarkeitsdaten in erkanntem Text. Deutsche Lesart: Tag vor Monat.
enum ExpiryDateParser {

    /// Fester gregorianischer Kalender, damit das Ergebnis nicht von den
    /// Regionseinstellungen des Geräts abhängt.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    /// Wie weit ein Datum von heute entfernt sein darf, um noch als
    /// Haltbarkeitsdatum durchzugehen. Hält Chargennummern draußen.
    static let earliestYearOffset = -10
    static let latestYearOffset = 20

    // MARK: Öffentliche Einstiege

    static func candidates(in text: String, confidence: Float = 1, now: Date = Date()) -> [ExpiryDateCandidate] {
        candidates(in: [RecognizedTextLine(text, confidence: confidence)], now: now)
    }

    static func candidates(in lines: [RecognizedTextLine], now: Date = Date()) -> [ExpiryDateCandidate] {
        var found: [ExpiryDateCandidate] = []
        for line in lines {
            found.append(contentsOf: candidates(inLine: line, now: now))
        }
        // Dasselbe Datum aus mehreren Zeilen nur einmal, mit der besten Konfidenz.
        var byDate: [Date: ExpiryDateCandidate] = [:]
        for candidate in found {
            if let existing = byDate[candidate.date], existing.confidence >= candidate.confidence { continue }
            byDate[candidate.date] = candidate
        }
        return sorted(Array(byDate.values), now: now)
    }

    /// Zukunft zuerst, das nächstliegende Datum vorn, Vergangenes hinten.
    static func sorted(_ candidates: [ExpiryDateCandidate], now: Date = Date()) -> [ExpiryDateCandidate] {
        let today = calendar.startOfDay(for: now)
        return candidates.sorted { lhs, rhs in
            let left = days(from: today, to: lhs.date)
            let right = days(from: today, to: rhs.date)
            if (left < 0) != (right < 0) { return right < 0 }
            if abs(left) != abs(right) { return abs(left) < abs(right) }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.date < rhs.date
        }
    }

    // MARK: Muster

    private enum Shape {
        case isoFull            // 2026-10-12
        case numericFull        // 12.10.2026, 12/10/26, 12-10-2026
        case dayMonthName       // 12. Okt 2026, 12 OKT 26
        case monthNameYear      // Okt 2026
        case numericMonthYear   // 10.2026, 10/26
    }

    private static let patterns: [(shape: Shape, regex: NSRegularExpression)] = {
        let raw: [(Shape, String)] = [
            (.isoFull, #"(?<!\d)(\d{4})[./-](\d{1,2})[./-](\d{1,2})(?!\d)"#),
            (.numericFull, #"(?<!\d)(\d{1,2})\s{0,2}[./-]\s{0,2}(\d{1,2})\s{0,2}[./-]\s{0,2}(\d{4}|\d{2})(?!\d)"#),
            (.dayMonthName, #"(?<![\p{L}\d])(\d{1,2})\s{0,2}\.?\s{0,2}([\p{L}]{3,9})\.?\s{0,2}(\d{4}|\d{2})(?!\d)"#),
            (.monthNameYear, #"(?<![\p{L}\d])([\p{L}]{3,9})\.?\s{0,2}(\d{4}|\d{2})(?!\d)"#),
            (.numericMonthYear, #"(?<!\d)(\d{1,2})\s{0,2}[./-]\s{0,2}(\d{4}|\d{2})(?!\d)"#),
        ]
        return raw.compactMap { shape, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return (shape, regex)
        }
    }()

    /// Wortstämme deutscher und englischer Monatsnamen, auf Umlaute normalisiert.
    private static let monthStems: [(stem: String, month: Int)] = [
        ("jan", 1), ("feb", 2), ("mar", 3), ("maer", 3), ("mrz", 3), ("apr", 4),
        ("mai", 5), ("may", 5), ("jun", 6), ("jul", 7), ("aug", 8),
        ("sep", 9), ("okt", 10), ("oct", 10), ("nov", 11), ("dez", 12), ("dec", 12),
    ]

    /// Wörter, die für ein Haltbarkeitsdatum sprechen.
    private static let expiryHints = ["mhd", "haltbar", "verbrauch", "best before", "mdh"]
    /// Wörter, die für ein Herstell- oder Abfülldatum sprechen.
    private static let productionHints = ["herstell", "hergestellt", "produziert", "abgefuellt", "abgefüllt", "verpackt", "gebraut"]

    // MARK: Eine Zeile

    private static func candidates(inLine line: RecognizedTextLine, now: Date) -> [ExpiryDateCandidate] {
        let text = line.text
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let lineConfidence = adjustedConfidence(line.confidence, text: text)

        var consumed: [NSRange] = []
        var result: [ExpiryDateCandidate] = []

        // Reihenfolge zählt: vollständige Daten zuerst, damit "12.10.2026" nicht
        // zusätzlich als "10.2026" durchgeht.
        for (shape, regex) in patterns {
            for match in regex.matches(in: text, options: [], range: whole) {
                let range = match.range
                if consumed.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
                guard let date = date(from: match, shape: shape, in: ns, now: now) else { continue }
                consumed.append(range)
                let penalty: Float = isPartial(shape) ? 0.1 : 0
                result.append(
                    ExpiryDateCandidate(
                        date: date,
                        rawText: ns.substring(with: range).trimmingCharacters(in: .whitespaces),
                        confidence: min(1, max(0, lineConfidence - penalty))
                    )
                )
            }
        }
        return result
    }

    private static func isPartial(_ shape: Shape) -> Bool {
        shape == .monthNameYear || shape == .numericMonthYear
    }

    private static func date(from match: NSTextCheckingResult, shape: Shape, in ns: NSString, now: Date) -> Date? {
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return ns.substring(with: range)
        }
        switch shape {
        case .isoFull:
            guard let year = number(group(1)), let month = number(group(2)), let day = number(group(3)) else { return nil }
            return date(day: day, month: month, year: year, now: now)
        case .numericFull:
            guard let day = number(group(1)), let month = number(group(2)), let year = fullYear(group(3)) else { return nil }
            return date(day: day, month: month, year: year, now: now)
        case .dayMonthName:
            guard let day = number(group(1)), let month = month(named: group(2)), let year = fullYear(group(3)) else { return nil }
            return date(day: day, month: month, year: year, now: now)
        case .monthNameYear:
            guard let month = month(named: group(1)), let year = fullYear(group(2)) else { return nil }
            return lastDayOfMonth(month: month, year: year, now: now)
        case .numericMonthYear:
            guard let month = number(group(1)), let year = fullYear(group(2)) else { return nil }
            return lastDayOfMonth(month: month, year: year, now: now)
        }
    }

    // MARK: Bausteine

    private static func number(_ text: String?) -> Int? {
        guard let text else { return nil }
        return Int(text)
    }

    /// "26" wird zu 2026, "2026" bleibt.
    private static func fullYear(_ text: String?) -> Int? {
        guard let value = number(text) else { return nil }
        return value < 100 ? 2000 + value : value
    }

    private static func month(named raw: String?) -> Int? {
        guard let raw else { return nil }
        let folded = raw.lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
        return monthStems.first { folded.hasPrefix($0.stem) }?.month
    }

    private static func date(day: Int, month: Int, year: Int, now: Date) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        // Fängt den 31.02. ab: der Kalender würde daraus den 03.03. machen.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return plausible(date, now: now) ? date : nil
    }

    /// "10.2026" meint den letzten Tag des Monats.
    private static func lastDayOfMonth(month: Int, year: Int, now: Date) -> Date? {
        guard (1...12).contains(month) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let first = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        return date(day: range.upperBound - 1, month: month, year: year, now: now)
    }

    private static func plausible(_ date: Date, now: Date) -> Bool {
        let year = calendar.component(.year, from: date)
        let current = calendar.component(.year, from: now)
        return year >= current + earliestYearOffset && year <= current + latestYearOffset
    }

    private static func adjustedConfidence(_ base: Float, text: String) -> Float {
        var value = base
        let lower = text.lowercased()
        if expiryHints.contains(where: { lower.contains($0) }) { value += 0.15 }
        if productionHints.contains(where: { lower.contains($0) }) { value -= 0.25 }
        return min(1, max(0, value))
    }

    private static func days(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }
}

// MARK: - Bilderkennung

enum ExpiryDateRecognizerError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "Das Bild konnte nicht gelesen werden"
        }
    }
}

/// Liest Text aus einem Bild und gibt die gefundenen Haltbarkeitsdaten zurück.
/// Läuft vollständig auf dem Gerät, es geht keine Anfrage ins Netz.
enum ExpiryDateRecognizer {

    private enum Source {
        case image(CGImage)
        case pixelBuffer(CVPixelBuffer)
    }

    static func candidates(
        in image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        now: Date = Date()
    ) async throws -> [ExpiryDateCandidate] {
        let lines = try await recognize(.image(image), orientation: orientation)
        return ExpiryDateParser.candidates(in: lines, now: now)
    }

    static func candidates(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up,
        now: Date = Date()
    ) async throws -> [ExpiryDateCandidate] {
        let lines = try await recognize(.pixelBuffer(pixelBuffer), orientation: orientation)
        return ExpiryDateParser.candidates(in: lines, now: now)
    }

    /// Für Bilddaten aus der Mediathek oder einem Foto. Die Ausrichtung kommt
    /// aus den EXIF-Daten, sonst liest Vision ein gedrehtes Foto nicht.
    static func candidates(in data: Data, now: Date = Date()) async throws -> [ExpiryDateCandidate] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ExpiryDateRecognizerError.unreadableImage
        }
        var orientation = CGImagePropertyOrientation.up
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let raw = properties[kCGImagePropertyOrientation] as? UInt32,
           let exif = CGImagePropertyOrientation(rawValue: raw) {
            orientation = exif
        }
        return try await candidates(in: image, orientation: orientation, now: now)
    }

    // MARK: Vision

    private static func recognize(
        _ source: Source,
        orientation: CGImagePropertyOrientation
    ) async throws -> [RecognizedTextLine] {
        if #available(iOS 18.0, *) {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]
            let observations: [RecognizedTextObservation]
            switch source {
            case .image(let image):
                observations = try await request.perform(on: image, orientation: orientation)
            case .pixelBuffer(let buffer):
                observations = try await request.perform(on: buffer, orientation: orientation)
            }
            return observations.compactMap { observation in
                guard let top = observation.topCandidates(1).first else { return nil }
                return RecognizedTextLine(top.string, confidence: weighted(top.confidence, box: observation.boundingBox.cgRect))
            }
        }

        // iOS 17: die ältere Vision-API, sonst startet die App dort nicht.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["de-DE", "en-US"]
        let handler: VNImageRequestHandler
        switch source {
        case .image(let image):
            handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        case .pixelBuffer(let buffer):
            handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation)
        }
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let top = observation.topCandidates(1).first else { return nil }
            return RecognizedTextLine(top.string, confidence: weighted(top.confidence, box: observation.boundingBox))
        }
    }

    /// Text in der Bildmitte, also im Rahmen, zählt mehr als Text am Rand.
    private static func weighted(_ confidence: Float, box: CGRect) -> Float {
        let distance = hypot(box.midX - 0.5, box.midY - 0.5)
        let closeness = Float(max(0, 1 - distance / 0.7))
        return confidence * (0.75 + 0.25 * closeness)
    }
}
