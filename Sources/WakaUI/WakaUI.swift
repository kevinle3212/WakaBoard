import Charts
import Observation
import SwiftUI
import WakaCore

/// Presentation-only state used by previews and the app shell.
public struct WakaDashboard: Sendable {
    public var todayMinutes: Int
    public var weekMinutes: Int
    public var activeDays: Int
    public var topProject: String?
    public var topLanguage: String?
    public var dailyMinutes: [Int]

    public init(todayMinutes: Int = 0, weekMinutes: Int = 0, activeDays: Int = 0,
                topProject: String? = nil, topLanguage: String? = nil, dailyMinutes: [Int] = []) {
        self.todayMinutes = todayMinutes; self.weekMinutes = weekMinutes; self.activeDays = activeDays
        self.topProject = topProject; self.topLanguage = topLanguage; self.dailyMinutes = dailyMinutes
    }

    public static let fixture = WakaDashboard(todayMinutes: 187, weekMinutes: 1_064, activeDays: 5,
                                                topProject: "WakaBoard", topLanguage: "Swift",
                                                dailyMinutes: [90, 140, 0, 220, 187, 205, 222])
}

public enum WakaLoadState: Sendable { case loading, loaded, empty, offline, stale, expired, rateLimited, failed(String) }

@MainActor @Observable public final class WakaUIModel {
    public var dashboard: WakaDashboard = .fixture
    public var state: WakaLoadState = .loaded
    public var selectedRange = "7D"
    public init() {}
    public func refresh() { state = .loaded }
}

public struct MetricCard: View {
    let title: String; let value: String; let detail: String
    public init(title: String, value: String, detail: String) { self.title = title; self.value = value; self.detail = detail }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

public struct WakaDashboardView: View {
    @Bindable var model: WakaUIModel
    public init(model: WakaUIModel) { self.model = model }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch model.state {
                case .loading: ProgressView("Loading your analytics…").frame(maxWidth: .infinity, minHeight: 180)
                case .expired: WakaStateView(title: "Reconnect WakaTime", message: "Your session expired. Sign in again to refresh analytics.", action: "Open Settings")
                case .offline, .stale: WakaStateView(title: "Showing cached data", message: "Refresh when you are back online. Cached analytics remain available.", action: "Refresh")
                case .rateLimited: WakaStateView(title: "Refresh paused", message: "WakaTime asked us to wait. Your cached data is still available.", action: "Try later")
                case .failed(let message): WakaStateView(title: "Couldn’t load analytics", message: message, action: "Retry")
                case .empty: WakaStateView(title: "No activity yet", message: "Start coding and WakaBoard will show your first summary.", action: "Learn more")
                case .loaded: loaded
                }
            }.padding()
        }.navigationTitle("Overview")
            .toolbar { ToolbarItem { Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh).accessibilityHint("Loads the latest available analytics") } }
    }
    private var loaded: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) { Text("Today").font(.headline); Text(duration(model.dashboard.todayMinutes)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit(); Text("Coding time").foregroundStyle(.secondary) }
                .accessibilityElement(children: .combine).accessibilityLabel("Today, \(duration(model.dashboard.todayMinutes)) of coding time")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) {
                MetricCard(title: "This week", value: duration(model.dashboard.weekMinutes), detail: "Calendar week")
                MetricCard(title: "Active days", value: "\(model.dashboard.activeDays)", detail: "Days with activity")
                MetricCard(title: "Top project", value: model.dashboard.topProject ?? "—", detail: "By coding time")
                MetricCard(title: "Top language", value: model.dashboard.topLanguage ?? "—", detail: "Usage, not proficiency")
            }
            ActivityChart(minutes: model.dashboard.dailyMinutes)
        }
    }
    private func duration(_ minutes: Int) -> String { minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m" }
}

public struct ActivityChart: View {
    let minutes: [Int]
    public init(minutes: [Int]) { self.minutes = minutes }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily activity").font(.headline)
            Chart(Array(minutes.enumerated()), id: \.offset) { index, value in
                BarMark(x: .value("Day", index + 1), y: .value("Minutes", value)).foregroundStyle(.tint)
            }.frame(height: 160).chartYAxisLabel("Minutes")
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine).accessibilityLabel("Daily activity. \(summary)")
    }
    private var summary: String { minutes.isEmpty ? "No activity recorded." : "\(minutes.reduce(0, +)) minutes across \(minutes.filter { $0 > 0 }.count) active days." }
}

public struct WakaStateView: View {
    let title: String; let message: String; let action: String
    public init(title: String, message: String, action: String) { self.title = title; self.message = message; self.action = action }
    public var body: some View { ContentUnavailableView { Label(title, systemImage: "chart.bar.xaxis") } description: { Text(message) } actions: { Button(action) {}.buttonStyle(.borderedProminent).frame(minHeight: 44) } }
}

public enum WakaRoute: String, CaseIterable, Identifiable { case overview = "Overview", activity = "Activity", projects = "Projects", languages = "Languages", insights = "Insights", settings = "Settings"; public var id: Self { self }; var icon: String { switch self { case .overview: "square.grid.2x2"; case .activity: "chart.xyaxis.line"; case .projects: "folder"; case .languages: "chevron.left.forwardslash.chevron.right"; case .insights: "lightbulb"; case .settings: "gearshape" } } }

