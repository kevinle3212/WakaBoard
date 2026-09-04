import SwiftUI
import WakaCore

// MARK: - Sign in

/// Sign-in. The only screen shown before a credential exists.
struct WakaSignInView: View {
    @Bindable var model: WakaUIModel

    var body: some View {
        Form {
            Section("Connect WakaTime") {
                HStack(spacing: WakaDesign.Spacing.tight) {
                    Group {
                        if model.isKeyVisible {
                            TextField("WakaTime API key", text: $model.apiKeyInput)
                        } else {
                            SecureField("WakaTime API key", text: $model.apiKeyInput)
                        }
                    }
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("WakaTime API key")
                    .accessibilityHint("Paste the personal API key from your WakaTime account settings")

                    Button {
                        model.isKeyVisible.toggle()
                    } label: {
                        Image(systemName: model.isKeyVisible ? "eye.slash" : "eye")
                            .frame(
                                width: WakaAccessibility.minimumTargetSize,
                                height: WakaAccessibility.minimumTargetSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The label alone would read as "eye"; state and effect matter more.
                    .accessibilityLabel(model.isKeyVisible ? "Hide API key" : "Show API key")
                    .accessibilityHint("Toggles whether the key is displayed as plain text")
                }
                .padding(.horizontal, WakaDesign.Spacing.snug)
                .frame(minHeight: WakaAccessibility.minimumTargetSize)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: WakaDesign.Radius.control))

                Button {
                    Task { await model.signIn() }
                } label: {
                    Text(model.isBusy ? "Verifying…" : "Connect")
                        .frame(maxWidth: .infinity, minHeight: WakaAccessibility.minimumTargetSize)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.apiKeyInput.isEmpty || model.isBusy)

                // Reads `signInError`, not `state`. Driving this from `state` meant a
                // failed sign-in flipped the app to the dashboard and back, so the
                // message never stayed on screen long enough to be read.
                if let message = model.signInError {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Sign-in failed. \(message)")
                }
            }

            Section("Where to Find Your Key") {
                Text("Open wakatime.com, go to Account Settings, and copy your secret API key. "
                     + "WakaBoard stores it in the system Keychain on this device only, and sends it "
                     + "to nowhere except wakatime.com.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                WakaExternalLink(
                    title: "Open WakaTime Account Settings",
                    url: URL(string: "https://wakatime.com/settings/account")
                )
            }

            Section("Data Source") {
                WakaTimeCredit()
            }

            Section("Your Privacy") {
                Text("WakaBoard has no server. Your analytics are fetched directly by this device and "
                     + "stored only on it. The developer receives nothing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sign In")
    }
}

// MARK: - Overview

/// The overview dashboard.
struct WakaDashboardView: View {
    @Bindable var model: WakaUIModel

    var body: some View {
        WakaScreen(model: model) {
            loaded
        }
        .navigationTitle("Overview")
        .toolbar { RefreshToolbarItem(model: model) }
        #if !os(tvOS)
        .refreshable { await model.refresh() }
        #endif
    }

    private var loaded: some View {
        let formatter = DurationFormatter()
        let today = model.days.last?.duration ?? 0
        let overview = model.overview
        return VStack(alignment: .leading, spacing: WakaDesign.Spacing.loose) {
            VStack(alignment: .leading, spacing: WakaDesign.Spacing.hairline) {
                Text("Today").font(.wakaSectionTitle)
                Text(formatter.string(today))
                    .font(.wakaHeroNumeral)
                Text("Coding Time").foregroundStyle(.secondary)
            }
            .wakaHeroSurface()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WakaAccessibility.todayLabel(duration: today))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: WakaDesign.Spacing.snug)], spacing: WakaDesign.Spacing.snug) {
                MetricCard(
                    title: "Selected Period",
                    value: formatter.string(overview?.total ?? 0),
                    detail: model.selectedRange.accessibleName
                )
                MetricCard(
                    title: "Daily Average",
                    value: formatter.string(overview?.calendarDayAverage ?? 0),
                    detail: "Across every calendar day"
                )
                MetricCard(
                    title: "Active Day Average",
                    value: formatter.string(overview?.activeDayAverage ?? 0),
                    detail: "Across days with any coding"
                )
                MetricCard(
                    title: "Current Streak",
                    value: "\(overview?.streak ?? 0)",
                    detail: "Days over 15 minutes"
                )
                MetricCard(
                    title: "Top Project",
                    value: model.projects.first?.name ?? "—",
                    detail: "By coding time"
                )
                MetricCard(
                    title: "Top Language",
                    value: model.languages.first?.name ?? "—",
                    detail: "Usage, not proficiency"
                )
            }

