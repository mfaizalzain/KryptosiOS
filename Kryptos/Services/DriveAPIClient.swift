import Foundation

typealias TokenRefresher = @Sendable () async -> String?

struct DriveFile: Decodable {
    var id: String
    var modifiedTime: String?
}

struct DriveList: Decodable {
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

/// Low-level Google Drive REST client (files list/upload/folder/download).
final class DriveAPIClient {
    let myDriveFolderName = "KryptosBackups"
    private let decoder = JSONDecoder()

    func findFile(session: DriveSession, name: String, parent: String? = nil, appData: Bool) async throws -> DriveFile? {
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

    func uploadOrReplace(session: DriveSession, name: String, data: Data, mime: String, parent: String, appData: Bool) async throws {
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

    func getOrCreateFolder(session: DriveSession) async throws -> String {
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

    func download(session: DriveSession, fileId: String) async throws -> Data {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        return try await request(session: session, url: url)
    }

    func request<T: Decodable>(session: DriveSession, url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await self.request(session: session, request: request)
    }

    func request<T: Decodable>(session: DriveSession, request: URLRequest) async throws -> T {
        let data: Data = try await self.request(session: session, request: request)
        return try decoder.decode(T.self, from: data)
    }

    func request(session: DriveSession, request original: URLRequest) async throws -> Data {
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
}