private extension WakaRoute {
    init(_ deepLink: DeepLink) {
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

private struct RankedUsage: Identifiable {
    let usage: Usage
    let total: TimeInterval
    var id: String { usage.id }
    var percentage: Int { total > 0 ? Int((usage.duration / total * 100).rounded()) : 0 }
}

private let sampleProjects = [
    Usage(name: "Example API", duration: 28_140),
    Usage(name: "Mobile App", duration: 19_320),
    Usage(name: "Website", duration: 12_360),
    Usage(name: "Long Project Name for Accessibility", duration: 7_500)
]

private let sampleLanguages = [
    Usage(name: "Swift", duration: 31_560),
    Usage(name: "TypeScript", duration: 18_600),
    Usage(name: "Markdown", duration: 9_000),
    Usage(name: "JSON", duration: 4_680)
]

private struct UsageListView: View {
    let title: String
    let subtitle: String
    let usage: [Usage]
    let icon: String

    private var total: TimeInterval { usage.reduce(0) { $0 + $1.duration } }

    var body: some View {
        List(usage.map { RankedUsage(usage: $0, total: total) }) { item in
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(item.usage.name, systemImage: icon).lineLimit(1)
                    Spacer()
                    Text(DurationFormatter().string(item.usage.duration)).monospacedDigit()
                }
                ProgressView(value: item.usage.duration, total: max(total, 1))
                    .accessibilityLabel("\(item.usage.name), \(item.percentage) percent of selected activity")
                Text("\(item.percentage)% of selected activity").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(title)
        .safeAreaInset(edge: .top) {
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 8)
                .background(.bar)
        }
    }
}

private struct WakaActivityView: View {
    @Bindable var model: WakaUIModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Period", selection: $model.selectedRange) {
                    Text("7D").tag("7D"); Text("30D").tag("30D"); Text("3M").tag("3M")
                }.pickerStyle(.segmented).accessibilityHint("Changes the analytics period")
                ActivityChart(minutes: model.dashboard.dailyMinutes)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Consistency").font(.headline)
                    Text("\(model.dashboard.activeDays) active days this week")
                    Text("A coding day requires at least 15 minutes. This is a WakaBoard calculation, not a WakaTime metric.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding().background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }.padding()
        }.navigationTitle("Activity")
    }
}

private struct WakaInsightsView: View {
    let model: WakaUIModel
    var body: some View {
        List {
            Section("Recent insights") {
                Label("You coded \(duration(model.dashboard.weekMinutes)) this week.", systemImage: "calendar")
                Label("\(model.dashboard.topLanguage ?? "No language") is your most-used language this week.", systemImage: "chevron.left.forwardslash.chevron.right")
                Label("\(model.dashboard.topProject ?? "No project") accounts for the largest share of selected time.", systemImage: "folder")
            }
            Section("How insights work") { Text("Insights are generated locally from normalized summaries. WakaBoard omits a claim when there is not enough comparison data.").font(.footnote) }
        }.navigationTitle("Insights")
    }
    private func duration(_ minutes: Int) -> String { DurationFormatter().string(TimeInterval(minutes * 60)) }
}

private struct WakaSettingsView: View {
    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Connection", value: "Not connected")
                Text("Production sign-in is designed for an OAuth relay because WakaTime documents a client secret and does not currently document PKCE. A personal API key is an advanced, Keychain-only development path.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Connect WakaTime") {}
            }
            Section("Data") {
                Button("Refresh analytics") {}
                Button("Clear local cache", role: .destructive) {}
                Text("Cached analytics are stored locally. Credentials never enter the shared widget snapshot.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Widgets") { Text("Add WakaBoard from the widget gallery. Widgets open the relevant in-app screen and show only cached analytics.") }
            Section("Privacy") { Text("No telemetry, advertising SDKs, or crash-reporting SDKs are included.") }
        }.navigationTitle("Settings")
    }
}

public struct WakaShellView: View {
    @State private var model = WakaUIModel()
    @State private var selection: WakaRoute? = .overview
    public init() {}
    public var body: some View {
        NavigationSplitView { List(WakaRoute.allCases, selection: $selection) { route in Label(route.rawValue, systemImage: route.icon).tag(route) }.navigationTitle("WakaBoard") } detail: {
            Group {
                switch selection {
                case .overview: WakaDashboardView(model: model)
                case .activity: WakaActivityView(model: model)
                case .projects: UsageListView(title: "Projects", subtitle: "Sorted by selected coding time", usage: sampleProjects, icon: "folder")
                case .languages: UsageListView(title: "Languages", subtitle: "Usage time is not a measure of proficiency", usage: sampleLanguages, icon: "chevron.left.forwardslash.chevron.right")
                case .insights: WakaInsightsView(model: model)
                case .settings: WakaSettingsView()
                case nil: WakaStateView(title: "WakaBoard", message: "Choose a section to view cached analytics.", action: "Overview")
                }
            }
        }
        .onOpenURL { url in
            guard let link = DeepLink(url: url, scheme: "wakaboard") else { return }
            selection = WakaRoute(link)
        }
    }
}
