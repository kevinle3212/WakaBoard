import Foundation
import Observation
import WakaCore
import WidgetKit

/// The period the user is looking at.
public enum RangeOption: String, CaseIterable, Identifiable, Sendable {
    case week = "7D"
    case month = "30D"
    case quarter = "3M"

    public var id: Self { self }

    /// A spoken-language name, because "7D" is not what VoiceOver should read.
    public var accessibleName: String {
        switch self {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .quarter: "Last 3 months"
        }
    }

    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    /// Builds the concrete date range ending today in `timeZone`.
    func range(now: Date, timeZone: TimeZone, calendar: Calendar = .current) -> ActivityRange {
        var calendar = calendar
        calendar.timeZone = timeZone
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: end) ?? end
        return ActivityRange(start: start, end: end, timeZone: timeZone)
    }
}

/// What the dashboard is currently able to show.
///
/// Each case carries what the UI needs to say something true. `stale` is separate
/// from `loaded` because showing cached numbers as if they were current is the
/// specific failure this app must not have.
public enum WakaLoadState: Equatable, Sendable {
    /// No credential stored. The only screen that should appear is sign-in.
    case signedOut
    case loading
    case loaded
    /// Loaded successfully, but the account has no recorded activity in this range.
    case empty
    /// Showing cached data because the last refresh failed.
    case stale(reason: String)
    /// The API asked us to slow down. Cached data, if any, is still shown.
    case rateLimited(retryAfter: TimeInterval?)
    /// The stored credential was rejected. The user must sign in again.
    case expired
    case failed(String)
}

/// Drives every screen from real data.
///
/// Replaces the generated placeholder, which held a hard-coded fixture and whose
/// `refresh()` set `state = .loaded` without loading anything — so the shipped app
/// would have displayed invented coding statistics.
@MainActor
@Observable
public final class WakaUIModel {
    public private(set) var state: WakaLoadState = .signedOut
    public private(set) var days: [ActivityDay] = []
    public private(set) var overview: AnalyticsOverview?
    public private(set) var insights: [Insight] = []
    public private(set) var isBusy = false

    /// Bound to the sign-in field. Cleared as soon as the key reaches the Keychain.
    public var apiKeyInput = ""
    public var selectedRange: RangeOption = .week {
        didSet { if oldValue != selectedRange { Task { await refresh() } } }
    }

    private let environment: WakaEnvironment
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let reloadWidgets: @Sendable () -> Void

    /// - Parameters:
    ///   - reloadWidgets: Injected so tests do not call into WidgetKit, which is
    ///     unavailable outside a real app bundle.
    public init(
        environment: WakaEnvironment,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { .now },
        reloadWidgets: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.environment = environment
        self.timeZone = timeZone
        self.now = now
        self.reloadWidgets = reloadWidgets
    }

    /// Projects across the loaded period, largest first.
    public var projects: [Usage] { ranked(days.flatMap(\.projects)) }

    /// Languages across the loaded period, largest first.
    public var languages: [Usage] { ranked(days.flatMap(\.languages)) }

    /// Total time in the loaded period, for the chart and the header.
    public var dailyDurations: [TimeInterval] { days.sorted { $0.date < $1.date }.map(\.duration) }

    /// Whether a credential is present, deciding sign-in versus dashboard.
    public var isSignedIn: Bool { state != .signedOut }

    /// Loads stored credentials and performs the first fetch.
    public func start() async {
        guard ((try? environment.credentials.load()) ?? nil) != nil else {
            state = .signedOut
            return
        }
        await refresh()
    }

