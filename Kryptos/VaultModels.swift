import Foundation
import SwiftData
import SwiftUI

enum VaultTemplate: String, Codable, CaseIterable, Identifiable {
    case idCard
    case passport
    case driversLicense
    case birthCertificate
    case paymentCard
    case bankAccount
    case taxNumber
    case apiKey
    case note
    case qrCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idCard: "ID card"
        case .passport: "Passport"
        case .driversLicense: "Driver's license"
        case .birthCertificate: "Birth certificate"
        case .paymentCard: "Payment card"
        case .bankAccount: "Bank"
        case .taxNumber: "Tax number"
        case .apiKey: "API key"
        case .note: "Note"
        case .qrCode: "QR code"
        }
    }

    var pluralTitle: String {
        switch self {
        case .idCard: "ID Cards"
        case .passport: "Passports"
        case .driversLicense: "Licenses"
        case .birthCertificate: "Certificates"
        case .paymentCard: "Payment Cards"
        case .bankAccount: "Bank Accounts"
        case .taxNumber: "Tax Numbers"
        case .apiKey: "API Keys"
        case .note: "Notes"
        case .qrCode: "QR Codes"
        }
    }

    var symbol: String {
        switch self {
        case .idCard: "person.text.rectangle"
        case .passport: "airplane.departure"
        case .driversLicense: "car"
        case .birthCertificate: "doc.text"
        case .paymentCard: "creditcard"
        case .bankAccount: "building.columns"
        case .taxNumber: "number.square"
        case .apiKey: "key"
        case .note: "note.text"
        case .qrCode: "qrcode"
        }
    }

    var defaultFields: [String] {
        switch self {
        case .idCard: ["Full name", "ID number", "Date of birth", "Nationality"]
        case .passport: ["Surname", "Given names", "Passport number", "Nationality", "Date of birth", "Sex", "Expiry"]
        case .driversLicense: ["Full name", "License number", "Class", "Date of birth", "Expiry", "Country/State"]
        case .birthCertificate: ["Full name", "Date of birth", "Place of birth", "Father's name", "Mother's name", "Registration number", "Date of issue"]
        case .paymentCard: ["Issuer", "Cardholder", "Number", "Expiry", "CVV"]
        case .bankAccount: ["Bank", "Account holder", "Account number", "IBAN", "SWIFT/BIC", "PIN"]
        case .taxNumber: ["Full name", "Tax number", "Country"]
        case .apiKey: ["Service", "Environment", "Key", "Secret"]
        case .note: ["Content"]
        case .qrCode: ["Data"]
        }
    }

    var supportsCameraScan: Bool {
        switch self {
        case .idCard, .passport, .driversLicense, .birthCertificate, .paymentCard, .bankAccount, .taxNumber:
            true
        case .apiKey, .note, .qrCode:
            false
        }
    }

    var heroFieldKeys: Set<String> {
        switch self {
        case .idCard: ["full name", "id number", "date of birth", "nationality"]
        case .passport: ["surname", "given names", "passport number", "nationality", "date of birth", "sex", "expiry"]
        case .driversLicense: ["full name", "license number", "class", "date of birth", "expiry", "country/state"]
        case .birthCertificate: ["full name", "date of birth", "place of birth", "father's name", "mother's name", "registration number", "date of issue"]
        case .paymentCard: ["issuer", "cardholder", "number", "card number", "card no", "card no.", "expiry", "cvv", "cvc", "security code"]
        case .bankAccount: ["bank", "account holder", "account number", "iban", "swift/bic", "pin"]
        case .taxNumber: ["full name", "tax number", "country"]
        case .apiKey: ["service", "environment", "key", "secret"]
        case .note: ["content"]
        case .qrCode: ["data"]
        }
    }
}

struct VaultField: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var value: String
}

@Model
final class VaultEntryRecord {
    @Attribute(.unique) var id: UUID
    var ownerId: String
    var templateRaw: String
    var title: String
    @Attribute(.externalStorage) var encryptedFields: Data
    @Attribute(.externalStorage) var encryptedAttachment: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerId: String,
        template: VaultTemplate,
        title: String,
        encryptedFields: Data,
        encryptedAttachment: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerId = ownerId
        self.templateRaw = template.rawValue
        self.title = title
        self.encryptedFields = encryptedFields
        self.encryptedAttachment = encryptedAttachment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var template: VaultTemplate {
        get { VaultTemplate(rawValue: templateRaw) ?? .idCard }
        set { templateRaw = newValue.rawValue }
    }
}

struct VaultEntryDraft: Identifiable, Hashable {
    var id: UUID?
    var template: VaultTemplate
    var title: String
    var fields: [VaultField]
    var attachment: Data?

    var stableId: UUID { id ?? UUID() }

    init(record: VaultEntryRecord? = nil, crypto: VaultCrypto) {
        if let record {
            self.id = record.id
            self.template = record.template
            self.title = record.title
            self.fields = (try? crypto.decodeFields(record.encryptedFields)) ?? []
            self.attachment = record.encryptedAttachment.flatMap { try? crypto.open($0) }
        } else {
            self.id = nil
            self.template = .idCard
            self.title = ""
            self.fields = VaultTemplate.idCard.defaultFields.map { VaultField(name: $0, value: "") }
            self.attachment = nil
        }
    }
}

extension Array where Element == VaultField {
    func value(_ name: String) -> String {
        first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
    }

    func firstValue(_ names: String...) -> String {
        for name in names {
            let candidate = value(name)
            if !candidate.isEmpty { return candidate }
        }
        return ""
    }
}

enum BrandPalette {
    static let deepNavy = Color(red: 15/255, green: 23/255, blue: 48/255)
    static let midnight = Color(red: 31/255, green: 42/255, blue: 74/255)
    static let primary = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 123/255, green: 168/255, blue: 255/255, alpha: 1)
            : UIColor(red: 0/255, green: 86/255, blue: 210/255, alpha: 1)
    })

    static let primaryGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 165/255, green: 198/255, blue: 255/255, alpha: 1)
                    : UIColor(red: 123/255, green: 168/255, blue: 255/255, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 92/255, green: 145/255, blue: 240/255, alpha: 1)
                    : UIColor(red: 0/255, green: 86/255, blue: 210/255, alpha: 1)
            })
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [deepNavy, midnight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension String {
    var normalizedIdentifier: String {
        String(lowercased().filter { $0.isLetter || $0.isNumber })
    }

    var digitsOnly: String {
        String(filter { $0.isNumber })
    }

    var looksSecretFieldName: Bool {
        let value = lowercased()
        return ["password", "pin", "cvv", "cvc", "secret", "token", "key", "code", "ssn"].contains { value.contains($0) }
    }
}
