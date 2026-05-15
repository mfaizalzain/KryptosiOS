import AVFoundation
import SwiftUI
import Vision
import VisionKit

struct DocumentScanView: UIViewControllerRepresentable {
    let template: VaultTemplate
    let onComplete: ([VaultField], String?, Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(template: template, onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard VNDocumentCameraViewController.isSupported else {
            return UIHostingController(rootView: ContentUnavailableView("Document scan is unavailable", systemImage: "camera.viewfinder", description: Text("Run on a device with a camera to scan documents.")))
        }
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let template: VaultTemplate
        let onComplete: ([VaultField], String?, Data?) -> Void

        init(template: VaultTemplate, onComplete: @escaping ([VaultField], String?, Data?) -> Void) {
            self.template = template
            self.onComplete = onComplete
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else {
                controller.dismiss(animated: true)
                return
            }
            let image = scan.imageOfPage(at: 0)
            let imageData = image.jpegData(compressionQuality: 0.82)
            recognizeText(in: image) { [template, onComplete] text in
                let fields = OCRParser.parse(text: text, template: template)
                onComplete(fields, text, imageData)
                controller.dismiss(animated: true)
            }
        }

        private func recognizeText(in image: UIImage, completion: @escaping (String) -> Void) {
            guard let cgImage = image.cgImage else {
                completion("")
                return
            }
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                DispatchQueue.main.async { completion(text) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cgImage).perform([request])
            }
        }
    }
}

enum OCRParser {
    static func parse(text: String, template: VaultTemplate) -> [VaultField] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")

        switch template {
        case .paymentCard:
            return compactFields([
                ("Number", firstMatch(in: joined, pattern: #"(\d[ -]?){13,19}"#)?.digitsOnly ?? ""),
                ("Expiry", firstMatch(in: joined, pattern: #"\b(0[1-9]|1[0-2])\s*/?\s*([0-9]{2})\b"#)?.digitsOnly ?? ""),
                ("Cardholder", probableName(lines: lines))
            ])
        case .passport:
            return compactFields([
                ("Passport number", firstMatch(in: joined, pattern: #"\b[A-Z0-9]{6,9}\b"#) ?? ""),
                ("Surname", value(after: ["surname", "last name"], in: lines)),
                ("Given names", value(after: ["given", "first name"], in: lines)),
                ("Nationality", value(after: ["nationality"], in: lines)),
                ("Date of birth", firstDate(in: joined)),
                ("Expiry", value(after: ["expiry", "expiration", "expires"], in: lines))
            ])
        case .driversLicense:
            return compactFields([
                ("License number", value(after: ["license", "licence", "dl"], in: lines)),
                ("Full name", probableName(lines: lines)),
                ("Date of birth", firstDate(in: joined)),
                ("Expiry", value(after: ["expiry", "expiration", "expires"], in: lines))
            ])
        case .idCard:
            return compactFields([
                ("Full name", probableName(lines: lines)),
                ("ID number", value(after: ["id", "identity", "number"], in: lines)),
                ("Date of birth", firstDate(in: joined)),
                ("Nationality", value(after: ["nationality"], in: lines))
            ])
        case .birthCertificate:
            return compactFields([
                ("Full name", probableName(lines: lines)),
                ("Date of birth", firstDate(in: joined)),
                ("Place of birth", value(after: ["place of birth"], in: lines)),
                ("Registration number", value(after: ["registration"], in: lines))
            ])
        case .bankAccount:
            return compactFields([
                ("Bank", lines.first ?? ""),
                ("Account number", firstMatch(in: joined, pattern: #"\b\d{8,18}\b"#) ?? ""),
                ("IBAN", firstMatch(in: joined, pattern: #"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#) ?? "")
            ])
        case .taxNumber:
            return compactFields([
                ("Full name", probableName(lines: lines)),
                ("Tax number", value(after: ["tax", "tin"], in: lines)),
                ("Country", value(after: ["country"], in: lines))
            ])
        case .apiKey, .note, .qrCode:
            return []
        }
    }

    private static func compactFields(_ pairs: [(String, String)]) -> [VaultField] {
        pairs
            .map { VaultField(name: $0.0, value: $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.value.isEmpty }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func firstDate(in text: String) -> String {
        firstMatch(in: text, pattern: #"\b\d{4}-\d{2}-\d{2}\b"#)
        ?? firstMatch(in: text, pattern: #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#)
        ?? ""
    }

    private static func probableName(lines: [String]) -> String {
        lines.first { line in
            let letters = line.filter { $0.isLetter }.count
            return letters > 5 && line == line.uppercased() && !line.contains("PASSPORT") && !line.contains("CARD")
        } ?? ""
    }

    private static func value(after labels: [String], in lines: [String]) -> String {
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if labels.contains(where: { lower.contains($0) }) {
                let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
                if pieces.count == 2, !pieces[1].trimmingCharacters(in: .whitespaces).isEmpty {
                    return pieces[1]
                }
                if index + 1 < lines.count { return lines[index + 1] }
            }
        }
        return ""
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onResult: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onResult = onResult
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}

    final class Coordinator {
        let onResult: (String) -> Void
        init(onResult: @escaping (String) -> Void) {
            self.onResult = onResult
        }
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onResult: ((String) -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            showUnavailable()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showUnavailable()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        Task.detached { [session] in
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (view.layer.sublayers?.first as? AVCaptureVideoPreviewLayer)?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        session.stopRunning()
        onResult?(value)
        dismiss(animated: true)
    }

    private func showUnavailable() {
        let label = UILabel()
        label.text = "Camera unavailable"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

struct NFCScanInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let template: VaultTemplate

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "NFC scan needs entitlement setup",
                systemImage: "wave.3.right.circle",
                description: Text(template == .passport ? "Core NFC can read ISO 7816 passport chips after adding the NFC entitlement and passport AIDs. The Android JMRTD flow is intentionally isolated from the rest of the vault so it can be implemented here without changing storage or UI." : "iOS restricts payment-card NFC access. The app keeps this flow separate for supported entitlements and future issuer-approved implementations.")
            )
            .navigationTitle("Scan NFC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
