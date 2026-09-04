import Foundation

/// How long WakaBoard keeps data on the device.
///
/// This is the machine-readable half of `RETENTION.md`. A published retention
/// policy that nothing enforces is not a policy, so the numbers live here and the
/// document quotes them. Changing a value here changes the product's actual
/// behavior, and the document must be updated in the same change.
public enum RetentionPolicy: Sendable {
    /// Cached daily activity older than this is deleted on the next read or write.
    ///
    /// Ninety days covers every range the UI offers with room for comparison
    /// against the preceding period, and nothing beyond that has a use that would
    /// justify keeping a record of when the user was working.
    public static let cachedActivity: TimeInterval = 90 * 24 * 60 * 60

    /// A widget snapshot older than this is treated as absent rather than shown.
    ///
    /// WidgetKit refresh is best-effort, so a stale snapshot is normal; showing a
    /// two-week-old figure as if it were current is not.
    public static let widgetSnapshot: TimeInterval = 7 * 24 * 60 * 60

    /// Freshness window before the app will refetch in the foreground.
    public static let cacheFreshness: TimeInterval = 300
}

/// A versioned cache envelope that can be invalidated without guessing at old
/// schema shapes.
public struct CacheEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    public let version: Int
    public let writtenAt: Date
    public let value: Value

    public init(version: Int = 1, writtenAt: Date, value: Value) {
        self.version = version
        self.writtenAt = writtenAt
        self.value = value
    }
}

public enum CacheError: Error, Equatable, Sendable { case corrupt; case unsupportedVersion; case unavailable }

/// App Group bridge for the deliberately credential-free widget summary.
///
/// Credentials stay in the Keychain and never enter this `UserDefaults` suite. The
/// type system enforces it: ``WidgetSnapshot`` has no field that can hold one, and
/// a test asserts the encoded form contains no credential-shaped key.
public struct WidgetSnapshotStore: Sendable {
    private let suiteName: String
    private let key: String

    public init(suiteName: String, key: String = "widgetSnapshot.v1") {
        self.suiteName = suiteName
        self.key = key
    }

    /// Returns the snapshot only when it is inside the retention window.
    ///
    /// - Parameter now: Clock reading, injected for tests.
    public func load(now: Date = .now) -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName), let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        guard now.timeIntervalSince(snapshot.generatedAt) <= RetentionPolicy.widgetSnapshot else {
            clear()
            return nil
        }
        return snapshot
    }

    public func store(_ snapshot: WidgetSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw CacheError.unavailable }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
    }

    public func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }
}

/// Actor-isolated JSON cache. Values are atomically replaced and never contain
/// credentials.
public actor JSONCache<Value: Codable & Sendable> {
    private let fileURL: URL
    private let version: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, version: Int = 1, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.fileURL = fileURL
        self.version = version
        self.encoder = encoder
        self.decoder = decoder
    }

    /// How the cache file is written.
    ///
    /// `.atomic` everywhere, so a crash mid-write leaves the previous cache intact
    /// rather than a truncated file.
    ///
    /// Data protection is applied only on the platforms that implement it for an
    /// ordinary app. On macOS, writing `.completeFileProtectionUnlessOpen` produces a
    /// file the same process cannot read back: `Data(contentsOf:)` fails with
    /// `NSCocoaErrorDomain 257` wrapping `EPERM`, because the protection class needs
    /// an entitlement this build does not carry — the same reason
    /// `RealKeychainTests` records the data-protection keychain as unavailable here.
    /// Silently, that made the offline fallback unreachable on macOS: every write
    /// succeeded and every read after it looked like an empty cache. The owner-only
    /// file mode set immediately below is what protects the file there.
    static var writingOptions: Data.WritingOptions {
        #if os(macOS)
        [.atomic]
        #else
        [.atomic, .completeFileProtectionUnlessOpen]
        #endif
    }

    public func load(now: Date = .now, maximumAge: TimeInterval) throws -> (value: Value, isFresh: Bool)? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch { throw CacheError.corrupt }
        let envelope: CacheEnvelope<Value>
        do { envelope = try decoder.decode(CacheEnvelope<Value>.self, from: data) } catch { throw CacheError.corrupt }
        guard envelope.version == version else { throw CacheError.unsupportedVersion }
        return (envelope.value, now.timeIntervalSince(envelope.writtenAt) <= maximumAge)
    }

    public func store(_ value: Value, writtenAt: Date = .now) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(CacheEnvelope(version: version, writtenAt: writtenAt, value: value))
        try data.write(to: fileURL, options: Self.writingOptions)
        try restrictPermissions()
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Narrows the cache file to owner-only access.
    ///
    /// macOS has no data protection class, so `.completeFileProtectionUnlessOpen` is
    /// a no-op there and the file lands with the process umask. On a shared or
    /// multi-user Mac that can leave another account able to read the user's coding
    /// history, so the mode is set explicitly.
    private func restrictPermissions() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

