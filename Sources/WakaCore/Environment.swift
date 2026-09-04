import Foundation

/// Identifiers shared by the app and its widget extension.
///
/// These are the only strings both targets must agree on. Duplicating them as
/// literals in each target is how an App Group handoff silently stops working, so
/// they live here once and both sides import them.
public enum WakaIdentifiers {
    /// App Group container shared with the widget extension.
    public static let appGroup = "group.org.wakaboard.shared"
    /// Keychain service name for the signed-in credential.
    public static let keychainService = "org.wakaboard.credentials"
    /// Custom URL scheme used by widget deep links.
    public static let urlScheme = "wakaboard"
}

/// Everything the app needs to do real work, assembled in one place.
///
/// The generated code had all of these pieces and no composition root, which is
/// why the UI rendered fixtures: nothing ever constructed a repository or handed
/// it to a view. This is that missing seam, and it is also the seam tests and
/// previews substitute at.
public struct WakaEnvironment: Sendable {
    public let repository: AnalyticsRepository
    public let client: WakaTimeClient
    public let credentials: any CredentialStore
    public let snapshots: WidgetSnapshotStore

    public init(
        repository: AnalyticsRepository,
        client: WakaTimeClient,
        credentials: any CredentialStore,
        snapshots: WidgetSnapshotStore
    ) {
        self.repository = repository
        self.client = client
        self.credentials = credentials
        self.snapshots = snapshots
    }

    /// The real environment: hardened network client, on-disk cache, Keychain, App Group.
    public static func live() -> WakaEnvironment {
        let client = WakaTimeClient()
        return WakaEnvironment(
            repository: AnalyticsRepository(
                client: client,
                cache: JSONCache(fileURL: Self.cacheURL(), version: AnalyticsRepository.cacheSchemaVersion)
            ),
            client: client,
            credentials: KeychainCredentialStore(service: WakaIdentifiers.keychainService),
            snapshots: WidgetSnapshotStore(suiteName: WakaIdentifiers.appGroup)
        )
    }

    /// Location of the on-disk analytics cache.
    ///
    /// Application Support rather than Caches: the file is the offline fallback the
    /// app shows when the network is unavailable, and the system may evict Caches at
    /// any time. It is excluded from backup because it is reconstructible from the
    /// API and there is no reason for a user's coding history to be copied into
    /// iCloud or an encrypted device backup.
    public static func cacheURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL.temporaryDirectory
        var url = base.appendingPathComponent("WakaBoard", isDirectory: true).appendingPathComponent("activity.json")
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
        return url
    }

    /// Erases every trace of the signed-in account from this device.
    ///
    /// Ordering matters: the credential goes first, so a failure part-way through
    /// cannot leave a usable key behind alongside cleared data. Each step runs even
    /// if an earlier one threw, because a partial sign-out is worse than a noisy one
    /// — the user asked to be signed out and must end up signed out.
    public func signOut() async throws {
        var firstFailure: (any Error)?
        do { try credentials.remove() } catch { firstFailure = error }
        do { try await repository.clearCache() } catch { firstFailure = firstFailure ?? error }
        snapshots.clear()
        if let firstFailure { throw firstFailure }
    }
}
