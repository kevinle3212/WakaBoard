# WakaBoard

WakaBoard is an independent, open-source native analytics client for WakaTime for
macOS, iPhone, and iPad. It presents local-first coding summaries without treating
usage time as a measure of skill.

**There is no WakaBoard server.** Your device talks directly to WakaTime; the
developer receives no data about you at all. See [PRIVACY.md](PRIVACY.md).

> **Status: not yet released, and not yet verified on a physical device.**
> Everything below is covered by an automated test or a build on both platforms.
> Signing, App Group sharing, live WidgetKit scheduling, a real WakaTime API
> response, and an on-device VoiceOver pass are **not** yet verified — see
> [GATES.md](GATES.md) G20. Screenshots are pending for the same reason.

## What it does

- Dashboard, activity, projects, languages, insights, and settings, adaptive across
  macOS, iPhone, and iPad.
- Swift Charts activity view with a real text alternative for VoiceOver, accessible
  metric cards, and honest loading, empty, offline, rate-limited, and expired-auth
  states.
- Today, Weekly Activity, and Coding Overview widgets, fed by a credential-free App
  Group snapshot. Widgets never hold your API key.
- Analytics computed on-device: calendar and active-day averages, streaks, a
  consistency score, project and language shares, and insights that are omitted when
  there is not enough data to support them.
- Client-side rate limiting so the app cannot get your WakaTime account throttled.
- No runtime third-party dependencies, no telemetry, no advertising, no crash SDK.

## Requirements

iOS/iPadOS 18 or macOS 15. Built with Xcode 26.6 and Swift 6.3.3, under Swift 6
strict concurrency with warnings treated as errors.

## Architecture

`WakaCore` owns models, API DTOs and request construction, rate limiting, the
Keychain store, the versioned cache and repository, retention, analytics formulas,
and deep-link validation. `WakaUI` owns the SwiftUI presentation layer and the view
model. `WakaBoardApp` and `WakaBoardWidgets` are thin platform shells.
`WakaEnvironment` is the single composition root that assembles them, and the seam
tests substitute at.

Dependencies point inward: app and widgets → UI → core. Raw WakaTime DTOs stop at the
repository boundary. See [docs/planning/ARCHITECTURE.md](docs/planning/ARCHITECTURE.md).

## Build and test

1. Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
   (`brew install xcodegen`).
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` for local signing
   values. It is gitignored.
3. Generate and open the project:

   ```sh
   xcodegen generate
   open WakaBoard.xcodeproj
   ```

Run the suite — 66 tests, no network access, no credential required:

```sh
swift test
```

Build every shipping target on both platforms:

```sh
sh scripts/build-all.sh
```

Verify the acceptance ledger in [GATES.md](GATES.md):

```sh
node scripts/audit-checks.mjs --self-test   # prove the detectors can fail
node scripts/audit-checks.mjs legal         # and the rest, per GATES.md
```

CI runs all three on every push and pull request.

## Signing in

WakaBoard uses a **personal API key**, entered once and stored in the system
Keychain on that device only — never synced to iCloud, never in a device backup.
Get yours from [WakaTime account settings](https://wakatime.com/settings/account).

Settings → *Sign out and erase local data* removes the key, the cache, and the
widget snapshot.

**OAuth is not implemented, deliberately.** WakaTime documents an authorization-code
exchange requiring a client secret and does not document PKCE. A secret embedded in
an open-source binary is a public secret, so none is embedded; public OAuth would
need an operator-run relay that does not exist. The callback-validation types are
written and tested, but no runtime path reaches them. See
[SECURITY.md](SECURITY.md).

## Data and retention

| Data | Kept for |
|---|---|
| API key | Until you sign out |
| Cached analytics | 90 days, pruned automatically |
| Widget snapshot | 7 days, then discarded |

These numbers are enforced in code and asserted by a test, not just documented. See
[RETENTION.md](RETENTION.md).

## Documents

| | |
|---|---|
| [PRIVACY.md](PRIVACY.md) | What is stored, where, and the per-jurisdiction disclosures |
| [TERMS.md](TERMS.md) | Terms of service |
| [RETENTION.md](RETENTION.md) | Data retention policy, and how deletion works |
| [ACCESSIBILITY.md](ACCESSIBILITY.md) | WCAG 2.2 AA conformance status and known gaps |
| [DISCLAIMER.md](DISCLAIMER.md) | Warranty disclaimer and liability limits |
| [SECURITY.md](SECURITY.md) | Reporting, threat model, residual risks |
| [docs/AUDIT.md](docs/AUDIT.md) | Full audit of the generated scaffold |
| [GATES.md](GATES.md) | The acceptance ledger, including what is still open |

Contributions are welcome under [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Licence

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

WakaBoard uses the WakaTime API but is not affiliated with, endorsed by, or
sponsored by WakaTime. "WakaTime" is a trademark of its respective owner. WakaBoard
is likewise not affiliated with Apple Inc.

## Roadmap

In priority order: on-device verification (GATES.md G20), an audited OAuth relay or
native PKCE if WakaTime documents one, configurable project widgets, localization,
and an audio graph for the activity chart.
