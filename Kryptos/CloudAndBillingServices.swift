import CloudKit
import Combine
import Foundation
import StoreKit
import SwiftData

@MainActor
final class BillingService: ObservableObject {
    static let freeEntryLimit = 10
    static let productID = "kryptos_pro_upgrade"

    @Published private(set) var isPremium: Bool
    @Published var message: String?

    private let premiumKey = "billing.isPremium"

    init() {
        isPremium = UserDefaults.standard.bool(forKey: premiumKey)
        Task { await refreshEntitlements() }
    }

    func purchasePremium() async {
        do {
            guard let product = try await Product.products(for: [Self.productID]).first else {
                message = "Pro upgrade is not configured in App Store Connect yet."
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "The purchase could not be verified."
                    return
                }
                await transaction.finish()
                setPremium(true)
            case .userCancelled:
                break
            case .pending:
                message = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID {
                setPremium(true)
                return
            }
        }
    }

    private func setPremium(_ value: Bool) {
        isPremium = value
        UserDefaults.standard.set(value, forKey: premiumKey)
    }
}

struct BackupPayload: Codable {
    struct Entry: Codable {
        var id: UUID
        var ownerId: String
        var templateRaw: String
        var title: String
        var encryptedFields: Data
        var encryptedAttachment: Data?
        var createdAt: Date
        var updatedAt: Date
    }

    var version: Int
    var exportedAt: Date
    var entries: [Entry]
}

@MainActor
final class DriveBackupService: ObservableObject {
    @Published var workingMessage: String?
    @Published var feedback: String?

    private let backupName = "kryptos-ios-vault.json"
    private let keyName = "kryptos-ios.key"
    private let lastBackupKey = "drive.lastBackupAt"
    private let lastICloudBackupKey = "icloud.lastBackupAt"
    private let iCloudContainerIdentifier = "iCloud.com.fmz.kryptos"
    private let iCloudRecordType = "KryptosVaultBackup"
    private let iCloudRecordName = "vault"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var lastBackupAt: Date? {
        let value = UserDefaults.standard.double(forKey: lastBackupKey)
        return value == 0 ? nil : Date(timeIntervalSince1970: value)
    }

    var lastICloudBackupAt: Date? {
        let value = UserDefaults.standard.double(forKey: lastICloudBackupKey)
        return value == 0 ? nil : Date(timeIntervalSince1970: value)
    }

