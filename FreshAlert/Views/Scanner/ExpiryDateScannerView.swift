import SwiftUI
import AVFoundation
import ImageIO

/// Liest das Haltbarkeitsdatum vom Etikett. Läuft offline auf dem Gerät,
/// es wird nichts aufgenommen und nichts verschickt.
struct ExpiryDateScannerView: View {
    /// Wird mit dem übernommenen Datum aufgerufen, danach schließt die Ansicht.
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    /// Der Vorschlag, der gerade als Pille angeboten wird.
    @State private var bestCandidate: ExpiryDateCandidate?
    /// Zwischenstand: erst wenn dasselbe Datum zweimal hintereinander gelesen
    /// wurde, wird es angeboten. Sonst flackert die Pille bei jedem Bild.
    @State private var pendingCandidate: ExpiryDateCandidate?
    @State private var pendingHits = 0
    @State private var isVisible = false
    /// Was die Kamera gerade tut. Eine Unterbrechung wird gemeldet, statt ein
    /// eingefrorenes Bild stehen zu lassen.
    @State private var cameraStatus: CameraStatus = .idle
    /// Wird hochgezählt, um die Session hart neu aufzubauen.
    @State private var cameraRebuild = 0

    var body: some View {
        NavigationStack {
            ZStack {
                if cameraPermission == .authorized {
                    cameraView
                } else {
                    permissionView
                }
            }
            .navigationTitle("Datum scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onAppear {
                isVisible = true
                checkCameraPermission()
            }
            .onDisappear { isVisible = false }
        }
    }

    /// Kamera ruht, sobald die Ansicht weg ist oder die App in den Hintergrund geht.
    private var isPaused: Bool {
        !isVisible || scenePhase != .active
    }

    // MARK: - Kamera

    private var cameraView: some View {
        ZStack {
            // Die Vorschau steht nur in der Hierarchie, solange sie laufen soll.
            // Dadurch greift `dismantleUIView` und die Kamera wird sicher frei.
            if isPaused {
                Color.black.ignoresSafeArea()
            } else {
                ExpiryTextCameraPreview(
                    status: $cameraStatus,
                    rebuildToken: cameraRebuild,
                    onCandidates: { candidates in handle(candidates) }
                )
                .ignoresSafeArea()
            }

            DateScannerOverlay()
                .ignoresSafeArea()

            VStack {
                Spacer()
                if let meldung = cameraStatus.meldung {
                    stoerungsBox(meldung)
                } else {
                    hintPill
                    if let candidate = bestCandidate {
                        acceptPill(for: candidate)
                            .padding(.top, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(.bottom, 48)
        }
    }

    private var hintPill: some View {
        Text("Halte das Haltbarkeitsdatum in den Rahmen")
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.horizontal, 24)
    }

    /// Statt eines eingefrorenen Bildes eine deutliche Meldung mit Ausweg.
    private func stoerungsBox(_ text: String) -> some View {
        VStack(spacing: 12) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Button("Erneut versuchen") {
                    bestCandidate = nil
                    pendingCandidate = nil
                    pendingHits = 0
                    cameraRebuild += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.freshGreen)

                Button("Datum von Hand wählen") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).strokeBorder(.orange.opacity(0.7), lineWidth: 1.5)
        )
        .padding(.horizontal, 24)
        .transition(.opacity)
    }

    private func acceptPill(for candidate: ExpiryDateCandidate) -> some View {
        Button {
            onPick(candidate.date)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("\(Self.dateString(candidate.date)) übernehmen")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Color.freshGreen, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Datum \(Self.dateString(candidate.date)) übernehmen")
    }

    // MARK: - Ohne Kameraberechtigung

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Kamerazugriff benötigt")
                .font(.title2.bold())
            Text("FreshAlert benötigt Zugriff auf die Kamera, um das Haltbarkeitsdatum zu lesen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.freshGreen)

            Button("Datum von Hand wählen") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Ablauf

    private func handle(_ candidates: [ExpiryDateCandidate]) {
        guard let top = candidates.first else { return }
        if let pending = pendingCandidate, pending.date == top.date {
            pendingHits += 1
        } else {
            pendingCandidate = top
            pendingHits = 1
        }
        guard pendingHits >= 2, bestCandidate?.date != top.date else { return }
        withAnimation(.spring(response: 0.3)) { bestCandidate = top }
        Feedback.scanSuccess()
    }

    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                }
            }
        } else {
            cameraPermission = status
        }
    }

    /// "12.10.2026"
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Rahmen

