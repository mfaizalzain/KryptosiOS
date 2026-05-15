import CoreImage.CIFilterBuiltins
import SwiftUI

struct VaultHeroCard: View {
    let template: VaultTemplate
    let title: String
    let fields: [VaultField]
    let attachment: Data?
    var compact = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(background)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)

            content
                .padding(compact ? 16 : 20)
        }
        .foregroundStyle(.white)
        .aspectRatio(template == .note ? 1.35 : 1.586, contentMode: .fit)
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
            LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .passport:
            LinearGradient(colors: [Color(red: 0.07, green: 0.14, blue: 0.28), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .driversLicense:
            LinearGradient(colors: [.teal, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .birthCertificate:
            LinearGradient(colors: [.mint, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paymentCard:
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.12), .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bankAccount:
            LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .taxNumber:
            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .apiKey:
            LinearGradient(colors: [.black, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .note:
            LinearGradient(colors: [.brown, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .qrCode:
            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            photoSlot
                .frame(width: compact ? 72 : 92)

            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Text(title.isEmpty ? template.title.uppercased() : title)
                    .font((compact ? Font.headline : Font.title3).bold())
                    .lineLimit(1)

                LabelValue(label: template == .passport ? "Number" : "Identifier", value: fields.firstValue("Passport number", "ID number", "License number"))
                LabelValue(label: "Name", value: fields.firstValue("Full name", "Surname", "Given names"))
                HStack {
                    LabelValue(label: "DOB", value: fields.value("Date of birth"))
                    LabelValue(label: "Expiry", value: fields.value("Expiry"))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var paymentCard: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(fields.value("Issuer").isEmpty ? title.ifEmpty("KRYPTOS CARD") : fields.value("Issuer"))
                    .font(.headline.bold())
                    .lineLimit(1)
                Spacer()
                Image(systemName: "creditcard.chip")
                    .font(.title2)
            }

            Spacer()

            Text(maskCard(fields.firstValue("Number", "Card number")))
                .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .monospaced))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: template.symbol)
                    .font(.title2)
                Text(title.ifEmpty(template.title))
                    .font(.title3.bold())
                    .lineLimit(1)
            }
            Spacer()
            ForEach(fields.prefix(compact ? 3 : 5)) { field in
                LabelValue(label: field.name, value: field.value)
            }
        }
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "key.fill")
                Text(fields.value("Service").ifEmpty(title.ifEmpty("API Key")))
                    .font(.title3.bold())
                    .lineLimit(1)
            }
            Spacer()
            Text(maskSecret(fields.firstValue("Key", "Secret")))
                .font(.system(.headline, design: .monospaced))
                .lineLimit(2)
            LabelValue(label: "Environment", value: fields.value("Environment"))
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.ifEmpty("Secure Note"))
                .font(.title3.bold())
            Text(fields.value("Content").ifEmpty("No content"))
                .font(.body)
                .lineLimit(compact ? 4 : 8)
            Spacer()
        }
    }

    private var qrCard: some View {
        HStack(spacing: 16) {
            if let image = QRCode.makeImage(from: fields.value("Data")) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(width: compact ? 96 : 130)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 64))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title.ifEmpty("QR Code"))
                    .font(.title3.bold())
                    .lineLimit(2)
                Text(fields.value("Data"))
                    .font(.caption)
                    .lineLimit(4)
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
                    .font(.title)
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
