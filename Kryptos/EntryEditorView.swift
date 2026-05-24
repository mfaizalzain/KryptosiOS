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
    @State private var isLoading = false

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
                                    .tint(BrandPalette.primary)
                                Text("Decrypting securely...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                } else {
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
            }
            .navigationTitle(record == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
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

private struct QRTypePicker: View {
    let selected: QRPayloadType
    let onSelect: (QRPayloadType) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(QRPayloadType.allCases) { type in
                Button {
                    onSelect(type)
                } label: {
                    Label(type.label, systemImage: type.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected == type ? BrandPalette.primary.opacity(0.16) : Color.secondary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected == type ? BrandPalette.primary : .primary)
            }
        }
        .padding(.vertical, 4)
    }
}

private enum QRPayloadType: String, CaseIterable, Identifiable {
    case text
    case contact
    case wifi
    case email
    case phone
    case sms
    case location
    case calendar
    case payment

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Text"
        case .contact: "Contact"
        case .wifi: "Wi-Fi"
        case .email: "Email"
        case .phone: "Phone"
        case .sms: "SMS"
        case .location: "Location"
        case .calendar: "Calendar"
        case .payment: "Payment"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .contact: "person.crop.circle.badge.plus"
        case .wifi: "wifi"
        case .email: "envelope"
        case .phone: "phone"
        case .sms: "message"
        case .location: "mappin.and.ellipse"
        case .calendar: "calendar"
        case .payment: "creditcard"
        }
    }

    var defaultTitle: String {
        switch self {
        case .text: "QR code"
        case .contact: "Contact QR"
        case .wifi: "Wi-Fi QR"
        case .email: "Email QR"
        case .phone: "Phone QR"
        case .sms: "SMS QR"
        case .location: "Location QR"
        case .calendar: "Calendar QR"
        case .payment: "Payment QR"
        }
    }
}

private enum QRPayloadBuilder {
    static let typeField = "QR type"
    static let dataField = "Data"

    static func defaultFields(for type: QRPayloadType) -> [VaultField] {
        switch type {
        case .text:
            fields(type, dataField)
        case .contact:
            fields(type, dataField, "Full name", "Phone", "Email", "Organization", "Job title", "Website", "Address", "Note")
        case .wifi:
            [
                VaultField(name: typeField, value: type.label),
                VaultField(name: dataField, value: ""),
                VaultField(name: "Network name", value: ""),
                VaultField(name: "Password", value: ""),
                VaultField(name: "Security", value: "WPA"),
                VaultField(name: "Hidden", value: "false")
            ]
        case .email:
            fields(type, dataField, "Email", "Subject", "Body")
        case .phone:
            fields(type, dataField, "Phone")
        case .sms:
            fields(type, dataField, "Phone", "Message")
        case .location:
            fields(type, dataField, "Latitude", "Longitude", "Label")
        case .calendar:
            fields(type, dataField, "Title", "Starts", "Ends", "Location", "Description")
        case .payment:
            fields(type, dataField, "URI or address", "Amount", "Network", "Note")
        }
    }

    static func selectedType(from fields: [VaultField]) -> QRPayloadType {
        let raw = fields.value(typeField)
        guard !raw.isEmpty else { return .text }
        return QRPayloadType.allCases.first {
            $0.label.localizedCaseInsensitiveCompare(raw) == .orderedSame ||
            $0.rawValue.localizedCaseInsensitiveCompare(raw) == .orderedSame
        } ?? .text
    }

