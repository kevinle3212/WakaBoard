import Foundation

/// A versioned cache envelope that can be invalidated without guessing at old schema shapes.
public struct CacheEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    public let version: Int
    public let writtenAt: Date
    public let value: Value
    public init(version: Int = 1, writtenAt: Date, value: Value) { self.version = version; self.writtenAt = writtenAt; self.value = value }
}

public enum CacheError: Error, Equatable, Sendable { case corrupt; case unsupportedVersion }

/// App Group bridge for the deliberately credential-free widget summary.
/// Credentials stay in Keychain and never enter this `UserDefaults` suite.
public struct WidgetSnapshotStore: Sendable {
    private let suiteName: String
    private let key: String

    public init(suiteName: String, key: String = "widgetSnapshot.v1") {
        self.suiteName = suiteName
        self.key = key
    }

    public func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName), let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func store(_ snapshot: WidgetSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw CacheError.corrupt }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
    }

    public func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }
}

/// Actor-isolated JSON cache. Values are atomically replaced and never contain credentials.
public actor JSONCache<Value: Codable & Sendable> {
    private let fileURL: URL
    private let version: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, version: Int = 1, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.fileURL = fileURL; self.version = version; self.encoder = encoder; self.decoder = decoder
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
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    public func clear() throws { if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) } }
}

/// Equivalent fetches share a single task, avoiding duplicate safe GET requests.
public actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private var tasks: [Key: Task<Value, Error>] = [:]
    public init() {}
    public func value(for key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let existing = tasks[key] { return try await existing.value }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        return try await task.value
    }
}

/// Fetches analytics cached-first and preserves stale data for offline/error states.
public actor AnalyticsRepository {
    private let client: WakaTimeClient
    private let cache: JSONCache<[ActivityDay]>
    private let coalescer = RequestCoalescer<String, [ActivityDay]>()
    private let now: @Sendable () -> Date

    public init(client: WakaTimeClient, cache: JSONCache<[ActivityDay]>, now: @escaping @Sendable () -> Date = { .now }) { self.client = client; self.cache = cache; self.now = now }
    public func days(range: ActivityRange, credentials: Credentials, timeZone: TimeZone, maximumAge: TimeInterval = 300) async throws -> (days: [ActivityDay], isStale: Bool) {
        let cached: (value: [ActivityDay], isFresh: Bool)?
        do { cached = try await cache.load(now: now(), maximumAge: maximumAge) } catch { cached = nil }
        if let cached, cached.isFresh { return (cached.value, false) }
        let key = "\(range.queryDates().start)-\(range.queryDates().end)"
        do {
            let fetched = try await coalescer.value(for: key) { [client] in try await client.summaries(range: range, authorization: credentials.authorization, timeZone: timeZone) }
            try await cache.store(fetched, writtenAt: now())
            return (fetched, false)
        } catch {
            if let cached { return (cached.value, true) }
            throw error
        }
    }
}
