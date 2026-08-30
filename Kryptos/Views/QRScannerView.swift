import AVFoundation
import SwiftUI

/// Camera QR scanner. Owns the permission flow so a denied camera shows an
/// explanation and a route into Settings instead of a black rectangle.
struct QRScannerView: View {
    let onResult: (String) -> Void

    @State private var permission: CameraPermission = .undetermined

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch permission {
            case .undetermined:
                ProgressView()
                    .tint(Theme.accent)
            case .granted:
                QRScannerRepresentable(onResult: onResult)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) { scanHint }
            case .denied:
                permissionDenied
            case .unavailable:
                unavailable
            }
        }
        .task { permission = await CameraPermission.current() }
    }

    private var scanHint: some View {
        Text("Point the camera at a QR code")
            .font(Theme.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.space4)
            .padding(.vertical, Theme.space3)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(.bottom, Theme.space8)
    }

    private var permissionDenied: some View {
        VStack(spacing: Theme.space5) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: Theme.space2) {
                Text("Camera access is off")
                    .font(Theme.titleMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("Kryptos needs the camera to scan QR codes. You can turn it back on in Settings — nothing is recorded or uploaded.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settingsURL) {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.space6)
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Camera unavailable",
            systemImage: "camera.badge.ellipsis",
            description: Text("This device has no camera available for scanning.")
        )
    }
}

/// Resolved camera authorization, including the "no camera at all" case that
/// `AVAuthorizationStatus` on its own does not distinguish.
enum CameraPermission {
    case undetermined
    case granted
    case denied
    case unavailable

    static func current() async -> CameraPermission {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onResult: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onResult = onResult
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onResult: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "com.fmz.kryptos.qr-capture", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Guards against the delegate firing repeatedly before the session stops.
    private var hasDelivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        startSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Free the camera as soon as the scanner leaves the screen; a running
        // session keeps the hardware (and the indicator light) alive.
        captureQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func startSession() {
        // startRunning() blocks; run it on a dedicated capture queue so the
        // main thread stays responsive (standard AVFoundation pattern).
        captureQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasDelivered,
              let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        else { return }
        hasDelivered = true

        captureQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true) { [onResult] in
            onResult?(value)
        }
    }
}
