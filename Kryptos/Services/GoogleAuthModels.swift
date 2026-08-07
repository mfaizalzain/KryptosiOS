import Foundation

enum AuthProvider: String, Codable {
    case google
    case apple

    var label: String {
        switch self {
        case .google: "Google"
        case .apple: "Apple"
        }
    }
}

struct GoogleAccount: Codable, Equatable {
    var id: String
    var email: String?
    var displayName: String?
    var photoURL: URL?
    var accessToken: String?
    var refreshToken: String?
    var grantedScopes: Set<String>
    var provider: AuthProvider

    init(
        id: String,
        email: String?,
        displayName: String?,
        photoURL: URL?,
        accessToken: String?,
        refreshToken: String?,
        grantedScopes: Set<String>,
        provider: AuthProvider
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.grantedScopes = grantedScopes
        self.provider = provider
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName
        case photoURL
        case accessToken
        case refreshToken
        case grantedScopes
        case provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        grantedScopes = try container.decodeIfPresent(Set<String>.self, forKey: .grantedScopes) ?? []
        provider = try container.decodeIfPresent(AuthProvider.self, forKey: .provider) ?? .google
    }
}

struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?
    var scope: String?
    var tokenType: String?
    var idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
        case idToken = "id_token"
    }
}

struct UserInfoResponse: Decodable {
    var sub: String
    var email: String?
    var name: String?
    var picture: URL?
}
