import Combine
import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UIKit
import UniformTypeIdentifiers

enum KryptosSecurityError: LocalizedError {
    case keychainReadFailed
    case keychainWriteFailed
    case encryptionFailed
    case weakPassphrase

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed: "Unable to read the secure vault key."
        case .keychainWriteFailed: "Unable to store the secure vault key."
        case .encryptionFailed: "Unable to encrypt or decrypt the vault data."
        case .weakPassphrase: "The backup passphrase must be at least 6 characters."
        }
    }
}

/// Envelope format for passphrase-wrapped backup keys.
/// `[ "KRY2" ][ salt (16) ][ AES.GCM.combined ]` where the AES key is PBKDF2-derived from the passphrase.
enum BackupKeyEnvelope {
    nonisolated static let magic = Data("KRY2".utf8)
    nonisolated static let saltSize = 16
    nonisolated static let pbkdf2Iterations: UInt32 = 200_000
    nonisolated static let minimumPassphraseLength = 6

    nonisolated static func isWrapped(_ data: Data) -> Bool {
        data.count > magic.count + saltSize && data.prefix(magic.count) == magic
    }
}

protocol KeychainStoring {
    nonisolated func data(for key: String) -> Data?
    nonisolated func set(_ data: Data, for key: String) throws
    nonisolated func remove(_ key: String)
}

nonisolated final class KeychainStore: KeychainStoring, @unchecked Sendable {
    static let shared = KeychainStore()
    private init() {}

    func data(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.fmz.kryptos",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    func set(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.fmz.kryptos",
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            attributes.forEach { newItem[$0.key] = $0.value }
            guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
                throw KryptosSecurityError.keychainWriteFailed
            }
        } else if status != errSecSuccess {
            throw KryptosSecurityError.keychainWriteFailed
        }
    }

    func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.fmz.kryptos",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated final class VaultCrypto: @unchecked Sendable {
    static let shared = VaultCrypto()
    private let keychain: KeychainStoring
    private let keyName: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let lock = NSLock()
    private var cachedKey: SymmetricKey?

    init(keyName: String = "vault.crypto.key.v1", keychain: KeychainStoring = KeychainStore.shared) {
        self.keyName = keyName
        self.keychain = keychain
    }

    private var key: SymmetricKey {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            
            if let cached = cachedKey {
                return cached
            }
            if let stored = keychain.data(for: keyName) {
                let decryptedKey = SymmetricKey(data: stored)
                cachedKey = decryptedKey
                return decryptedKey
            }
            var bytes = Data(count: 32)
            let result = bytes.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
            }
            guard result == errSecSuccess else { throw KryptosSecurityError.keychainReadFailed }
            try keychain.set(bytes, for: keyName)
            let newKey = SymmetricKey(data: bytes)
            cachedKey = newKey
            return newKey
        }
    }

    func seal(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw KryptosSecurityError.encryptionFailed }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    /// Tries to open data with an explicit key without touching the local keychain.
    /// Used to validate a backup before its key replaces the local vault key.
    func canOpen(_ data: Data, using keyData: Data) -> Bool {
        let candidate = SymmetricKey(data: keyData)
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return false }
        return (try? AES.GCM.open(box, using: candidate)) != nil
    }

    /// Wraps the vault key with a passphrase so the cloud copy is useless without it.
    func wrapKeyData(_ keyData: Data, withPassphrase passphrase: String) throws -> Data {
        guard passphrase.count >= BackupKeyEnvelope.minimumPassphraseLength else {
            throw KryptosSecurityError.weakPassphrase
        }
        let salt = Data((0..<BackupKeyEnvelope.saltSize).map { _ in UInt8.random(in: .min ... .max) })
        let derived = try Self.deriveBackupKey(from: passphrase, salt: salt)
        let box = try AES.GCM.seal(keyData, using: derived)
        guard let combined = box.combined else { throw KryptosSecurityError.encryptionFailed }
        var envelope = BackupKeyEnvelope.magic
        envelope.append(salt)
        envelope.append(combined)
        return envelope
    }

    /// Unwraps a backup key envelope. Returns nil for a wrong passphrase or a malformed envelope.
    func unwrapKeyData(_ envelope: Data, withPassphrase passphrase: String) -> Data? {
        guard BackupKeyEnvelope.isWrapped(envelope) else { return nil }
        let salt = envelope[BackupKeyEnvelope.magic.count ..< BackupKeyEnvelope.magic.count + BackupKeyEnvelope.saltSize]
        let combined = envelope.dropFirst(BackupKeyEnvelope.magic.count + BackupKeyEnvelope.saltSize)
        guard
            let derived = try? Self.deriveBackupKey(from: passphrase, salt: Data(salt)),
            let box = try? AES.GCM.SealedBox(combined: Data(combined))
        else { return nil }
        return try? AES.GCM.open(box, using: derived)
    }

    private static func deriveBackupKey(from passphrase: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(passphrase.utf8)
        var derived = Data(count: 32)
        let derivedCount = derived.count
        let status: OSStatus = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        BackupKeyEnvelope.pbkdf2Iterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        derivedCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw KryptosSecurityError.encryptionFailed }
        return SymmetricKey(data: derived)
    }

    func encodeFields(_ fields: [VaultField]) throws -> Data {
        try seal(encoder.encode(fields))
    }

    func decodeFields(_ encrypted: Data) throws -> [VaultField] {
        try decoder.decode([VaultField].self, from: open(encrypted))
    }

    func exportKeyData() throws -> Data {
        if let data = keychain.data(for: keyName) { return data }
        _ = try key
        guard let data = keychain.data(for: keyName) else { throw KryptosSecurityError.keychainReadFailed }
        return data
    }

    func importKeyData(_ data: Data) throws {
        try keychain.set(data, for: keyName)
        lock.lock()
        cachedKey = SymmetricKey(data: data)
        lock.unlock()
    }

    func destroyLocalKey() {
        keychain.remove(keyName)
        lock.lock()
        cachedKey = nil
        lock.unlock()
    }
}

