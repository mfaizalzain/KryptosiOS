//
//  KryptosTests.swift
//  KryptosTests
//
//  Created by Faizal Zain on 14/05/2026.
//

import XCTest
@testable import Kryptos

private final class InMemoryKeychain: KeychainStoring {
    private var store: [String: Data] = [:]

    func data(for key: String) -> Data? { store[key] }
    func set(_ data: Data, for key: String) throws { store[key] = data }
    func remove(_ key: String) { store[key] = nil }
}

final class KryptosTests: XCTestCase {
    private var crypto: VaultCrypto!

    override func setUpWithError() throws {
        crypto = VaultCrypto(keychain: InMemoryKeychain())
    }

    override func tearDownWithError() throws {
        crypto = nil
    }

    func testVaultCryptoEncryptionDecryption() throws {
        let originalFields = [
            VaultField(name: "Username", value: "alice_secure"),
            VaultField(name: "Password", value: "p@ssw0rd123")
        ]
        
        // Encode (encrypts internally)
        let encryptedData = try crypto.encodeFields(originalFields)
        XCTAssertFalse(encryptedData.isEmpty)
        
        // Decode (decrypts internally)
        let decryptedFields = try crypto.decodeFields(encryptedData)
        XCTAssertEqual(decryptedFields.count, originalFields.count)
        XCTAssertEqual(decryptedFields[0].name, "Username")
        XCTAssertEqual(decryptedFields[0].value, "alice_secure")
        XCTAssertEqual(decryptedFields[1].name, "Password")
        XCTAssertEqual(decryptedFields[1].value, "p@ssw0rd123")
    }

    func testVaultCryptoKeyLifecycle() throws {
        // Retrieve and check key data
        let initialKeyData = try crypto.exportKeyData()
        XCTAssertFalse(initialKeyData.isEmpty)
        
        // Destroy key
        crypto.destroyLocalKey()
        
        // Regenerate key
        let newKeyData = try crypto.exportKeyData()
        XCTAssertFalse(newKeyData.isEmpty)
        XCTAssertNotEqual(initialKeyData, newKeyData)
    }

    func testBackupKeyWrapUnwrapRoundTrip() throws {
        let keyData = try crypto.exportKeyData()
        let wrapped = try crypto.wrapKeyData(keyData, withPassphrase: "test-passphrase-123")
        XCTAssertTrue(BackupKeyEnvelope.isWrapped(wrapped))
        XCTAssertEqual(crypto.unwrapKeyData(wrapped, withPassphrase: "test-passphrase-123"), keyData)
    }

    func testBackupKeyWrongPassphraseFails() throws {
        let keyData = try crypto.exportKeyData()
        let wrapped = try crypto.wrapKeyData(keyData, withPassphrase: "test-passphrase-123")
        XCTAssertNil(crypto.unwrapKeyData(wrapped, withPassphrase: "wrong-passphrase"))
    }

    func testBackupKeyRejectsShortPassphrase() {
        XCTAssertThrowsError(try crypto.wrapKeyData(Data([0x01]), withPassphrase: "abc"))
    }

    func testLegacyRawKeyIsNotTreatedAsWrapped() throws {
        let keyData = try crypto.exportKeyData()
        XCTAssertFalse(BackupKeyEnvelope.isWrapped(keyData))
    }

    func testPasswordGeneratorLengthAndCharacterSets() {
        for _ in 0..<50 {
            let password = CredentialGenerator.password()
            XCTAssertEqual(password.count, 20)
            XCTAssertTrue(password.contains { $0.isLowercase })
            XCTAssertTrue(password.contains { $0.isUppercase })
            XCTAssertTrue(password.contains { $0.isNumber })
            XCTAssertTrue(password.contains { "!@#$%^&*()-_=+[]{};:,.<>?/~".contains($0) })
            XCTAssertFalse(password.contains { "Il1O0o".contains($0) })
        }
    }

    func testApiKeyIsHexWithExpectedLength() {
        let key = CredentialGenerator.apiKey()
        XCTAssertEqual(key.count, 48)
        XCTAssertTrue(key.allSatisfy { $0.isHexDigit })
        XCTAssertNotEqual(key, CredentialGenerator.apiKey())
    }

    func testPinContainsOnlyDigits() {
        let pin = CredentialGenerator.pin()
        XCTAssertEqual(pin.count, 6)
        XCTAssertTrue(pin.allSatisfy { $0.isNumber })
    }

}
