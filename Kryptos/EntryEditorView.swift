import SwiftData
import SwiftUI

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

    init(record: VaultEntryRecord?, ownerId: String, initialQRPayload: String? = nil) {
        self.record = record
        self.ownerId = ownerId
        self.initialQRPayload = initialQRPayload
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

                Section {
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
            .onAppear {
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
                    .foregroundStyle(BrandPalette.primary)
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
            let encryptedFields = try VaultCrypto.shared.encodeFields(fields)
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

private struct FieldEditorRow: View {
    let template: VaultTemplate
    @Binding var field: VaultField
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDefault {
                Text(field.name.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrandPalette.primary)
            } else {
                TextField("Field name", text: $field.name)
            }

            switch inputKind {
            case .multiline:
                TextEditor(text: $field.value)
                    .frame(minHeight: 120)
            case .date:
                DatePicker(
                    "Value",
                    selection: dateBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
            case .paymentExpiry, .integer, .text:
                TextField("Value", text: Binding(
                    get: { displayedValue },
                    set: { field.value = FieldInputRules.sanitize($0, for: template, fieldName: field.name) }
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

    private var inputKind: FieldInputRules.Kind {
        FieldInputRules.kind(for: template, fieldName: field.name)
    }

    private var keyboardType: UIKeyboardType {
        switch inputKind {
        case .integer, .paymentExpiry:
            return .numberPad
        case .date, .text, .multiline:
            return .default
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { FieldInputRules.date(from: field.value) ?? Date() },
            set: { field.value = FieldInputRules.dateString(from: $0) }
        )
    }
}

private enum FieldInputRules {
    enum Kind {
        case text
        case multiline
        case integer(maxDigits: Int?)
        case paymentExpiry
        case date
    }

    static func kind(for template: VaultTemplate, fieldName: String) -> Kind {
        let name = fieldName.lowercased()

        if template == .note && name == "content" {
            return .multiline
        }

        if template == .paymentCard && (name.contains("expiry") || name.contains("expires")) {
            return .paymentExpiry
        }

        if isDateField(template: template, fieldName: name) {
            return .date
        }

        if let maxDigits = integerMaxDigits(template: template, fieldName: name) {
            return .integer(maxDigits: maxDigits)
        }

        return .text
    }

    static func sanitize(_ value: String, for template: VaultTemplate, fieldName: String) -> String {
        switch kind(for: template, fieldName: fieldName) {
        case .integer(let maxDigits):
            let digits = value.digitsOnly
            if let maxDigits {
                return String(digits.prefix(maxDigits))
            }
            return digits
        case .paymentExpiry:
            return String(value.digitsOnly.prefix(4))
        case .date:
            return normalizedDateString(from: value)
        case .text, .multiline:
            return value
        }
    }

    static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for formatter in inputDateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    static func dateString(from date: Date) -> String {
        storageDateFormatter.string(from: date)
    }

    private static func isDateField(template: VaultTemplate, fieldName name: String) -> Bool {
        if name.contains("date") {
            return true
        }
        if template != .paymentCard && (name == "expiry" || name.contains("expiration") || name.contains("expires")) {
            return true
        }
        return false
    }

    private static func integerMaxDigits(template: VaultTemplate, fieldName name: String) -> Int?? {
        if name.contains("cvv") || name.contains("cvc") || name.contains("security code") {
            return .some(4)
        }
        if name.contains("pin") {
            return .some(nil)
        }
        if template == .paymentCard && (name == "number" || name.contains("card number")) {
            return .some(19)
        }
        if template == .bankAccount && name == "account number" {
            return .some(nil)
        }
        return nil
    }

    private static func normalizedDateString(from value: String) -> String {
        if let date = date(from: value) {
            return dateString(from: date)
        }
        let digits = value.digitsOnly
        if digits.count == 8 {
            let dayFirst = "\(digits.prefix(2))/\(digits.dropFirst(2).prefix(2))/\(digits.suffix(4))"
            if let date = date(from: dayFirst) {
                return dateString(from: date)
            }
            let yearFirst = "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))"
            if let date = date(from: yearFirst) {
                return dateString(from: date)
            }
        }
        return value
    }

    private static let storageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let inputDateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy", "MM-dd-yyyy", "dd/MM/yy", "MM/dd/yy"].map { format in
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()
}