    static func fieldsWithGeneratedData(_ fields: [VaultField]) -> [VaultField] {
        let type = selectedType(from: fields)
        let payload = build(type: type, fields: fields)
        var normalized = fields
        if !normalized.contains(where: { $0.name.localizedCaseInsensitiveCompare(typeField) == .orderedSame }) {
            normalized.insert(VaultField(name: typeField, value: type.label), at: 0)
        }
        if let index = normalized.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(dataField) == .orderedSame }) {
            normalized[index].value = payload
        } else {
            normalized.insert(VaultField(name: dataField, value: payload), at: 0)
        }
        return normalized
    }

    private static func build(type: QRPayloadType, fields: [VaultField]) -> String {
        switch type {
        case .text:
            fields.value(dataField)
        case .contact:
            vCard(fields)
        case .wifi:
            wifi(fields)
        case .email:
            email(fields)
        case .phone:
            "tel:\(fields.value("Phone"))"
        case .sms:
            sms(fields)
        case .location:
            location(fields)
        case .calendar:
            calendar(fields)
        case .payment:
            payment(fields)
        }
    }

    private static func fields(_ type: QRPayloadType, _ names: String...) -> [VaultField] {
        [VaultField(name: typeField, value: type.label)] + names.map { VaultField(name: $0, value: "") }
    }

    private static func vCard(_ fields: [VaultField]) -> String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        appendLine(&lines, "FN", fields.value("Full name"))
        appendLine(&lines, "TEL", fields.value("Phone"))
        appendLine(&lines, "EMAIL", fields.value("Email"))
        appendLine(&lines, "ORG", fields.value("Organization"))
        appendLine(&lines, "TITLE", fields.value("Job title"))
        appendLine(&lines, "URL", fields.value("Website"))
        let address = fields.value("Address")
        if !address.isEmpty {
            lines.append("ADR:;;\(escapeVCard(address));;;;")
        }
        appendLine(&lines, "NOTE", fields.value("Note"))
        lines.append("END:VCARD")
        return lines.joined(separator: "\n")
    }

    private static func wifi(_ fields: [VaultField]) -> String {
        let security = fields.value("Security").isEmpty ? "nopass" : fields.value("Security")
        let ssid = fields.value("Network name")
        let password = fields.value("Password")
        let hidden = fields.value("Hidden").localizedCaseInsensitiveCompare("true") == .orderedSame
        return "WIFI:T:\(escapeWifi(security));S:\(escapeWifi(ssid));" +
            (password.isEmpty ? "" : "P:\(escapeWifi(password));") +
            (hidden ? "H:true;" : "") + ";"
    }

    private static func email(_ fields: [VaultField]) -> String {
        let address = fields.value("Email")
        let query = [
            queryItem("subject", fields.value("Subject")),
            queryItem("body", fields.value("Body"))
        ].compactMap { $0 }.joined(separator: "&")
        return "mailto:\(address)" + (query.isEmpty ? "" : "?\(query)")
    }

    private static func sms(_ fields: [VaultField]) -> String {
        let phone = fields.value("Phone")
        let message = fields.value("Message")
        guard !message.isEmpty else { return "sms:\(phone)" }
        return "sms:\(phone)?body=\(encode(message))"
    }

    private static func location(_ fields: [VaultField]) -> String {
        let latitude = fields.value("Latitude")
        let longitude = fields.value("Longitude")
        let label = fields.value("Label")
        guard !label.isEmpty else { return "geo:\(latitude),\(longitude)" }
        return "geo:\(latitude),\(longitude)?q=\(latitude),\(longitude)(\(encode(label)))"
    }

    private static func calendar(_ fields: [VaultField]) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT"]
        appendLine(&lines, "SUMMARY", fields.value("Title"))
        appendLine(&lines, "DTSTART", calendarDate(fields.value("Starts")))
        appendLine(&lines, "DTEND", calendarDate(fields.value("Ends")))
        appendLine(&lines, "LOCATION", fields.value("Location"))
        appendLine(&lines, "DESCRIPTION", fields.value("Description"))
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\n")
    }

    private static func payment(_ fields: [VaultField]) -> String {
        let base = fields.value("URI or address")
        let params = [
            queryItem("amount", fields.value("Amount")),
            queryItem("network", fields.value("Network")),
            queryItem("message", fields.value("Note"))
        ].compactMap { $0 }.joined(separator: "&")
        if base.contains(":") || params.isEmpty { return base }
        return "\(base)?\(params)"
    }

    private static func appendLine(_ lines: inout [String], _ key: String, _ value: String) {
        guard !value.isEmpty else { return }
        lines.append("\(key):\(escapeVCard(value))")
    }

    private static func queryItem(_ name: String, _ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        return "\(name)=\(encode(value))"
    }

    private static func calendarDate(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "T")
    }

    private static func escapeVCard(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    private static func escapeWifi(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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
