# WakaBoard

WakaBoard is an independent, open-source native analytics client for WakaTime.
It presents local-first coding summaries without treating usage time as a
measure of skill.

> Screenshots are intentionally pending: committed fixtures use fictional
> projects only, and no personal WakaTime activity is captured for this repo.

## What is in the foundation

- SwiftUI dashboard, activity, projects, languages, insights, and settings for
  macOS, iPhone, and adaptable iPad layouts.
- Swift Charts activity view, duration formatting, accessible metric cards,
  empty/offline/auth-expired states, and keyboard refresh command on macOS.
- Today, Weekly Activity, and Coding Overview widgets; iOS also has a concise
  Lock Screen Today family. Widgets render only cached aggregate values.
- Shared Swift `WakaCore` package for typed WakaTime summaries, normalized
  analytics, deterministic formulas, caching, deep links, and Keychain auth.
- No runtime third-party dependencies, telemetry, advertising, or crash SDKs.

## Platforms

The generated project targets iOS/iPadOS 18 and macOS 15. It was generated
with Xcode 26.6 and Swift 6.3.3. The supported platform choice permits modern
Swift Concurrency, Observation, Swift Charts, WidgetKit, and App Intents-era
widget families while keeping the surface small.

## Architecture

`WakaCore` owns API DTOs, normalized models, Keychain storage, cache and
repository policy, analytics formulas, and deep-link validation. `WakaUI`
contains feature-oriented SwiftUI presentation. The app and widget extensions
are thin platform shells. Widgets are deliberately credential-free; a future
App Group snapshot is the handoff boundary. See
[architecture](docs/planning/ARCHITECTURE.md).

## Build and test

1. Install a current Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` for local
   signing values; it is ignored by Git.
3. Generate and open the project:

   ```sh
   xcodegen generate
   open WakaBoard.xcodeproj
   ```

4. Run the core suite without real WakaTime requests:

   ```sh
   swift test
   ```

The CI workflow runs the same mock-only test suite and regenerates the Xcode
project. It never receives WakaTime credentials.

## Authentication and widgets

WakaTime currently documents an authorization-code exchange requiring a client
secret and does not document PKCE. WakaBoard therefore does not embed a
pretend-secret: public OAuth requires a small operator-controlled relay. Until
one is deployed, the planned advanced personal API-key path is local-only and
Keychain-backed. Do not put a key in an `.xcconfig`, a widget configuration, or
source control. The full threat model is in [SECURITY.md](SECURITY.md).

After connecting an account in a future configured build, add WakaBoard from
the system widget gallery. Widgets are best-effort timelines—Apple, not the
app, schedules the actual refresh. They open the appropriate in-app route.

## Privacy, security, and contributing

Read [PRIVACY.md](PRIVACY.md) for the local-data and no-telemetry promise, and
[SECURITY.md](SECURITY.md) for reporting and the credential model. Contributions
are welcome under [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). The project is Apache-2.0 licensed.

WakaBoard uses the WakaTime API but is not affiliated with, endorsed by, or
sponsored by WakaTime. “WakaTime” is a trademark of its respective owner.

## Roadmap

Before a public release, the priority is an audited OAuth relay or documented
native PKCE alternative, App Group cache handoff, live repository wiring,
configurable project widgets, UI/device tests, and a real-device accessibility
review. Exact release gates live in [GATES.md](GATES.md).