/// Equivalent fetches share a single task, avoiding duplicate safe GET requests.
public actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private var tasks: [Key: Task<Value, any Error>] = [:]

    public init() {}

    public func value(for key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let existing = tasks[key] { return try await existing.value }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}

/// The cached days for one period, tagged with the period they belong to.
///
/// The tag is the whole point. Before it existed the cache was a bare
/// `[ActivityDay]` in a single file with no record of which range produced it, so
/// asking for thirty days within five minutes of asking for seven returned the
/// seven that were already cached and presented them as the thirty-day period —
/// and changing the period is the most common thing a user does in this app.
public struct CachedActivity: Codable, Sendable, Equatable {
    /// The range these days answer, in the same `start-end` form the repository keys on.
    public let rangeKey: String
    public let days: [ActivityDay]

    public init(rangeKey: String, days: [ActivityDay]) {
        self.rangeKey = rangeKey
        self.days = days
    }
}

/// Fetches analytics cached-first, preserves stale data for offline and error
/// states, and enforces the published retention window.
public actor AnalyticsRepository {
    /// On-disk schema version for the analytics cache.
    ///
    /// Bumped to 2 when the cached value gained its range tag and `ActivityDay`
    /// gained editors, operating systems, and categories. A version mismatch makes
    /// `JSONCache` throw, which the repository already treats as an empty cache, so
    /// an older file is discarded rather than misread.
    public static let cacheSchemaVersion = 2

    private let client: WakaTimeClient
    // ponytail: one range cached at a time. Switching period discards the previous
    // period's offline copy. A dictionary keyed by range would keep both, at the
    // cost of per-entry write timestamps; add it if offline period-switching ever
    // matters more than the smaller file.
    private let cache: JSONCache<CachedActivity>
    private let coalescer = RequestCoalescer<String, [ActivityDay]>()
    private let now: @Sendable () -> Date

    public init(client: WakaTimeClient, cache: JSONCache<CachedActivity>, now: @escaping @Sendable () -> Date = { .now }) {
        self.client = client
        self.cache = cache
        self.now = now
    }

    /// Returns activity for `range`, preferring a fresh cache and falling back to a
    /// stale one when the network fails.
    ///
    /// - Returns: The days, and whether they came from a stale cache — the caller
    ///   needs that flag to tell the user what they are looking at rather than
    ///   presenting old numbers as current.
    public func days(
        range: ActivityRange,
        credential: Credential,
        timeZone: TimeZone,
        maximumAge: TimeInterval = RetentionPolicy.cacheFreshness
    ) async throws -> (days: [ActivityDay], isStale: Bool) {
        let key = range.cacheKey
        // A corrupt or version-mismatched cache is not an error the user should see;
        // it just means there is nothing usable to show while the network is tried.
        // A cache holding a *different* period is treated the same way: it is not
        // this question's answer, and offering it as one is how a period switch
        // silently returned the previous period's numbers.
        let cached = pruned(try? await cache.load(now: now(), maximumAge: maximumAge), matching: key)
        if let cached, cached.isFresh { return (cached.value, false) }

        do {
            let fetched = try await coalescer.value(for: key) { [client] in
                try await client.summaries(range: range, credential: credential, timeZone: timeZone)
            }
            let retained = retain(fetched)
            try await cache.store(CachedActivity(rangeKey: key, days: retained), writtenAt: now())
            return (retained, false)
        } catch {
            if let error = error as? WakaTimeError { WakaLog.networkFailure(error) }
            if let cached { return (cached.value, true) }
            throw error
        }
    }

    /// Erases every locally cached analytic. Called on sign-out and from Settings.
    public func clearCache() async throws {
        breakdowns.removeAll()
        try await cache.clear()
    }

    /// Completed drill-downs, keyed by bucket and period.
    ///
    /// Memory only, and deliberately so. A drill-down holds file names, which are the
    /// most identifying thing WakaTime returns — a path can name an employer, a
    /// client, or an unannounced product. `RETENTION.md` allows ninety days for
    /// cached analytics; this keeps them for the lifetime of the process, which is
    /// well inside that and costs the user nothing, because the whole result is
    /// re-derivable with one tap.
    private var breakdowns: [String: BreakdownResult] = [:]

    /// The file types inside one unresolved language bucket, over `range`.
    ///
    /// One request per day, bounded by ``FileTypeBreakdown/maximumDays``, every one
    /// of them through the shared rate limiter. A day that fails is skipped rather
    /// than failing the whole drill-down: a partial answer labelled as partial is
    /// more use than an error, and the result records how many days it covers so the
    /// UI can say which it is. If no day at all succeeds, the failure is thrown.
    public func fileTypes(
        inBucket bucket: String,
        range: ActivityRange,
        credential: Credential,
        timeZone: TimeZone
    ) async throws -> BreakdownResult {
        let key = "\(bucket.lowercased())|\(range.cacheKey)"
        if let cached = breakdowns[key] { return cached }

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let days = FileTypeBreakdown.days(in: range, calendar: calendar)
        var heartbeats: [WakaTimeHeartbeat] = []
        var covered = 0
        var firstFailure: (any Error)?
        for day in days {
            do {
                heartbeats += try await client.heartbeats(day: formatter.string(from: day), credential: credential)
                covered += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let error = error as? WakaTimeError { WakaLog.networkFailure(error) }
                firstFailure = firstFailure ?? error
            }
        }
        guard covered > 0 else { throw firstFailure ?? WakaTimeError.transport }

        let result = BreakdownResult(
            rows: FileTypeBreakdown.rows(from: heartbeats, bucket: bucket),
            daysCovered: covered,
            daysInPeriod: range.calendarDayCount(calendar: calendar)
        )
        breakdowns[key] = result
        return result
    }

    /// Drops a cache written for a different period, then drops cached days that
    /// have aged out of the retention window.
    private func pruned(
        _ cached: (value: CachedActivity, isFresh: Bool)?,
        matching rangeKey: String
    ) -> (value: [ActivityDay], isFresh: Bool)? {
        guard let cached, cached.value.rangeKey == rangeKey else { return nil }
        let days = cached.value.days
        let retained = retain(days)
        if retained.count != days.count {
            WakaLog.retentionPruned(dayCount: days.count - retained.count)
        }
        return retained.isEmpty ? nil : (retained, cached.isFresh)
    }

    /// Applies ``RetentionPolicy/cachedActivity`` to a set of days.
    private func retain(_ days: [ActivityDay]) -> [ActivityDay] {
        let cutoff = now().addingTimeInterval(-RetentionPolicy.cachedActivity)
        return days.filter { $0.date >= cutoff }
    }
}
