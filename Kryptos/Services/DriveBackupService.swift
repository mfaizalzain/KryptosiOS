import CloudKit
import Combine
import Foundation
import SwiftData

@MainActor
final class DriveBackupService: ObservableObject {
    @Published var workingMessage: String?
    @Published var feedback: String?

    private let backupName = "kryptos-ios-vault.json"
    private let keyName = "kryptos-ios.key"
    private let myDriveFolderName = "KryptosBackups"
    private let lastAppDataBackupKey = "drive.lastAppDataBackupAt"
    private let lastMyDriveBackupKey = "drive.lastMyDriveBackupAt"
    private let legacyDriveBackupKey = "drive.lastBackupAt"
    private let lastICloudBackupKey = "icloud.lastBackupAt"
    private let iCloudContainerIdentifier = "iCloud.com.fmz.kryptos"
    private let iCloudRecordType = "KryptosVaultBackup"
    private let iCloudRecordName = "vault"
    private let iCloudVaultField = "vault"
    private let iCloudVaultAssetField = "vaultAsset"
    private let iCloudKeyField = "key"
    private let iCloudUpdatedAtField = "updatedAt"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let drive = DriveAPIClient()

    var lastAppDataBackupAt: Date? { storedDate(forKey: lastAppDataBackupKey) ?? storedDate(forKey: legacyDriveBackupKey) }
    var lastMyDriveBackupAt: Date? { storedDate(forKey: lastMyDriveBackupKey) }

    var lastDriveBackupAt: Date? {
        [lastAppDataBackupAt, lastMyDriveBackupAt].compactMap { $0 }.max()
    }

    var lastICloudBackupAt: Date? { storedDate(forKey: lastICloudBackupKey) }

    private func storedDate(forKey key: String) -> Date? {
        let value = UserDefaults.standard.double(forKey: key)
        return value == 0 ? nil : Date(timeIntervalSince1970: value)
    }

    typealias TokenRefresher = @Sendable () async -> String?

