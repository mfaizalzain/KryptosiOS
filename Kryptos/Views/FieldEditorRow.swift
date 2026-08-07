import SwiftUI
import SwiftData

struct FieldEditorRow: View {
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
                HStack(alignment: .center, spacing: 10) {
                    TextField("Value", text: Binding(
                        get: { displayedValue },
                        set: { field.value = FieldInputRules.sanitize($0, for: template, fieldName: field.name) }
                    ), axis: .vertical)
                    .keyboardType(keyboardType)
                    .frame(maxWidth: .infinity)

                    if let generator {
                        Button {
                            field.value = generator()
                        } label: {
                            Image(systemName: "dice.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(BrandPalette.primary)
                                .frame(width: 36, height: 36)
                                .background(BrandPalette.primary.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Generate secure value")
                    }
                }
            }
        }
    }

    private var generator: (() -> String)? {
        let name = field.name.lowercased()
        if name.contains("pin") {
            return { CredentialGenerator.pin() }
        }
        if template == .apiKey && (name == "key" || name.contains("secret")) {
            return { CredentialGenerator.apiKey() }
        }
        if ["password", "secret", "token", "passphrase", "passcode", "key", "code"].contains(where: { name.contains($0) }) {
            return { CredentialGenerator.password() }
        }
        return nil
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

enum FieldInputRules {
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
