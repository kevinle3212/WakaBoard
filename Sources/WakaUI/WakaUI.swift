import Charts
import SwiftUI
import WakaCore

/// Every user-facing accessibility string, built by pure functions.
///
/// These live apart from the views for one reason: a claim of WCAG 2.2 AA
/// conformance has to be checkable. View bodies cannot be asserted against in a
/// unit test, but these can, so the label text that VoiceOver actually speaks is
/// covered by the suite rather than only by a manual pass.
public enum WakaAccessibility {
    /// Minimum hit target, per WCAG 2.2 SC 2.5.8 (24×24 CSS px) and Apple's stricter
    /// 44×44 point guidance. The larger of the two is used.
    public static let minimumTargetSize: CGFloat = 44

    public static func todayLabel(duration: TimeInterval) -> String {
        "Today, \(DurationFormatter().string(duration)) of coding time"
    }

    public static func metricLabel(title: String, value: String, detail: String) -> String {
        "\(title): \(value). \(detail)."
    }

    public static func usageLabel(name: String, duration: TimeInterval, percentage: Int) -> String {
        "\(name), \(DurationFormatter().string(duration)), \(percentage) percent of the selected period"
    }

    /// Text alternative for the activity chart.
    ///
    /// A `Chart` is invisible to VoiceOver without one. This sentence is the chart's
    /// content, not a description of it, which is what SC 1.1.1 requires.
    public static func chartSummary(durations: [TimeInterval]) -> String {
        guard !durations.isEmpty else { return "No activity recorded in this period." }
        let formatter = DurationFormatter()
        let total = durations.reduce(0, +)
        let activeDays = durations.filter { $0 > 0 }.count
        guard let peak = durations.max(), peak > 0 else {
            return "No activity recorded across \(durations.count) days."
        }
        return "\(formatter.string(total)) across \(durations.count) days, "
            + "\(activeDays) with activity. Busiest day, \(formatter.string(peak))."
    }

    public static func stateLabel(_ state: WakaLoadState) -> String {
        switch state {
        case .signedOut: "Not signed in. Enter a WakaTime API key to continue."
        case .loading: "Loading your analytics."
        case .loaded: "Analytics up to date."
        case .empty: "No coding activity recorded in this period."
        case .stale(let reason): "Showing saved data. \(reason)"
        case .rateLimited: "Refresh paused at WakaTime's request. Saved data is still shown."
        case .expired: "Your WakaTime key was rejected. Sign in again."
        case .failed(let message): "Could not load analytics. \(message)"
        }
    }
}

/// A single headline number.
public struct MetricCard: View {
    let title: String
    let value: String
    let detail: String

    public init(title: String, value: String, detail: String) {
        self.title = title
        self.value = value
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WakaAccessibility.metricLabel(title: title, value: value, detail: detail))
    }
}

/// Daily coding time, with a text alternative for assistive technology.
public struct ActivityChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let durations: [TimeInterval]

    public init(durations: [TimeInterval]) { self.durations = durations }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily activity").font(.headline)
            Chart(Array(durations.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("Day", index + 1),
                    y: .value("Minutes", value / 60)
                )
                .foregroundStyle(.tint)
            }
            .frame(height: 160)
            .chartYAxisLabel("Minutes")
            // Respect Reduce Motion: the transition between ranges is animated only
            // when the user has not asked the system to stop animating things.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: durations)
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily activity chart. \(summary)")
    }

    private var summary: String { WakaAccessibility.chartSummary(durations: durations) }
}

/// An explanatory state with a single recovery action.
public struct WakaStateView: View {
    let title: String
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    public init(title: String, message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "chart.bar.xaxis")
        } description: {
            Text(message)
        } actions: {
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: WakaAccessibility.minimumTargetSize, minHeight: WakaAccessibility.minimumTargetSize)
            }
        }
    }
}

/// Sign-in. The only screen shown before a credential exists.
struct WakaSignInView: View {
    @Bindable var model: WakaUIModel

