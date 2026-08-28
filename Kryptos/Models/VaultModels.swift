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
        case .paymentCard: ["Issuer", "Cardholder", "Number", "Expiry"]
        case .bankAccount: ["Bank", "Account holder", "Account number", "IBAN", "SWIFT/BIC", "PIN"]
        case .taxNumber: ["Full name", "Tax number", "Country"]
        case .apiKey: ["Service", "Environment", "Key", "Secret"]
        case .note: ["Content"]
        case .qrCode: ["QR type", "Data"]
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

    /// Accent tint used for icons, chips, and highlights of this template.
    var accentColor: Color {
        switch self {
        case .idCard: Color(red: 122/255, green: 158/255, blue: 255/255)
        case .passport: Color(red: 108/255, green: 150/255, blue: 255/255)
        case .driversLicense: Color(red: 92/255, green: 200/255, blue: 205/255)
        case .birthCertificate: Color(red: 96/255, green: 200/255, blue: 160/255)
        case .paymentCard: Color(red: 190/255, green: 140/255, blue: 235/255)
        case .bankAccount: Color(red: 90/255, green: 190/255, blue: 220/255)
        case .taxNumber: Color(red: 255/255, green: 170/255, blue: 110/255)
        case .apiKey: Color(red: 150/255, green: 165/255, blue: 190/255)
        case .note: Color(red: 255/255, green: 210/255, blue: 90/255)
        case .qrCode: Color(red: 110/255, green: 180/255, blue: 255/255)
        }
    }

    /// The gradient drawn behind hero cards for this template.
    var heroGradient: LinearGradient {
        switch self {
        case .idCard:
            LinearGradient(colors: [Color(red: 0.05, green: 0.20, blue: 0.50), Color(red: 0.00, green: 0.34, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .passport:
            LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.20), Color(red: 0.10, green: 0.22, blue: 0.46)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .driversLicense:
            LinearGradient(colors: [Color(red: 0.04, green: 0.30, blue: 0.45), Color(red: 0.10, green: 0.55, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .birthCertificate:
            LinearGradient(colors: [Color(red: 0.05, green: 0.34, blue: 0.30), Color(red: 0.12, green: 0.55, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paymentCard:
            LinearGradient(colors: [Color(red: 0.08, green: 0.08, blue: 0.14), Color(red: 0.18, green: 0.10, blue: 0.32), Color(red: 0.38, green: 0.12, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bankAccount:
            LinearGradient(colors: [Color(red: 0.05, green: 0.32, blue: 0.40), Color(red: 0.08, green: 0.46, blue: 0.50)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .taxNumber:
            LinearGradient(colors: [Color(red: 0.42, green: 0.18, blue: 0.10), Color(red: 0.65, green: 0.32, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .apiKey:
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.22, green: 0.24, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .note:
            LinearGradient(colors: [Color(red: 0.92, green: 0.74, blue: 0.18), Color(red: 0.98, green: 0.85, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .qrCode:
            LinearGradient(colors: [Color(red: 0.08, green: 0.30, blue: 0.55), Color(red: 0.10, green: 0.55, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Whether this template's hero card should show an expiry badge.
    var supportsExpiryBadge: Bool {
        switch self {
        case .idCard, .passport, .driversLicense, .paymentCard:
            true
        case .birthCertificate, .bankAccount, .taxNumber, .apiKey, .note, .qrCode:
            false
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
    // Backwards-compatible aliases to the new design system.
    static let deepNavy = Theme.background
    static let midnight = Color(red: 31/255, green: 42/255, blue: 74/255)
    static let primary = Theme.accent
    static let primaryGradient = Theme.accentGradient
    static let surfaceGradient = LinearGradient(
        colors: [Theme.background, midnight],
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
        return [
            "password", "pin", "cvv", "cvc", "secret", "token", "key", "code", "ssn",
            "account number", "account no", "iban", "tax number", "tax id"
        ].contains { value.contains($0) }
    }
}
