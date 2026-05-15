import SwiftData
import SwiftUI

struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VaultEntryRecord.updatedAt, order: .reverse) private var allRecords: [VaultEntryRecord]

    let record: VaultEntryRecord?
    let ownerId: String

    @State private var title: String
    @State private var template: VaultTemplate
    @State private var fields: [VaultField]
    @State private var attachment: Data?
    @State private var activeScan: ScanMode?
    @State private var duplicate: VaultEntryRecord?
    @State private var saveError: String?

    init(record: VaultEntryRecord?, ownerId: String) {
        self.record = record
        self.ownerId = ownerId
        let draft = VaultEntryDraft(record: record, crypto: .shared)
        _title = State(initialValue: draft.title)
        _template = State(initialValue: draft.template)
        _fields = State(initialValue: draft.fields)
        _attachment = State(initialValue: draft.attachment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                }

                Section("Type") {
                    Picker("Template", selection: $template) {
                        ForEach(VaultTemplate.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: template) { _, newValue in
                        if fields.allSatisfy({ $0.value.isEmpty }) {
                            fields = newValue.defaultFields.map { VaultField(name: $0, value: "") }
                        }
                    }
                }

                if template.supportsCameraScan || template.supportsNFC {
                    Section {
                        Button {
                            activeScan = .document
                        } label: {
                            Label("Scan document", systemImage: "doc.viewfinder")
                        }
                        .disabled(!template.supportsCameraScan)

                        Button {
                            activeScan = .qr
                        } label: {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                        }

                        Button {
                            activeScan = .nfc
                        } label: {
                            Label("Scan NFC", systemImage: "wave.3.right.circle")
                        }
                        .disabled(!template.supportsNFC)
                    } header: {
                        Text("Fill from scan")
                    } footer: {
                        Text(scanFooter)
                    }
                }

                Section("Fields") {
                    ForEach($fields) { $field in
                        FieldEditorRow(template: template, field: $field, isDefault: template.defaultFields.contains { $0.localizedCaseInsensitiveCompare(field.name) == .orderedSame })
                    }
                    .onDelete { indexSet in
                        fields.remove(atOffsets: indexSet)
                    }

                    Button {
                        fields.append(VaultField(name: "Field", value: ""))
                    } label: {
                        Label("Add field", systemImage: "plus")
                    }
                }

                if let attachment, let image = UIImage(data: attachment) {
                    Section("Attachment") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button(role: .destructive) {
                            self.attachment = nil
                        } label: {
                            Label("Remove attachment", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(record == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(item: $activeScan) { mode in
                switch mode {
                case .document:
                    DocumentScanView(template: template) { parsed, rawText, imageData in
                        applyParsedFields(parsed, fallbackText: rawText)
                        if let imageData { attachment = imageData }
                        activeScan = nil
                    }
                case .qr:
                    QRScannerView { value in
                        applyQR(value)
                        activeScan = nil
                    }
                case .nfc:
                    NFCScanInfoView(template: template)
                }
            }
            .alert("Potential duplicate", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } })) {
                Button("Save anyway") {
                    let ignored = duplicate
                    duplicate = nil
                    save(skipDuplicate: ignored)
                }
                Button("Cancel", role: .cancel) { duplicate = nil }
            } message: {
                Text("An entry with similar details already exists (\(duplicate?.title ?? "Untitled")). Save this anyway?")
            }
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var scanFooter: String {
        switch template {
        case .passport:
            "Use the camera for the photo page. NFC passport reading needs the iOS Core NFC entitlement and an ISO 7816 passport implementation."
        case .paymentCard:
            "Camera scan extracts visible card text. iOS restricts EMV NFC access; the NFC hook is kept separate for entitlement-backed implementation."
        default:
            "Camera and QR scans can prefill fields. You can edit every value before saving."
        }
    }

    private func save(skipDuplicate: VaultEntryRecord? = nil) {
        if let duplicate = findDuplicate(), duplicate.id != skipDuplicate?.id {
            self.duplicate = duplicate
            return
        }

        do {
            let encryptedFields = try VaultCrypto.shared.encodeFields(fields)
            let encryptedAttachment = try attachment.map { try VaultCrypto.shared.seal($0) }
            if let record {
                record.template = template
                record.title = title
                record.encryptedFields = encryptedFields
                record.encryptedAttachment = encryptedAttachment
                record.updatedAt = .now
            } else {
                modelContext.insert(VaultEntryRecord(
                    ownerId: ownerId,
                    template: template,
                    title: title,
                    encryptedFields: encryptedFields,
                    encryptedAttachment: encryptedAttachment
                ))
            }
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func findDuplicate() -> VaultEntryRecord? {
        let titleKey = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let identifiers = duplicateKeys(for: template).compactMap { key in
            fields.first { $0.name.localizedCaseInsensitiveCompare(key) == .orderedSame }?.value.normalizedIdentifier
        }.filter { !$0.isEmpty }

        return allRecords.first { existing in
            guard existing.ownerId == ownerId, existing.id != record?.id else { return false }
            if !titleKey.isEmpty && existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == titleKey {
                return true
            }
            guard existing.template == template, !identifiers.isEmpty else { return false }
            let existingFields = (try? VaultCrypto.shared.decodeFields(existing.encryptedFields)) ?? []
            return duplicateKeys(for: template).contains { key in
                guard let value = existingFields.first(where: { $0.name.localizedCaseInsensitiveCompare(key) == .orderedSame })?.value.normalizedIdentifier else {
                    return false
                }
                return identifiers.contains(value)
            }
        }
    }

    private func duplicateKeys(for template: VaultTemplate) -> [String] {
        switch template {
        case .idCard: ["ID number"]
        case .passport: ["Passport number"]
        case .driversLicense: ["License number"]
        case .birthCertificate: ["Registration number"]
        case .paymentCard: ["Number"]
        case .bankAccount: ["Account number", "IBAN"]
        case .taxNumber: ["Tax number"]
        case .apiKey: ["Key"]
        case .note: []
        case .qrCode: ["Data"]
        }
    }

    private func applyParsedFields(_ parsed: [VaultField], fallbackText: String?) {
        if parsed.isEmpty, let fallbackText, !fallbackText.isEmpty {
            mergeField(name: template == .qrCode ? "Data" : "Scanned text", value: fallbackText)
            return
        }
        parsed.forEach { mergeField(name: $0.name, value: $0.value) }
    }

    private func applyQR(_ value: String) {
        if
            let data = value.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            object.keys.sorted().forEach { key in
                mergeField(name: key, value: "\(object[key] ?? "")")
            }
        } else {
            mergeField(name: template == .qrCode ? "Data" : "Scanned text", value: value)
        }
    }

    private func mergeField(name: String, value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let index = fields.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            fields[index].value = sanitized(value: value, fieldName: fields[index].name)
        } else {
            fields.append(VaultField(name: name, value: sanitized(value: value, fieldName: name)))
        }
    }

    private func sanitized(value: String, fieldName: String) -> String {
        let lowered = fieldName.lowercased()
        if template == .paymentCard, lowered.contains("expiry") || lowered.contains("expires") {
            return String(value.digitsOnly.prefix(4))
        }
        if lowered == "number" || lowered.contains("cvv") || lowered.contains("cvc") || lowered.contains("pin") {
            return value.digitsOnly
        }
        return value
    }
}

private enum ScanMode: Identifiable {
    case document
    case qr
    case nfc

    var id: String {
        switch self {
        case .document: "document"
        case .qr: "qr"
        case .nfc: "nfc"
        }
    }
}

private struct FieldEditorRow: View {
    let template: VaultTemplate
    @Binding var field: VaultField
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDefault {
                Text(field.name.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
            } else {
                TextField("Field name", text: $field.name)
            }

            if template == .note && field.name.localizedCaseInsensitiveCompare("Content") == .orderedSame {
                TextEditor(text: $field.value)
                    .frame(minHeight: 120)
            } else {
                TextField("Value", text: Binding(
                    get: { displayedValue },
                    set: { field.value = sanitize($0) }
                ), axis: .vertical)
                .keyboardType(keyboardType)
            }
        }
    }

    private var displayedValue: String {
        if template == .paymentCard && field.name.lowercased().contains("expiry") {
            let digits = field.value.digitsOnly
            guard digits.count > 2 else { return digits }
            return "\(digits.prefix(2))/\(digits.dropFirst(2))"
        }
        return field.value
    }

    private var keyboardType: UIKeyboardType {
        let name = field.name.lowercased()
        if name == "number" || name.contains("cvv") || name.contains("cvc") || name.contains("pin") || name.contains("expiry") {
            return .numberPad
        }
        return .default
    }

    private func sanitize(_ input: String) -> String {
        let name = field.name.lowercased()
        if template == .paymentCard && name.contains("expiry") {
            return String(input.digitsOnly.prefix(4))
        }
        if name == "number" || name.contains("cvv") || name.contains("cvc") || name.contains("pin") {
            return input.digitsOnly
        }
        return input
    }
}