@MainActor
final class BiometricGate: ObservableObject {
    @Published var unlocked = false
    @Published var message: String?

    func unlock() {
        let context = LAContext()
        var error: NSError?
        let reason = "Unlock your zero-knowledge vault."

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, authError in
            let message = authError?.localizedDescription ?? "Authentication was cancelled."
            Task { @MainActor [weak self, success, message] in
                if success {
                    self?.unlocked = true
                } else {
                    self?.message = message
                }
            }
        }
    }

    func lock() {
        unlocked = false
    }
}

enum SecureClipboard {
    static let clearAfter: TimeInterval = 30

    /// Copies a secret with a pasteboard expiry so it disappears after 30
    /// seconds even if the app is backgrounded or killed in the meantime — an
    /// in-process timer alone leaves secrets on the clipboard indefinitely.
    static func copy(value: String) {
        let expiry = Date().addingTimeInterval(clearAfter)
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [.expirationDate: expiry]
        )

        // Belt and braces: clear eagerly while we are still running, so the
        // value is gone the moment it expires rather than at the next read.
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) {
            if UIPasteboard.general.string == value {
                UIPasteboard.general.items = []
            }
        }
    }
}

/// Cryptographically secure random password / API key / PIN generation.
enum CredentialGenerator {
    struct Options {
        var length: Int
        var includeLowercase: Bool
        var includeUppercase: Bool
        var includeDigits: Bool
        var includeSymbols: Bool
        var excludeAmbiguous: Bool
    }

    private static let lowercase = "abcdefghijklmnopqrstuvwxyz"
    private static let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digits = "0123456789"
    private static let symbols = "!@#$%^&*()-_=+[]{};:,.<>?/~"
    private static let ambiguous = Set("Il1O0o")

    static func password(options: Options = .password) -> String {
        var sets: [String] = []
        if options.includeLowercase { sets.append(lowercase) }
        if options.includeUppercase { sets.append(uppercase) }
        if options.includeDigits { sets.append(digits) }
        if options.includeSymbols { sets.append(symbols) }
        guard !sets.isEmpty else { return "" }

        var pool = sets.joined()
        var eligibleSets: [String] = sets
        if options.excludeAmbiguous {
            pool = pool.filter { !ambiguous.contains($0) }
            eligibleSets = sets.map { $0.filter { !ambiguous.contains($0) } }.filter { !$0.isEmpty }
        }
        guard !pool.isEmpty else { return "" }

        var characters: [Character] = []
        // Guarantee at least one character from each requested set.
        for set in eligibleSets {
            characters.append(randomCharacter(from: set))
        }
        while characters.count < options.length {
            characters.append(randomCharacter(from: pool))
        }
        characters.shuffle()
        return String(characters.prefix(options.length))
    }

    static func apiKey(length: Int = 48) -> String {
        let byteCount = (length + 1) / 2
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else { return "" }
        return bytes.map { String(format: "%02x", $0) }.joined().prefix(length).description
    }

    static func pin(length: Int = 6) -> String {
        var result = ""
        for _ in 0..<length {
            result.append(randomCharacter(from: digits))
        }
        return result
    }

    private static func randomCharacter(from set: String) -> Character {
        let index = randomIndex(set.count)
        return set[set.index(set.startIndex, offsetBy: index)]
    }

    /// Uniform random index using rejection sampling to avoid modulo bias.
    private static func randomIndex(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let modulus = UInt32(count)
        let limit = UInt32.max - (UInt32.max % modulus)
        var value: UInt32 = 0
        repeat {
            _ = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &value)
        } while value >= limit
        return Int(value % modulus)
    }
}

extension CredentialGenerator.Options {
    static let password = CredentialGenerator.Options(
        length: 20,
        includeLowercase: true,
        includeUppercase: true,
        includeDigits: true,
        includeSymbols: true,
        excludeAmbiguous: true
    )
}
