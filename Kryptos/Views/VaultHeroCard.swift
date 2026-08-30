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
                .foregroundStyle(foreground)
                .frame(height: 132)
        } else {
            card
                .foregroundStyle(foreground)
                .aspectRatio(template == .note ? 1.35 : 1.586, contentMode: .fit)
        }
    }

    private var foreground: Color {
        switch template {
        case .note:
            Color(red: 0.18, green: 0.13, blue: 0.05)
        default:
            .white
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

                // Slow diagonal shine sweep across the card.
                ShineSweep(cornerRadius: cornerRadius)

                content
                    .padding(compact ? 14 : 20)
            }

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(compact ? 0.14 : 0.22), lineWidth: 1)

            if template.supportsExpiryBadge, !showsScannedPreview,
               let status = ExpiryStatus(date: expiryDate),
               !compact || status.isUrgent {
                VStack {
                    HStack {
                        Spacer()
                        expiryBadge(status)
                            .padding(compact ? 10 : 12)
                    }
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var expiryDate: Date? {
        ExpiryReminderService.shared.expiryDate(forFields: fields, template: template)
    }

    private func expiryBadge(_ status: ExpiryStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(status.label)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }

    private var cornerRadius: CGFloat {
        compact ? 14 : 22
    }

    /// Horizontal space the expiry badge occupies in the top-trailing corner,
    /// reserved by the content so titles don't run underneath it. The badge
    /// uses a fixed 10pt font, so its width does not shrink on compact cards —
    /// the reservation is the same either way, plus the card's own inset.
    private var badgeReservedWidth: CGFloat {
        guard template.supportsExpiryBadge,
              let status = ExpiryStatus(date: expiryDate),
              !compact || status.isUrgent
        else { return 0 }
        return 118
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
                Text(title.ifBlank(template.title))
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
        template.heroGradient
    }

    private var identityCard: some View {
        HStack(spacing: compact ? 12 : 16) {
            photoSlot
                .frame(width: compact ? 58 : 92)

            VStack(alignment: .leading, spacing: compact ? 5 : 12) {
                Text(title.isEmpty ? template.title.uppercased() : title)
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.trailing, badgeReservedWidth)

                LabelValue(label: template == .passport ? "Number" : "Identifier", value: maskIdentifier(fields.firstValue("Passport number", "ID number", "License number")))
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.space3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.ifBlank(fields.value("Issuer").ifBlank("KRYPTOS CARD")))
                        .font((compact ? Font.subheadline : Font.headline).bold())
                        .lineLimit(1)
                    if !title.isEmpty, !fields.value("Issuer").isEmpty, title != fields.value("Issuer") {
                        Text(fields.value("Issuer"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Leaves room for the expiry badge pinned to the same corner.
                Color.clear.frame(width: badgeReservedWidth, height: 1)
            }

            if !compact {
                Spacer(minLength: 8)
                chipMark
            }

            Spacer(minLength: compact ? 6 : 10)

            Text(maskCard(fields.firstValue("Number", "Card number")))
                .font(.system(size: compact ? 15 : 22, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: compact ? 6 : 10)

            HStack(alignment: .bottom) {
                LabelValue(label: "Cardholder", value: fields.value("Cardholder"))
                Spacer(minLength: Theme.space3)
                LabelValue(label: "Expires", value: formattedExpiry(fields.value("Expiry")))
            }
        }
    }

    /// The stamped foil chip on full-size payment cards.
    private var chipMark: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 34, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    private var documentCard: some View {
        HStack(spacing: compact ? 12 : 16) {
            iconPlaceholder(symbol: template.symbol)
                .frame(width: compact ? 58 : 92)

            VStack(alignment: .leading, spacing: compact ? 6 : 12) {
                Text(title.ifBlank(template.title))
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(1)
                ForEach(fields.prefix(compact ? 2 : 5)) { field in
                    LabelValue(label: field.name, value: displayValue(field))
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private var apiKeyCard: some View {
        HStack(spacing: compact ? 12 : 16) {
            iconPlaceholder(symbol: "key.fill")
                .frame(width: compact ? 58 : 92)

            VStack(alignment: .leading, spacing: compact ? 6 : 12) {
                Text(fields.value("Service").ifBlank(title.ifBlank("API Key")))
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(1)
                Text(maskSecret(fields.firstValue("Key", "Secret")))
                    .font(.system(compact ? .subheadline : .headline, design: .monospaced))
                    .lineLimit(compact ? 1 : 2)
                LabelValue(label: "Environment", value: fields.value("Environment"))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private var noteCard: some View {
        HStack(spacing: compact ? 12 : 16) {
            iconPlaceholder(symbol: "note.text")
                .frame(width: compact ? 58 : 92)

            VStack(alignment: .leading, spacing: compact ? 6 : 12) {
                Text(title.ifBlank("Secure Note"))
                    .font((compact ? Font.subheadline : Font.title3).bold())
                    .lineLimit(1)
                Text(fields.value("Content").ifBlank("No content"))
                    .font(compact ? .caption : .body)
                    .lineLimit(compact ? 3 : 8)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private func iconPlaceholder(symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(foreground.opacity(0.18))
            if let attachment, let image = ImageCache.shared.image(for: attachment) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: symbol)
                    .font(compact ? .title3 : .title)
                    .foregroundStyle(foreground.opacity(0.78))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                Text(title.ifBlank("QR Code"))
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
        iconPlaceholder(symbol: "person.crop.rectangle")
    }

    private func maskCard(_ number: String) -> String {
        let digits = number.digitsOnly
        guard digits.count > 4 else { return number.ifBlank("•••• •••• •••• ••••") }
        return "•••• •••• •••• \(digits.suffix(4))"
    }

    private func maskSecret(_ value: String) -> String {
        guard !value.isEmpty else { return "••••••••••••••••" }
        return String(repeating: "•", count: min(value.count, 18))
    }

    private func maskIdentifier(_ value: String) -> String {
        let significant = value.filter { !$0.isWhitespace }
        guard significant.count > 4 else { return maskSecret(value) }
        return "•••• \(significant.suffix(4))"
    }

    /// Masks sensitive values in card previews so full financial and document
    /// identifiers never appear on the home screen.
    private func displayValue(_ field: VaultField) -> String {
        if field.name.looksSecretFieldName {
            return maskSecret(field.value)
        }
        if template == .paymentCard,
           field.name.localizedCaseInsensitiveCompare("Number") == .orderedSame ||
           field.name.lowercased().contains("card number") {
            return maskCard(field.value)
        }
        return field.value
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
            Text(value.ifBlank("-"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

/// A slow, subtle diagonal highlight that drifts across hero cards,
/// giving premium cards a "living metal" feel.
private struct ShineSweep: View {
    let cornerRadius: CGFloat

    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var offset: CGFloat = -1.4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.0),
                            .white.opacity(0.09),
                            .white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width * 0.55)
                .rotationEffect(.degrees(24))
                .offset(x: offset * width, y: -height * 0.4)
                .blendMode(.overlay)
                .onAppear {
                    // Purely decorative; park it off-card under Reduce Motion.
                    guard ambientMotionEnabled else { return }
                    withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: false)) {
                        offset = 1.4
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSData, UIImage>()
    private init() {}
    
    func image(for data: Data) -> UIImage? {
        let nsData = data as NSData
        if let cached = cache.object(forKey: nsData) {
            return cached
        }
        if let image = UIImage(data: data) {
            cache.setObject(image, forKey: nsData)
            return image
        }
        return nil
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

// MARK: - Previews

#Preview("Hero Card — Payment", traits: .sizeThatFitsLayout) {
    VaultHeroCard(
        template: .paymentCard,
        title: "Platinum Rewards",
        fields: [
            VaultField(name: "Cardholder", value: "Faizal Zain"),
            VaultField(name: "Number", value: "4539 1234 5678 9012"),
            VaultField(name: "Expiry", value: "09/28")
        ],
        attachment: nil
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Hero Card — Passport", traits: .sizeThatFitsLayout) {
    VaultHeroCard(
        template: .passport,
        title: "Faizal Zain",
        fields: [
            VaultField(name: "Passport number", value: "A12345678"),
            VaultField(name: "Full name", value: "Faizal Zain"),
            VaultField(name: "Date of birth", value: "1990-01-01"),
            VaultField(name: "Expiry", value: "2031-04-12")
        ],
        attachment: nil
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
