import Foundation
import OSLog
import Security

/// Coarse, privacy-safe diagnostics. Callers must pass only error categories, never request data.
public enum WakaLog {
    private static let networking = Logger(subsystem: "org.wakaboard", category: "networking")
    private static let authentication = Logger(subsystem: "org.wakaboard", category: "authentication")

    public static func networkFailure(_ error: WakaTimeError) {
        networking.error("WakaTime request failed with category: \(String(describing: error), privacy: .public)")
    }

    public static func authenticationFailure() {
        authentication.error("Authentication callback validation failed")
    }
}

/// Locally stored credentials; this type is intentionally not Codable.
public struct Credentials: Equatable, Sendable {
    public let authorization: String
    public init(authorization: String) { self.authorization = authorization }
}

public protocol CredentialStore: Sendable {
    func load() throws -> Credentials?
    func save(_ credentials: Credentials) throws
    func remove() throws
}

/// Keychain persistence for credentials, unavailable to widgets and JSON caches.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account: String

    public init(service: String, account: String = "wakaboard") { self.service = service; self.account = account }
    public func load() throws -> Credentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw KeychainError.unavailable }
        return Credentials(authorization: value)
    }
    public func save(_ credentials: Credentials) throws {
        let data = Data(credentials.authorization.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw KeychainError.unavailable }; return
        }
        guard status == errSecSuccess else { throw KeychainError.unavailable }
    }
    public func remove() throws { let status = SecItemDelete(baseQuery as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unavailable } }
    private var baseQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
}

public enum KeychainError: Error, Equatable, Sendable { case unavailable }

/// Validates a one-time OAuth callback before a relay exchange happens.
public struct OAuthSession: Sendable {
    public let state: String
    public let callbackScheme: String
    public let callbackHost: String
    public let callbackPath: String

    public init(state: String = UUID().uuidString, callbackScheme: String, callbackHost: String, callbackPath: String) { self.state = state; self.callbackScheme = callbackScheme; self.callbackHost = callbackHost; self.callbackPath = callbackPath }
    public func authorizationURL(baseURL: URL, clientID: String, redirectURI: String) throws -> URL {
        guard baseURL.scheme == "https", !clientID.isEmpty else { throw OAuthError.invalidCallback }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "redirect_uri", value: redirectURI), URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "state", value: state)]
        guard let url = components?.url else { throw OAuthError.invalidCallback }; return url
    }
    public func validate(callback: URL) throws -> String {
        guard callback.scheme == callbackScheme, callback.host == callbackHost, callback.path == callbackPath,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let returnedState = exactValue(named: "state", in: components), returnedState == state,
              let code = exactValue(named: "code", in: components), !code.isEmpty else {
            WakaLog.authenticationFailure()
            throw OAuthError.invalidCallback
        }
        return code
    }

    private func exactValue(named name: String, in components: URLComponents) -> String? {
        let values = (components.queryItems ?? []).filter { $0.name == name }.compactMap(\.value)
        guard values.count == 1 else { return nil }
        return values[0]
    }
}

public enum OAuthError: Error, Equatable, Sendable { case invalidCallback }

/// Holds one pending session and consumes it after a successful callback, rejecting replay attempts.
public actor OAuthCallbackValidator {
    private var pending: OAuthSession?

    public init() {}

    public func begin(_ session: OAuthSession) { pending = session }

    public func consume(callback: URL) throws -> String {
        guard let session = pending else { throw OAuthError.invalidCallback }
        let code = try session.validate(callback: callback)
        pending = nil
        return code
    }
}

/// Makes the advanced local personal-key pathway explicit in API surface.
public enum AuthenticationMethod: Sendable { case personalAPIKey(String); case oauth(Credentials) }
public extension AuthenticationMethod { var credentials: Credentials { switch self { case .personalAPIKey(let key): Credentials(authorization: key); case .oauth(let credentials): credentials } } }
