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
    private let snapshotStore = WidgetSnapshotStore(suiteName: WakaIdentifiers.appGroup)

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
        return WakaWidgetEntry(
            date: snapshot.generatedAt,
            todayMinutes: Int((snapshot.todayDuration / 60).rounded()),
            weekMinutes: Int((snapshot.weekDuration / 60).rounded()),
            topProject: snapshot.topProject,
            dailyMinutes: snapshot.dailyDurations.map { Int(($0 / 60).rounded()) },
            placeholder: false
        )
    }
}

private func duration(_ minutes: Int) -> String {
    minutes == 0 ? "—" : "\(minutes / 60)h \(minutes % 60)m"
}

/// Which families each widget offers, per platform.
///
/// A watch has no home-screen grid, so it gets complication families only; a
/// television has no WidgetKit at all and so has no widget target. Listing a family
/// a platform does not have is not a warning — it is a widget that silently never
/// appears in the gallery.
private enum Families {
    static var today: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
        #elseif os(iOS)
        [.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        #else
        [.systemSmall]
        #endif
    }

    /// The larger families, which exist only where there is a home screen to put them on.
    static var wide: [WidgetFamily] {
        #if os(watchOS)
        []
        #else
        [.systemMedium]
        #endif
    }

    static var tall: [WidgetFamily] {
        #if os(watchOS)
        []
        #else
        [.systemMedium, .systemLarge]
        #endif
    }
}

private struct WidgetRoot<Content: View>: View {
    let route: DeepLink
    @ViewBuilder let content: Content

    var body: some View {
        content
            .widgetURL(route.url(scheme: WakaIdentifiers.urlScheme))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WakaWidgetEntry

    var body: some View {
        WidgetRoot(route: .overview) {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Today: \(duration(entry.todayMinutes)) of coding time, measured by WakaTime")
        }
    }

    @ViewBuilder private var content: some View {
        // The accessory families exist only where there are complications or a Lock
        // Screen to put them on. Naming one on a platform that has no such family is
        // a compile error, not a warning, which is why these cases are conditional
        // rather than merely unreachable.
        switch family {
        #if os(iOS) || os(watchOS)
        case .accessoryInline:
            Text("Coding \(duration(entry.todayMinutes))")
        case .accessoryCircular:
            AccessoryCircularToday(minutes: entry.todayMinutes)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Today").font(.caption2).foregroundStyle(.secondary)
                Text(duration(entry.todayMinutes)).font(.headline).monospacedDigit()
                Text(entry.topProject ?? "No project data").font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCircularToday(minutes: entry.todayMinutes)
        #endif
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.headline)
                Text(duration(entry.todayMinutes)).font(.title2.bold()).monospacedDigit()
                Text(entry.placeholder ? "Coding time" : "Cached coding time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Via WakaTime").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The circular complication face: a glyph over today's total.
private struct AccessoryCircularToday: View {
    let minutes: Int

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.caption2)
            Text(duration(minutes)).font(.caption2).monospacedDigit().minimumScaleFactor(0.6)
        }
    }
}

private struct WeekWidgetView: View {
    let entry: WakaWidgetEntry

    var body: some View {
        WidgetRoot(route: .activity) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("This Week").font(.headline)
                    Spacer()
                    Text(duration(entry.weekMinutes)).font(.headline).monospacedDigit()
                }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(entry.dailyMinutes.enumerated()), id: \.offset) { _, minutes in
                        Capsule().fill(.tint).frame(maxWidth: .infinity).frame(height: max(5, CGFloat(minutes) / 8))
                    }
                }
                .frame(height: 32)
                .accessibilityHidden(true)
                Text("Coding time measured by WakaTime.").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("This week: \(duration(entry.weekMinutes)) of coding time, measured by WakaTime")
        }
    }
}

private struct OverviewWidgetView: View {
    let entry: WakaWidgetEntry

    var body: some View {
        WidgetRoot(route: .breakdown) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Coding Overview").font(.headline)
                HStack {
                    VStack(alignment: .leading) {
                        Text("Today").font(.caption).foregroundStyle(.secondary)
                        Text(duration(entry.todayMinutes)).font(.title3.bold()).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Week").font(.caption).foregroundStyle(.secondary)
                        Text(duration(entry.weekMinutes)).font(.title3.bold()).monospacedDigit()
                    }
                }
                Divider()
                Label(entry.topProject ?? "No project data", systemImage: "folder").font(.caption).lineLimit(1)
                Text("Measured by WakaTime.").font(.caption2).foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coding overview, measured by WakaTime. Today \(duration(entry.todayMinutes)); this week \(duration(entry.weekMinutes)); top project \(entry.topProject ?? "unavailable")")
        }
    }
}

struct WakaTodayWidget: Widget {
    let kind = "WakaTodayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakaWidgetProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today")
            .description("A cached view of today's coding time, measured by WakaTime.")
            .supportedFamilies(Families.today)
    }
}

struct WakaWeekWidget: Widget {
    let kind = "WakaWeekWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakaWidgetProvider()) { WeekWidgetView(entry: $0) }
            .configurationDisplayName("Weekly Activity")
            .description("Your cached weekly coding total and daily pattern, measured by WakaTime.")
            .supportedFamilies(Families.wide)
    }
}

struct WakaOverviewWidget: Widget {
    let kind = "WakaOverviewWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakaWidgetProvider()) { OverviewWidgetView(entry: $0) }
            .configurationDisplayName("Coding Overview")
            .description("Today, this week, and your top cached project, measured by WakaTime.")
            .supportedFamilies(Families.tall)
    }
}

@main struct WakaBoardWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WakaTodayWidget()
        // The wide families do not exist on a watch, and a widget with no supported
        // family cannot be installed. Only Today is offered there.
        #if !os(watchOS)
        WakaWeekWidget()
        WakaOverviewWidget()
        #endif
    }
}
