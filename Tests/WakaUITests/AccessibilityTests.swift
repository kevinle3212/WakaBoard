import Foundation
import Testing
import WakaCore
@testable import WakaUI

/// Assertions behind the conformance claim in `ACCESSIBILITY.md`.
///
/// These cover the parts a unit test can decide: that every state and every data
/// row produces a spoken label, that the chart has a text alternative carrying its
/// actual content, and that the declared hit-target constant meets the standard.
/// Traversal order, contrast rendering, and real VoiceOver behavior remain manual
/// device checks, and `ACCESSIBILITY.md` says so rather than implying otherwise.
@Suite("Accessibility")
struct AccessibilityTests {
    @Test("the hit-target constant meets both WCAG 2.2 and Apple's guidance")
    func targetSize() {
        // WCAG 2.2 SC 2.5.8 requires 24×24; Apple's HIG requires 44×44. The stricter
        // of the two is what the views actually apply.
        #expect(WakaAccessibility.minimumTargetSize >= 44)
    }

    @Test("every load state has a spoken label that is not empty or a raw enum name")
    func everyStateIsSpoken() {
        let states: [WakaLoadState] = [
            .signedOut, .loading, .loaded, .empty,
            .stale(reason: "Cached."), .rateLimited(retryAfter: 30),
            .expired, .failed("Network unavailable.")
        ]
        for state in states {
            let label = WakaAccessibility.stateLabel(state)
            #expect(!label.isEmpty)
            // A label must be a sentence, not a leaked identifier.
            #expect(!label.contains("("))
            #expect(label.first?.isUppercase == true)
            #expect(label.hasSuffix(".") || label.hasSuffix("!"))
        }
    }

    @Test("the chart carries its content as text, not just a description of itself")
    func chartHasTextAlternative() {
        // SC 1.1.1: the alternative must convey the same information, so the numbers
        // have to appear in it.
        let summary = WakaAccessibility.chartSummary(durations: [3_600, 0, 7_200])
        #expect(summary.contains("3h"))
        #expect(summary.contains("2 with activity"))
        #expect(summary.contains("Busiest day"))

        // Degenerate inputs still produce a usable sentence rather than "0m across 0 days".
        #expect(WakaAccessibility.chartSummary(durations: []) == "No activity recorded in this period.")
        #expect(WakaAccessibility.chartSummary(durations: [0, 0]).contains("No activity"))
    }

    @Test("additional analytics state their values and handle empty input honestly")
    func additionalAnalyticsAlternatives() {
        let peak = AnalyticsEngine.DailyValue(date: .now, duration: 7_200)
        let summary = AnalyticsEngine.ActivitySummary(
            dayCount: 7,
            activeDayCount: 4,
            activeShare: 4.0 / 7.0,
            peak: peak,
            medianDuration: 1_800
        )
        let balance = WakaAccessibility.activityBalanceSummary(summary)
        #expect(balance.contains("4 of 7"))
        #expect(balance.contains("2h 0m"))
        #expect(balance.contains("30m"))
        #expect(WakaAccessibility.activityBalanceSummary(nil).contains("nothing recorded"))

        let weeks = [
            AnalyticsEngine.WeekTotal(start: .now, duration: 3_600, dayCount: 4, isPartial: true),
            AnalyticsEngine.WeekTotal(start: .now.addingTimeInterval(604_800), duration: 7_200, dayCount: 7, isPartial: false)
        ]
        let weekly = WakaAccessibility.weeklySummary(weeks)
        #expect(weekly.contains("2 calendar weeks"))
        #expect(weekly.contains("3h 0m"))
        #expect(weekly.contains("1 weeks cover"))

        let points = [
            AnalyticsEngine.TrendPoint(date: .now, name: "Ωmega", duration: 900, seriesIndex: 0),
            AnalyticsEngine.TrendPoint(date: .now, name: "Beta", duration: 300, seriesIndex: 1)
        ]
        let trend = WakaAccessibility.trendSummary(title: "Projects Trend", points: points)
        #expect(trend.contains("Ωmega"))
        #expect(trend.contains("15m"))
        #expect(trend.contains("Beta"))
        #expect(WakaAccessibility.trendSummary(title: "Projects Trend", points: []).contains("nothing recorded"))
    }

