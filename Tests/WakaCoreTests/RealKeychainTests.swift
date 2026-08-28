import Foundation
import Security
import Testing
@testable import WakaCore

/// Exercises the **real** system Keychain, not a double.
///
/// Every other Keychain test asserts query construction or error mapping. None of
/// them could catch the defect that actually shipped: requiring
/// `kSecUseDataProtectionKeychain` made `SecItemAdd` return `errSecMissingEntitlement`
/// (-34018) in any build without a provisioning profile, so sign-in verified the key
/// against WakaTime, silently failed to store it, and bounced the user back to the
/// sign-in screen.
///
/// These run against the login keychain of whoever runs the suite, under a service
/// name reserved for tests, and clean up after themselves.
@Suite("RealKeychain", .serialized)
struct RealKeychainTests {
    private func store() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "org.wakaboard.tests.\(UUID().uuidString)")
    }

    @Test("a credential round-trips through the real Keychain in this build")
    func roundTrip() throws {
        let subject = store()
        defer { try? subject.remove() }

        #expect(try subject.load() == nil)
        try subject.save(.personalAPIKey("real-keychain-round-trip"))
        #expect(try subject.load() == .personalAPIKey("real-keychain-round-trip"))
    }

    @Test("saving twice updates rather than duplicating or failing")
    func updateInPlace() throws {
        let subject = store()
        defer { try? subject.remove() }

        try subject.save(.personalAPIKey("first"))
        try subject.save(.personalAPIKey("second"))
        #expect(try subject.load() == .personalAPIKey("second"))
    }

    @Test("removal erases the credential from every keychain variant")
    func removalIsThorough() throws {
        let subject = store()
        try subject.save(.personalAPIKey("to-be-removed"))
        #expect(try subject.load() != nil)

        try subject.remove()
        // Signing out must not leave a usable key behind in whichever keychain this
        // build happened not to be using.
        #expect(try subject.load() == nil)
        // Removing an absent item is not an error.
        #expect(throws: Never.self) { try subject.remove() }
    }

    @Test("the credential kind survives a real round trip")
    func kindSurvives() throws {
        let subject = store()
        defer { try? subject.remove() }

        try subject.save(.bearerToken("bearer-round-trip"))
        // A key must never come back as a token or the reverse; that conflation was
        // the original Authorization-header defect.
        #expect(try subject.load() == .bearerToken("bearer-round-trip"))
    }

    @Test("the data-protection keychain is unavailable without a provisioning profile")
    func documentsTheFallbackReason() {
        // This is the measurement the fallback exists for, asserted rather than
        // described. If a future build *is* provisioned, this returns success and the
        // test records that instead — either way the fallback stays honest.
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.wakaboard.tests.entitlement-probe",
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data("probe".utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        defer { SecItemDelete(query as CFDictionary) }

        // Either the entitlement is missing (unprovisioned, the common case for a
        // local build) or it succeeds (properly provisioned). Anything else is a
        // genuine surprise worth failing on.
        #expect(
            status == errSecMissingEntitlement || status == errSecSuccess,
            "unexpected OSStatus \(status) probing the data-protection keychain"
        )
    }
}
