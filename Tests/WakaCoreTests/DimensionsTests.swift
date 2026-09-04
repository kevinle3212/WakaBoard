import Foundation
import Testing
@testable import WakaCore

/// One day of the real summaries shape, with every bucket list WakaTime documents.
private let fullDayJSON = """
{"data":[{"range":{"date":"2026-08-20"},"grand_total":{"total_seconds":7200},
"projects":[{"name":"WakaBoard","total_seconds":5400},{"name":"dotfiles","total_seconds":1800}],
"languages":[{"name":"Swift","total_seconds":5400},{"name":"Other","total_seconds":1800}],
"editors":[{"name":"Xcode","total_seconds":6000},{"name":"Vim","total_seconds":1200}],
"operating_systems":[{"name":"Mac","total_seconds":7200}],
"categories":[{"name":"Coding","total_seconds":6300},{"name":"Debugging","total_seconds":900}],
"dependencies":[{"name":"Foundation","total_seconds":100}],
"machines":[{"name":"laptop","total_seconds":7200}]}]}
"""

/// The same day as written by a WakaTime account that has produced none of the
/// newer buckets — the lists are absent rather than empty.
private let sparseDayJSON = """
{"data":[{"range":{"date":"2026-08-20"},"grand_total":{"total_seconds":600},
"projects":[{"name":"WakaBoard","total_seconds":600}],
"languages":[{"name":"Swift","total_seconds":600}]}]}
"""

@Suite("Decoding the extra dimensions")
struct DimensionDecodingTests {
    private func decode(_ json: String) throws -> [ActivityDay] {
        try JSONDecoder()
            .decode(WakaTimeSummariesResponse.self, from: Data(json.utf8))
            .normalized(timeZone: .gmt)
    }

    @Test("editors, operating systems, and categories reach the model")
    func decodesEveryDimension() throws {
        let day = try #require(try decode(fullDayJSON).first)
        #expect(day.editors.map(\.name) == ["Xcode", "Vim"])
        #expect(day.operatingSystems.map(\.name) == ["Mac"])
        #expect(day.categories.map(\.name) == ["Coding", "Debugging"])
        #expect(day.editors.first?.duration == 6_000)
    }

    @Test("a response missing the newer buckets still loads the ones it has")
    func toleratesAbsentBuckets() throws {
        let day = try #require(try decode(sparseDayJSON).first)
        #expect(day.projects.count == 1)
        #expect(day.editors.isEmpty)
        #expect(day.operatingSystems.isEmpty)
        #expect(day.categories.isEmpty)
    }

    @Test("project normalization drops unused rows and restores path separators")
    func normalizesProjectRows() throws {
        let json = """
        {"data":[{"range":{"date":"2026-08-20"},"grand_total":{"total_seconds":30},
        "projects":[
          {"name":"Users-kevinkhanhle","total_seconds":30},
          {"name":"never-touched","total_seconds":0},
          {"name":"waka-board","total_seconds":1}
        ]}]}
        """

        let projects = try #require(try decode(json).first).projects
        #expect(projects.map(\.name) == ["/Users/kevinkhanhle", "waka-board"])
        #expect(projects.map(\.duration) == [30, 1])
    }

    @Test("the new buckets are bounded exactly like the old ones")
    func boundsApplyToEveryDimension() throws {
        // An absurd duration and an oversized name must be clamped in an editor
        // bucket for the same reason they are in a project bucket: every one of them
        // reaches a chart axis and a list row.
        let hostile = """
        {"data":[{"range":{"date":"2026-08-20"},"grand_total":{"total_seconds":60},
        "editors":[{"name":"\(String(repeating: "e", count: 400))","total_seconds":999999999}]}]}
        """
        let day = try #require(try decode(hostile).first)
        #expect(day.editors.first?.name.count == ResponseBounds.maximumNameLength)
        #expect(day.editors.first?.duration == ResponseBounds.maximumDailySeconds)
    }

    @Test("every dimension resolves to its own bucket list")
    func dimensionLookup() throws {
        let day = try #require(try decode(fullDayJSON).first)
        #expect(ActivityDimension.projects.usage(in: day).count == 2)
        #expect(ActivityDimension.editors.usage(in: day).count == 2)
        #expect(ActivityDimension.operatingSystems.usage(in: day).count == 1)
        #expect(ActivityDimension.categories.usage(in: day).count == 2)
        // Every dimension needs a Title Cased heading and a sentence explaining it,
        // or a screen built from one renders a blank header.
        for dimension in ActivityDimension.allCases {
            #expect(!dimension.title.isEmpty)
            #expect(dimension.explanation.hasSuffix("."))
        }
    }
}

