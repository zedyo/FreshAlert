import SwiftUI
import AVFoundation

// MARK: - Main View

struct BarcodeScannerView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var scannedBarcode: String?
    @State private var showAddSheet = false
    @State private var showManualEntry = false
    @State private var manualBarcode = ""
    @State private var torchOn = false
    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scanStatus: ScanStatus = .waiting
    @State private var scanTask: Task<Void, Never>?
    @State private var showManualForm = false

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
                checkCameraPermission()
                startNoCodeTimer()
            }
            .onDisappear { scanTask?.cancel() }
            .onChange(of: scannedBarcode) { _, barcode in
                guard barcode != nil else { return }
                scanStatus = .success
                scanTask?.cancel()
                showAddSheet = true
            }
            .sheet(isPresented: $showAddSheet, onDismiss: {
                scannedBarcode = nil
                scanStatus = .waiting
                startNoCodeTimer()
            }) {
                if let barcode = scannedBarcode {
                    AddFoodItemView(barcode: barcode)
                }
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
                    if !manualBarcode.isEmpty {
                        scannedBarcode = manualBarcode
                        manualBarcode = ""
                    }
                }
            } message: {
                Text("Gib den Barcode manuell ein.")
            }
        }
    }

    // MARK: - Camera View
    private var cameraView: some View {
        ZStack {
            CameraPreview(scannedBarcode: $scannedBarcode, torchOn: $torchOn)
                .ignoresSafeArea()

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
    }

    private var manualFormButton: some View {
        Button { showManualForm = true } label: {
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

            Button("Ohne Barcode hinzufügen") { showManualForm = true }
                .buttonStyle(.bordered)
        }
        .padding()
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

    private let frameW: CGFloat = 270
    private let frameH: CGFloat = 140

    private var borderColor: Color {
        switch scanStatus {
        case .waiting:       return Color.freshGreen
        case .noCodeDetected: return .orange
        case .success:       return .white
        }
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
            // phaseAnimator restarts cleanly whenever the overlay reappears
            // (e.g. after a tab switch) — unlike a repeatForever animation,
            // which would stack and let the line drift out of the frame.
            if scanStatus == .waiting {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.freshGreen.opacity(0.9), .clear],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: frameW - 20, height: 2.5)
                    .phaseAnimator([0, 1] as [CGFloat]) { line, phase in
                        line.position(x: geo.size.width / 2, y: frameY + phase * frameH)
                    } animation: { _ in
                        .easeInOut(duration: 1.6)
                    }
            }
        }
    }
}

// MARK: - AVFoundation Camera Preview

final class ScannerUIView: UIView {
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var metadataOutput: AVCaptureMetadataOutput?

    // Scan frame dimensions (must match ScannerOverlay)
    private let frameW: CGFloat = 270
    private let frameH: CGFloat = 140

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
}

struct CameraPreview: UIViewRepresentable {
    @Binding var scannedBarcode: String?
    @Binding var torchOn: Bool

    private let sessionQueue = DispatchQueue(label: "com.freshalert.camera", qos: .userInitiated)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ScannerUIView {
        let view = ScannerUIView()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }

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
            output.setMetadataObjectsDelegate(context.coordinator, queue: sessionQueue)
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .qr]
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        view.session = session
        view.previewLayer = preview
        view.metadataOutput = output

        sessionQueue.async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: ScannerUIView, context: Context) {
        uiView.previewLayer?.frame = uiView.bounds
        uiView.updateRectOfInterest()
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: CameraPreview
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
