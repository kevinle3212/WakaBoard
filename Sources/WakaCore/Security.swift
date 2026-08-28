import Foundation
import OSLog
import Security

/// Coarse, privacy-safe diagnostics.
///
/// Every value logged here is a fixed category string chosen at the call site. No
/// credential, response body, project name, username, URL, or query string is ever
/// passed to these functions — which is why the interpolations can be marked
/// `.public` without leaking anything. Analytics content is the user's private
/// data and does not belong in a system log that other tooling can read.
public enum WakaLog {
    private static let networking = Logger(subsystem: "org.wakaboard", category: "networking")
    private static let authentication = Logger(subsystem: "org.wakaboard", category: "authentication")
    private static let storage = Logger(subsystem: "org.wakaboard", category: "storage")

    /// Logs the *category* of a network failure, never the request or its contents.
    public static func networkFailure(_ error: WakaTimeError) {
        networking.error("WakaTime request failed: \(error.logCategory, privacy: .public)")
    }

    public static func authenticationFailure() {
        authentication.error("Authentication callback validation failed")
    }

    public static func credentialStoreFailure(_ error: KeychainError) {
        authentication.error("Keychain operation failed: \(error.logCategory, privacy: .public)")
    }

    public static func retentionPruned(dayCount: Int) {
        storage.info("Pruned \(dayCount, privacy: .public) cached days past the retention window")
    }
}

private extension WakaTimeError {
    /// A stable, content-free label safe to write to the system log.
    var logCategory: String {
        switch self {
        case .invalidEndpoint: "invalidEndpoint"
        case .unauthenticated: "unauthenticated"
        case .forbidden: "forbidden"
        case .unavailable: "unavailable"
        case .rateLimited: "rateLimited"
        case .serviceUnavailable: "serviceUnavailable"
        case .transport: "transport"
        case .decoding: "decoding"
        case .responseTooLarge: "responseTooLarge"
        }
    }
}

public protocol CredentialStore: Sendable {
    func load() throws -> Credential?
    func save(_ credential: Credential) throws
    func remove() throws
}

/// Distinguishable Keychain failures.
///
/// The generated code collapsed every `OSStatus` into a single `.unavailable`,
/// which made "the user has never signed in", "the device is locked", and "the
/// keychain is corrupt" indistinguishable — so the UI could not tell the user
/// which one had happened or what to do about it.
public enum KeychainError: Error, Equatable, Sendable {
    /// The stored item exists but is not a credential this version can read.
    case malformedItem
    /// The keychain is locked or requires user interaction that is unavailable.
    case interactionNotAllowed
    /// Any other `OSStatus`, retained for diagnosis without being interpreted.
    case unhandled(status: Int32)

    var logCategory: String {
        switch self {
        case .malformedItem: "malformedItem"
        case .interactionNotAllowed: "interactionNotAllowed"
        case .unhandled(let status): "unhandled(\(status))"
        }
    }

    static func from(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecInteractionNotAllowed, errSecAuthFailed: .interactionNotAllowed
        default: .unhandled(status: status)
        }
    }
}

/// Keychain persistence for the signed-in credential.
///
/// Three properties matter and all three were missing or wrong in the generated
/// version:
///
/// - `kSecUseDataProtectionKeychain` is set on every query. Without it, macOS
///   silently uses the legacy file-based keychain, which has different unlock
///   semantics and no data-protection class — so the `kSecAttrAccessible` value
///   below was simply ignored there.
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is applied on **update** as
///   well as create. Setting it only on the add path means an item created by an
///   older build keeps its weaker accessibility forever.
/// - `ThisDeviceOnly` keeps the credential out of iCloud Keychain and out of
///   encrypted device backups, so restoring a backup onto another device does not
///   carry the user's API key with it.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account: String

    public init(service: String, account: String = "wakaboard") {
        self.service = service
        self.account = account
    }

    public func load() throws -> Credential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            let error = KeychainError.from(status)
            WakaLog.credentialStoreFailure(error)
            throw error
        }
        guard let data = result as? Data, let encoded = String(data: data, encoding: .utf8),
              let credential = Self.decode(encoded) else {
            WakaLog.credentialStoreFailure(.malformedItem)
            throw KeychainError.malformedItem
        }
        return credential
    }

    public func save(_ credential: Credential) throws {
        guard credential.isWellFormed else { throw KeychainError.malformedItem }
        let data = Data(Self.encode(credential).utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                let error = KeychainError.from(addStatus)
                WakaLog.credentialStoreFailure(error)
                throw error
            }
            return
        }
        guard status == errSecSuccess else {
            let error = KeychainError.from(status)
            WakaLog.credentialStoreFailure(error)
            throw error
        }
    }

    public func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let error = KeychainError.from(status)
            WakaLog.credentialStoreFailure(error)
            throw error
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    // MARK: - Tagged encoding

    // The credential kind is stored alongside the secret so a key is never later
    // replayed as a bearer token, or the reverse. An untagged blob is what made the
    // original `Authorization: Basic <anything>` bug possible.

    private static let apiKeyPrefix = "apikey:"
    private static let bearerPrefix = "bearer:"

    static func encode(_ credential: Credential) -> String {
        switch credential {
        case .personalAPIKey(let key): apiKeyPrefix + key
        case .bearerToken(let token): bearerPrefix + token
        }
    }

    static func decode(_ raw: String) -> Credential? {
        if raw.hasPrefix(apiKeyPrefix) {
            let value = String(raw.dropFirst(apiKeyPrefix.count))
            let credential = Credential.personalAPIKey(value)
            return credential.isWellFormed ? credential : nil
        }
        if raw.hasPrefix(bearerPrefix) {
            let value = String(raw.dropFirst(bearerPrefix.count))
            let credential = Credential.bearerToken(value)
            return credential.isWellFormed ? credential : nil
        }
        return nil
    }
}

