import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Main View

struct BarcodeScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject private var store: StoreManager
    @State private var scannedBarcode: String?
    @State private var showAddSheet = false
    @State private var showManualEntry = false
    @State private var manualBarcode = ""
    @State private var torchOn = false
    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scanStatus: ScanStatus = .waiting
    @State private var scanTask: Task<Void, Never>?
    @State private var showManualForm = false
    @State private var showPaywall = false
    @State private var isTabVisible = false
    /// Bereits vorhandenes Produkt mit demselben Barcode (Dubletten-Dialog).
    @State private var duplicateItem: FoodItem?
    @State private var showDuplicateDialog = false
    /// Was die Kamera gerade tut. Eine Unterbrechung wird gemeldet, statt ein
    /// eingefrorenes Bild stehen zu lassen.
    @State private var cameraStatus: CameraStatus = .idle
    /// Wird hochgezählt, um die Session hart neu aufzubauen.
    @State private var cameraRebuild = 0

    /// Solange ein Sheet offen ist oder der Tab nicht sichtbar, ruht die Kamera.
    private var isScannerPaused: Bool {
        !isTabVisible || showAddSheet || showManualForm || showPaywall || showManualEntry || showDuplicateDialog
    }

    enum ScanStatus { case waiting, noCodeDetected, success }

    var body: some View {
        NavigationStack {
            ZStack {
                if cameraPermission == .authorized {
                    cameraView
                } else {
                    permissionView
                }
            }
            .navigationTitle("Scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                isTabVisible = true
                checkCameraPermission()
                startNoCodeTimer()
            }
            .onDisappear {
                isTabVisible = false
                scanTask?.cancel()
            }
            .onChange(of: scannedBarcode) { _, barcode in
                guard let barcode else { return }
                scanStatus = .success
                scanTask?.cancel()
                // Erst Dublette, dann Limit: die Menge zu erhöhen legt kein neues
                // Produkt an, braucht also auch kein Pro.
                if let existing = existingItem(for: barcode) {
                    duplicateItem = existing
                    showDuplicateDialog = true
                } else {
                    openAddSheetOrPaywall()
                }
            }
            // Paywall aus dem Scanner: der Barcode bleibt erhalten. Wird Pro
            // gekauft, geht es direkt mit demselben Barcode weiter, sonst wird
            // er verworfen.
            .onChange(of: store.isPro) { _, isPro in
                guard isPro, showPaywall else { return }
                showPaywall = false
            }
            .sheet(isPresented: $showPaywall, onDismiss: {
                if store.isPro, scannedBarcode != nil {
                    showAddSheet = true
                } else {
                    resetScanner()
                }
            }) {
                PaywallView(reason: .limitReached)
            }
            .sheet(isPresented: $showAddSheet, onDismiss: {
                resetScanner()
            }) {
                if let barcode = scannedBarcode {
                    AddFoodItemView(barcode: barcode)
                }
            }
            .confirmationDialog(
                "\(duplicateItem?.name ?? "Produkt") ist schon da",
                isPresented: $showDuplicateDialog,
                titleVisibility: .visible,
                presenting: duplicateItem
            ) { item in
                Button("Menge um 1 erhöhen") {
                    viewModel.incrementQuantity(item)
                    Feedback.itemSaved()
                    resetScanner()
                }
                Button("Als neues Produkt anlegen") {
                    openAddSheetOrPaywall()
                }
                Button("Abbrechen", role: .cancel) {
                    resetScanner()
                }
            } message: { item in
                Text("\(item.quantity)×, haltbar bis \(item.expiryDate.formatted(date: .numeric, time: .omitted))")
            }
            .sheet(isPresented: $showManualForm, onDismiss: {
                startNoCodeTimer()
            }) {
                AddFoodItemView(barcode: "")
            }
            .alert("Barcode eingeben", isPresented: $showManualEntry) {
                TextField("z.B. 4000417025005", text: $manualBarcode)
                    .keyboardType(.numberPad)
                Button("Abbrechen", role: .cancel) { manualBarcode = "" }
                Button("Weiter") {
                    let code = manualBarcode.trimmingCharacters(in: .whitespaces)
                    manualBarcode = ""
                    guard !code.isEmpty else { return }
                    // Läuft über denselben Weg wie ein gescannter Code:
                    // Dubletten-Prüfung, dann Limit oder Formular.
                    scannedBarcode = code
                }
            } message: {
                Text("Gib den Barcode manuell ein.")
            }
        }
    }

    // MARK: - Camera View
    private var cameraView: some View {
        ZStack {
            // Die Vorschau steht nur in der Hierarchie, solange sie laufen soll.
            // Damit greift `dismantleUIView`, die Session wird abgebaut und das
            // Gerät ist für den Datum-Scanner frei. Nur `stopRunning()` reicht
            // nicht: der Input hält die Kamera weiter.
            if isScannerPaused {
                Color.black.ignoresSafeArea()
            } else {
                CameraPreview(
                    scannedBarcode: $scannedBarcode,
                    torchOn: $torchOn,
                    status: $cameraStatus,
                    rebuildToken: cameraRebuild
                )
                .ignoresSafeArea()
            }

            ScannerOverlay(scanStatus: scanStatus)
                .ignoresSafeArea()

            VStack {
                HStack {
                    torchButton
                    Spacer()
                    manualButton
                }
                .padding(.top, 60)
                .padding(.horizontal, 20)

                Spacer()

                statusHint

                manualFormButton
                    .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var statusHint: some View {
        VStack(spacing: 10) {
            if let stoerung = cameraStatus.kurzmeldung {
                HStack(spacing: 10) {
                    scanHintPill(stoerung, color: .orange, icon: "exclamationmark.triangle.fill")
                    Button("Erneut versuchen") { cameraRebuild += 1 }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            switch scanStatus {
            case .waiting:
                scanHintPill("Barcode in den Rahmen halten", color: .white)

            case .noCodeDetected:
                scanHintPill("Kein Barcode erkannt", color: .orange, icon: "exclamationmark.triangle.fill")
                VStack(spacing: 4) {
                    Text("Tipps:")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                    Text("• Kamera näher an den Barcode halten\n• Für mehr Licht die Taschenlampe nutzen\n• Barcode manuell eingeben")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.move(edge: .bottom).combined(with: .opacity))

            case .success:
                scanHintPill("Barcode erkannt ✓", color: Color.freshGreen)
            }

            if !viewModel.isOnline {
                scanHintPill("Offline – wird später synchronisiert", color: .orange, icon: "wifi.slash")
            }
        }
    }

    private func scanHintPill(_ text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.caption.weight(.semibold))
            }
            Text(text).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(color == .white ? Color.primary : .white)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(color == .white ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(color.opacity(0.85)))
        .clipShape(Capsule())
    }

    // MARK: - Buttons
    private var torchButton: some View {
        Button { torchOn.toggle() } label: {
            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.title3)
                .foregroundStyle(torchOn ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel(torchOn ? "Taschenlampe ausschalten" : "Taschenlampe einschalten")
    }

    private var manualButton: some View {
        Button { showManualEntry = true } label: {
            Image(systemName: "keyboard")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel("Barcode eingeben")
    }

    private var manualFormButton: some View {
        Button {
            if isAtFreeLimit() { showPaywall = true } else { showManualForm = true }
        } label: {
            Label("Ohne Barcode hinzufügen", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    // MARK: - Permission View
    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Kamerazugriff benötigt")
                .font(.title2.bold())
            Text("FreshAlert benötigt Zugriff auf die Kamera, um Barcodes zu scannen.")
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

            Divider().padding(.horizontal, 40)

            Button("Barcode manuell eingeben") { showManualEntry = true }
                .buttonStyle(.bordered)

            Button("Ohne Barcode hinzufügen") {
                if isAtFreeLimit() { showPaywall = true } else { showManualForm = true }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Helpers

    private func isAtFreeLimit() -> Bool {
        guard !store.isPro else { return false }
        let count = (try? modelContext.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        return count >= StoreManager.freeLimit
    }

    /// Vorhandenes Produkt mit demselben, nicht leeren Barcode.
    private func existingItem(for barcode: String) -> FoodItem? {
        guard !barcode.isEmpty else { return nil }
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.barcode == barcode }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Öffnet das Formular für `scannedBarcode` oder, am Limit, die Paywall.
    /// Der Barcode bleibt in beiden Fällen gesetzt.
    private func openAddSheetOrPaywall() {
        if isAtFreeLimit() {
            showPaywall = true
        } else {
            showAddSheet = true
        }
    }

    /// Zurück in den Wartezustand, wie nach dem Schließen des Formulars.
    private func resetScanner() {
        scannedBarcode = nil
        duplicateItem = nil
        scanStatus = .waiting
        startNoCodeTimer()
    }

    // MARK: - No-code hint timer
    private func startNoCodeTimer() {
        scanTask?.cancel()
        scanStatus = .waiting
        scanTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.4)) {
                    if scanStatus == .waiting { scanStatus = .noCodeDetected }
                }
            }
        }
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
}

// MARK: - Scanner Overlay

struct ScannerOverlay: View {
    let scanStatus: BarcodeScannerView.ScanStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let frameW: CGFloat = 270
    private let frameH: CGFloat = 140

    private var borderColor: Color {
        switch scanStatus {
        case .waiting:       return Color.freshGreen
        case .noCodeDetected: return .orange
        case .success:       return .white
        }
    }

    private func scanLine(width: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.freshGreen.opacity(0.9), .clear],
                    startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: width, height: 2.5)
            .accessibilityHidden(true)
    }

    var body: some View {
        GeometryReader { geo in
            let frameY = (geo.size.height - frameH) / 2 - 40

            // Dimmed mask with transparent cutout
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

            // Scan frame border — color reflects status
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 2.5)
                .frame(width: frameW, height: frameH)
                .position(x: geo.size.width / 2, y: frameY + frameH / 2)
                .animation(.easeInOut(duration: 0.3), value: scanStatus)

            // Animated scan line (hidden on success/no-code).
            // Driven purely by elapsed time via TimelineView: the position is
            // a function of the clock, so there is nothing to interpolate,
            // stack or "fly in" — it renders correctly on every frame and
            // resumes seamlessly after a tab switch.
            // Bei "Bewegung reduzieren" steht die Linie still in der Mitte.
            if scanStatus == .waiting {
                if reduceMotion {
                    scanLine(width: frameW - 20)
                        .position(x: geo.size.width / 2, y: frameY + frameH / 2)
                } else {
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSinceReferenceDate
                        let cycle = 3.2  // seconds for a full down-and-up sweep
                        let progress = (1 - cos(2 * .pi * elapsed / cycle)) / 2
                        scanLine(width: frameW - 20)
                            .position(x: geo.size.width / 2,
                                      y: frameY + CGFloat(progress) * frameH)
                    }
                }
            }
        }
    }
}

// MARK: - AVFoundation Camera Preview

/// Hält die Barcode-Session. Baut sie **vollständig** ab, sobald sie nicht mehr
/// laufen soll: Session stoppen, Inputs und Outputs entfernen, Preview-Layer
/// lösen. `stopRunning()` allein reicht nicht, der `AVCaptureDeviceInput` hält
/// die Kamera weiter und der Datum-Scanner bekommt sie nicht.
final class ScannerUIView: UIView {
    /// Meldet Zustandswechsel nach oben.
    var onStatus: ((CameraStatus) -> Void)?
    /// Empfänger der erkannten Codes.
    weak var metadataDelegate: AVCaptureMetadataOutputObjectsDelegate?

    private let sessionQueue = DispatchQueue(label: "com.freshalert.camera", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var device: AVCaptureDevice?
    private var observers: [NSObjectProtocol] = []
    private var wantsCamera = false
    private var torchOn = false
    private var status: CameraStatus = .idle

    // Scan frame dimensions (must match ScannerOverlay)
    private let frameW: CGFloat = 270
    private let frameH: CGFloat = 140

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        updateRectOfInterest()
    }

    // Restrict AVFoundation's scan area to the visible frame cutout.
    // This dramatically improves recognition speed and reliability.
    func updateRectOfInterest() {
        guard let output = metadataOutput,
              let preview = previewLayer,
              bounds.width > 0 else { return }
        let scanRect = CGRect(
            x: (bounds.width  - frameW) / 2,
            y: (bounds.height - frameH) / 2 - 40,
            width: frameW,
            height: frameH
        )
        output.rectOfInterest = preview.metadataOutputRectConverted(fromLayerRect: scanRect)
    }

    // MARK: Lebenszyklus

    /// Fordert die Kamera an oder gibt sie zurück. Beides läuft über den
    /// `CameraArbiter`, damit nie zwei Sessions dasselbe Gerät wollen.
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
            .barcode,
            claimant: self,
            teardown: { [weak self] fertig in
                guard let self else { fertig(); return }
                self.teardown(fertig: fertig)
            },
            granted: { [weak self] in self?.buildAndStart() }
        )
    }

    /// Harter Neuaufbau: abgeben und neu anfordern. Ein bloßes `startRunning()`
    /// hilft nach einer Unterbrechung nicht zuverlässig.
    func rebuild() {
        guard wantsCamera else { return }
        cameraLog.info("Barcode-Scanner: Neuaufbau der Session")
        setWantsCamera(false)
        setWantsCamera(true)
    }

    func setTorch(_ an: Bool) {
        guard torchOn != an else { return }
        torchOn = an
        applyTorch(an)
    }

    func shutdown() {
        wantsCamera = false
        CameraArbiter.shared.release(self)
    }

    // MARK: Aufbau

    private func buildAndStart() {
        guard wantsCamera else {
            // In der Zwischenzeit doch pausiert: sofort wieder abgeben.
            CameraArbiter.shared.release(self)
            return
        }
        guard session == nil else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            cameraLog.error("Barcode-Scanner: keine Rückkamera verfügbar")
            report(.failed("Es wurde keine Kamera gefunden."))
            return
        }

        // Optimise focus and exposure for close-up barcode scanning
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()

        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720  // good resolution without excessive CPU

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            // Process on dedicated queue, not main — prevents dropped frames
            output.setMetadataObjectsDelegate(metadataDelegate, queue: sessionQueue)
            // Nur Handelsbarcodes. QR-Codes sind keine Produktnummern und landeten
            // vorher als Anfrage bei Open Food Facts.
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39]
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer.addSublayer(preview)
        self.session = session
        self.previewLayer = preview
        self.metadataOutput = output
        self.device = device
        updateRectOfInterest()
        observe(session)

        sessionQueue.async { [weak self] in
            session.startRunning()
            aufMainActor {
                guard let self, self.session === session else { return }
                self.report(session.isRunning ? .running : .interrupted(.unknown))
                self.applyTorch(self.torchOn)
            }
        }
    }

    /// Session anhalten und auseinandernehmen. `fertig` läuft auf der
    /// Session-Queue, sobald das Gerät wirklich frei ist.
    private func teardown(fertig: @escaping @Sendable () -> Void) {
        applyTorch(false)
        removeObservers()
        let alte = session
        session = nil
        metadataOutput = nil
        device = nil
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
            cameraLog.info("Barcode-Scanner: Session abgebaut, Kamera frei")
            fertig()
        }
    }

    private func applyTorch(_ an: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        try? device.lockForConfiguration()
        device.torchMode = an ? .on : .off
        device.unlockForConfiguration()
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
        cameraLog.error("Barcode-Scanner unterbrochen: \(grund.protokollname, privacy: .public)")
        report(.interrupted(grund))
    }

    /// Ohne das hier bleibt nach einer Unterbrechung das letzte Bild stehen,
    /// auch wenn die Kamera längst wieder frei ist.
    private func interruptionEnded() {
        cameraLog.info("Barcode-Scanner: Unterbrechung beendet")
        guard wantsCamera, let session else { return }
        report(.starting)
        sessionQueue.async { [weak self] in
            if !session.isRunning { session.startRunning() }
            aufMainActor {
                guard let self, self.session === session else { return }
                self.report(session.isRunning ? .running : .interrupted(.unknown))
                self.applyTorch(self.torchOn)
            }
        }
    }

    private func runtimeError(_ fehler: NSError?) {
        cameraLog.error("Barcode-Scanner: Laufzeitfehler \(fehler?.code ?? -1)")
        if fehler?.code == AVError.Code.mediaServicesWereReset.rawValue {
            rebuild()
        } else {
            report(.failed("Die Kamera hat einen Fehler gemeldet."))
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @Binding var scannedBarcode: String?
    @Binding var torchOn: Bool
    @Binding var status: CameraStatus
    /// Jede Änderung erzwingt einen harten Neuaufbau der Session.
    var rebuildToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ScannerUIView {
        let view = ScannerUIView()
        view.metadataDelegate = context.coordinator
        let coordinator = context.coordinator
        coordinator.rebuildToken = rebuildToken
        view.onStatus = { [weak coordinator] neu in
            // Nicht mitten im SwiftUI-Update schreiben.
            DispatchQueue.main.async { coordinator?.parent.status = neu }
        }
        view.setWantsCamera(true)
        return view
    }

    func updateUIView(_ uiView: ScannerUIView, context: Context) {
        context.coordinator.parent = self
        uiView.setNeedsLayout()
        uiView.updateRectOfInterest()
        uiView.setTorch(torchOn)

        if context.coordinator.rebuildToken != rebuildToken {
            context.coordinator.rebuildToken = rebuildToken
            uiView.rebuild()
        }
    }

    static func dismantleUIView(_ uiView: ScannerUIView, coordinator: Coordinator) {
        uiView.onStatus = nil
        uiView.shutdown()
        let parent = coordinator.parent
        DispatchQueue.main.async { parent.status = .idle }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: CameraPreview
        var rebuildToken = 0
        private var lastScan: Date = .distantPast
        private let debounce: TimeInterval = 0.8   // was 2.0 — still prevents double-fire

        init(_ parent: CameraPreview) { self.parent = parent }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard Date().timeIntervalSince(lastScan) > debounce else { return }
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue, !value.isEmpty else { return }
            lastScan = Date()
            DispatchQueue.main.async {
                self.parent.scannedBarcode = value
                Feedback.scanSuccess()
            }
        }
    }
}
