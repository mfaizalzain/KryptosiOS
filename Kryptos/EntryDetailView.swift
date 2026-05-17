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

    private var reminderText: String? {
        guard ExpiryReminderService.shared.isEnabled else { return nil }
        guard let expiry = ExpiryReminderService.shared.expiryDate(forFields: fields, template: record.template) else { return nil }
        let formatted = expiry.formatted(date: .abbreviated, time: .omitted)
        if expiry < .now {
            return "Expired on \(formatted). Update the Expiry field to schedule new reminders."
        }
        return "Reminders set for 30, 7, and 1 day before \(formatted)."
    }

    private var heroShowsAttachment: Bool {
        guard attachment != nil else { return false }
        switch record.template {
        case .idCard, .driversLicense, .paymentCard, .passport, .birthCertificate:
            return true
        case .bankAccount, .taxNumber, .apiKey, .note, .qrCode:
            return false
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VaultHeroCard(template: record.template, title: record.title, fields: fields, attachment: attachment)
                        .frame(maxWidth: 320)
                    Spacer(minLength: 0)
                }
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

            if let attachment, !heroShowsAttachment, let image = UIImage(data: attachment) {
                Section("Attachment") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            if let reminderText {
                Section {
                    Label {
                        Text(reminderText)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(BrandPalette.primary)
                    }
                }
            }

            Section {
                Button {
                    qrPayload = QRPayload(value: makeQRPayload(), title: record.title)
                } label: {
                    Label("Share with another device", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                .listRowBackground(Color.clear)

                Text("Scan the QR from another Kryptos app (iOS or Android) to import this entry instantly. Works fully offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
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
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share entry")
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
                let id = record.id
                modelContext.delete(record)
                try? modelContext.save()
                ExpiryReminderService.shared.cancelReminders(for: id)
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
        let fieldDict = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
        let envelope: [String: Any] = [
            "kryptos": 1,
            "template": record.template.rawValue,
            "title": record.title,
            "fields": fieldDict
        ]
        let data = (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
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
