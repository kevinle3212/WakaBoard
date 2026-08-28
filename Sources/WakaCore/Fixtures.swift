import Foundation

/// Non-personal sample data for previews and deterministic tests.
public enum WakaFixtures {
    public static let referenceTimeZone = TimeZone(identifier: "America/Los_Angeles")!
    public static let activeWeek: [ActivityDay] = [
        ActivityDay(date: Date(timeIntervalSince1970: 1_736_208_000), duration: 10_800, projects: [Usage(name: "Orbit Compiler", duration: 7_200)], languages: [Usage(name: "Swift", duration: 9_000)]),
        ActivityDay(date: Date(timeIntervalSince1970: 1_736_294_400), duration: 7_200, projects: [Usage(name: "Signal Garden", duration: 5_400)], languages: [Usage(name: "TypeScript", duration: 4_800)])
    ]
}