            ActivityBalanceChart(summary: model.activitySummary)
            ActivityChart(daily: model.dailySeries, rollingAverage: model.rollingAverage)
            ActivityRibbon(cells: model.density)
            ShareChart(title: "Language Share", usage: model.foldedUsage(.languages))

            WakaTimeCredit()
        }
    }
}

// MARK: - Activity

/// Activity over the selected period, with the period picker.
struct WakaActivityView: View {
    @Bindable var model: WakaUIModel

    var body: some View {
        WakaScreen(model: model, header: { PeriodPicker(model: model) }) {
            VStack(alignment: .leading, spacing: WakaDesign.Spacing.loose) {
                ActivityChart(daily: model.dailySeries, rollingAverage: model.rollingAverage)
                CumulativeChart(running: model.cumulative)
                WeeklyTotalsChart(totals: model.weeklyTotals)
                WeekdayChart(totals: model.weekdayTotals)
                consistency
                WakaTimeCredit(showsLink: false)
            }
        }
        .navigationTitle("Activity")
        .toolbar { RefreshToolbarItem(model: model) }
    }

    private var consistency: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.tight) {
            Text("Consistency").font(.wakaSectionTitle)
            if let score = model.overview?.consistencyScore {
                Text("Consistency score \(Int(score.rounded())) out of 100.")
            } else {
                Text("Not enough activity yet to score consistency.")
            }
            Text("A coding day requires at least 15 minutes. Both the streak rule and the "
                 + "consistency score are WakaBoard's own calculations, not WakaTime metrics.")
                .font(.wakaCaption)
                .foregroundStyle(.secondary)
        }
        .wakaCard()
    }
}

// MARK: - Breakdown

/// Every dimension of the period — projects, languages, editors, operating systems,
/// and categories — behind one picker.
///
/// One screen rather than five near-identical ones. Five sidebar entries that differ
/// only in which array they read is what makes an app feel assembled; it also does
/// not survive contact with a watch, where a five-entry list is the whole screen.
struct WakaBreakdownView: View {
    @Bindable var model: WakaUIModel
    /// Set when the user taps a bucket that can be opened further.
    @State private var drilling: Usage?

    var body: some View {
        // Ranking can aggregate thousands of API buckets. Derive it once per render
        // instead of independently for both charts and the full-detail list.
        let usage = model.ranked(model.selectedDimension)
        let folded = AnalyticsEngine.topBuckets(usage)
        let chartUsage = folded.top + [folded.remainder].compactMap { $0 }
        let total = usage.reduce(0) { $0 + $1.duration }

        WakaScreen(model: model, header: { dimensionPicker }) {
            VStack(alignment: .leading, spacing: WakaDesign.Spacing.loose) {
                Text(model.selectedDimension.explanation)
                    .font(.wakaCaption)
                    .foregroundStyle(.secondary)

                DailyTrendChart(
                    title: "\(model.selectedDimension.title) Trend",
                    points: model.dailyTrends(model.selectedDimension)
                )
                ShareChart(title: "\(model.selectedDimension.title) Share", usage: chartUsage)
                ComparisonChart(title: "Top \(model.selectedDimension.title)", usage: chartUsage)
                rankedList(usage: usage, total: total)
                WakaTimeCredit(showsLink: false)
            }
        }
        .navigationTitle(model.selectedDimension.title)
        .toolbar { RefreshToolbarItem(model: model) }
        .sheet(item: $drilling) { bucket in
            FileTypeBreakdownView(model: model, bucket: bucket)
        }
    }