    var body: some View {
        Form {
            Section("Connect WakaTime") {
                // `SecureField` so the key is not shown on screen or captured in a
                // screenshot, and autocorrect/capitalisation are off because they
                // silently corrupt a pasted key.
                SecureField("WakaTime API key", text: $model.apiKeyInput)
                    .textContentType(.password)
                    .disableAutocorrection(true)
                    .frame(minHeight: WakaAccessibility.minimumTargetSize)
                    .accessibilityLabel("WakaTime API key")
                    .accessibilityHint("Paste the personal API key from your WakaTime account settings")
                Button {
                    Task { await model.signIn() }
                } label: {
                    Text(model.isBusy ? "Verifying…" : "Connect")
                        .frame(maxWidth: .infinity, minHeight: WakaAccessibility.minimumTargetSize)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.apiKeyInput.isEmpty || model.isBusy)

                if case .failed(let message) = model.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Sign-in failed. \(message)")
                }
            }
            Section("Where to find your key") {
                Text("Open wakatime.com, go to Account Settings, and copy your secret API key. "
                     + "WakaBoard stores it in the system Keychain on this device only, and sends it "
                     + "to nowhere except wakatime.com.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Open WakaTime account settings", destination: URL(string: "https://wakatime.com/settings/account")!)
                    .frame(minHeight: WakaAccessibility.minimumTargetSize)
            }
            Section("Your privacy") {
                Text("WakaBoard has no server. Your analytics are fetched directly by this device and "
                     + "stored only on it. The developer receives nothing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sign in")
    }
}

/// The overview dashboard.
struct WakaDashboardView: View {
    @Bindable var model: WakaUIModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch model.state {
                case .signedOut:
                    WakaStateView(title: "Not connected", message: "Add your WakaTime API key to see your analytics.")
                case .loading:
                    ProgressView("Loading your analytics…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .accessibilityLabel(WakaAccessibility.stateLabel(.loading))
                case .expired:
                    WakaStateView(
                        title: "Reconnect WakaTime",
                        message: "WakaTime rejected your stored key. Sign in again to refresh analytics.",
                        actionLabel: "Sign out",
                        action: { Task { await model.signOut() } }
                    )
                case .empty:
                    WakaStateView(
                        title: "No activity yet",
                        message: "No coding time is recorded for this period. Start coding and WakaBoard will show it here.",
                        actionLabel: "Refresh",
                        action: { Task { await model.refresh() } }
                    )
                case .failed(let message):
                    WakaStateView(title: "Couldn't load analytics", message: message, actionLabel: "Retry", action: { Task { await model.refresh() } })
                case .stale, .rateLimited, .loaded:
                    banner
                    loaded
                }
            }
            .padding()
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isBusy)
                    .accessibilityHint("Loads the latest available analytics from WakaTime")
            }
        }
        .task { await model.start() }
        .refreshable { await model.refresh() }
    }

    /// Shown above real data whenever that data is not current.
    @ViewBuilder private var banner: some View {
        switch model.state {
        case .stale(let reason):
            Label(reason, systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(WakaAccessibility.stateLabel(model.state))
        case .rateLimited:
            Label("Refresh paused at WakaTime's request. Your saved data is still shown.", systemImage: "clock.badge.exclamationmark")
                .font(.footnote)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(WakaAccessibility.stateLabel(model.state))
        default:
            EmptyView()
        }
    }

    private var loaded: some View {
        let formatter = DurationFormatter()
        let today = model.days.last?.duration ?? 0
        let overview = model.overview
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(.headline)
                Text(formatter.string(today))
                    // `.largeTitle` relative sizing rather than a fixed point size, so
                    // the number scales with Dynamic Type instead of staying 40pt.
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("Coding time").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WakaAccessibility.todayLabel(duration: today))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) {
                MetricCard(
                    title: "Selected period",
                    value: formatter.string(overview?.total ?? 0),
                    detail: model.selectedRange.accessibleName
                )
                MetricCard(
                    title: "Daily average",
                    value: formatter.string(overview?.calendarDayAverage ?? 0),
                    detail: "Across every calendar day"
                )
                MetricCard(
                    title: "Streak",
                    value: "\(overview?.streak ?? 0)",
                    detail: "Days over 15 minutes"
                )
                MetricCard(
                    title: "Top project",
                    value: model.projects.first?.name ?? "—",
                    detail: "By coding time"
                )
                MetricCard(
                    title: "Top language",
                    value: model.languages.first?.name ?? "—",
                    detail: "Usage, not proficiency"
                )
            }

            ActivityChart(durations: model.dailyDurations)
        }
    }
}

/// Activity over the selected period, with the range picker.
struct WakaActivityView: View {
    @Bindable var model: WakaUIModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Period", selection: $model.selectedRange) {
                    ForEach(RangeOption.allCases) { option in
                        Text(option.rawValue).tag(option).accessibilityLabel(option.accessibleName)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: WakaAccessibility.minimumTargetSize)
                .accessibilityLabel("Analytics period")
                .accessibilityHint("Changes the period shown on every screen")

