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

    func restorePurchases() async {
        message = "Restoring purchases…"
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPremium ? "Pro restored." : "No previous Pro purchase found on this Apple ID."
        } catch {
            message = error.localizedDescription
        }
    }

    private func setPremium(_ value: Bool) {
        isPremium = value
        UserDefaults.standard.set(value, forKey: premiumKey)
    }
}

enum BackupError: LocalizedError {
    case noInternet
    case driveAuthExpired
    case drivePermission
    case driveRateLimited
    case driveTemporary
    case driveUnknown
    case iCloudSignedOut
    case iCloudQuota
    case iCloudPermission
    case iCloudConflict
    case iCloudMissingData
    case iCloudUnknown
    case noBackupFound

    var errorDescription: String? {
        switch self {
        case .noInternet:
            "No internet connection. Please reconnect and try again."
        case .driveAuthExpired:
            "Your Google sign-in has expired. Sign out and sign in again to back up to Drive."
        case .drivePermission:
            "Kryptos doesn't have permission to use Google Drive. Sign in again and allow access."
        case .driveRateLimited:
            "Too many Drive requests. Please wait a moment and try again."
        case .driveTemporary:
            "Google Drive is temporarily unavailable. Please try again later."
        case .driveUnknown:
            "Couldn't reach Google Drive. Please try again."
        case .iCloudSignedOut:
            "Sign in to iCloud in your device Settings to back up."
        case .iCloudQuota:
            "Your iCloud storage is full. Free up space in your device Settings to continue."
        case .iCloudPermission:
            "Kryptos doesn't have permission to use iCloud. Check your device Settings."
        case .iCloudConflict:
            "Your iCloud backup was updated from another device. Please try again."
        case .iCloudMissingData:
            "The iCloud backup is missing some data. Please back up again from this device."
        case .iCloudUnknown:
            "Couldn't reach iCloud. Please try again."
        case .noBackupFound:
            "No backup found yet."
        }
    }

    static func fromDrive(status: Int) -> BackupError {
        switch status {
        case 401: .driveAuthExpired
        case 403: .drivePermission
        case 429: .driveRateLimited
        case 500...599: .driveTemporary
        default: .driveUnknown
        }
    }

    static func from(_ error: Error) -> BackupError {
        if let backup = error as? BackupError { return backup }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .noInternet
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .driveTemporary
            default:
                return .driveUnknown
            }
        }
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return .noInternet
            case .notAuthenticated, .accountTemporarilyUnavailable:
                return .iCloudSignedOut
            case .quotaExceeded:
                return .iCloudQuota
            case .permissionFailure:
                return .iCloudPermission
            case .serverRecordChanged, .changeTokenExpired, .batchRequestFailed:
                return .iCloudConflict
            case .unknownItem, .zoneNotFound, .userDeletedZone, .assetFileNotFound, .assetFileModified:
                return .iCloudMissingData
            default:
                return .iCloudUnknown
            }
        }
        return .driveUnknown
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
                let folderId = try await getOrCreateFolder(session: session)
                try await uploadOrReplace(session: session, name: backupName, data: payload.vault, mime: "application/json", parent: folderId, appData: false)
                try await uploadOrReplace(session: session, name: keyName, data: payload.key, mime: "application/octet-stream", parent: folderId, appData: false)
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastMyDriveBackupKey)
                feedback = "Backup to My Drive complete."
            } else {
                workingMessage = "Uploading to your private Drive folder..."
                try await uploadOrReplace(session: session, name: backupName, data: payload.vault, mime: "application/json", parent: "appDataFolder", appData: true)
                try await uploadOrReplace(session: session, name: keyName, data: payload.key, mime: "application/octet-stream", parent: "appDataFolder", appData: true)
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
        guard let backupFile = try await findFile(session: session, name: backupName, appData: true) else { return nil }
        let data = try await download(session: session, fileId: backupFile.id)
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var keyData: Data?
        if let keyFile = try await findFile(session: session, name: keyName, appData: true) {
            keyData = try await download(session: session, fileId: keyFile.id)
        }
        return DriveBackupCandidate(source: .appData, payload: payload, keyData: keyData)
    }

    private func findMyDriveCandidate(session: DriveSession) async throws -> DriveBackupCandidate? {
        guard let folder = try await findFile(session: session, name: myDriveFolderName, appData: false) else { return nil }
        guard let backupFile = try await findFile(session: session, name: backupName, parent: folder.id, appData: false) else { return nil }
        let data = try await download(session: session, fileId: backupFile.id)
        let payload = try decoder.decode(BackupPayload.self, from: data)
        var keyData: Data?
        if let keyFile = try await findFile(session: session, name: keyName, parent: folder.id, appData: false) {
            keyData = try await download(session: session, fileId: keyFile.id)
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

    private struct DriveFile: Decodable {
        var id: String
        var modifiedTime: String?
    }

    private struct DriveList: Decodable {
        var files: [DriveFile]
    }

    final class DriveSession {
        private(set) var token: String
        private let refresh: TokenRefresher?

        init(token: String, refresh: TokenRefresher?) {
            self.token = token
            self.refresh = refresh
        }

        func renewIfPossible() async -> Bool {
            guard let refresh, let newToken = await refresh() else { return false }
            token = newToken
            return true
        }
    }

    private func findFile(session: DriveSession, name: String, parent: String? = nil, appData: Bool) async throws -> DriveFile? {
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
        let list: DriveList = try await request(session: session, url: components.url!)
        return list.files.first
    }

    private func uploadOrReplace(session: DriveSession, name: String, data: Data, mime: String, parent: String, appData: Bool) async throws {
        if let existing = try await findFile(session: session, name: name, parent: appData ? nil : parent, appData: appData) {
            var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files/\(existing.id)")!
            components.queryItems = [URLQueryItem(name: "uploadType", value: "media")]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "PATCH"
            request.setValue(mime, forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let _: Data = try await self.request(session: session, request: request)
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
        let _: Data = try await self.request(session: session, request: request)
    }

    private func getOrCreateFolder(session: DriveSession) async throws -> String {
        if let folder = try await findFile(session: session, name: myDriveFolderName, appData: false) {
            return folder.id
        }
        let metadata = ["name": myDriveFolderName, "mimeType": "application/vnd.google-apps.folder"]
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let created: DriveFile = try await self.request(session: session, request: request)
        return created.id
    }

    private func download(session: DriveSession, fileId: String) async throws -> Data {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        return try await request(session: session, url: url)
    }

    private func request<T: Decodable>(session: DriveSession, url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await self.request(session: session, request: request)
    }

    private func request<T: Decodable>(session: DriveSession, request: URLRequest) async throws -> T {
        let data: Data = try await self.request(session: session, request: request)
        return try decoder.decode(T.self, from: data)
    }

    private func request(session: DriveSession, request original: URLRequest) async throws -> Data {
        var attempt = original
        attempt.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: attempt)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 401, await session.renewIfPossible() {
            var retry = original
            retry.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
            let retryStatus = (retryResponse as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(retryStatus) else {
                throw BackupError.fromDrive(status: retryStatus)
            }
            return retryData
        }
        guard (200..<300).contains(status) else {
            throw BackupError.fromDrive(status: status)
        }
        return data
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