    private var dimensionPicker: some View {
        WakaSegmentedPicker(
            label: "Breakdown dimension",
            hint: "Chooses which dimension of the selected period is shown",
            options: ActivityDimension.allCases,
            title: \.title,
            selection: $model.selectedDimension
        )
    }

    @ViewBuilder private func rankedList(usage: [Usage], total: TimeInterval) -> some View {
        if usage.isEmpty {
            WakaStateView(
                title: "Nothing to Show",
                message: "No \(model.selectedDimension.title.lowercased()) were recorded in the selected period."
            )
        } else {
            // Keep the long tail virtualized. The response bounds permit a large
            // selected period, but off-screen rows should not become view work.
            LazyVStack(alignment: .leading, spacing: WakaDesign.Spacing.snug) {
                Text("All \(model.selectedDimension.title)").font(.wakaSectionTitle)
                ForEach(usage.indices, id: \.self) { index in
                    let item = usage[index]
                    let drillable = model.canDrillInto(item, dimension: model.selectedDimension)
                    let row = UsageRow(
                        item: item,
                        total: total,
                        icon: model.selectedDimension.icon,
                        rank: index,
                        isDrillable: drillable
                    )
                    if drillable {
                        Button { drilling = item } label: { row }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the file types inside this bucket")
                    } else {
                        row
                    }
                }
            }
            .wakaCard()
        }
    }
}

// MARK: - Insights

/// Locally derived insights, or an honest statement that there are none.
///
/// Cards rather than a `List`, for two reasons that happen to agree: it matches every
/// other data screen, and `ImageRenderer` cannot rasterize a `List`, so a list here
/// would be the one screen the snapshot check could never look at.
struct WakaInsightsView: View {
    let model: WakaUIModel