                ActivityChart(durations: model.dailyDurations)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Consistency").font(.headline)
                    if let score = model.overview?.consistencyScore {
                        Text("Consistency score \(Int(score.rounded())) out of 100")
                    } else {
                        Text("Not enough activity yet to score consistency.")
                    }
                    Text("A coding day requires at least 15 minutes. Both the streak rule and the "
                         + "consistency score are WakaBoard's own calculations, not WakaTime metrics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle("Activity")
    }
}

/// A ranked project or language list.
struct UsageListView: View {
    let title: String
    let subtitle: String
    let usage: [Usage]
    let icon: String

    private var total: TimeInterval { usage.reduce(0) { $0 + $1.duration } }

    var body: some View {
        Group {
            if usage.isEmpty {
                WakaStateView(title: "Nothing to show", message: "No \(title.lowercased()) recorded in the selected period.")
            } else {
                List(usage) { item in
                    let percentage = total > 0 ? Int((item.duration / total * 100).rounded()) : 0
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(item.name, systemImage: icon).lineLimit(2)
                            Spacer()
                            Text(DurationFormatter().string(item.duration)).monospacedDigit()
                        }
                        ProgressView(value: item.duration, total: max(total, 1))
                        Text("\(percentage)% of the selected period").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WakaAccessibility.usageLabel(name: item.name, duration: item.duration, percentage: percentage))
                }
            }
        }
        .navigationTitle(title)
        .safeAreaInset(edge: .top) {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }
}

/// Locally derived insights, or an honest statement that there are none.
struct WakaInsightsView: View {
    let model: WakaUIModel