/// Abgedunkeltes Bild mit einem freien Fenster in der Mitte. Breiter und
/// flacher als beim Barcode, ein Datum ist eine kurze Zeile.
private struct DateScannerOverlay: View {
    private let frameW: CGFloat = 280
    private let frameH: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            let frameY = (geo.size.height - frameH) / 2 - 40

            Color.black.opacity(0.55)
                .mask(
                    Rectangle()
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .frame(width: frameW, height: frameH)
                                .position(x: geo.size.width / 2, y: frameY + frameH / 2)
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                )

            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.freshGreen, lineWidth: 2.5)
                .frame(width: frameW, height: frameH)
                .position(x: geo.size.width / 2, y: frameY + frameH / 2)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Kamera mit laufender Texterkennung

/// Hält die Session des Datum-Scanners. Baut sie **vollständig** ab, sobald sie
/// nicht laufen soll, damit die Rückkamera frei wird.
final class TextScannerUIView: UIView {
    var onStatus: ((CameraStatus) -> Void)?
    weak var sampleDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    /// Wird beim Aufbau gesetzt: so muss Vision das Bild drehen.
    var onOrientation: ((CGImagePropertyOrientation) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.freshalert.datecamera", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var observers: [NSObjectProtocol] = []
    private var wantsCamera = false
    private var status: CameraStatus = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    // MARK: Lebenszyklus

    func setWantsCamera(_ wants: Bool) {
        guard wants != wantsCamera else { return }
        wantsCamera = wants
        guard wants else {
            CameraArbiter.shared.release(self)
            report(.idle)
            return
        }
        report(.starting)
        CameraArbiter.shared.acquire(
            .expiryDate,
            claimant: self,
            teardown: { [weak self] fertig in
                guard let self else { fertig(); return }
                self.teardown(fertig: fertig)
            },
            granted: { [weak self] in self?.buildAndStart() }
        )
    }

    /// Harter Neuaufbau, nicht nur `startRunning()`.
    func rebuild() {
        guard wantsCamera else { return }
        cameraLog.info("Datum-Scanner: Neuaufbau der Session")
        setWantsCamera(false)
        setWantsCamera(true)
    }

    func shutdown() {
        wantsCamera = false
        CameraArbiter.shared.release(self)
    }

    // MARK: Aufbau

    private func buildAndStart() {
        guard wantsCamera else {
            CameraArbiter.shared.release(self)
            return
        }
        guard session == nil else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            cameraLog.error("Datum-Scanner: keine Rückkamera verfügbar")
            report(.failed("Es wurde keine Kamera gefunden."))
            return
        }

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()

        let session = AVCaptureSession()
        // Kleine Schrift auf Folie braucht Auflösung, deshalb mehr als beim Barcode.
        session.sessionPreset = .hd1920x1080

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setSampleBufferDelegate(sampleDelegate, queue: sessionQueue)
        }
        session.commitConfiguration()

