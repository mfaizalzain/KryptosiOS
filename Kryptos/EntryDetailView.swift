import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let record: VaultEntryRecord
    @State private var showingEditor = false
    @State private var confirmingDelete = false
    @State private var revealedFields = Set<UUID>()
    @State private var qrPayload: QRPayload?

    private var fields: [VaultField] {
        (try? VaultCrypto.shared.decodeFields(record.encryptedFields)) ?? []
    }

    private var attachment: Data? {
        record.encryptedAttachment.flatMap { try? VaultCrypto.shared.open($0) }
    }

    var body: some View {
        List {
            Section {
                VaultHeroCard(template: record.template, title: record.title, fields: fields, attachment: attachment)
                    .listRowInsets(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
                    .listRowBackground(Color.clear)
            }

            let copyableFields = fields.filter { !$0.value.isEmpty }
            if !copyableFields.isEmpty {
                Section("Values") {
                    ForEach(copyableFields) { field in
                        FieldRow(
                            field: field,
                            sensitive: isSensitive(field),
                            revealed: !isSensitive(field) || revealedFields.contains(field.id),
                            onToggle: {
                                if revealedFields.contains(field.id) {
                                    revealedFields.remove(field.id)
                                } else {
                                    revealedFields.insert(field.id)
                                }
                            },
                            onValueTap: {
                                if isSensitive(field) {
                                    revealedFields.insert(field.id)
                                }
                                SecureClipboard.copy(label: field.name, value: field.value)
                            }
                        )
                    }
                }
            }

            if let attachment, record.template != .idCard, record.template != .passport, let image = UIImage(data: attachment) {
                Section("Attachment") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            Section {
                Text("Tap a value to reveal and copy it. The clipboard clears automatically after 30 seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(record.title.isEmpty ? "Entry Details" : record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    qrPayload = QRPayload(value: makeQRPayload(), title: record.title)
                } label: {
                    Image(systemName: "qrcode")
                }
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            EntryEditorView(record: record, ownerId: record.ownerId)
        }
        .sheet(item: $qrPayload) { payload in
            QRShareView(payload: payload)
        }
        .alert("Delete this entry?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                modelContext.delete(record)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(record.title.isEmpty ? "this entry" : record.title) from your vault.")
        }
    }

    private func makeQRPayload() -> String {
        if record.template == .qrCode {
            return fields.first { $0.name.localizedCaseInsensitiveCompare("Data") == .orderedSame }?.value ?? fields.first?.value ?? ""
        }
        let object = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func isSensitive(_ field: VaultField) -> Bool {
        let fieldName = field.name.lowercased()
        if fieldName.looksSecretFieldName {
            return true
        }
        if record.template == .paymentCard {
            return fieldName == "number" || fieldName.contains("card number")
        }
        return false
    }
}

private struct FieldRow: View {
    let field: VaultField
    let sensitive: Bool
    let revealed: Bool
    let onToggle: () -> Void
    let onValueTap: () -> Void

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
                SecureClipboard.copy(label: field.name, value: field.value)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
    }
}

private struct QRPayload: Identifiable {
    let id: String
    let value: String
    let title: String

    init(value: String, title: String) {
        self.value = value
        self.title = title
        self.id = "\(title)-\(value.hashValue)"
    }
}

private struct QRShareView: View {
    @Environment(\.dismiss) private var dismiss
    let payload: QRPayload

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = QRCode.makeImage(from: payload.value) {
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
