import CloudKit
import Foundation

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
    case invalidBackup
    case backupPassphraseRequired
    case backupPassphraseIncorrect

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
        case .invalidBackup:
            "This backup could not be validated. Back up again from the device that still has your entries."
        case .backupPassphraseRequired:
            "This backup is protected by a passphrase. Enter your backup passphrase to restore."
        case .backupPassphraseIncorrect:
            "The backup passphrase is incorrect."
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