        // Das Bild aus dem Datenausgang liegt quer. Kann die Verbindung drehen,
        // bekommt Vision ein aufrechtes Bild, sonst wird es beim Erkennen gedreht.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
                onOrientation?(.up)
            } else {
                onOrientation?(.right)
            }
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer.addSublayer(preview)
        self.session = session
        self.previewLayer = preview
        observe(session)

        sessionQueue.async { [weak self] in
            session.startRunning()
            aufMainActor {
                guard let self, self.session === session else { return }
                self.report(session.isRunning ? .running : .interrupted(.unknown))
            }
        }
    }

    private func teardown(fertig: @escaping @Sendable () -> Void) {
        removeObservers()
        let alte = session
        session = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        report(.idle)
        guard let alte else { fertig(); return }
        sessionQueue.async {
            if alte.isRunning { alte.stopRunning() }
            alte.beginConfiguration()
            alte.inputs.forEach { alte.removeInput($0) }
            alte.outputs.forEach { alte.removeOutput($0) }
            alte.commitConfiguration()
            cameraLog.info("Datum-Scanner: Session abgebaut, Kamera frei")
            fertig()
        }
    }

    private func report(_ neu: CameraStatus) {
        guard status != neu else { return }
        status = neu
        onStatus?(neu)
    }

    // MARK: Unterbrechungen

    private func observe(_ session: AVCaptureSession) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { [weak self] note in
            let roh = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            aufMainActor { self?.interrupted(roh) }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main
        ) { [weak self] _ in
            aufMainActor { self?.interruptionEnded() }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            let fehler = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            aufMainActor { self?.runtimeError(fehler) }
        })
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func interrupted(_ roh: Int?) {
        let grund = CameraInterruption(rawReason: roh)
        cameraLog.error("Datum-Scanner unterbrochen: \(grund.protokollname, privacy: .public)")
        report(.interrupted(grund))
    }

    /// Genau der Fall aus dem Fehlerbericht: ohne Neustart bleibt das letzte
    /// Bild stehen, auch wenn die Kamera längst wieder frei ist.
    private func interruptionEnded() {
        cameraLog.info("Datum-Scanner: Unterbrechung beendet, Session wird neu aufgebaut")
        guard wantsCamera else { return }
        rebuild()
    }

    private func runtimeError(_ fehler: NSError?) {
        cameraLog.error("Datum-Scanner: Laufzeitfehler \(fehler?.code ?? -1)")
        if fehler?.code == AVError.Code.mediaServicesWereReset.rawValue {
            rebuild()
        } else {
            report(.failed("Die Kamera hat einen Fehler gemeldet."))
        }
    }
}

struct ExpiryTextCameraPreview: UIViewRepresentable {
    @Binding var status: CameraStatus
    /// Jede Änderung erzwingt einen harten Neuaufbau der Session.
    var rebuildToken: Int = 0
    var onCandidates: ([ExpiryDateCandidate]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TextScannerUIView {
        let view = TextScannerUIView()
        let coordinator = context.coordinator
        coordinator.rebuildToken = rebuildToken
        view.sampleDelegate = coordinator
        view.onOrientation = { [weak coordinator] ausrichtung in
            coordinator?.orientation = ausrichtung
        }
        view.onStatus = { [weak coordinator] neu in
            // Nicht mitten im SwiftUI-Update schreiben.
            DispatchQueue.main.async { coordinator?.parent.status = neu }
        }
        // Startet erst, wenn der CameraArbiter die Kamera freigibt.
        view.setWantsCamera(true)
        return view
    }

    func updateUIView(_ uiView: TextScannerUIView, context: Context) {
        context.coordinator.parent = self
        uiView.setNeedsLayout()

        if context.coordinator.rebuildToken != rebuildToken {
            context.coordinator.rebuildToken = rebuildToken
            uiView.rebuild()
        }
    }

    static func dismantleUIView(_ uiView: TextScannerUIView, coordinator: Coordinator) {
        uiView.onStatus = nil
        uiView.onOrientation = nil
        uiView.shutdown()
        let parent = coordinator.parent
        DispatchQueue.main.async { parent.status = .idle }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: ExpiryTextCameraPreview
        var orientation: CGImagePropertyOrientation = .right
        var rebuildToken = 0
        /// Texterkennung kostet spürbar Rechenzeit, deshalb nicht jedes Bild.
        private let interval: TimeInterval = 0.45
        private var lastRun: Date = .distantPast
        private var isRunning = false

        init(_ parent: ExpiryTextCameraPreview) { self.parent = parent }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard !isRunning else { return }
            guard Date().timeIntervalSince(lastRun) > interval else { return }
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lastRun = Date()
            isRunning = true
            let orientation = self.orientation
            Task { [weak self] in
                defer { self?.isRunning = false }
                guard let candidates = try? await ExpiryDateRecognizer.candidates(in: buffer, orientation: orientation),
                      !candidates.isEmpty else { return }
                await MainActor.run { [weak self] in
                    self?.parent.onCandidates(candidates)
                }
            }
        }
    }
}