/// In-memory credential store for previews and tests. Never used in a shipping build.
///
/// `CredentialStore` is synchronous because the Keychain API is synchronous, so the
/// double is a plain lock-guarded class rather than an actor.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Credential?
    private let failure: KeychainError?

    /// - Parameter failure: When set, every operation throws it, so callers can be
    ///   tested against a locked or corrupt keychain rather than only the happy path.
    public init(seeded: Credential? = nil, failure: KeychainError? = nil) {
        self.stored = seeded
        self.failure = failure
    }

    public func load() throws -> Credential? {
        if let failure { throw failure }
        return lock.withLock { stored }
    }

    public func save(_ credential: Credential) throws {
        if let failure { throw failure }
        guard credential.isWellFormed else { throw KeychainError.malformedItem }
        lock.withLock { stored = credential }
    }

    public func remove() throws {
        if let failure { throw failure }
        lock.withLock { stored = nil }
    }
}

/// Validates a one-time OAuth callback before a relay exchange happens.
///
/// Reserved for the operator-relay flow documented in `SECURITY.md`. This build
/// ships the personal API key path only, so nothing calls this type at runtime; it
/// is retained, tested, and validated so the future path starts from a correct
/// implementation rather than a rewritten one.
public struct OAuthSession: Sendable {
    public let state: String
    public let callbackScheme: String
    public let callbackHost: String
    public let callbackPath: String

    public init(state: String = UUID().uuidString, callbackScheme: String, callbackHost: String, callbackPath: String) {
        self.state = state
        self.callbackScheme = callbackScheme
        self.callbackHost = callbackHost
        self.callbackPath = callbackPath
    }

    public func authorizationURL(baseURL: URL, clientID: String, redirectURI: String) throws -> URL {
        guard baseURL.scheme == "https", !clientID.isEmpty,
              let redirect = URL(string: redirectURI), redirect.scheme == callbackScheme else {
            throw OAuthError.invalidCallback
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else { throw OAuthError.invalidCallback }
        return url
    }

    public func validate(callback: URL) throws -> String {
        guard callback.scheme == callbackScheme, callback.host == callbackHost, callback.path == callbackPath,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let returnedState = exactValue(named: "state", in: components),
              constantTimeEquals(returnedState, state),
              let code = exactValue(named: "code", in: components), !code.isEmpty, code.count <= 512 else {
            WakaLog.authenticationFailure()
            throw OAuthError.invalidCallback
        }
        return code
    }

    /// Returns the value of `name` only when it appears exactly once.
    ///
    /// A duplicated parameter is a classic smuggling technique: the client validates
    /// one occurrence and a downstream parser reads the other.
    private func exactValue(named name: String, in components: URLComponents) -> String? {
        let values = (components.queryItems ?? []).filter { $0.name == name }.compactMap(\.value)
        guard values.count == 1 else { return nil }
        return values[0]
    }

    /// Compares two states without returning early on the first differing byte, so
    /// the comparison does not leak the state prefix through its timing.
    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

public enum OAuthError: Error, Equatable, Sendable { case invalidCallback }

/// Holds one pending session and consumes it after a successful callback, rejecting
/// replay attempts.
public actor OAuthCallbackValidator {
    private var pending: OAuthSession?

    public init() {}

    public func begin(_ session: OAuthSession) { pending = session }

    public func consume(callback: URL) throws -> String {
        guard let session = pending else { throw OAuthError.invalidCallback }
        // Clear before validating: a callback that fails validation must still burn
        // the pending session, or an attacker can probe state values indefinitely.
        pending = nil
        return try session.validate(callback: callback)
    }
}
