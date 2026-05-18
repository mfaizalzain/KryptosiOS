import CoreImage.CIFilterBuiltins
import SwiftUI

struct VaultHeroCard: View {
    let template: VaultTemplate
    let title: String
    let fields: [VaultField]
    let attachment: Data?
    var compact = false

    var body: some View {
        if compact {
            card
                .foregroundStyle(.white)
                .frame(height: 132)
        } else {
            card
                .foregroundStyle(.white)
                .aspectRatio(template == .note ? 1.35 : 1.586, contentMode: .fit)
        }
    }

    private var card: some View {
        ZStack {
            if showsScannedPreview, let scannedImage {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.black.opacity(0.06))

                Image(uiImage: scannedImage)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)

                scannedPreviewBadge
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.0)],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .blendMode(.overlay)

                content
                    .padding(compact ? 14 : 20)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(compact ? 0.14 : 0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var cornerRadius: CGFloat {
        compact ? 14 : 22
    }

    private var showsScannedPreview: Bool {
        !compact && scannedImage != nil && template.usesScannedPreviewOnMainPage
    }

    private var scannedImage: UIImage? {
        attachment.flatMap(UIImage.init(data:))
    }

    private var scannedPreviewBadge: some View {
        VStack {
            HStack(spacing: 6) {
                Image(systemName: template.symbol)
                    .font(.caption2.weight(.semibold))
                Text(title.ifEmpty(template.title))
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.52), in: Capsule())
            .padding(8)

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch template {
        case .paymentCard:
            paymentCard
        case .passport, .idCard, .driversLicense:
            identityCard
        case .apiKey:
            apiKeyCard
        case .qrCode:
            qrCard
        case .note:
            noteCard
        default:
            documentCard
        }
    }

    private var background: LinearGradient {
        switch template {
        case .idCard:
            LinearGradient(colors: [Color(red: 0.05, green: 0.20, blue: 0.50), Color(red: 0.00, green: 0.34, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .passport:
            LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.20), Color(red: 0.10, green: 0.22, blue: 0.46)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .driversLicense:
            LinearGradient(colors: [Color(red: 0.04, green: 0.30, blue: 0.45), Color(red: 0.10, green: 0.55, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .birthCertificate:
            LinearGradient(colors: [Color(red: 0.05, green: 0.34, blue: 0.30), Color(red: 0.12, green: 0.55, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paymentCard:
            LinearGradient(colors: [Color(red: 0.08, green: 0.08, blue: 0.14), Color(red: 0.18, green: 0.10, blue: 0.32), Color(red: 0.38, green: 0.12, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bankAccount:
            LinearGradient(colors: [Color(red: 0.05, green: 0.32, blue: 0.40), Color(red: 0.08, green: 0.46, blue: 0.50)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .taxNumber:
            LinearGradient(colors: [Color(red: 0.42, green: 0.18, blue: 0.10), Color(red: 0.65, green: 0.32, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .apiKey:
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.22, green: 0.24, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .note:
            LinearGradient(colors: [Color(red: 0.92, green: 0.74, blue: 0.18), Color(red: 0.98, green: 0.85, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .qrCode:
            LinearGradient(colors: [Color(red: 0.08, green: 0.30, blue: 0.55), Color(red: 0.10, green: 0.55, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var identityCard: some View {
        HStack(spacing: compact ? 12 : 16) {
            photoSlot
                .frame(width: compact ? 58 : 92)

            VStack(alignment: .leading, spacing: compact ? 5 : 12) {
                Text(title.isEmpty ? template.title.uppercased() : title)
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(1)

                LabelValue(label: template == .passport ? "Number" : "Identifier", value: fields.firstValue("Passport number", "ID number", "License number"))
                LabelValue(label: "Name", value: fields.firstValue("Full name", "Surname", "Given names"))
                if !compact {
                    HStack {
                        LabelValue(label: "DOB", value: fields.value("Date of birth"))
                        LabelValue(label: "Expiry", value: fields.value("Expiry"))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var paymentCard: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.ifEmpty(fields.value("Issuer").ifEmpty("KRYPTOS CARD")))
                        .font((compact ? Font.subheadline : Font.headline).bold())
                        .lineLimit(1)
                    if !title.isEmpty, !fields.value("Issuer").isEmpty, title != fields.value("Issuer") {
                        Text(fields.value("Issuer"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "creditcard.fill")
                    .font(compact ? .body : .title2)
            }

            Spacer()

            Text(maskCard(fields.firstValue("Number", "Card number")))
                .font(.system(size: compact ? 17 : 24, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack {
                LabelValue(label: "Cardholder", value: fields.value("Cardholder"))
                Spacer()
                LabelValue(label: "Expires", value: formattedExpiry(fields.value("Expiry")))
            }
        }
    }

    private var documentCard: some View {
        HStack(spacing: compact ? 12 : 16) {
            iconPlaceholder(symbol: template.symbol)
                .frame(width: compact ? 58 : 92)

            VStack(alignment: .leading, spacing: compact ? 6 : 12) {
                Text(title.ifEmpty(template.title))
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(1)
                ForEach(fields.prefix(compact ? 2 : 5)) { field in
                    LabelValue(label: field.name, value: field.value)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                Image(systemName: "key.fill")
                Text(fields.value("Service").ifEmpty(title.ifEmpty("API Key")))
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer()
            Text(maskSecret(fields.firstValue("Key", "Secret")))
                .font(.system(compact ? .subheadline : .headline, design: .monospaced))
                .lineLimit(compact ? 1 : 2)
            LabelValue(label: "Environment", value: fields.value("Environment"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text(title.ifEmpty("Secure Note"))
                .font((compact ? Font.subheadline : Font.title3).bold())
                .lineLimit(1)
            Text(fields.value("Content").ifEmpty("No content"))
                .font(compact ? .caption : .body)
                .lineLimit(compact ? 3 : 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconPlaceholder(symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.18))
            if let attachment, let image = UIImage(data: attachment) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(compact ? .title3 : .title)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private var qrCard: some View {
        HStack(spacing: compact ? 12 : 16) {
            if let image = QRCode.makeImage(from: fields.value("Data")) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(compact ? 6 : 8)
                    .background(.white, in: RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous))
                    .frame(width: compact ? 72 : 130)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: compact ? 42 : 64))
            }
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                Text(title.ifEmpty("QR Code"))
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(2)
                Text(fields.value("Data"))
                    .font(compact ? .caption2 : .caption)
                    .lineLimit(compact ? 3 : 4)
                    .foregroundStyle(.white.opacity(0.82))
            }
            Spacer(minLength: 0)
        }
    }

    private var photoSlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.18))
            if let attachment, let image = UIImage(data: attachment) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "person.crop.rectangle")
                    .font(compact ? .title3 : .title)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private func maskCard(_ number: String) -> String {
        let digits = number.digitsOnly
        guard digits.count > 4 else { return number.ifEmpty("•••• •••• •••• ••••") }
        return "•••• •••• •••• \(digits.suffix(4))"
    }

    private func maskSecret(_ value: String) -> String {
        guard !value.isEmpty else { return "••••••••••••••••" }
        return String(repeating: "•", count: min(value.count, 18))
    }

    private func formattedExpiry(_ value: String) -> String {
        let digits = value.digitsOnly
        guard digits.count == 4 else { return value }
        return "\(digits.prefix(2))/\(digits.suffix(2))"
    }
}

private struct LabelValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
            Text(value.ifEmpty("-"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

enum QRCode {
    static func makeImage(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard
            let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
            let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private extension VaultTemplate {
    var usesScannedPreviewOnMainPage: Bool {
        switch self {
        case .idCard, .driversLicense, .paymentCard, .passport, .birthCertificate:
            true
        case .bankAccount, .taxNumber, .apiKey, .note, .qrCode:
            false
        }
    }
}