    /// Validates and stores a personal API key, then loads data.
    ///
    /// The key is verified against the account endpoint *before* it is written to
    /// the Keychain, so a typo fails immediately with a clear message instead of
    /// being persisted and failing on every later refresh.
    public func signIn() async {
        let credential = Credential.personalAPIKey(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
        guard credential.isWellFormed else {
            state = .failed("That does not look like a WakaTime API key. Check for stray spaces or line breaks.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.client.verifyCredential(credential)
            try environment.credentials.save(credential)
            apiKeyInput = ""
            await refresh()
        } catch let error as WakaTimeError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed("Could not verify that key. Check your connection and try again.")
        }
    }

    /// Erases the credential, the cache, and the widget snapshot.
    public func signOut() async {
        isBusy = true
        defer { isBusy = false }
        // Clear presented data first: whatever happens to storage, the screen must
        // not keep showing the previous account's analytics.
        days = []
        overview = nil
        insights = []
        apiKeyInput = ""
        do {
            try await environment.signOut()
            state = .signedOut
        } catch {
            state = .failed("Signed out on this screen, but some stored data could not be removed. Try again.")
        }
        reloadWidgets()
    }

    /// Deletes cached analytics without signing out.
    public func clearCache() async {
        isBusy = true
        defer { isBusy = false }
        try? await environment.repository.clearCache()
        environment.snapshots.clear()
        days = []
        overview = nil
        insights = []
        reloadWidgets()
        await refresh()
    }

    /// Fetches the selected range, cache-first, and maps every outcome to a state.
    public func refresh() async {
        guard let credential = (try? environment.credentials.load()) ?? nil else {
            state = .signedOut
            return
        }
        isBusy = true
        defer { isBusy = false }
        if days.isEmpty { state = .loading }

        let range = selectedRange.range(now: now(), timeZone: timeZone)
        do {
            let result = try await environment.repository.days(range: range, credential: credential, timeZone: timeZone)
            apply(days: result.days, range: range)
            state = result.isStale
                ? .stale(reason: "Showing your last saved data. The most recent refresh did not reach WakaTime.")
                : (result.days.allSatisfy { $0.duration == 0 } ? .empty : .loaded)
            publishWidgetSnapshot()
        } catch let error as WakaTimeError {
            state = Self.state(for: error, hasCachedData: !days.isEmpty)
        } catch is CancellationError {
            // The user moved on; leave whatever is on screen alone.
        } catch {
            state = .failed("Something went wrong loading your analytics.")
        }
    }

    private func apply(days loaded: [ActivityDay], range: ActivityRange) {
        days = loaded.sorted { $0.date < $1.date }
        let computed = AnalyticsEngine.overview(days: days, previousTotal: nil, range: range)
        overview = computed
        insights = AnalyticsEngine.insights(overview: computed)
    }

    /// Writes the credential-free aggregate the widget reads, then asks WidgetKit to reload.
    ///
    /// This is the App Group handoff the generated code documented but never
    /// performed, which is why widgets could only ever render placeholders.
    private func publishWidgetSnapshot() {
        // The days were normalized in the user's WakaTime timezone, so "today" must be
        // resolved in that same zone. Using the device calendar here silently shifted
        // the widget's today total for anyone whose two timezones differ.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let snapshot = WidgetSnapshot(days: days, generatedAt: now(), calendar: calendar)
        try? environment.snapshots.store(snapshot)
        reloadWidgets()
    }

    private func ranked(_ usage: [Usage]) -> [Usage] {
        AnalyticsEngine.aggregate(usage)
            .filter { $0.duration > 0 }
            .sorted { $0.duration == $1.duration ? $0.name < $1.name : $0.duration > $1.duration }
    }

    /// Maps an API failure to the state the UI should present.
    nonisolated static func state(for error: WakaTimeError, hasCachedData: Bool) -> WakaLoadState {
        switch error {
        case .unauthenticated:
            .expired
        case .rateLimited(let retryAfter):
            .rateLimited(retryAfter: retryAfter)
        default:
            hasCachedData
                ? .stale(reason: message(for: error))
                : .failed(message(for: error))
        }
    }

    /// User-facing copy for a failure category.
    ///
    /// Deliberately free of status codes, URLs, and header values: an error message
    /// is a place private request detail leaks into screenshots and bug reports.
    nonisolated static func message(for error: WakaTimeError) -> String {
        switch error {
        case .invalidEndpoint: "WakaBoard could not build a valid request. This is a bug — please report it."
        case .unauthenticated: "WakaTime rejected your API key. Sign in again to continue."
        case .forbidden: "That key does not have permission to read your analytics."
        case .unavailable: "WakaTime could not find that data."
        case .rateLimited: "WakaTime asked WakaBoard to slow down. Your saved data is still shown."
        case .serviceUnavailable: "WakaTime is having trouble right now. Try again shortly."
        case .transport: "WakaBoard could not reach WakaTime. Check your connection."
        case .decoding: "WakaTime sent a response WakaBoard could not read."
        case .responseTooLarge: "WakaTime sent more data than WakaBoard will load at once."
        }
    }
}
