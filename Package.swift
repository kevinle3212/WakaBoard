// swift-tools-version: 6.2
import PackageDescription

/// Strict settings applied to every target.
///
/// Warnings are errors so a warning cannot accumulate into noise that hides the
/// next real one, and the upcoming-feature flags opt in to the stricter Swift 7
/// semantics now rather than discovering them at migration time.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "WakaBoard",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "WakaCore", targets: ["WakaCore"]),
        .library(name: "WakaUI", targets: ["WakaUI"])
    ],
    targets: [
        .target(name: "WakaCore", swiftSettings: strictSettings),
        .target(name: "WakaUI", dependencies: ["WakaCore"], swiftSettings: strictSettings),
        .testTarget(name: "WakaCoreTests", dependencies: ["WakaCore"], swiftSettings: strictSettings),
        .testTarget(name: "WakaUITests", dependencies: ["WakaUI", "WakaCore"], swiftSettings: strictSettings)
    ]
)
