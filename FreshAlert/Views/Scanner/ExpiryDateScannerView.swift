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
            ExpiryTextCameraPreview(isPaused: isPaused) { candidates in
                handle(candidates)
            }
            .ignoresSafeArea()

            DateScannerOverlay()
                .ignoresSafeArea()

            VStack {
                Spacer()
                hintPill
                if let candidate = bestCandidate {
                    acceptPill(for: candidate)
                        .padding(.top, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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

final class TextScannerUIView: UIView {
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var isPaused = false

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct ExpiryTextCameraPreview: UIViewRepresentable {
    var isPaused: Bool
    var onCandidates: ([ExpiryDateCandidate]) -> Void

    private let sessionQueue = DispatchQueue(label: "com.freshalert.datecamera", qos: .userInitiated)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TextScannerUIView {
        let view = TextScannerUIView()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }

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
            output.setSampleBufferDelegate(context.coordinator, queue: sessionQueue)
        }
        session.commitConfiguration()

        // Das Bild aus dem Datenausgang liegt quer. Kann die Verbindung drehen,
        // bekommt Vision ein aufrechtes Bild, sonst wird es beim Erkennen gedreht.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
                context.coordinator.orientation = .up
            } else {
                context.coordinator.orientation = .right
            }
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        view.session = session
        view.previewLayer = preview

        sessionQueue.async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: TextScannerUIView, context: Context) {
        context.coordinator.parent = self
        uiView.previewLayer?.frame = uiView.bounds

        if let session = uiView.session, uiView.isPaused != isPaused {
            uiView.isPaused = isPaused
            let shouldRun = !isPaused
            sessionQueue.async {
                if shouldRun, !session.isRunning { session.startRunning() }
                if !shouldRun, session.isRunning { session.stopRunning() }
            }
        }
    }

    static func dismantleUIView(_ uiView: TextScannerUIView, coordinator: Coordinator) {
        guard let session = uiView.session else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: ExpiryTextCameraPreview
        var orientation: CGImagePropertyOrientation = .right
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
            guard !parent.isPaused, !isRunning else { return }
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
