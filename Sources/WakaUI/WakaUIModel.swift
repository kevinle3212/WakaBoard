import Foundation
import Observation
import Security
import WakaCore
// tvOS is the one Apple platform with no WidgetKit at all — `AppleTVOS.sdk` ships no
// `WidgetKit.framework`, and its analogue is Top Shelf, which WakaBoard does not use.
// An unconditional import here is what would stop the tvOS target compiling.
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    /// The Keychain could not be read — locked, corrupt, or missing an entitlement.
    ///
    /// Distinct from ``signedOut``: the user may well have a credential stored, and
    /// telling them they are "not signed in" sends them to re-enter a key that will
    /// fail to save for the same underlying reason.
    case credentialUnavailable(String)
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

    /// Whether the sign-in field reveals the key. Off by default.
    public var isKeyVisible = false

    /// The last sign-in failure, shown on the sign-in screen.
    ///
    /// Deliberately separate from ``state``: expressing a sign-in failure as
    /// `.failed` made ``isSignedIn`` true, which swapped the sign-in screen for the
    /// dashboard, whose own load then failed and swapped it back — so a failed
    /// sign-in looked like the Connect button doing nothing at all.
    public private(set) var signInError: String?
    public var selectedRange: RangeOption = .week {
        didSet {
            guard oldValue != selectedRange else { return }
            // The picker now asks a different question, so the old period cannot
            // remain on screen while its replacement loads. Invalidating here also
            // prevents an older in-flight response from winning the race back.
            refreshGeneration += 1
            days = []
            overview = nil
            insights = []
            state = .loading
            Task { await refresh() }
        }
    }

    /// The dimension the breakdown screen is showing.
    ///
    /// Unlike the period, changing this triggers no fetch: every dimension is
    /// already in the days that were loaded, so switching is instant and costs
    /// WakaTime nothing.
    public var selectedDimension: ActivityDimension = .projects

    private let environment: WakaEnvironment
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let reloadWidgets: @Sendable () -> Void
    /// Monotonic identity of the latest refresh allowed to update presented state.
    private var refreshGeneration = 0

    /// - Parameters:
    ///   - reloadWidgets: Injected so tests do not call into WidgetKit, which is
    ///     unavailable outside a real app bundle — and absent entirely on tvOS.
    public init(
        environment: WakaEnvironment,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { .now },
        reloadWidgets: @escaping @Sendable () -> Void = WakaUIModel.reloadWidgetTimelines
    ) {
        self.environment = environment
        self.timeZone = timeZone
        self.now = now
        self.reloadWidgets = reloadWidgets
    }

    /// Asks WidgetKit to refresh, where WidgetKit exists.
    ///
    /// A free function rather than an inline default argument so the `#if` lives in
    /// one place instead of inside a parameter list, where it reads badly and cannot
    /// be documented.
    public nonisolated static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// The buckets of `dimension` across the loaded period, largest first.
    public func ranked(_ dimension: ActivityDimension) -> [Usage] {
        AnalyticsEngine.ranked(dimension, in: days)
    }

    /// Projects across the loaded period, largest first.
    public var projects: [Usage] { ranked(.projects) }

    /// Languages across the loaded period, largest first.
    public var languages: [Usage] { ranked(.languages) }

    /// Totals by day of the week across the loaded period.
    public var weekdayTotals: [AnalyticsEngine.WeekdayTotal] {
        AnalyticsEngine.weekdayTotals(days: days, range: loadedRange)
    }

    /// The running total across the loaded period, oldest day first.
    public var cumulative: [(date: Date, total: TimeInterval)] { AnalyticsEngine.cumulative(days: days) }

    /// The trailing seven-day mean across the loaded period.
    public var rollingAverage: [(date: Date, average: TimeInterval)] { AnalyticsEngine.rollingAverage(days: days) }

    /// The loaded period as a week-by-weekday grid, for the activity ribbon.
    public var density: [AnalyticsEngine.DensityCell] {
        AnalyticsEngine.density(days: days, range: loadedRange)
    }

    /// Active-day, peak, and median figures for the loaded period.
    public var activitySummary: AnalyticsEngine.ActivitySummary? {
        AnalyticsEngine.activitySummary(days: days, range: loadedRange)
    }

    /// Calendar-week totals for the loaded period, oldest week first.
    public var weeklyTotals: [AnalyticsEngine.WeekTotal] {
        AnalyticsEngine.weeklyTotals(days: days, range: loadedRange)
    }

    /// Daily points for the leading buckets of `dimension`.
    public func dailyTrends(_ dimension: ActivityDimension) -> [AnalyticsEngine.TrendPoint] {
        AnalyticsEngine.dailyTrends(dimension, days: days, range: loadedRange)
    }

    /// The range the presented days belong to.
    ///
    /// Derived from the selection rather than stored, so it can never disagree with
    /// the picker the user is looking at.
    private var loadedRange: ActivityRange { selectedRange.range(now: now(), timeZone: timeZone) }

    /// Total time in the loaded period, for the chart and the header.
    public var dailyDurations: [TimeInterval] { days.sorted { $0.date < $1.date }.map(\.duration) }

    /// Daily totals paired with their dates, oldest first.
    ///
    /// Charts plot the real date rather than the position in an array: a period with
    /// a missing day would otherwise silently compress its own axis.
    public var dailySeries: [(date: Date, duration: TimeInterval)] {
        days.sorted { $0.date < $1.date }.map { ($0.date, $0.duration) }
    }

    /// A dimension's buckets with the tail folded into one labelled row, ready to
    /// hand to a chart with a fixed eight-slot palette.
    public func foldedUsage(_ dimension: ActivityDimension) -> [Usage] {
        let folded = AnalyticsEngine.topBuckets(ranked(dimension))
        return folded.top + [folded.remainder].compactMap { $0 }
    }

    /// Whether tapping this row opens a further breakdown.
    ///
    /// Only WakaTime's unresolved language buckets can be opened. Everything else is
    /// already as specific as WakaTime's data gets, and a chevron on a row that opens
    /// nothing is worse than no chevron at all.
    public func canDrillInto(_ item: Usage, dimension: ActivityDimension) -> Bool {
        dimension == .languages && FileTypeBreakdown.isUnresolvedBucket(item.name)
    }

    /// Whether the dashboard should be shown rather than the sign-in screen.
    public var isSignedIn: Bool {
        switch state {
        case .signedOut, .credentialUnavailable: false
        default: true
        }
    }

    /// What the file-type drill-down currently has to show.
    public enum BreakdownState: Equatable, Sendable {
        case loading
        case loaded(BreakdownResult)
        /// The reason it could not be produced, phrased for a user.
        case failed(String)
    }

    /// The drill-down for the bucket currently open, if one is open.
    public private(set) var breakdown: BreakdownState?

    /// Loads the file types inside `bucket` for the selected period.
    ///
    /// User-initiated only: nothing calls this on refresh, on launch, or on a period
    /// change. It is the one path in the app that issues more than one request per
    /// action, so it stays behind a deliberate tap.
    public func loadBreakdown(for bucket: Usage) async {
        breakdown = .loading
        guard case .success(let stored?) = storedCredential() else {
            breakdown = .failed("WakaBoard could not read your saved key, so it cannot load this breakdown.")
            return
        }
        do {
            let result = try await environment.repository.fileTypes(
                inBucket: bucket.name,
                range: loadedRange,
                credential: stored,
                timeZone: timeZone
            )
            breakdown = result.rows.isEmpty
                ? .failed("WakaTime returned no file-level detail for this period, so there is nothing to break down.")
                : .loaded(result)
        } catch is CancellationError {
            breakdown = nil
        } catch let error as WakaTimeError {
            breakdown = .failed(Self.message(for: error))
        } catch {
            breakdown = .failed("Something went wrong loading the file types for this period.")
        }
    }

    /// Discards the open drill-down when its sheet closes.
    public func clearBreakdown() { breakdown = nil }

    /// Reads the stored credential, distinguishing "absent" from "unreadable".
    ///
    /// The generated shape (`try? load()`) collapsed those two cases, so a locked
    /// Keychain was reported to the user as "not signed in".
    private func storedCredential() -> Result<Credential?, KeychainError> {
        do { return .success(try environment.credentials.load()) }
        catch let error as KeychainError { return .failure(error) }
        catch { return .failure(.unhandled(status: errSecInternalError)) }
    }

    /// User-facing copy for a Keychain failure.
    nonisolated static func message(for error: KeychainError) -> String {
        switch error {
        case .interactionNotAllowed:
            "WakaBoard could not read the Keychain. Unlock your device and try again."
        case .malformedItem:
            "The saved WakaTime key could not be read. Sign in again to replace it."
        case .unhandled:
            "WakaBoard could not reach the Keychain on this device, so it cannot load your saved key."
        }
    }

    /// Loads stored credentials and performs the first fetch.
    public func start() async {
        switch storedCredential() {
        case .success(nil):
            state = .signedOut
        case .success:
            await refresh()
        case .failure(let error):
            state = .credentialUnavailable(Self.message(for: error))
        }
    }

    /// Validates and stores a personal API key, then loads data.
    ///
    /// The key is verified against the account endpoint *before* it is written to
    /// the Keychain, so a typo fails immediately with a clear message instead of
    /// being persisted and failing on every later refresh.
    public func signIn() async {
        signInError = nil
        let credential = Credential.personalAPIKey(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
        guard credential.isWellFormed else {
            signInError = "That does not look like a WakaTime API key. Check for stray spaces or line breaks."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await environment.client.verifyCredential(credential)
            try environment.credentials.save(credential)
            apiKeyInput = ""
            isKeyVisible = false
            await refresh()
        } catch let error as WakaTimeError {
            signInError = Self.message(for: error)
        } catch let error as KeychainError {
            // Previously collapsed into "check your connection", which was actively
            // misleading: the key had already been accepted by WakaTime and it was
            // storage that failed.
            signInError = "Your key was accepted by WakaTime, but WakaBoard could not save it. "
                + Self.message(for: error)
        } catch is CancellationError {
            return
        } catch {
            signInError = "Could not verify that key. Check your connection and try again."
        }
    }

    /// Erases the credential, the cache, and the widget snapshot.
    public func signOut() async {
        isBusy = true
        defer { isBusy = false }
        refreshGeneration += 1
        // Clear presented data first: whatever happens to storage, the screen must
        // not keep showing the previous account's analytics.
        days = []
        overview = nil
        insights = []
        apiKeyInput = ""
        isKeyVisible = false
        signInError = nil
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
        refreshGeneration += 1
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
        let credential: Credential
        switch storedCredential() {
        case .success(let stored?):
            credential = stored
        case .success(nil):
            state = .signedOut
            return
        case .failure(let error):
            state = .credentialUnavailable(Self.message(for: error))
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        isBusy = true
        defer {
            if generation == refreshGeneration { isBusy = false }
        }
        if days.isEmpty { state = .loading }

        let range = selectedRange.range(now: now(), timeZone: timeZone)
        do {
            let result = try await environment.repository.days(range: range, credential: credential, timeZone: timeZone)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            apply(days: result.days, range: range)
            state = result.isStale
                ? .stale(reason: "Showing your last saved data. The most recent refresh did not reach WakaTime.")
                : (result.days.allSatisfy { $0.duration == 0 } ? .empty : .loaded)
            publishWidgetSnapshot()
        } catch let error as WakaTimeError {
            guard generation == refreshGeneration else { return }
            state = Self.state(for: error, hasCachedData: !days.isEmpty)
        } catch is CancellationError {
            // The user moved on; leave whatever is on screen alone.
        } catch {
            guard generation == refreshGeneration else { return }
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
