import Combine
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UIKit

enum KryptosSecurityError: LocalizedError {
    case keychainReadFailed
    case keychainWriteFailed
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed: "Unable to read the secure vault key."
        case .keychainWriteFailed: "Unable to store the secure vault key."
        case .encryptionFailed: "Unable to encrypt or decrypt the vault data."
        }
    }
}

final class KeychainStore {
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

final class VaultCrypto {
    static let shared = VaultCrypto()
    private let keychain = KeychainStore.shared
    private let keyName = "vault.crypto.key.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let lock = NSLock()
    private var cachedKey: SymmetricKey?

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
            Task { @MainActor in
                if success {
                    self?.unlocked = true
                } else {
                    self?.message = authError?.localizedDescription ?? "Authentication was cancelled."
                }
            }
        }
    }

    func lock() {
        unlocked = false
    }
}

enum SecureClipboard {
    static func copy(label: String, value: String) {
        UIPasteboard.general.string = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if UIPasteboard.general.string == value {
                UIPasteboard.general.string = ""
            }
        }
    }
}
