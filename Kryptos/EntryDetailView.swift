import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let record: VaultEntryRecord
    @State private var showingEditor = false
    @State private var confirmingDelete = false
    @State private var revealedFields = Set<UUID>()
    @State private var qrPayload: String?

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

            let heroKeys = record.template.heroFieldKeys
            let extras = fields.filter { !heroKeys.contains($0.name.lowercased()) && !$0.value.isEmpty }
            if !extras.isEmpty {
                Section("Details") {
                    ForEach(extras) { field in
                        FieldRow(
                            field: field,
                            revealed: !field.name.looksSecretFieldName || revealedFields.contains(field.id),
                            onToggle: {
                                if revealedFields.contains(field.id) {
                                    revealedFields.remove(field.id)
                                } else {
                                    revealedFields.insert(field.id)
                                }
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
                Text("Tap any field to copy. The clipboard clears automatically after 30 seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(record.title.isEmpty ? "Entry Details" : record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    qrPayload = makeQRPayload()
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
        .sheet(item: Binding(
            get: { qrPayload.map { QRPayload(value: $0, title: record.title) } },
            set: { qrPayload = $0?.value }
        )) { payload in
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
}

private struct FieldRow: View {
    let field: VaultField
    let revealed: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(revealed ? field.value : String(repeating: "•", count: min(field.value.count, 16)))
                    .font(.body)
                    .textSelection(.enabled)
            }
            Spacer()
            if field.name.looksSecretFieldName {
                Button(action: onToggle) {
                    Image(systemName: revealed ? "eye.slash" : "eye")
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
        .onTapGesture {
            SecureClipboard.copy(label: field.name, value: field.value)
        }
    }
}

private struct QRPayload: Identifiable {
    let id = UUID()
    let value: String
    let title: String
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
        .presentationDetents([.medium, .large])
    }
}
