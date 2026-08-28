import SwiftUI
import WidgetKit
import WakaCore
import WakaUI

struct WakaWidgetEntry: TimelineEntry {
    let date: Date
    let todayMinutes: Int
    let weekMinutes: Int
    let topProject: String?
    let dailyMinutes: [Int]
    let placeholder: Bool
}

struct WakaWidgetProvider: TimelineProvider {
    private let snapshotStore = WidgetSnapshotStore(suiteName: "group.org.wakaboard.shared")

    func placeholder(in context: Context) -> WakaWidgetEntry {
        WakaWidgetEntry(date: .now, todayMinutes: 0, weekMinutes: 0, topProject: nil, dailyMinutes: [], placeholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WakaWidgetEntry) -> Void) {
        completion(snapshot(isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WakaWidgetEntry>) -> Void) {
        // WidgetKit selects refresh time; this is a best-effort request, not a guarantee.
        completion(Timeline(entries: [snapshot(isPlaceholder: false)], policy: .after(.now.addingTimeInterval(1_800))))
    }

    private func snapshot(isPlaceholder: Bool) -> WakaWidgetEntry {
        guard !isPlaceholder, let snapshot = snapshotStore.load() else {
            return WakaWidgetEntry(date: .now, todayMinutes: 0, weekMinutes: 0, topProject: nil, dailyMinutes: [], placeholder: true)
        }
        return WakaWidgetEntry(date: snapshot.generatedAt, todayMinutes: Int((snapshot.todayDuration / 60).rounded()),
                               weekMinutes: Int((snapshot.weekDuration / 60).rounded()), topProject: snapshot.topProject,
                               dailyMinutes: [], placeholder: false)
    }
}

private func duration(_ minutes: Int) -> String {
    minutes == 0 ? "—" : "\(minutes / 60)h \(minutes % 60)m"
}

private struct WidgetRoot<Content: View>: View {
    let route: String
    @ViewBuilder let content: Content

    var body: some View {
        content
            .widgetURL(URL(string: "wakaboard://open/\(route)"))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct TodayWidgetView: View {
    let entry: WakaWidgetEntry
    var body: some View {
        WidgetRoot(route: "overview") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.headline)
                Text(duration(entry.todayMinutes)).font(.title2.bold()).monospacedDigit()
                Text(entry.placeholder ? "Coding time" : "Cached coding time").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today: \(duration(entry.todayMinutes)) of coding time")
        }
    }
}

private struct WeekWidgetView: View {
    let entry: WakaWidgetEntry
    var body: some View {
        WidgetRoot(route: "activity") {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("This week").font(.headline); Spacer(); Text(duration(entry.weekMinutes)).font(.headline).monospacedDigit() }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(entry.dailyMinutes.enumerated()), id: \.offset) { _, minutes in
                        Capsule().fill(.tint).frame(maxWidth: .infinity).frame(height: max(5, CGFloat(minutes) / 8))
                    }
                }.frame(height: 32).accessibilityHidden(true)
                Text("Open activity in WakaBoard").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("This week: \(duration(entry.weekMinutes)) of coding time")
        }
    }
}

private struct OverviewWidgetView: View {
    let entry: WakaWidgetEntry
    var body: some View {
        WidgetRoot(route: "projects") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Coding overview").font(.headline)
                HStack {
                    VStack(alignment: .leading) { Text("Today").font(.caption).foregroundStyle(.secondary); Text(duration(entry.todayMinutes)).font(.title3.bold()).monospacedDigit() }
                    Spacer()
                    VStack(alignment: .trailing) { Text("Week").font(.caption).foregroundStyle(.secondary); Text(duration(entry.weekMinutes)).font(.title3.bold()).monospacedDigit() }
                }
                Divider()
                Label(entry.topProject ?? "No project data", systemImage: "folder").font(.caption).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coding overview. Today \(duration(entry.todayMinutes)); this week \(duration(entry.weekMinutes)); top project \(entry.topProject ?? "unavailable")")
        }
    }
}

struct WakaTodayWidget: Widget {
    let kind = "WakaTodayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakaWidgetProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today")
            .description("A cached view of today's coding time.")
            .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }
}

struct WakaWeekWidget: Widget {
    let kind = "WakaWeekWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakaWidgetProvider()) { WeekWidgetView(entry: $0) }
            .configurationDisplayName("Weekly activity")
            .description("Your cached weekly coding total and daily pattern.")
            .supportedFamilies([.systemMedium])
    }
}

struct WakaOverviewWidget: Widget {
    let kind = "WakaOverviewWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakaWidgetProvider()) { OverviewWidgetView(entry: $0) }
            .configurationDisplayName("Coding overview")
            .description("Today, this week, and your top cached project.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main struct WakaBoardWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WakaTodayWidget()
        WakaWeekWidget()
        WakaOverviewWidget()
    }
}
