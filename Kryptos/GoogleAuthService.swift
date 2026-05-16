import AuthenticationServices
import Combine
import Foundation
import UIKit

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

private struct TokenResponse: Decodable {
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

private struct UserInfoResponse: Decodable {
    var sub: String
    var email: String?
    var name: String?
    var picture: URL?
}

@MainActor
final class GoogleAuthService: NSObject, ObservableObject {
    static let clientID = "706867595241-9d97s277u0sjfi742dqk66i5u0867ulf.apps.googleusercontent.com"
    static let redirectScheme = "com.googleusercontent.apps.706867595241-9d97s277u0sjfi742dqk66i5u0867ulf"
    static let redirectURI = "\(redirectScheme):/oauth2redirect"
    static let appDataScope = "https://www.googleapis.com/auth/drive.appdata"
    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    @Published private(set) var account: GoogleAccount?
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let accountKey = "google.account.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var session: ASWebAuthenticationSession?
    private var appleSignInContinuation: CheckedContinuation<GoogleAccount, Error>?

    override init() {
        super.init()
        if let data = KeychainStore.shared.data(for: accountKey) {
            account = try? decoder.decode(GoogleAccount.self, from: data)
        }
    }

    func signIn(scopes extraScopes: [String] = []) async -> GoogleAccount? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let scopes = ["openid", "email", "profile"] + extraScopes
            let code = try await requestAuthorizationCode(scopes: scopes)
            let token = try await exchangeCode(code)
            let info = try await fetchUserInfo(accessToken: token.accessToken)
            let mergedScopes = Set((token.scope?.split(separator: " ").map(String.init) ?? scopes))
            let signedIn = GoogleAccount(
                id: info.sub,
                email: info.email,
                displayName: info.name,
                photoURL: info.picture,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? account?.refreshToken,
                grantedScopes: mergedScopes,
                provider: .google
            )
            try persist(signedIn)
            account = signedIn
            return signedIn
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func accessToken(requiring scope: String) async -> String? {
        if account?.provider == .google, account?.accessToken != nil, account?.grantedScopes.contains(scope) == true {
            return account?.accessToken
        }
        return await signIn(scopes: [scope])?.accessToken
    }

    @discardableResult
    func refreshAccessToken() async -> String? {
        guard let current = account, current.provider == .google, let refreshToken = current.refreshToken else {
            return nil
        }
        do {
            let token = try await exchangeRefreshToken(refreshToken)
            let mergedScopes: Set<String>
            if let scope = token.scope {
                mergedScopes = Set(scope.split(separator: " ").map(String.init)).union(current.grantedScopes)
            } else {
                mergedScopes = current.grantedScopes
            }
            let refreshed = GoogleAccount(
                id: current.id,
                email: current.email,
                displayName: current.displayName,
                photoURL: current.photoURL,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? current.refreshToken,
                grantedScopes: mergedScopes,
                provider: .google
            )
            try persist(refreshed)
            account = refreshed
            return token.accessToken
        } catch {
            return nil
        }
    }

    func signInWithApple() async -> GoogleAccount? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let account = try await requestAppleAuthorization()
            try persist(account)
            self.account = account
            return account
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func signOut() {
        account = nil
        KeychainStore.shared.remove(accountKey)
    }

    private func persist(_ account: GoogleAccount) throws {
        try KeychainStore.shared.set(encoder.encode(account), for: accountKey)
    }

    private func requestAppleAuthorization() async throws -> GoogleAccount {
        try await withCheckedThrowingContinuation { continuation in
            appleSignInContinuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func requestAuthorizationCode(scopes: [String]) async throws -> String {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent")
        ]
        let url = components.url!

        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.redirectScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard
                    let callbackURL,
                    let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
                else {
                    continuation.resume(throwing: URLError(.badURL))
                    return
                }
                if let oauthError = items.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: NSError(domain: "GoogleAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: oauthError]))
                    return
                }
                guard let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: URLError(.userAuthenticationRequired))
                    return
                }
                continuation.resume(returning: code)
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            session = authSession
            authSession.start()
        }
    }

    private func exchangeCode(_ code: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func exchangeRefreshToken(_ refreshToken: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func fetchUserInfo(accessToken: String) async throws -> UserInfoResponse {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(UserInfoResponse.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Google request failed."
            throw NSError(domain: "GoogleAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

extension GoogleAuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

extension GoogleAuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                appleSignInContinuation?.resume(throwing: URLError(.userAuthenticationRequired))
                appleSignInContinuation = nil
            }
            return
        }

        let user = credential.user
        let email = credential.email
        let fullName = credential.fullName

        Task { @MainActor in
            let components = PersonNameComponentsFormatter()
            let name = fullName.map { components.string(from: $0) }?.nilIfBlank
            let account = GoogleAccount(
                id: user,
                email: email,
                displayName: name ?? email,
                photoURL: nil,
                accessToken: nil,
                refreshToken: nil,
                grantedScopes: [],
                provider: .apple
            )
            appleSignInContinuation?.resume(returning: account)
            appleSignInContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            appleSignInContinuation?.resume(throwing: error)
            appleSignInContinuation = nil
        }
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