    func backup(records: [VaultEntryRecord], accessToken: String, toMyDrive: Bool = false, refresh: TokenRefresher? = nil) async {
        workingMessage = "Preparing encrypted backup..."
        feedback = nil
        let session = DriveSession(token: accessToken, refresh: refresh)
        do {
            let payload = try makeBackupData(records: records)

            if toMyDrive {
                workingMessage = "Finding \(myDriveFolderName) folder..."
                let folderId = try await drive.getOrCreateFolder(session: session)
                try await drive.uploadOrReplace(session: session, name: backupName, data: payload.vault, mime: "application/json", parent: folderId, appData: false)
                try await drive.uploadOrReplace(session: session, name: keyName, data: payload.key, mime: "application/octet-stream", parent: folderId, appData: false)
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastMyDriveBackupKey)
                feedback = "Backup to My Drive complete."
            } else {
                workingMessage = "Uploading to your private Drive folder..."
                try await drive.uploadOrReplace(session: session, name: backupName, data: payload.vault, mime: "application/json", parent: "appDataFolder", appData: true)
                try await drive.uploadOrReplace(session: session, name: keyName, data: payload.key, mime: "application/octet-stream", parent: "appDataFolder", appData: true)
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastAppDataBackupKey)
                feedback = "Backup complete."
            }
        } catch {
            feedback = BackupError.from(error).errorDescription
        }
        workingMessage = nil
    }

    func backupToICloud(records: [VaultEntryRecord]) async {
        workingMessage = "Preparing encrypted iCloud backup..."
        feedback = nil
        var assetDirectory: URL?
        do {
            let payload = try makeBackupData(records: records)
            let recordID = CKRecord.ID(recordName: iCloudRecordName)
            let record = try await fetchICloudRecord(id: recordID) ?? CKRecord(recordType: iCloudRecordType, recordID: recordID)
            let vaultAsset = try makeICloudAsset(data: payload.vault, fileName: backupName)
            assetDirectory = vaultAsset.fileURL.deletingLastPathComponent()

            record[iCloudVaultAssetField] = vaultAsset.asset
            record[iCloudKeyField] = payload.key as NSData
            record[iCloudUpdatedAtField] = Date.now as NSDate

            workingMessage = "Uploading to iCloud..."
            _ = try await saveICloudRecord(record)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastICloudBackupKey)
            feedback = "iCloud backup complete."
        } catch {
            feedback = BackupError.from(error).errorDescription
        }
        if let assetDirectory {
            try? FileManager.default.removeItem(at: assetDirectory)
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
            guard let vaultData = try iCloudVaultData(from: record), let keyData = record[iCloudKeyField] as? Data else {
                feedback = BackupError.iCloudMissingData.errorDescription
                workingMessage = nil
                return
            }

            try VaultCrypto.shared.importKeyData(keyData)
            try restorePayload(vaultData, modelContext: modelContext, ownerId: ownerId)
            feedback = "iCloud restore complete."
        } catch {
            feedback = BackupError.from(error).errorDescription
        }
        workingMessage = nil
    }

    func restore(appDataToken: String?, myDriveToken: String?, modelContext: ModelContext, ownerId: String, refresh: TokenRefresher? = nil) async {
        workingMessage = "Looking for Drive backup..."
        feedback = nil
        do {
            var candidates: [DriveBackupCandidate] = []

            if let token = appDataToken,
               let candidate = try await findAppDataCandidate(session: DriveSession(token: token, refresh: refresh)) {
                candidates.append(candidate)
            }

            if let token = myDriveToken,
               let candidate = try await findMyDriveCandidate(session: DriveSession(token: token, refresh: refresh)) {
                candidates.append(candidate)
            }

            guard let chosen = candidates.max(by: { $0.payload.exportedAt < $1.payload.exportedAt }) else {
                if appDataToken == nil && myDriveToken == nil {
                    feedback = "Sign in with Google to restore from Drive."
                } else {
                    feedback = "No backup found in Google Drive."
                }
                workingMessage = nil
                return
            }

            workingMessage = "Restoring from \(chosen.source.label)..."
            if let keyData = chosen.keyData {
                try VaultCrypto.shared.importKeyData(keyData)
            }
            try restoreDecodedPayload(chosen.payload, modelContext: modelContext, ownerId: ownerId)

            let extra = candidates.count > 1 ? " (newer of \(candidates.count) found)" : ""
            feedback = "Restore complete from \(chosen.source.label)\(extra)."
        } catch {
            feedback = BackupError.from(error).errorDescription
        }
        workingMessage = nil
    }

    private struct DriveBackupCandidate {
        let source: DriveBackupSource
        let payload: BackupPayload
        let keyData: Data?
    }

    private enum DriveBackupSource {
        case appData
        case myDrive

        var label: String {
            switch self {
            case .appData: "Drive (hidden)"
            case .myDrive: "My Drive"
            }
        }
    }

    private func findAppDataCandidate(session: DriveSession) async throws -> DriveBackupCandidate? {
        guard let backupFile = try await drive.findFile(session: session, name: backupName, appData: true) else { return nil }
        let data = try await drive.download(session: session, fileId: backupFile.id)
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var keyData: Data?
        if let keyFile = try await drive.findFile(session: session, name: keyName, appData: true) {
            keyData = try await drive.download(session: session, fileId: keyFile.id)
        }
        return DriveBackupCandidate(source: .appData, payload: payload, keyData: keyData)
    }

    private func findMyDriveCandidate(session: DriveSession) async throws -> DriveBackupCandidate? {
        guard let folder = try await drive.findFile(session: session, name: myDriveFolderName, appData: false) else { return nil }
        guard let backupFile = try await drive.findFile(session: session, name: backupName, parent: folder.id, appData: false) else { return nil }
        let data = try await drive.download(session: session, fileId: backupFile.id)
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var keyData: Data?
        if let keyFile = try await drive.findFile(session: session, name: keyName, parent: folder.id, appData: false) {
            keyData = try await drive.download(session: session, fileId: keyFile.id)
        }
        return DriveBackupCandidate(source: .myDrive, payload: payload, keyData: keyData)
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
        try restoreDecodedPayload(payload, modelContext: modelContext, ownerId: ownerId)
    }

    private func restoreDecodedPayload(_ payload: BackupPayload, modelContext: ModelContext, ownerId: String) throws {
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

    private func makeICloudAsset(data: Data, fileName: String) throws -> (asset: CKAsset, fileURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kryptos-icloud-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: fileName)
        try data.write(to: fileURL, options: .atomic)
        return (CKAsset(fileURL: fileURL), fileURL)
    }

    private func iCloudVaultData(from record: CKRecord) throws -> Data? {
        if let asset = record[iCloudVaultAssetField] as? CKAsset, let fileURL = asset.fileURL {
            return try Data(contentsOf: fileURL)
        }
        if let data = record[iCloudVaultField] as? Data {
            return data
        }
        return nil
    }

    private var iCloudDatabase: CKDatabase {
        CKContainer(identifier: iCloudContainerIdentifier).privateCloudDatabase
    }

    private func fetchICloudRecord(id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await iCloudDatabase.record(for: id)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    private func saveICloudRecord(_ record: CKRecord) async throws -> CKRecord {
        try await iCloudDatabase.save(record)
    }
}
