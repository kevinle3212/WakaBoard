# Testing

WakaBoard separates pure analytics contracts, boundary behavior, rendered UI states,
and live-system checks so that a passing unit suite does not overstate what it proves.
The default `swift test` run is offline and uses no stored credential.

## Source-to-Test Coverage

| Production contract | Primary automated evidence |
|---|---|
| Active-day share, peak and median days, calendar normalization, duplicate dates, zero and hostile values | `AdditionalAnalyticsTests` |
| Calendar-week totals, partial weeks, sparse periods, and daylight-saving boundaries | `AdditionalAnalyticsTests` |
| Stable bounded per-dimension trends, missing buckets, ties, Unicode, and every dimension | `AdditionalAnalyticsTests` |
| Period changes clear old figures and late responses cannot overwrite the newest selection | `LiveDataPathTests.latestRangeWinsRefreshRace` |
| Model derivations use fetched summaries and clear on sign-out | `LiveDataPathTests` |
| Figure summaries carry real values and honest empty-state language | `AccessibilityTests.additionalAnalyticsAlternatives` |
| New figures render loaded, empty, and boundary data at compact accessibility sizing | `SnapshotTests.rendersAdditionalAnalyticsStates` |
| Every data screen renders across compact, regular, and wide widths, two Dynamic Type sizes, and light/dark appearances | `SnapshotTests.rendersEveryScreen` and `scripts/snapshot-check.sh` |
| Chart framing, direct summaries, design tokens, casing, accessibility structure, and lazy rendering | `scripts/audit-checks.mjs` |
| Every Apple app and widget target compiles with warnings treated as errors | `scripts/build-all.sh` |

## Verification Boundaries

`swift test` exercises deterministic logic, mocked transport, cache and credential
boundaries, view-model transitions, accessibility copy, and macOS `ImageRenderer`
snapshots. Live WakaTime checks are opt-in and require the corresponding environment
flag. Signing, App Group behavior under a provisioning profile, physical-device
WidgetKit behavior, and human VoiceOver, contrast, and visual-quality review remain
separate release gates in `TODO.md` and `GATES.md`.