    var body: some View {
        List {
            if model.insights.isEmpty {
                Section {
                    Text("Not enough activity yet for a claim WakaBoard can support. "
                         + "Insights appear once there is enough data to compare against.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Recent insights") {
                    ForEach(Array(model.insights.enumerated()), id: \.offset) { _, insight in
                        Label(Self.sentence(for: insight), systemImage: Self.icon(for: insight))
                    }
                }
            }
            Section("How insights work") {
                Text("Insights are computed on this device from your normalized summaries. "
                     + "WakaBoard omits a claim rather than making one it cannot support.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Insights")
    }

    nonisolated static func sentence(for insight: Insight) -> String {
        switch insight {
        case .streak(let days):
            "You have coded at least 15 minutes on \(days) days in a row."
        case .strongestProject(let name, let share):
            "\(name) accounts for \(Int((share * 100).rounded()))% of your time this period."
        case .consistency(let score):
            "Your day-to-day coding time is fairly even, scoring \(Int(score.rounded())) out of 100."
        }
    }

    nonisolated static func icon(for insight: Insight) -> String {
        switch insight {
        case .streak: "flame"
        case .strongestProject: "folder"
        case .consistency: "waveform.path.ecg"
        }
    }
}

/// Account, data, and legal controls. Every button here does real work.
struct WakaSettingsView: View {
    @Bindable var model: WakaUIModel
    @State private var confirmingSignOut = false
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Connection", value: model.isSignedIn ? "Connected" : "Not connected")
                if model.isSignedIn {
                    Button("Sign out and erase local data", role: .destructive) { confirmingSignOut = true }
                        .frame(minHeight: WakaAccessibility.minimumTargetSize)
                        .accessibilityHint("Removes your API key, cached analytics, and widget data from this device")
                }
                Text("WakaBoard signs in with a personal API key stored in the system Keychain on this "
                     + "device only. It is never synced to iCloud and never included in a device backup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Refresh analytics") { Task { await model.refresh() } }
                    .disabled(model.isBusy)
                    .frame(minHeight: WakaAccessibility.minimumTargetSize)
                Button("Clear local cache", role: .destructive) { confirmingClear = true }
                    .frame(minHeight: WakaAccessibility.minimumTargetSize)
                Text("Cached analytics are kept on this device for up to 90 days and are deleted "
                     + "automatically after that. Widget data is kept for up to 7 days.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Widgets") {
                Text("Add WakaBoard from the system widget gallery. Widgets read only the cached summary "
                     + "and never receive your API key. The system, not WakaBoard, decides when they refresh.")
            }

            Section("Privacy and legal") {
                Text("WakaBoard has no server, no telemetry, no advertising, and no crash-reporting SDK. "
                     + "The developer receives no data about you at all.")
                    .font(.footnote)
                LegalLink(title: "Privacy Policy", file: "PRIVACY")
                LegalLink(title: "Terms of Service", file: "TERMS")
                LegalLink(title: "Data Retention", file: "RETENTION")
                LegalLink(title: "Accessibility Statement", file: "ACCESSIBILITY")
                LegalLink(title: "Disclaimer and Liability", file: "DISCLAIMER")
            }

            Section("About") {
                Text("WakaBoard is an independent open-source client. It is not affiliated with, "
                     + "endorsed by, or sponsored by WakaTime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign out of WakaBoard?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out and erase", role: .destructive) { Task { await model.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your API key, cached analytics, and widget data will be removed from this device. "
                 + "Nothing is deleted from your WakaTime account.")
        }
        .confirmationDialog(
            "Clear cached analytics?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear cache", role: .destructive) { Task { await model.clearCache() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WakaBoard will refetch your analytics on the next refresh. You stay signed in.")
        }
    }
}

/// Opens a bundled legal document, falling back to the public repository copy.
private struct LegalLink: View {
    let title: String
    let file: String

    var body: some View {
        Link(destination: url) { Text(title) }
            .frame(minHeight: WakaAccessibility.minimumTargetSize)
            .accessibilityHint("Opens the \(title) document")
    }

    /// The published copy of the document.
    ///
    /// Documents are linked rather than bundled: a symlinked copy inside a
    /// code-signed bundle is fragile, and the repository is the authoritative
    /// version users should read.
    private var url: URL {
        URL(string: "https://github.com/lekevin1/WakaBoard/blob/main/\(file).md")
            ?? URL(string: "https://github.com/lekevin1/WakaBoard")!
    }
}

/// Top-level routes.
public enum WakaRoute: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case activity = "Activity"
    case projects = "Projects"
    case languages = "Languages"
    case insights = "Insights"
    case settings = "Settings"

    public var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .activity: "chart.xyaxis.line"
        case .projects: "folder"
        case .languages: "chevron.left.forwardslash.chevron.right"
        case .insights: "lightbulb"
        case .settings: "gearshape"
        }
    }

    /// Maps a validated deep link onto a route.
    public init(_ deepLink: DeepLink) {
        switch deepLink {
        case .overview: self = .overview
        case .activity: self = .activity
        case .projects: self = .projects
        case .languages: self = .languages
        case .insights: self = .insights
        case .settings: self = .settings
        }
    }
}

/// The app shell. Owns the model and routes between screens.
public struct WakaShellView: View {
    @State private var model: WakaUIModel
    @State private var selection: WakaRoute? = .overview

    /// - Parameter environment: Defaults to the live environment; tests and previews
    ///   inject their own.
    public init(environment: WakaEnvironment = .live()) {
        _model = State(initialValue: WakaUIModel(environment: environment))
    }

    /// Accepts a model owned by the app, so a menu command and the views share state.
    public init(model: WakaUIModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            List(WakaRoute.allCases, selection: $selection) { route in
                Label(route.rawValue, systemImage: route.icon)
                    .frame(minHeight: WakaAccessibility.minimumTargetSize)
                    .tag(route)
            }
            .navigationTitle("WakaBoard")
        } detail: {
            detail
        }
        .task { await model.start() }
        .onOpenURL { url in
            guard let link = DeepLink(url: url, scheme: WakaIdentifiers.urlScheme) else { return }
            selection = WakaRoute(link)
        }
    }

    @ViewBuilder private var detail: some View {
        if !model.isSignedIn {
            WakaSignInView(model: model)
        } else {
            switch selection {
            case .overview: WakaDashboardView(model: model)
            case .activity: WakaActivityView(model: model)
            case .projects:
                UsageListView(title: "Projects", subtitle: "Sorted by coding time in the selected period", usage: model.projects, icon: "folder")
            case .languages:
                UsageListView(title: "Languages", subtitle: "Usage time is not a measure of proficiency", usage: model.languages, icon: "chevron.left.forwardslash.chevron.right")
            case .insights: WakaInsightsView(model: model)
            case .settings: WakaSettingsView(model: model)
            case nil:
                WakaStateView(title: "WakaBoard", message: "Choose a section from the sidebar.")
            }
        }
    }
}
