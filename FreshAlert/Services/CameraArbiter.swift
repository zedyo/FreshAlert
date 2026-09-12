import AVFoundation
import Foundation
import os

/// Gemeinsames Log beider Kamera-Ansichten. Im Gerätelog unter
/// `subsystem:com.freshalert.app category:camera` zu finden.
let cameraLog = Logger(subsystem: "com.freshalert.app", category: "camera")

/// Führt `block` auf dem Main-Actor aus, egal von welcher Queue der Aufruf kommt.
/// Die AVFoundation-Rückrufe landen auf der Session-Queue, die Ansichten sind
/// aber Main-Actor.
func aufMainActor(_ block: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { block() }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { block() } }
    }
}

// MARK: - Zustand einer Kameravorschau

/// Warum die Kamera unterbrochen wurde. Übersetzt `AVCaptureSession.InterruptionReason`
/// in etwas, das man einem Menschen zeigen kann.
enum CameraInterruption: Equatable {
    /// Eine andere Stelle hält die Kamera. Genau der Fall, wenn Barcode- und
    /// Datum-Scanner gleichzeitig laufen wollen.
    case inUseByAnotherClient
    case background
    case multipleForegroundApps
    case systemPressure
    case unknown

    init(rawReason: Int?) {
        switch AVCaptureSession.InterruptionReason(rawValue: rawReason ?? -1) {
        case .videoDeviceInUseByAnotherClient, .audioDeviceInUseByAnotherClient:
            self = .inUseByAnotherClient
        case .videoDeviceNotAvailableInBackground:
            self = .background
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            self = .multipleForegroundApps
        case .videoDeviceNotAvailableDueToSystemPressure:
            self = .systemPressure
        default:
            self = .unknown
        }
    }

    /// Text für den Datum-Scanner.
    var hinweis: String {
        switch self {
        case .inUseByAnotherClient:
            return "Die Kamera ist gerade belegt. Schließe den Barcode-Scanner und versuche es erneut."
        case .background:
            return "Die Kamera steht im Hintergrund nicht zur Verfügung."
        case .multipleForegroundApps:
            return "Die Kamera steht im geteilten Bildschirm nicht zur Verfügung."
        case .systemPressure:
            return "Die Kamera pausiert, weil das Gerät zu warm ist. Gleich noch einmal versuchen."
        case .unknown:
            return "Die Kamera wurde unterbrochen. Versuche es erneut."
        }
    }

    /// Kurzfassung für die Pille im Barcode-Scanner.
    var kurzhinweis: String {
        switch self {
        case .inUseByAnotherClient: return "Kamera gerade belegt"
        case .background:           return "Kamera pausiert"
        case .multipleForegroundApps: return "Kamera nicht verfügbar"
        case .systemPressure:       return "Kamera pausiert, Gerät zu warm"
        case .unknown:              return "Kamera unterbrochen"
        }
    }

    var protokollname: String {
        switch self {
        case .inUseByAnotherClient: return "inUseByAnotherClient"
        case .background: return "background"
        case .multipleForegroundApps: return "multipleForegroundApps"
        case .systemPressure: return "systemPressure"
        case .unknown: return "unknown"
        }
    }
}

/// Was die Vorschau gerade tut. Die SwiftUI-Seite macht daraus eine Meldung,
/// statt ein eingefrorenes oder schwarzes Bild stehen zu lassen.
enum CameraStatus: Equatable {
    /// Noch nichts aufgebaut oder bewusst pausiert.
    case idle
    /// Aufbau läuft, wartet eventuell noch auf die Freigabe der anderen Ansicht.
    case starting
    case running
    case interrupted(CameraInterruption)
    /// Kamera konnte nicht aufgebaut werden (kein Gerät, Laufzeitfehler).
    case failed(String)

    var istStoerung: Bool {
        switch self {
        case .interrupted, .failed: return true
        case .idle, .starting, .running: return false
        }
    }

    /// Text für den Datum-Scanner, `nil` wenn alles in Ordnung ist.
    var meldung: String? {
        switch self {
        case .interrupted(let grund): return grund.hinweis
        case .failed(let text): return text
        case .idle, .starting, .running: return nil
        }
    }

