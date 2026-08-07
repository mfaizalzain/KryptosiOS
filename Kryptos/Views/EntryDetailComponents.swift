import SwiftUI

struct FieldRow: View {
    let field: VaultField
    let sensitive: Bool
    let revealed: Bool
    let onToggle: () -> Void
    let onValueTap: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button(action: onValueTap) {
                    Text(revealed ? field.value : String(repeating: "•", count: min(field.value.count, 16)))
                        .font(.body)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if sensitive && !revealed {
                Button(action: onToggle) {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
            } else if sensitive {
                Button(action: onToggle) {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
            }
            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
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
            VStack(spacing: 20) {
                if let image = QRCode.makeImage(from: payload.value) {
                    Text("Scan from another Kryptos app (iOS or Android) to import this entry. Works fully offline — nothing leaves your device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(radius: 8)
                        .padding(.horizontal)

                    ShareLink(item: payload.value, preview: SharePreview(payload.title.isEmpty ? "Kryptos QR" : payload.title, image: Image(uiImage: image))) {
                        Label("Share QR Code", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView("No QR data", systemImage: "qrcode")
                }
            }
            .padding()
            .navigationTitle("Share entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Close") { dismiss() }
            }
        }
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
    }
}
