import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var scannedBarcode: String?
    @State private var showAddSheet = false
    @State private var showManualEntry = false
    @State private var manualBarcode = ""
    @State private var torchOn = false
    @State private var cameraPermission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

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
            .onAppear { checkCameraPermission() }
            .onChange(of: scannedBarcode) { _, barcode in
                if barcode != nil { showAddSheet = true }
            }
            .sheet(isPresented: $showAddSheet, onDismiss: {
                scannedBarcode = nil
            }) {
                if let barcode = scannedBarcode {
                    AddFoodItemView(barcode: barcode)
                }
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

            // Dimmed overlay with cutout effect
            ScannerOverlay()
                .ignoresSafeArea()

            VStack {
                // Top bar
                HStack {
                    torchButton
                    Spacer()
                    manualButton
                }
                .padding(.top, 60)
                .padding(.horizontal, 20)

                Spacer()

                // Scanner frame hint
                VStack(spacing: 8) {
                    Text("Barcode in den Rahmen halten")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                    if !viewModel.isOnline {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                            Text("Offline – Produkt wird später synchronisiert")
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.8))
                        .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }

    private var torchButton: some View {
        Button {
            torchOn.toggle()
        } label: {
            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.title3)
                .foregroundStyle(torchOn ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }

    private var manualButton: some View {
        Button {
            showManualEntry = true
        } label: {
            Image(systemName: "keyboard")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
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
            .tint(Color(red: 0.2, green: 0.78, blue: 0.2))

            Divider().padding(.horizontal, 40)

            Button("Manuell eingeben") {
                showManualEntry = true
            }
            .buttonStyle(.bordered)
        }
        .padding()
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
    var body: some View {
        GeometryReader { geo in
            let frameW: CGFloat = 260
            let frameH: CGFloat = 130
            let frameY = (geo.size.height - frameH) / 2 - 40

            // Dark mask with transparent cutout
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

            // Animated green border
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.78, blue: 0.2), .white],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2.5)
                .frame(width: frameW, height: frameH)
                .position(x: geo.size.width / 2, y: frameY + frameH / 2)
        }
    }
}

// MARK: - AVFoundation Camera Preview
final class ScannerUIView: UIView {
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct CameraPreview: UIViewRepresentable {
    @Binding var scannedBarcode: String?
    @Binding var torchOn: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ScannerUIView {
        let view = ScannerUIView()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }

        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .qr]
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        view.session = session
        view.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: ScannerUIView, context: Context) {
        uiView.previewLayer?.frame = uiView.bounds
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            try? device.lockForConfiguration()
            device.torchMode = torchOn ? .on : .off
            device.unlockForConfiguration()
        }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: CameraPreview
        private var lastScan: Date = .distantPast

        init(_ parent: CameraPreview) { self.parent = parent }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            // Debounce: at least 2s between scans
            guard Date().timeIntervalSince(lastScan) > 2 else { return }
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue else { return }
            lastScan = Date()
            parent.scannedBarcode = value
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