    /// Kurzfassung für die Pille im Barcode-Scanner.
    var kurzmeldung: String? {
        switch self {
        case .interrupted(let grund): return grund.kurzhinweis
        case .failed(let text): return text
        case .idle, .starting, .running: return nil
        }
    }
}

// MARK: - Kameravergabe

/// Vergibt die Rückkamera an genau eine Ansicht.
///
/// Zwei `AVCaptureSession` auf demselben `AVCaptureDevice` laufen unter iOS nicht
/// gleichzeitig: die zweite wird sofort mit `videoDeviceInUseByAnotherClient`
/// unterbrochen und zeigt ein eingefrorenes Bild. Deshalb geht jede Vorschau
/// über diese Stelle. Der neue Besitzer startet erst, wenn der alte gemeldet hat,
/// dass seine Session abgebaut ist.
@MainActor
final class CameraArbiter {
    static let shared = CameraArbiter()

    enum Owner: String {
        case barcode = "Barcode-Scanner"
        case expiryDate = "Datum-Scanner"
    }

    /// Abbauen und danach `fertig()` rufen, egal von welcher Queue.
    typealias Teardown = (_ fertig: @escaping @Sendable () -> Void) -> Void

    private final class Claim {
        let owner: Owner
        weak var claimant: AnyObject?
        let teardown: Teardown
        let granted: () -> Void

        init(owner: Owner, claimant: AnyObject, teardown: @escaping Teardown, granted: @escaping () -> Void) {
            self.owner = owner
            self.claimant = claimant
            self.teardown = teardown
            self.granted = granted
        }
    }

    private var current: Claim?
    /// Höchstens eine Anfrage wartet. Eine neuere ersetzt die ältere.
    private var pending: Claim?
    /// Solange der alte Besitzer abbaut, wird nichts vergeben.
    private var isHandingOver = false

    private init() {}

    /// Wer gerade die Kamera hält. Nur für Protokoll und Tests.
    var currentOwner: Owner? { current?.owner }

    /// Fordert die Kamera an. `granted` läuft auf dem Main-Actor und erst, wenn
    /// der bisherige Besitzer seine Session wirklich abgebaut hat.
    func acquire(
        _ owner: Owner,
        claimant: AnyObject,
        teardown: @escaping Teardown,
        granted: @escaping () -> Void
    ) {
        let claim = Claim(owner: owner, claimant: claimant, teardown: teardown, granted: granted)

        // Derselbe Anfragende noch einmal: er hat sie schon.
        if let current, current.claimant === claimant, !isHandingOver {
            self.current = claim
            claim.granted()
            return
        }

        if current == nil, !isHandingOver {
            current = claim
            cameraLog.info("Kamera an \(owner.rawValue, privacy: .public)")
            claim.granted()
            return
        }

        cameraLog.info("\(owner.rawValue, privacy: .public) wartet auf die Kamera")
        pending = claim
        beginHandover()
    }

    /// Gibt die Kamera zurück. Der Abbau läuft über dieselbe Teardown-Closure,
    /// damit es nur einen Weg gibt, auf dem das Gerät frei wird.
    func release(_ claimant: AnyObject) {
        if let pending, pending.claimant === claimant { self.pending = nil }
        guard let current, current.claimant === claimant else { return }
        cameraLog.info("\(current.owner.rawValue, privacy: .public) gibt die Kamera frei")
        beginHandover()
    }

    // MARK: Übergabe

    private func beginHandover() {
        guard !isHandingOver else { return }
        guard let leaving = current else {
            servePending()
            return
        }
        isHandingOver = true
        leaving.teardown {
            // Kommt von der Session-Queue der Vorschau.
            Task { @MainActor in CameraArbiter.shared.handoverFinished() }
        }
    }

    private func handoverFinished() {
        current = nil
        isHandingOver = false
        servePending()
    }

    private func servePending() {
        guard let next = pending else { return }
        pending = nil
        current = next
        cameraLog.info("Kamera an \(next.owner.rawValue, privacy: .public)")
        next.granted()
    }
}