    @Test("data rows use compact percentages with units")
    func rowsAreSpoken() {
        let usage = WakaAccessibility.usageLabel(name: "Orbit Compiler", duration: 5_400, percentage: 42)
        #expect(usage == "Orbit Compiler, 1h 30m, 42% of the selected period")
        #expect(!usage.contains(" percent"))

        let share = WakaAccessibility.shareSummary(
            title: "Projects",
            usage: [Usage(name: "Orbit Compiler", duration: 5_400), Usage(name: "Other", duration: 3_600)]
        )
        #expect(share.contains("60%"))
        #expect(!share.contains(" percent"))

        let today = WakaAccessibility.todayLabel(duration: 3_660)
        #expect(today == "Today, 1h 1m of coding time")

        let metric = WakaAccessibility.metricLabel(title: "Streak", value: "4", detail: "Days over 15 minutes")
        #expect(metric == "Streak: 4. Days over 15 minutes.")
    }

    @Test("small genuine shares never read as zero")
    func smallSharesRemainVisible() {
        #expect(WakaAccessibility.sharePercentage(duration: 1, total: 1_000) == "<1%")
        #expect(WakaAccessibility.sharePercentage(duration: 0, total: 1_000) == "0%")
    }

    @Test("the range picker is spoken in words rather than as an abbreviation")
    func rangeLabels() {
        // "7D" is read as "seven dee". Every option carries a spoken name.
        for option in RangeOption.allCases {
            #expect(option.accessibleName.contains(" "))
            #expect(option.accessibleName != option.rawValue)
        }
        #expect(RangeOption.week.accessibleName == "Last 7 days")
    }

    @Test("insight sentences are complete and free of placeholder text")
    func insightSentences() {
        let sentences = [
            WakaInsightsView.sentence(for: .streak(days: 4)),
            WakaInsightsView.sentence(for: .strongestProject(name: "Orbit", share: 0.42)),
            WakaInsightsView.sentence(for: .consistency(score: 78))
        ]
        for sentence in sentences {
            #expect(sentence.hasSuffix("."))
            #expect(!sentence.contains("nil"))
            #expect(!sentence.contains("Optional"))
        }
        #expect(sentences[1].contains("42%"))
    }

    @Test("error copy never leaks request detail into what the user sees")
    func errorCopyIsSafe() {
        let errors: [WakaTimeError] = [
            .invalidEndpoint, .unauthenticated, .forbidden, .unavailable,
            .rateLimited(retryAfter: 30), .serviceUnavailable, .transport,
            .decoding, .responseTooLarge
        ]
        for error in errors {
            let message = WakaUIModel.message(for: error)
            #expect(!message.isEmpty)
            #expect(message.hasSuffix(".") || message.hasSuffix("!"))
            // Status codes, hosts, and header names belong in logs, not on screen or
            // in the screenshot a user attaches to a bug report.
            for leak in ["401", "403", "429", "500", "http", "wakatime.com/api", "Authorization", "Bearer", "Basic"] {
                #expect(!message.contains(leak))
            }
        }
    }

    @Test("an authentication failure routes to re-authentication, not a dead end")
    func failureRouting() {
        #expect(WakaUIModel.state(for: .unauthenticated, hasCachedData: false) == .expired)
        #expect(WakaUIModel.state(for: .rateLimited(retryAfter: 5), hasCachedData: false) == .rateLimited(retryAfter: 5))
        // With data on screen, a failure degrades to "stale" rather than blanking it.
        if case .stale = WakaUIModel.state(for: .transport, hasCachedData: true) {} else {
            Issue.record("a transport failure with cached data must degrade to stale")
        }
        if case .failed = WakaUIModel.state(for: .transport, hasCachedData: false) {} else {
            Issue.record("a transport failure with no cached data must surface as failed")
        }
    }
}
