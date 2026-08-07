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
                controller.dismiss(animated: true) {
                    onComplete(fields, text, imageData)
                }
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
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

nonisolated enum OCRParser {
    static func parse(text: String, template: VaultTemplate) -> [VaultField] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")

        switch template {
        case .paymentCard:
            return compactFields([
                ("Number", paymentCardNumber(in: lines)),
                ("Expiry", paymentExpiry(in: joined)),
                ("Cardholder", probableCardholder(lines: lines))
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

    private static func paymentCardNumber(in lines: [String]) -> String {
        var candidates: [String] = []
        for line in lines + [lines.joined(separator: " ")] {
            let normalized = normalizePaymentDigits(line)
            candidates.append(contentsOf: matches(in: normalized, pattern: #"(?:\d[ -]*){13,19}"#).map { String($0.filter(\.isNumber)) })
        }
        let validCandidates = removingDuplicates(from: candidates)
            .filter { (13...19).contains($0.count) }
        return validCandidates.first(where: isLuhnValid) ?? validCandidates.first ?? ""
    }

    private static func paymentExpiry(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(0[1-9]|1[0-2])\s*[/\-]?\s*([2-9][0-9])\b"#) else { return "" }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges >= 3,
            let monthRange = Range(match.range(at: 1), in: text),
            let yearRange = Range(match.range(at: 2), in: text)
        else { return "" }
        return "\(text[monthRange])\(text[yearRange])"
    }

    private static func probableCardholder(lines: [String]) -> String {
        lines.first { line in
            let upper = line.uppercased()
            let letters = upper.filter { $0.isLetter }.count
            let blocked = ["VISA", "MASTERCARD", "CARD", "DEBIT", "CREDIT", "VALID", "THRU", "EXP", "BANK"]
            return letters > 5 && upper == line && !blocked.contains { upper.contains($0) }
        } ?? ""
    }

    private static func normalizePaymentDigits(_ text: String) -> String {
        String(text.map { character in
            switch character {
            case "O", "o", "Q": "0"
            case "I", "l", "|": "1"
            case "S", "s": "5"
            case "B": "8"
            default: character
            }
        })
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private static func removingDuplicates(from values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func isLuhnValid(_ digits: String) -> Bool {
        let reversed = digits.reversed().compactMap { Int(String($0)) }
        guard reversed.count == digits.count else { return false }
        let checksum = reversed.enumerated().reduce(0) { total, pair in
            let (index, digit) = pair
            guard index.isMultiple(of: 2) == false else { return total + digit }
            let doubled = digit * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return checksum.isMultiple(of: 10)
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
