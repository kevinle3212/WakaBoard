# Architecture

## Context and targets

WakaBoard is a greenfield, independent Apple-platform analytics client for WakaTime. The local toolchain is Xcode 26.6, Swift 6.3.3, and macOS/iOS 26.5 SDKs. The initial deployment targets are iOS/iPadOS 18 and macOS 15: these provide Observation, Swift Charts, App Intents, and current WidgetKit while retaining a practical install base. Revisit before a public release.

The repository uses one XcodeGen specification and one local Swift package. XcodeGen is a development tool, not a runtime dependency. Production code uses Apple frameworks only.

## Module boundaries

- `WakaCore` — `Sendable` normalized models, duration/date formatting, analytics formulas, deterministic insights, deep links, API DTOs, request construction, error mapping, Keychain abstraction, versioned JSON cache, request coalescing, and widget snapshots.
- `WakaUI` — shared SwiftUI design system and feature views. It depends on `WakaCore`; it does not own networking or analytics formulas.
- `WakaBoardApp` — adaptive composition. iPhone uses tabs and `NavigationStack`; iPad and macOS use `NavigationSplitView`.
- `WakaBoardWidgets` — cached, credential-free WidgetKit presentation for Home Screen, desktop, and concise Lock Screen families.

Dependencies point inward: app/widgets → UI → core. Raw WakaTime DTOs stop at the repository boundary.

## Data flow

1. The app renders a cached `AnalyticsSnapshot` immediately.
2. `AnalyticsRepository` coalesces equivalent in-flight requests and applies a freshness policy.
3. `WakaTimeClient` requests only the required ranges and maps typed DTOs into normalized days.
4. `AnalyticsEngine` derives overview, shares, comparisons, streaks, and insights locally.
5. A versioned actor-backed JSON cache writes atomically. Authentication credentials remain in Keychain.
6. `WidgetSnapshotStore` is the App Group-only, credential-free handoff. The widget reads it now; the live repository-to-store write and targeted `WidgetCenter` reload are an explicit remaining integration gate.

The widget reads shared cached values and does not require credentials. Its timeline uses best-effort reload policies; Apple explicitly does not guarantee exact refresh times and applies per-widget budgets ([Apple: Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)).

## WakaTime integration

The first release integrates read-only resources documented at [WakaTime API Docs](https://wakatime.com/developers/):

- `GET /api/v1/users/current`
- `GET /api/v1/users/current/summaries?start=YYYY-MM-DD&end=YYYY-MM-DD`
- `GET /api/v1/users/current/stats/:range`
- `GET /api/v1/users/current/projects`

Summaries are the primary normalized source for daily/project/language/editor/OS activity. Stats supplements long-range aggregates and its `is_up_to_date`/202 behavior is honored. Heartbeats, write scopes, leaders, and organizations are out of scope.

## Time, cache, and analytics contracts

- Date query values are produced with the user-selected WakaTime timezone and Gregorian `yyyy-MM-dd`; calculations use an injected `Calendar` and timezone to survive DST.
- General daily average divides by calendar days. Active-day average is labeled separately.
- Percentage change is absent when the previous value is zero; the UI never renders infinity or a fabricated percentage.
- A streak day requires at least 15 minutes of coding. The threshold is a product convention, not a WakaTime metric.
- Consistency is labeled “Consistency score” and equals `100 × (1 - population standard deviation / mean)`, clamped to 0...100, for positive daily totals; insufficient samples return no score.
- Cache freshness is five minutes in the foreground and content remains usable when stale. Rate-limit retry timing honors `Retry-After`; only safe `GET` requests may retry.

## Configuration

Bundle IDs, App Group ID, callback scheme, and signing team use local/generated values. No owner signing identity or secret is committed. `Config/Local.xcconfig` is ignored; `Config/Local.xcconfig.example` documents required non-secret values.

## Verification

- [x] `swift test` passes core logic, API decoding/error, cache, date/DST, and snapshot tests — verified 2026-08-27 (10 tests).
- [x] `xcodegen generate` produces the project from `project.yml` — verified 2026-08-27.
- [x] macOS and generic iOS Simulator app/widget schemes build with strict concurrency warnings treated as errors — verified 2026-08-27.
- [x] Source inspection finds no raw API DTO consumed by views and no credential in App Group persistence — verified 2026-08-27 by source and encoded-snapshot test.
- [ ] Device checks verify signing, App Group sharing, real WidgetKit scheduling, VoiceOver, and callback behavior.
