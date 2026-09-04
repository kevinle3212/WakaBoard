<h1 align="center">
  <img src="docs/assets/wakaboard-wordmark.png" alt="WakaBoard" width="440">
</h1>

WakaBoard is an independent, open-source native analytics client for WakaTime,
built for every Apple platform: Mac, iPhone, iPad, Apple Watch, Apple Vision Pro,
and Apple TV. It presents local-first coding summaries without treating usage time
as a measure of skill.

**Every underlying duration WakaBoard shows is measured and provided by WakaTime.**
WakaBoard derives clearly labelled summaries such as medians and calendar-week totals
on the device; it does not invent activity. See [ATTRIBUTION.md](ATTRIBUTION.md).

**There is no WakaBoard server.** Your device talks directly to WakaTime; the
developer receives no data about you at all. See [PRIVACY.md](PRIVACY.md).

> **Status: not yet released.** Verified further than a compile: all six platforms
> build with warnings as errors, the macOS app runs on real hardware with its live
> accessibility tree audited, the iOS bundle installs and launches on a Simulator,
> and real HTTPS requests reach `api.wakatime.com`. Signing in with a real key works,
> real analytics render, and the widget snapshot is written and verified
> credential-free.
> **Not** verified: watchOS, tvOS, and visionOS have never been *run* — their
> simulator runtimes are not installed, so those three are compile-verified only, and
> the watchOS build additionally excludes its asset catalog because `actool` needs a
> watchsimulator runtime. A physical iPhone or iPad, a provisioning-profile build (so
> the App Group entitlement grant is unproven), Lock Screen widgets, and a human
> VoiceOver / Dynamic Type / contrast review are all still outstanding — see
> [TODO.md](TODO.md). Automated render snapshots are committed; human visual review
> remains pending.

## What it does

- Overview, Activity, Breakdown, Insights, and Settings — a sidebar on Mac, iPad,
  iPhone, and Vision Pro; a compact stack on Apple Watch; a focusable tab bar on
  Apple TV. None of the three is a shrunk copy of the others.
- Nine analytical figures, each with a text alternative that carries the figure's
  content rather than describing it: daily activity with a seven-day mean, the
  Activity Ribbon density grid, active-day balance with peak and median days, a share
  ring, a ranked comparison chart, cumulative time, calendar-week totals, weekday
  averages, and bounded daily trends for the leading buckets in each dimension.
- Five dimensions behind one picker: projects, languages, editors, operating systems,
  and WakaTime's own activity categories.
- **What is actually inside "Other".** WakaTime files anything it cannot classify
  under `Other`; tapping that row opens a breakdown by file extension, reconstructed
  on demand from your own coding events and labelled as a reconstruction.
- A design token layer — one spacing scale, three radii, one type ramp, and a
  categorical chart palette validated for contrast and colour-vision deficiency in
  both light and dark rather than chosen by eye.
- Today, Weekly Activity, and Coding Overview widgets plus Apple Watch complications,
  fed by a credential-free App Group snapshot. Widgets never hold your API key.
- Analytics computed on-device: calendar and active-day averages, streaks, a
  consistency score, active-day balance, peak and median days, calendar-week totals,
  per-dimension shares and trends, and insights that are omitted when there is not
  enough data to support them.
- Client-side rate limiting so the app cannot get your WakaTime account throttled.
- No runtime third-party dependencies, no telemetry, no advertising, no crash SDK.

## Requirements

iOS/iPadOS 18, macOS 15, watchOS 11, tvOS 18, or visionOS 26. Built with the Xcode
26.5 SDKs and Swift 6.3.3, under Swift 6 strict concurrency with warnings treated as
errors.

visionOS is the one high floor, and not by choice: WidgetKit did not exist on
visionOS before 26, so a lower floor cannot carry the widget extension at all.

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

Run the suite — 137 tests, no network access or credential required:

```sh
swift test
```

Build every shipping target on every platform. macOS and iOS build for a real
destination; watchOS, tvOS, and visionOS build against their device SDKs, because
their simulator runtimes are not installed:

```sh
sh scripts/build-all.sh
```

Verify on real hardware — launches the macOS app, audits its live accessibility tree,
and installs on a Simulator (needs Accessibility permission for your terminal):

```sh
sh scripts/device-check.sh
```

Check the real API is reachable, without needing a credential:

```sh
WAKABOARD_LIVE=1 swift test --filter LiveNetwork
```

Check your *stored* key against the live API (sign in through the app first). Nothing
is printed but pass/fail — no key, project name, or duration:

```sh
WAKABOARD_LIVE_AUTH=1 swift test --filter LiveAuthenticated
```

Redraw the app icon and the README lockup (the art is generated, not exported —
edit the constants at the top of the script and rerun it):

```sh
python3 scripts/make-icon.py
```

Verify the acceptance ledger in [GATES.md](GATES.md):

```sh
node scripts/audit-checks.mjs --self-test   # prove the detectors can fail
node scripts/audit-checks.mjs legal         # and the rest, per GATES.md
```

CI runs the suite, both platform builds, a Simulator install, and every ledger check
on each push and pull request. The macOS accessibility audit is local-only: it needs
a GUI session with Accessibility permission, which CI runners do not have.

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
| [docs/TESTING.md](docs/TESTING.md) | Source-to-test coverage and verification boundaries |
| [ATTRIBUTION.md](ATTRIBUTION.md) | How WakaTime is credited, and the trademark position |
| [GATES.md](GATES.md) | The acceptance ledger for the current work |
| [docs/production-readiness-gates.md](docs/production-readiness-gates.md) | The closed ledger from the production-readiness audit |
| [TODO.md](TODO.md) | Deferred work only Kevin can unblock |

Contributions are welcome under [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Licence

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Attribution

WakaBoard uses the WakaTime public API but is not affiliated with, endorsed by, or
sponsored by WakaTime. "WakaTime" is a trademark of WakaTime, used here nominatively
to identify the service this client connects to. No WakaTime logo or artwork appears
anywhere in this project, and a repository check fails the build if one is added.
WakaBoard is likewise not affiliated with Apple Inc.

The full position — every endpoint read, how WakaTime's rate limit is respected, and
an honest note on the naming question their trademark policy raises — is in
[ATTRIBUTION.md](ATTRIBUTION.md).

## Roadmap

In priority order: the remaining on-device and human sensory verification
([TODO.md](TODO.md)), a tvOS Brand Assets icon, an audited OAuth relay or native PKCE
if WakaTime documents one, configurable project widgets, localization, and an audio
graph for the activity chart.
