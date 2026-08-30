import SwiftUI

/// One name/value pair inside the detail screen's Values card. Sensitive values
/// stay masked until the user reveals them; tapping the value copies it.
struct FieldRow: View {
    let template: VaultTemplate
    let field: VaultField
    let sensitive: Bool
    let revealed: Bool
    let onToggle: () -> Void
    let onValueTap: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: Theme.space3) {
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(field.name.uppercased())
                    .font(Theme.captionSmall)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)

                Button(action: onValueTap) {
                    Text(displayedValue)
                        .font(revealed ? Theme.bodyMedium : .system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(field.name)
                .accessibilityValue(revealed ? field.value : "Hidden")
                .accessibilityHint("Double tap to copy")
            }

            if sensitive {
                Button(action: onToggle) {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Theme.surfaceRaised, in: Circle())
                }
                .buttonStyle(PressableButtonStyle(amount: 0.9))
                .accessibilityLabel(revealed ? "Hide \(field.name)" : "Reveal \(field.name)")
            }

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.14), in: Circle())
            }
            .buttonStyle(PressableButtonStyle(amount: 0.9))
            .accessibilityLabel("Copy \(field.name)")
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space3)
        .contentShape(Rectangle())
    }

    private var displayedValue: String {
        guard revealed else {
            return String(repeating: "•", count: min(max(field.value.count, 4), 16))
        }
        return FieldInputRules.displayString(field.value, for: template, fieldName: field.name)
    }
}

struct QRPayload: Identifiable {
    let id: String
    let value: String
    let title: String

    init(value: String, title: String) {
        self.value = value
        self.title = title
        self.id = UUID().uuidString
    }
}

struct QRShareView: View {
    @Environment(\.dismiss) private var dismiss
    let payload: QRPayload

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                if let image = QRCode.makeImage(from: payload.value) {
                    VStack(spacing: Theme.space5) {
                        Text("Scan from another Kryptos app (iOS or Android) to import this entry. Works fully offline — nothing leaves your device.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)

                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(Theme.space4)
                            .background(.white, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                            .accessibilityLabel("QR code for \(payload.title.ifBlank("this entry"))")

                        ShareLink(
                            item: payload.value,
                            preview: SharePreview(payload.title.ifBlank("Kryptos QR"), image: Image(uiImage: image))
                        ) {
                            Label("Share QR Code", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(Theme.space5)
                } else {
                    ContentUnavailableView("No QR data", systemImage: "qrcode")
                }
            }
            .navigationTitle("Share entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                Button("Close") { dismiss() }
            }
        }
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }
}

// MARK: - Previews

#Preview("Field rows", traits: .sizeThatFitsLayout) {
    VaultCard(padding: 0) {
        VStack(spacing: 0) {
            FieldRow(
                template: .paymentCard,
                field: VaultField(name: "Cardholder", value: "Faizal Zain"),
                sensitive: false,
                revealed: true,
                onToggle: {}, onValueTap: {}, onCopy: {}
            )
            VaultDivider()
            FieldRow(
                template: .paymentCard,
                field: VaultField(name: "Number", value: "4539123456789012"),
                sensitive: true,
                revealed: false,
                onToggle: {}, onValueTap: {}, onCopy: {}
            )
        }
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
