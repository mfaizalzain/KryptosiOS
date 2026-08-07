import Foundation

enum QRPayloadType: String, CaseIterable, Identifiable {
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

enum QRPayloadBuilder {
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