@Suite("Analytics derivations")
struct AnalyticsDerivationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Ten consecutive days starting Monday 2026-08-03, an hour of coding per day
    /// except the two weekend days, which are empty.
    private var days: [ActivityDay] {
        let start = Date(timeIntervalSince1970: 1_785_715_200) // Monday 2026-08-03, 00:00 GMT
        return (0 ..< 10).map { offset in
            let date = start.addingTimeInterval(Double(offset) * 86_400)
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 7
            return ActivityDay(date: date, duration: isWeekend ? 0 : 3_600)
        }
    }

    private var range: ActivityRange {
        ActivityRange(start: days[0].date, end: days[9].date, timeZone: .gmt)
    }

    @Test("weekday totals carry the day count, so the mean is not a lie")
    func weekdayTotalsCountTheirDays() throws {
        let totals = AnalyticsEngine.weekdayTotals(days: days, range: range, calendar: calendar)
        #expect(totals.count == 7)
        // Ten days from a Monday holds two Mondays and one Thursday, so a raw total
        // would make Monday look twice as busy as Thursday when the mean is equal.
        let monday = try #require(totals.first(where: { $0.weekday == 2 }))
        let thursday = try #require(totals.first(where: { $0.weekday == 5 }))
        #expect(monday.dayCount == 2)
        #expect(thursday.dayCount == 1)
        #expect(monday.average == thursday.average)
    }

    @Test("the running total only ever grows and ends at the period total")
    func cumulativeIsMonotonic() {
        let running = AnalyticsEngine.cumulative(days: days)
        #expect(running.count == days.count)
        #expect(zip(running, running.dropFirst()).allSatisfy { $0.total <= $1.total })
        #expect(running.last?.total == days.reduce(0) { $0 + $1.duration })
    }

    @Test("the rolling mean averages the days that exist, not padded zeros")
    func rollingAverageDoesNotPad() {
        let rolling = AnalyticsEngine.rollingAverage(days: days, window: 7)
        // The first day's window holds one day, so its mean is that day, not a
        // seventh of it — padding would draw a rise that never happened.
        #expect(rolling.first?.average == 3_600)
        #expect(rolling.count == days.count)
    }

    @Test("density places each day on a week-by-weekday grid, and zero is not a colour")
    func densityGrid() {
        let cells = AnalyticsEngine.density(days: days, range: range, calendar: calendar)
        #expect(cells.count == days.count)
        #expect(cells.first?.weekIndex == 0)
        #expect(cells.last?.weekIndex == 1)
        // A day with no coding is absence, not a small amount.
        #expect(cells.filter { $0.duration == 0 }.allSatisfy { $0.intensity == 0 })
        #expect(cells.contains { $0.intensity == 1 })
    }

    @Test("an empty period produces no grid rather than an empty-looking one")
    func densityOfNothing() {
        #expect(AnalyticsEngine.density(days: [], range: range, calendar: calendar).isEmpty)
        #expect(AnalyticsEngine.cumulative(days: []).isEmpty)
        #expect(AnalyticsEngine.rollingAverage(days: []).isEmpty)
    }

    @Test("the tail folds into one named row instead of reusing a hue")
    func topBucketsFoldsTheTail() {
        let usage = (1 ... 10).map { Usage(name: "p\($0)", duration: Double(11 - $0) * 60) }
        let folded = AnalyticsEngine.topBuckets(usage, limit: 7)
        #expect(folded.top.count == 7)
        #expect(folded.remainder?.name == "3 More")
        #expect(folded.remainder?.duration == usage.suffix(3).reduce(0) { $0 + $1.duration })
        // Nothing is folded when everything fits, so a short list gains no phantom row.
        #expect(AnalyticsEngine.topBuckets(Array(usage.prefix(3)), limit: 7).remainder == nil)
    }

    @Test("ranking is stable and drops empty buckets")
    func rankingIsStable() {
        let day = ActivityDay(
            date: .now,
            duration: 120,
            editors: [Usage(name: "Zed", duration: 60), Usage(name: "Ant", duration: 60), Usage(name: "Idle", duration: 0)]
        )
        let ranked = AnalyticsEngine.ranked(.editors, in: [day])
        #expect(ranked.map(\.name) == ["Ant", "Zed"])
    }
}