    var body: some View {
        WakaScreen(model: model) {
            VStack(alignment: .leading, spacing: WakaDesign.Spacing.loose) {
                if model.insights.isEmpty {
                    WakaStateView(
                        title: "No Insights Yet",
                        message: "There is not enough activity yet for a claim WakaBoard can support. "
                            + "Insights appear once there is enough data to compare against."
                    )
                } else {
                    VStack(alignment: .leading, spacing: WakaDesign.Spacing.snug) {
                        Text("Recent Insights").font(.wakaSectionTitle)
                        ForEach(Array(model.insights.enumerated()), id: \.offset) { _, insight in
                            Label(Self.sentence(for: insight), systemImage: Self.icon(for: insight))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .wakaCard()
                }

                VStack(alignment: .leading, spacing: WakaDesign.Spacing.tight) {
                    Text("How Insights Work").font(.wakaSectionTitle)
                    Text("Insights are computed on this device from your normalized summaries. "
                         + "WakaBoard omits a claim rather than making one it cannot support.")
                        .font(.wakaCaption)
                        .foregroundStyle(.secondary)
                }
                .wakaCard()

                WakaTimeCredit(showsLink: false)
            }
        }
        .navigationTitle("Insights")
    }

    nonisolated static func sentence(for insight: Insight) -> String {
        switch insight {
        case .streak(let days):
            "You have coded at least 15 minutes on \(days) days in a row."
        case .strongestProject(let name, let share):
            "\(name) accounts for \(WakaAccessibility.sharePercentage(duration: share, total: 1)) of your time this period."
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

// MARK: - Settings

/// Account, data, and legal controls. Every button here does real work.
struct WakaSettingsView: View {
    @Environment(\.wakaFlatLayout) private var isFlat
    @Bindable var model: WakaUIModel
    @State private var confirmingSignOut = false
    @State private var confirmingClear = false

    var body: some View {
        Group {
            if isFlat {
                settingsContent
            } else {
                ScrollView { settingsContent }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign out of WakaBoard?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign Out and Erase", role: .destructive) { Task { await model.signOut() } }
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
            Button("Clear Cache", role: .destructive) { Task { await model.clearCache() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WakaBoard will refetch your analytics on the next refresh. You stay signed in.")
        }
    }

    /// Vertically grouped settings content shared by the live scroll view and snapshots.
    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.loose) {
            SettingsSection(title: "Account") {
                HStack {
                    Text("Connection").font(.wakaCardTitle)
                    Spacer()
                    Text(model.isSignedIn ? "Connected" : "Not connected")
                        .foregroundStyle(.secondary)
                }
                if model.isSignedIn {
                    WakaFormButton(
                        title: "Sign Out and Erase Local Data",
                        role: .destructive,
                        hint: "Removes your API key, cached analytics, and widget data from this device"
                    ) { confirmingSignOut = true }
                }
                Text("WakaBoard signs in with a personal API key stored in the system Keychain on this "
                     + "device only. It is never synced to iCloud and never included in a device backup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(title: "Data Source") {
                WakaTimeCredit()
                LegalLink(title: "Attribution and Credit", file: "ATTRIBUTION")
                Text("WakaBoard reads three WakaTime endpoints, all of them read-only, and stays well "
                     + "inside WakaTime's published rate limit. It uses no WakaTime logo or artwork.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(title: "Data") {
                WakaFormButton(title: "Refresh Analytics", hint: "Fetches the latest analytics from WakaTime") {
                    Task { await model.refresh() }
                }
                .disabled(model.isBusy)
                WakaFormButton(
                    title: "Clear Local Cache",
                    role: .destructive,
                    hint: "Deletes cached analytics from this device; you stay signed in"
                ) { confirmingClear = true }
                Text("Cached analytics are kept on this device for up to 90 days and are deleted "
                     + "automatically after that. Widget data is kept for up to 7 days.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(title: "Widgets") {
                Text("Add WakaBoard from the system widget gallery. Widgets read only the cached summary "
                     + "and never receive your API key. The system, not WakaBoard, decides when they refresh.")
            }

            SettingsSection(title: "Privacy and Legal") {
                Text("WakaBoard has no server, no telemetry, no advertising, and no crash-reporting SDK. "
                     + "The developer receives no data about you at all.")
                    .font(.footnote)
                LegalLink(title: "Privacy Policy", file: "PRIVACY")
                LegalLink(title: "Terms of Service", file: "TERMS")
                LegalLink(title: "Data Retention", file: "RETENTION")
                LegalLink(title: "Accessibility Statement", file: "ACCESSIBILITY")
                LegalLink(title: "Disclaimer and Liability", file: "DISCLAIMER")
            }

            SettingsSection(title: "About") {
                Text("WakaBoard is an independent open-source client. It is not affiliated with, "
                     + "endorsed by, or sponsored by WakaTime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Created by Kevin Le.")
                    .font(.footnote)
                WakaExternalLink(
                    title: "Kevin Le on GitHub",
                    url: URL(string: "https://github.com/kevinle3212"),
                    hint: "Opens Kevin Le's GitHub profile"
                )
                WakaExternalLink(
                    title: "Kevin Le on LinkedIn",
                    url: URL(string: "https://www.linkedin.com/in/lekevin1"),
                    hint: "Opens Kevin Le's LinkedIn profile"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WakaDesign.Spacing.regular)
    }
}

/// A Settings group whose heading, actions, and explanation stay in one visual unit.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    /// Creates one vertically grouped Settings section.
    ///
    /// - Parameters:
    ///   - title: The visible section heading.
    ///   - content: Controls and supporting copy belonging to the heading.
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.tight) {
            Text(title).font(.wakaSectionTitle)
            content
        }
        .wakaCard()
    }
}

// MARK: - Shared scaffolding

/// Renders a screen as a plain stack instead of a scroll view.
///
/// Set only by the snapshot suite. `ImageRenderer` lays a `ScrollView` out at its
/// full height and then draws none of its content, so a screenshot check that went
/// through the scroll view would silently produce blank images and pass. This is the
/// seam that lets the same view hierarchy be rasterized; nothing in the app sets it.
private struct WakaFlatLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Whether this screen should lay out flat rather than inside a scroll view.
    var wakaFlatLayout: Bool {
        get { self[WakaFlatLayoutKey.self] }
        set { self[WakaFlatLayoutKey.self] = newValue }
    }
}

/// The frame every data screen shares: load-state handling, the banner, an optional
/// pinned header, and consistent padding.
///
/// Extracted because three screens previously repeated the same nine-case `switch`
/// over the load state, and a state added to one of them silently rendered as a
/// blank screen in the other two.
struct WakaScreen<Header: View, Content: View>: View {
    @Environment(\.wakaFlatLayout) private var isFlat

    let model: WakaUIModel
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    init(model: WakaUIModel, @ViewBuilder header: () -> Header = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.model = model
        self.header = header()
        self.content = content()
    }

    var body: some View {
        if isFlat {
            stack
        } else {
            ScrollView { stack }
        }
    }

    private var stack: some View {
            VStack(alignment: .leading, spacing: WakaDesign.Spacing.loose) {
                header
                switch model.state {
                case .signedOut:
                    WakaStateView(title: "Not Connected", message: "Add your WakaTime API key to see your analytics.")
                case .credentialUnavailable(let message):
                    WakaStateView(
                        title: "Saved Sign-In Unavailable",
                        message: message,
                        actionLabel: "Try Again",
                        action: { Task { await model.start() } }
                    )
                case .loading:
                    ProgressView("Loading your analytics…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .accessibilityLabel(WakaAccessibility.stateLabel(.loading))
                case .expired:
                    WakaStateView(
                        title: "Reconnect WakaTime",
                        message: "WakaTime rejected your stored key. Sign in again to refresh analytics.",
                        actionLabel: "Sign Out",
                        action: { Task { await model.signOut() } }
                    )
                case .empty:
                    WakaStateView(
                        title: "No Activity Yet",
                        message: "No coding time is recorded for this period. Start coding and WakaBoard will show it here.",
                        actionLabel: "Refresh",
                        action: { Task { await model.refresh() } }
                    )
                case .failed(let message):
                    WakaStateView(
                        title: "Couldn't Load Analytics",
                        message: message,
                        actionLabel: "Retry",
                        action: { Task { await model.refresh() } }
                    )
                case .stale(let reason):
                    WakaBanner(
                        message: reason,
                        icon: "wifi.exclamationmark",
                        spokenLabel: WakaAccessibility.stateLabel(model.state)
                    )
                    content
                case .rateLimited:
                    WakaBanner(
                        message: "Refresh paused at WakaTime's request. Your saved data is still shown.",
                        icon: "clock.badge.exclamationmark",
                        spokenLabel: WakaAccessibility.stateLabel(model.state)
                    )
                    content
                case .loaded:
                    content
                }
            }
            .padding(WakaDesign.Spacing.regular)
    }
}

/// The period picker, shared by every screen that offers one.
struct PeriodPicker: View {
    @Bindable var model: WakaUIModel

    var body: some View {
        WakaSegmentedPicker(
            label: "Analytics period",
            hint: "Changes the period shown on every screen",
            options: RangeOption.allCases,
            title: \.accessibleName,
            selection: $model.selectedRange
        )
    }
}

/// The Refresh control, which every data screen carries in the same place.
struct RefreshToolbarItem: ToolbarContent {
    let model: WakaUIModel

    var body: some ToolbarContent {
        ToolbarItem {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .disabled(model.isBusy)
                .accessibilityHint("Loads the latest available analytics from WakaTime")
        }
    }
}
