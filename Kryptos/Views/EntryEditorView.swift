import SwiftUI
import SwiftData

struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VaultEntryRecord.updatedAt, order: .reverse) private var allRecords: [VaultEntryRecord]

    let record: VaultEntryRecord?
    let ownerId: String
    let initialQRPayload: String?

    @State private var title: String
    @State private var template: VaultTemplate
    @State private var fields: [VaultField]
    @State private var attachment: Data?
    @State private var activeScan: ScanMode?
    @State private var duplicate: VaultEntryRecord?
    @State private var saveError: String?
    @State private var didApplyInitialQR = false
    @State private var isLoading = false
    @FocusState private var focusedFieldID: UUID?

    init(record: VaultEntryRecord?, ownerId: String, initialQRPayload: String? = nil) {
        self.record = record
        self.ownerId = ownerId
        self.initialQRPayload = initialQRPayload
        
        _title = State(initialValue: record?.title ?? "")
        _template = State(initialValue: record?.template ?? .idCard)
        
        if record == nil {
            _fields = State(initialValue: VaultTemplate.idCard.defaultFields.map { VaultField(name: $0, value: "") })
            _isLoading = State(initialValue: false)
        } else {
            _fields = State(initialValue: [])
            _isLoading = State(initialValue: true)
        }
        _attachment = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(Theme.accent)
                                Text("Decrypting securely…")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                } else {
                    Section {
                        TextField("Title", text: $title)
                            .textInputAutocapitalization(.words)
                    } footer: {
                        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label("A title is required before you can save.", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                        }
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

                    Section {
                        if template.supportsCameraScan {
                            Button {
                                activeScan = .document
                            } label: {
                                Label("Scan document", systemImage: "doc.viewfinder")
                            }
                        }

                        Button {
                            activeScan = .qr
                        } label: {
                            Label(template == .qrCode ? "Scan QR to import" : "Scan QR", systemImage: "qrcode.viewfinder")
                        }
                    } header: {
                        Text("Fill from scan")
                    } footer: {
                        Text(scanFooter)
                    }

                    if template == .qrCode {
                        Section {
                            QRTypePicker(selected: QRPayloadBuilder.selectedType(from: fields)) { type in
                                fields = QRPayloadBuilder.defaultFields(for: type)
                                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    title = type.defaultTitle
                                }
                            }
                        } header: {
                            Text("QR content type")
                        } footer: {
                            Text("Choose a standard format so other phones can open contacts, Wi-Fi, messages, maps, events, and payment addresses directly.")
                        }
                    }

                    Section {
                        ForEach($fields) { $field in
                            FieldEditorRow(
                                template: template,
                                field: $field,
                                isDefault: template.defaultFields.contains { $0.localizedCaseInsensitiveCompare(field.name) == .orderedSame },
                                nameFieldFocus: $focusedFieldID
                            )
                        }
                        .onDelete { indexSet in
                            fields.remove(atOffsets: indexSet)
                        }

                        Button {
                            addCustomField()
                        } label: {
                            Label("Add field", systemImage: "plus")
                        }
                    } header: {
                        Text("Fields")
                    } footer: {
                        reminderHint
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
            }
            .vaultFormChrome()
            .navigationTitle(record == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isLoading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                if let record = record, fields.isEmpty && attachment == nil {
                    isLoading = true
                    let encryptedFields = record.encryptedFields
                    let encryptedAttachment = record.encryptedAttachment
                    do {
                        let decryptedFields = try await Task.detached(priority: .userInitiated) {
                            try VaultCrypto.shared.decodeFields(encryptedFields)
                        }.value
                        
                        let decryptedAttachment = try await Task.detached(priority: .userInitiated) {
                            try encryptedAttachment.map { try VaultCrypto.shared.open($0) }
                        }.value
                        
                        await MainActor.run {
                            self.fields = decryptedFields
                            self.attachment = decryptedAttachment
                            self.isLoading = false
                        }
                    } catch {
                        await MainActor.run {
                            self.isLoading = false
                        }
                    }
                } else {
                    isLoading = false
                }

                if !didApplyInitialQR, let payload = initialQRPayload {
                    didApplyInitialQR = true
                    applyQR(payload)
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

    @ViewBuilder
    private var reminderHint: some View {
        if let expiry = ExpiryReminderService.shared.expiryDate(forFields: fields, template: template) {
            Label {
                Text("We'll remind you 30, 7, and 1 day before \(expiry.formatted(date: .abbreviated, time: .omitted)).")
            } icon: {
                Image(systemName: "bell.badge")
                    .foregroundStyle(Theme.accent)
            }
        } else {
            Text("Add an \"Expiry\" field with a date (e.g. 12/2028 or 2028-12-31) and Kryptos will remind you 30, 7, and 1 day before it expires.")
        }
    }

    private var scanFooter: String {
        switch template {
        case .passport:
            "Use the camera for the photo page. OCR can prefill fields, and you can edit every value before saving."
        case .paymentCard:
            "Camera scan extracts visible card text. You can edit every value before saving."
        case .qrCode:
            "Point the camera at any QR code to import its contents. Kryptos can regenerate the same QR from this entry."
        case .apiKey, .note:
            "Scan a QR shared from another Kryptos device to import this entry."
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
            let savableFields = template == .qrCode ? QRPayloadBuilder.fieldsWithGeneratedData(fields) : fields
            let encryptedFields = try VaultCrypto.shared.encodeFields(savableFields)
            let encryptedAttachment = try attachment.map { try VaultCrypto.shared.seal($0) }
            let saved: VaultEntryRecord
            if let record {
                record.template = template
                record.title = title
                record.encryptedFields = encryptedFields
                record.encryptedAttachment = encryptedAttachment
                record.updatedAt = .now
                saved = record
            } else {
                let inserted = VaultEntryRecord(
                    ownerId: ownerId,
                    template: template,
                    title: title,
                    encryptedFields: encryptedFields,
                    encryptedAttachment: encryptedAttachment
                )
                modelContext.insert(inserted)
                saved = inserted
            }
            try modelContext.save()
            Task { await ExpiryReminderService.shared.scheduleReminders(for: saved) }
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
            if
                object["kryptos"] != nil,
                let fieldDict = object["fields"] as? [String: Any]
            {
                if
                    let templateRaw = object["template"] as? String,
                    let incoming = VaultTemplate(rawValue: templateRaw),
                    incoming != template
                {
                    template = incoming
                    fields = incoming.defaultFields.map { VaultField(name: $0, value: "") }
                }
                if
                    let incomingTitle = object["title"] as? String,
                    !incomingTitle.isEmpty
                {
                    title = incomingTitle
                }
                fieldDict.keys.sorted().forEach { key in
                    mergeField(name: key, value: "\(fieldDict[key] ?? "")")
                }
            } else {
                object.keys.sorted().forEach { key in
                    mergeField(name: key, value: "\(object[key] ?? "")")
                }
            }
        } else {
            mergeField(name: template == .qrCode ? "Data" : "Scanned text", value: value)
        }
    }

    /// Appends a custom field with a name that is unique within the entry.
    /// Duplicated names used to collide when the entry was shared as a QR
    /// envelope, and gave the user two identical-looking rows to edit.
    private func addCustomField() {
        let base = "Custom field"
        var candidate = base
        var suffix = 2
        while fields.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        let field = VaultField(name: candidate, value: "")
        fields.append(field)
        focusedFieldID = field.id
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
        FieldInputRules.sanitize(value, for: template, fieldName: fieldName)
    }
}

private enum ScanMode: Identifiable {
    case document
    case qr

    var id: String {
        switch self {
        case .document: "document"
        case .qr: "qr"
        }
    }
}