    func backup(records: [VaultEntryRecord], accessToken: String, toMyDrive: Bool = false) async {
        workingMessage = "Preparing encrypted backup..."
        feedback = nil
        do {
            let payload = try makeBackupData(records: records)

            if toMyDrive {
                workingMessage = "Finding KryptosBackups folder..."
                let folderId = try await getOrCreateFolder(accessToken: accessToken)
                try await uploadOrReplace(accessToken: accessToken, name: backupName, data: payload.vault, mime: "application/json", parent: folderId, appData: false)
                try await uploadOrReplace(accessToken: accessToken, name: keyName, data: payload.key, mime: "application/octet-stream", parent: folderId, appData: false)
            } else {
                workingMessage = "Uploading to private Drive AppData..."
                try await uploadOrReplace(accessToken: accessToken, name: backupName, data: payload.vault, mime: "application/json", parent: "appDataFolder", appData: true)
                try await uploadOrReplace(accessToken: accessToken, name: keyName, data: payload.key, mime: "application/octet-stream", parent: "appDataFolder", appData: true)
            }

            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastBackupKey)
            feedback = toMyDrive ? "Backup to My Drive complete." : "Backup complete."
        } catch {
            feedback = error.localizedDescription
        }
        workingMessage = nil
    }

    func backupToICloud(records: [VaultEntryRecord]) async {
        workingMessage = "Preparing encrypted iCloud backup..."
        feedback = nil
        do {
            let payload = try makeBackupData(records: records)
            let recordID = CKRecord.ID(recordName: iCloudRecordName)
            let record = try await fetchICloudRecord(id: recordID) ?? CKRecord(recordType: iCloudRecordType, recordID: recordID)
            record["vault"] = payload.vault as NSData
            record["key"] = payload.key as NSData
            record["updatedAt"] = Date.now as NSDate

            workingMessage = "Uploading to iCloud..."
            _ = try await saveICloudRecord(record)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastICloudBackupKey)
            feedback = "iCloud backup complete."
        } catch {
            feedback = error.localizedDescription
        }
        workingMessage = nil
    }

    func restoreFromICloud(modelContext: ModelContext, ownerId: String) async {
        workingMessage = "Looking for iCloud backup..."
        feedback = nil
        do {
            let recordID = CKRecord.ID(recordName: iCloudRecordName)
            guard let record = try await fetchICloudRecord(id: recordID) else {
                feedback = "No iCloud backup found."
                workingMessage = nil
                return
            }
            guard
                let vaultData = record["vault"] as? Data,
                let keyData = record["key"] as? Data
            else {
                feedback = "The iCloud backup is incomplete."
                workingMessage = nil
                return
            }

            try VaultCrypto.shared.importKeyData(keyData)
            try restorePayload(vaultData, modelContext: modelContext, ownerId: ownerId)
            feedback = "iCloud restore complete."
        } catch {
            feedback = error.localizedDescription
        }
        workingMessage = nil
    }

    func restore(accessToken: String, modelContext: ModelContext, ownerId: String) async {
        workingMessage = "Looking for Drive backup..."
        feedback = nil
        do {
            guard let backupFile = try await findFile(accessToken: accessToken, name: backupName, appData: true) else {
                feedback = "No backup found in Drive AppData."
                workingMessage = nil
                return
            }
            if let keyFile = try await findFile(accessToken: accessToken, name: keyName, appData: true) {
                let keyData = try await download(accessToken: accessToken, fileId: keyFile.id)
                try VaultCrypto.shared.importKeyData(keyData)
            }

            let data = try await download(accessToken: accessToken, fileId: backupFile.id)
            try restorePayload(data, modelContext: modelContext, ownerId: ownerId)
            feedback = "Restore complete."
        } catch {
            feedback = error.localizedDescription
        }
        workingMessage = nil
    }

    private func makeBackupData(records: [VaultEntryRecord]) throws -> (vault: Data, key: Data) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = BackupPayload(
            version: 1,
            exportedAt: .now,
            entries: records.map {
                BackupPayload.Entry(
                    id: $0.id,
                    ownerId: $0.ownerId,
                    templateRaw: $0.templateRaw,
                    title: $0.title,
                    encryptedFields: $0.encryptedFields,
                    encryptedAttachment: $0.encryptedAttachment,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        )
        return (try encoder.encode(payload), try VaultCrypto.shared.exportKeyData())
    }

    private func restorePayload(_ data: Data, modelContext: ModelContext, ownerId: String) throws {
        let payload = try decoder.decode(BackupPayload.self, from: data)
        let existing = try modelContext.fetch(FetchDescriptor<VaultEntryRecord>())
        existing.forEach { modelContext.delete($0) }
        payload.entries.forEach {
            modelContext.insert(VaultEntryRecord(
                id: $0.id,
                ownerId: $0.ownerId.isEmpty ? ownerId : $0.ownerId,
                template: VaultTemplate(rawValue: $0.templateRaw) ?? .idCard,
                title: $0.title,
                encryptedFields: $0.encryptedFields,
                encryptedAttachment: $0.encryptedAttachment,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            ))
        }
        try modelContext.save()
    }

    private struct DriveFile: Decodable {
        var id: String
        var modifiedTime: String?
    }

    private struct DriveList: Decodable {
        var files: [DriveFile]
    }

    private func findFile(accessToken: String, name: String, parent: String? = nil, appData: Bool) async throws -> DriveFile? {
        var query = "name='\(name)' and trashed=false"
        if let parent { query += " and '\(parent)' in parents" }
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,modifiedTime)"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc")
        ]
        if appData {
            components.queryItems?.append(URLQueryItem(name: "spaces", value: "appDataFolder"))
        }
        let list: DriveList = try await request(accessToken: accessToken, url: components.url!)
        return list.files.first
    }

    private func uploadOrReplace(accessToken: String, name: String, data: Data, mime: String, parent: String, appData: Bool) async throws {
        if let existing = try await findFile(accessToken: accessToken, name: name, parent: appData ? nil : parent, appData: appData) {
            var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files/\(existing.id)")!
            components.queryItems = [URLQueryItem(name: "uploadType", value: "media")]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "PATCH"
            request.setValue(mime, forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let _: Data = try await self.request(accessToken: accessToken, request: request)
            return
        }

        let boundary = "KryptosBoundary\(Int(Date.now.timeIntervalSince1970))"
        let metadata = ["name": name, "parents": [parent], "mimeType": mime] as [String: Any]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files")!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "multipart"), URLQueryItem(name: "fields", value: "id")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let _: Data = try await self.request(accessToken: accessToken, request: request)
    }

    private func getOrCreateFolder(accessToken: String) async throws -> String {
        if let folder = try await findFile(accessToken: accessToken, name: "KryptosBackups", appData: false) {
            return folder.id
        }
        let metadata = ["name": "KryptosBackups", "mimeType": "application/vnd.google-apps.folder"]
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let created: DriveFile = try await self.request(accessToken: accessToken, request: request)
        return created.id
    }

    private func download(accessToken: String, fileId: String) async throws -> Data {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        return try await request(accessToken: accessToken, url: url)
    }

    private func request<T: Decodable>(accessToken: String, url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await self.request(accessToken: accessToken, request: request)
    }

    private func request<T: Decodable>(accessToken: String, request: URLRequest) async throws -> T {
        let data: Data = try await self.request(accessToken: accessToken, request: request)
        return try decoder.decode(T.self, from: data)
    }

    private func request(accessToken: String, request original: URLRequest) async throws -> Data {
        var request = original
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "DriveBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Drive request failed."])
        }
        return data
    }

    private var iCloudDatabase: CKDatabase {
        CKContainer(identifier: iCloudContainerIdentifier).privateCloudDatabase
    }

    private func fetchICloudRecord(id: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            iCloudDatabase.fetch(withRecordID: id) { record, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: record)
                }
            }
        }
    }

    private func saveICloudRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            iCloudDatabase.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let saved {
                    continuation.resume(returning: saved)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }
}
