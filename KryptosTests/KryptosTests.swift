//
//  KryptosTests.swift
//  KryptosTests
//
//  Created by Faizal Zain on 14/05/2026.
//

import XCTest
@testable import Kryptos

final class KryptosTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testVaultCryptoEncryptionDecryption() throws {
        let originalFields = [
            VaultField(name: "Username", value: "alice_secure"),
            VaultField(name: "Password", value: "p@ssw0rd123")
        ]
        
        // Encode (encrypts internally)
        let encryptedData = try VaultCrypto.shared.encodeFields(originalFields)
        XCTAssertFalse(encryptedData.isEmpty)
        
        // Decode (decrypts internally)
        let decryptedFields = try VaultCrypto.shared.decodeFields(encryptedData)
        XCTAssertEqual(decryptedFields.count, originalFields.count)
        XCTAssertEqual(decryptedFields[0].name, "Username")
        XCTAssertEqual(decryptedFields[0].value, "alice_secure")
        XCTAssertEqual(decryptedFields[1].name, "Password")
        XCTAssertEqual(decryptedFields[1].value, "p@ssw0rd123")
    }

    func testVaultCryptoKeyLifecycle() throws {
        // Retrieve and check key data
        let initialKeyData = try VaultCrypto.shared.exportKeyData()
        XCTAssertFalse(initialKeyData.isEmpty)
        
        // Destroy key
        VaultCrypto.shared.destroyLocalKey()
        
        // Regenerate key
        let newKeyData = try VaultCrypto.shared.exportKeyData()
        XCTAssertFalse(newKeyData.isEmpty)
    }

}
