# WakaBoard code audit

**Audited:** 27–28 August 2026
**Subject:** The Codex-generated scaffold, commit `031bd50` (`chore: baseline scaffold as generated`)
**Scope:** All Swift sources, tests, build configuration, CI, and documentation.
**Method:** Full manual read of all 1,130 lines of Swift; toolchain verification
(`swift test`, `xcodegen generate`, `xcodebuild` on both platforms); and an on-device
pass — the macOS app launched on real hardware with its live accessibility tree
audited, the iOS bundle installed and launched on a Simulator, and real authenticated
HTTPS requests made to `api.wakatime.com`.

Every finding below was **fixed** in this change unless explicitly marked otherwise.
Line references are to the audited baseline; the "Fix" line names where the
correction now lives.

---

## Summary

The generated code was well-organised, correctly layered, and largely well-documented.
Its problem was not structure but **completeness of the claim it made**: the
architecture documents, the security plan, and the README all described controls and
behaviour that no code implemented. Ten of eleven `GATES.md` boxes were checked; the
app itself did not work — and, as the on-device pass later showed, could not even be
installed.

| Severity | Count | Theme |
|---|---|---|
| **Critical** | 3 | The app displayed fabricated data, could not be installed, and sent a malformed auth header |
| **High** | 6 | Documented rate limiting, retention, and logout did not exist |
| **Medium** | 8 | Transport, Keychain, and decode-boundary hardening gaps |
| **Low** | 5 | Force-unwraps, dead surface, hygiene |

---

## Critical

### C1 — The shipped app displayed invented coding statistics

`Sources/WakaUI/WakaUI.swift:29` set `dashboard = .fixture`, and
`Sources/WakaUI/WakaUI.swift:33` defined `refresh()` as `{ state = .loaded }` — a
function that changed a state flag and loaded nothing. `Sources/WakaUI/WakaUI.swift:127`
and `Sources/WakaUI/WakaUI.swift:134` hard-coded `sampleProjects` and `sampleLanguages`,
which the Projects and Languages screens rendered directly
(`Sources/WakaUI/WakaUI.swift:237`).

`AnalyticsRepository`, `KeychainCredentialStore`, `WidgetSnapshotStore`, and
`WakaTimeClient` were all written and tested — and never called. No composition root
existed to connect them.

The consequence is not cosmetic. Built and submitted, WakaBoard would have presented
fabricated numbers to users as their own coding activity, and every Settings control
(`Sources/WakaUI/WakaUI.swift:214`, `:217`, `:218`) was an empty `{}` closure.

**Fix:** `Sources/WakaCore/Environment.swift` adds the missing composition root.
`Sources/WakaUI/WakaUIModel.swift` replaces the placeholder with a model that loads
through the repository and maps every outcome to a real state. Verified by
`Tests/WakaUITests/LiveDataPathTests.swift` (6 tests) and enforced permanently by
`scripts/audit-checks.mjs no-fixture-leak`, which fails the build if fixture data is
referenced from shipping code again.

### C2 — Every request sent a malformed `Authorization` header

`Sources/WakaCore/Networking.swift:60` interpolated the credential directly:

```swift
request.setValue("Basic \(authorization)", forHTTPHeaderField: "Authorization")
```

Two defects in one line. A WakaTime personal API key must be **base64-encoded** to be
a valid `Basic` credential; it was sent raw. And `AuthenticationMethod`
(`Sources/WakaCore/Security.swift:113`) distinguished `personalAPIKey` from `oauth`,
then `Credentials` (`Sources/WakaCore/Security.swift:20`) collapsed both into one
untagged `String` — so an OAuth bearer token would also have been sent as `Basic`,
authenticating nothing and leaking the token into a server-side malformed-auth log.

**Fix:** `Credential` in `Sources/WakaCore/Networking.swift` is a tagged enum whose
`authorizationHeaderValue` encodes each kind correctly and cannot be bypassed.
Keychain storage is tagged to match, so a key can never be replayed as a token.
Verified by `Tests/WakaCoreTests/SecurityTests.swift` (`Authorization`, 4 tests).

### C3 — The app could not be installed on any device or simulator

`Config/WakaBoardWidgets-Info.plist:25` declared `NSExtensionPrincipalClass`, injected
by `project.yml:116` and `project.yml:135` for both widget targets. That key is
**forbidden** for the `com.apple.widgetkit-extension` extension point — a WidgetKit
extension's entry point is the SwiftUI `@main WidgetBundle`.

`installd` rejects the bundle outright:

```
Appex bundle ... with id org.wakaboard.app.widgets defines either an
NSExtensionMainStoryboard or NSExtensionPrincipalClass key, which is not
allowed for the extension point com.apple.widgetkit-extension
```

The app therefore could not be installed on a simulator, on a device, or through the
App Store — while compiling cleanly on both platforms and passing every unit test.
The original `GATES.md` checked "XcodeGen app, shared WakaUI, and widget targets" on
the strength of `xcodebuild` succeeding, which is exactly the gap: a build proves
compilation, not installability.

**Fix:** the key is removed from both widget targets in `project.yml`. Verified by
`sh scripts/device-check.sh`, which installs and launches on a Simulator and fails if
installation is rejected.

---

## High

### H1 — No rate limiting existed, despite being documented

`docs/planning/SECURITY.md` promised "Retry only idempotent GETs with a small bounded
backoff and cancellation support." No such code existed.
`Sources/WakaCore/Networking.swift:123` parsed `Retry-After` into a value that was
then **discarded** — mapped into an error case and never acted on. Nothing bounded
the client's request rate, so a refresh loop or widget reload storm could produce
abusive traffic and get the user's own WakaTime account throttled.

**Fix:** `Sources/WakaCore/RateLimiting.swift` adds a `TokenBucket` throttle and a
`RetryPolicy` with bounded exponential backoff and full jitter, integrated into
`WakaTimeClient.send`. Only retryable categories are retried; `401` deliberately is
not. Verified by `Tests/WakaCoreTests/RateLimitingTests.swift` (9 tests).

### H2 — `Retry-After` parsing accepted hostile values

`Sources/WakaCore/Networking.swift:123` used bare `TimeInterval.init` on the header.
That accepts `-5` (retry immediately, in a tight loop), accepts `999999999` (hang for
32 years), and returns `nil` for the RFC 9110 HTTP-date form, which is a legal and
commonly emitted representation.

**Fix:** `RetryAfter.parse` in `Sources/WakaCore/RateLimiting.swift` handles both
forms, clamps to `0...300`, and bounds the header length. Verified by the `RetryAfter`
suite.

### H3 — The published retention policy was not enforced anywhere

`docs/planning/SECURITY.md` claimed "bounded history" and "explicit clear/logout
deletion". The cache in `Sources/WakaCore/CacheRepository.swift:40` never pruned
anything, and the widget snapshot at `Sources/WakaCore/CacheRepository.swift:24` was
returned at any age — so a widget could display a months-old figure as current.

**Fix:** `RetentionPolicy` in `Sources/WakaCore/CacheRepository.swift` defines the
window; pruning runs on read *and* write; `WidgetSnapshotStore.load` discards and
erases an expired snapshot. `RETENTION.md` documents it, and a test asserts document
and code agree. Verified by `Tests/WakaCoreTests/RetentionTests.swift` (7 tests).

### H4 — There was no logout, and no way to erase local data

`SECURITY.md` listed "Logout removes Keychain credentials and private cache" as a
release gate. No such code path existed; the Settings buttons were empty closures.

**Fix:** `WakaEnvironment.signOut()` in `Sources/WakaCore/Environment.swift` erases the
credential, the cache, and the widget snapshot, credential first, continuing through
failures so a partial sign-out cannot leave a usable key beside cleared data. Wired to
a confirmation dialog in Settings.

### H5 — The widget's App Group handoff was never performed

`docs/planning/ARCHITECTURE.md` described `WidgetSnapshotStore` as the handoff
boundary and noted the write was "an explicit remaining integration gate". Nothing
ever called `store(_:)`, so `Widgets/WakaBoardWidgets/WakaBoardWidgets.swift:32` always
fell through to its placeholder. `Widgets/WakaBoardWidgets/WakaBoardWidgets.swift:37`
also passed `dailyMinutes: []` unconditionally, so the weekly widget's bar row was
structurally empty.

**Fix:** `WakaUIModel.publishWidgetSnapshot()` writes the snapshot and reloads
timelines after every successful load. `WidgetSnapshot` gained a bounded 7-value daily
series. Verified by `LiveDataPathTests.publishesWidgetSnapshot`.

### H6 — Widget "today" was computed in the wrong timezone

Found while writing the tests for H5, not in the original read. `WidgetSnapshot.init(days:generatedAt:)`
defaulted to `Calendar.current`, but days are normalized in the user's *WakaTime*
timezone. For any user whose device timezone differs from their WakaTime timezone, the
widget's "today" total silently included or excluded the wrong day.

**Fix:** `WakaUIModel.publishWidgetSnapshot()` passes a calendar set to the data's
timezone. Caught by `LiveDataPathTests.publishesWidgetSnapshot` failing on a real
assertion.

---

## Medium

### M1 — `URLSession.shared` leaked private analytics to the on-disk URL cache

`Sources/WakaCore/Networking.swift:12` defaulted to the shared session: a shared cookie
store, a shared on-disk URL cache, and no timeout override. A user's project names and
coding hours were written into `~/Library/Caches` and survived app termination.

**Fix:** `URLSessionHTTPClient.makeSession()` builds an ephemeral session with no URL
cache, cookies disabled, a TLS 1.2 floor, and 20/45-second timeouts. Verified by
`TransportTests.sessionIsHardened`.

### M2 — Response bodies were unbounded

`Sources/WakaCore/Networking.swift:16` buffered the entire body into memory with no
ceiling.

**Fix:** `URLSessionHTTPClient.validateSize` rejects over 8 MB, checking both the
declared `Content-Length` and the received size so a lying header is not a bypass.

### M3 — Decoded values could poison every downstream calculation

`Sources/WakaCore/Models.swift:14` clamped with `max(0, duration)`. `max(0, .nan)`
evaluates to `.nan`, because every comparison against NaN is false — so a non-finite
value passed straight through into every mean, ratio, streak, and chart axis. Nothing
bounded day counts, bucket counts, or name lengths either.

**Fix:** `ResponseBounds` in `Sources/WakaCore/Networking.swift` rejects non-finite
values at the decode boundary and bounds durations, names, day counts, and bucket
counts. `ActivityDay.sanitized` handles the clamp correctly. Verified by the
`Untrusted` suite (6 tests).

### M4 — The Keychain used the legacy file-based keychain on macOS

`Sources/WakaCore/Security.swift:57` omitted `kSecUseDataProtectionKeychain`, so on
macOS the store silently used the legacy keychain, where the
`kSecAttrAccessible` value set at `Sources/WakaCore/Security.swift:51` is ignored.

**Fix:** the flag is set on every query in `KeychainCredentialStore.baseQuery`.

### M5 — Accessibility was applied on update but not on create

`Sources/WakaCore/Security.swift:49` ran `SecItemUpdate` with only
`kSecValueData`, so an item created by an earlier build kept its original
accessibility class forever.

**Fix:** `kSecAttrAccessible` is included in the update attributes as well as the add
path, and tightened from `AfterFirstUnlockThisDeviceOnly` to
`WhenUnlockedThisDeviceOnly`.

### M6 — Every Keychain failure collapsed to one error

`Sources/WakaCore/Security.swift:44` mapped every `OSStatus` to `.unavailable`, making
"never signed in", "device locked", and "keychain corrupt" indistinguishable — so the
UI could not tell the user which had happened.

**Fix:** `KeychainError` distinguishes `malformedItem`, `interactionNotAllowed`, and
`unhandled(status:)`.

### M7 — A failed OAuth callback left the pending session reusable

`Sources/WakaCore/Security.swift:104` cleared `pending` only after successful
validation, so an attacker could probe state values repeatedly against a live session.

**Fix:** `OAuthCallbackValidator.consume` burns the session before validating, and
state comparison is constant-time. Verified by `OAuthTests.failureBurnsSession`.

### M8 — The cache file was created with the process umask

`Sources/WakaCore/CacheRepository.swift:61` used `.completeFileProtectionUnlessOpen`,
which is a no-op on macOS. On a shared Mac the file could be world-readable, exposing
the user's coding history to another account.

**Fix:** `JSONCache.restrictPermissions` sets `0600` explicitly. Verified by
`CacheTests.filePermissions`.

---

## Low

### L1 — Force-unwraps in shipping code

`Sources/WakaCore/Analytics.swift:87` force-unwrapped `calendar.date(byAdding:)`, and
`Sources/WakaCore/Models.swift:118` force-unwrapped `URL(string:)`.

**Fix:** both replaced with graceful fallbacks; `DeepLink.url(scheme:)` now returns
`URL?`. Enforced permanently by `scripts/audit-checks.mjs hygiene`.

### L2 — Three of four endpoints were unreachable

`Sources/WakaCore/Networking.swift:37` defined `currentUser`, `stats`, and `projects`;
only `summaries` had a client method.

**Fix:** `verifyCredential` uses `currentUser` at sign-in. `stats` and `projects`
remain defined and tested but unused — retained deliberately, since the endpoint
construction is the security-relevant part and is covered by the host-allowlist tests.

### L3 — The `stats` range was under-validated

`Sources/WakaCore/Networking.swift:50` allowed any letter or number, including non-ASCII,
with no length bound.

**Fix:** restricted to ASCII alphanumerics plus `_` and `-`, length-bounded. Verified
by `TransportTests.statsRangeIsConstrained`.

### L4 — `LICENSE` was a truncated stub

The file contained only the Apache header and the boilerplate appendix notice — the
entire body, all nine sections including the copyright and patent grants, was missing.
An Apache-2.0 project that does not ship the licence text is not correctly licensed.

**Fix:** the full 202-line canonical text, with the appendix copyright filled in, plus
a `NOTICE` file. Verified by `scripts/audit-checks.mjs license`.

### L5 — Unused preview fixtures shipped in the library

`Sources/WakaCore/Fixtures.swift:4` defined `WakaFixtures`, referenced by nothing.

**Fix:** deleted.

---

## Found during on-device verification

These were **not** in the audited baseline. They are defects in the remediation
itself, or claims the remediation made that hardware disproved. They are listed
separately because presenting them as scaffold defects would be dishonest.

### D1 — A locked or unreadable Keychain was reported as "not signed in"

`WakaUIModel.start()` and `.refresh()` read the credential with `try?`, discarding the
`KeychainError` the hardened store had just been taught to distinguish. A locked
device, a corrupt item, or a missing entitlement all presented as `signedOut`, sending
the user to re-enter a key that would fail to save for the same underlying reason.

Surfaced while attempting to seed a credential on this Mac, where the data-protection
Keychain returned `errSecMissingEntitlement` (`-34018`) for an ad-hoc-signed binary.

**Fix:** `WakaLoadState.credentialUnavailable` is a distinct state with its own copy
and its own recovery action, and `storedCredential()` no longer collapses the two
cases. Verified by two regression tests in `Tests/WakaUITests/LiveDataPathTests.swift`.

### D2 — Two controls had hit targets far below the documented 44-point minimum

The unit suite asserted the constant was 44 and that it was *referenced* in the view
layer. Both were true. The live accessibility tree showed a `Link` rendering a
**16-point** target and a `SecureField` a **24-point** one, because `.frame(minHeight:)`
does not size either control.

**Fix:** `WakaExternalLink` replaces every `Link` with a `Button` that owns its frame.
Verified continuously by `scripts/ax-audit.swift`, which reads the real tree rather
than the source.

### D3 — A macOS text field's accessibility height is not author-controllable

Measured, not assumed: the `SecureField` reports a 16-point accessibility height
regardless of `.frame(height:)`, surrounding padding, or `.controlSize(.extraLarge)`.
The element AX exposes is AppKit's inner text control.

This is the WCAG 2.2 SC 2.5.8 "user agent control" exception, and SC 2.5.8's own
minimum is 24×24 rather than Apple's touch-oriented 44. It is reported by the audit
script as a named **exemption** with its reason, so the exception stays visible in the
output rather than being silently excluded.

### D4 — Hardening the Keychain made sign-in impossible

The most serious defect in the remediation, reported by Kevin: pasting a key and
pressing Connect appeared to do nothing.

Adding `kSecUseDataProtectionKeychain: true` unconditionally was correct on iOS and
wrong on macOS. That keychain requires an entitlement granted by a provisioning
profile; a locally-signed or ad-hoc build does not carry it. Measured on this machine:

```
dataProtection=true   SecItemAdd -> -34018   (errSecMissingEntitlement)
dataProtection=false  SecItemAdd -> 0
```

The failure chain: the key verified against WakaTime, `save()` threw, the generic
`catch` blamed the network ("check your connection"), `state = .failed` made
`isSignedIn` true so the shell swapped to the dashboard, whose `.task` re-read the
Keychain, failed again, and swapped straight back to sign-in. Visually: nothing.

**Fix:** `KeychainCredentialStore` now tries the data-protection keychain first and
falls back to the legacy keychain on `errSecMissingEntitlement`, so a provisioned
build still gets the stronger store. Sign-out deletes from both. Verified by
`Tests/WakaCoreTests/RealKeychainTests.swift`, which exercises the **real** system
keychain rather than a double — no test against a double could have caught this.

### D5 — A failed sign-in was expressed as a load state

`signIn()` reported failure by setting `state = .failed`, but `isSignedIn` treats
every state except `signedOut` as signed in, so the sign-in screen was replaced by
the dashboard the moment sign-in failed.

**Fix:** a dedicated `signInError` property, leaving `state` alone. Sign-in failures
now stay on the sign-in screen with a message that distinguishes a rejected key from
a storage failure. Four regression tests.

### D6 — Signing out of the sidebar made the app look broken

While signed out, every sidebar row rendered the sign-in form, so Settings was
unreachable and the sidebar appeared inert.

**Fix:** Settings is always reachable; other data screens show a "Not connected"
state with an action that returns to Overview.

### D7 — Three Settings buttons and the period picker had sub-44pt targets

Found once a real credential made those screens reachable to the audit. The Settings
buttons were 24pt — `.frame(minHeight:)` does not size a `Button` any more than it
sizes a `Link`. `WakaFormButton` pads the label instead, measured at 44pt.

The segmented picker is 28pt and stays that way: AppKit owns it. It passes WCAG 2.2
AA (24×24) and is recorded as an exemption, not silently ignored.

---

## Not defects, but worth recording

- **`.swiftpm/` was mode `0777`** (world-writable) in the working tree. Not a code
  defect and not tracked, but corrected.
- **The project was not under version control at all.** No `.git` directory existed,
  so nothing in the scaffold was recoverable. Initialized with the baseline committed
  first, so this audit's changes are reviewable as a diff.
- **`tmp/` held 13 `DerivedData-*` directories.** Gitignored, so harmless, but worth
  clearing.
- **`GATES.md` claimed more than it proved.** "Cached placeholders contain no private
  data" was verified by "source scan found only fictional fixture names" — true, but it
  passed *because* the app showed fixtures, which was the actual defect. A gate that
  passes for the wrong reason is worse than an unmet one.

---

## What remains open

The on-device pass, a real credential, and an authenticated round trip have closed
most of this. What is genuinely still unverified:

1. **No physical iOS or iPadOS device.** Kevin's iPhone 17 Pro and iPad Air (M3) are
   registered but were offline. iOS is verified on the Simulator: it installs,
   launches, and stays running. That is not hardware, and it cannot show a Lock Screen
   widget or real WidgetKit scheduling.
2. **No provisioning-profile build.** Xcode has no signed-in account, so the
   **App Group entitlement grant remains unverified**. On macOS the handoff is
   confirmed working through the shared `UserDefaults` suite — the snapshot is written
   after every fetch and contains five aggregate fields and no credential — but that
   works because a non-sandboxed app can reach the suite without the entitlement. A
   sandboxed or App Store build needs the real grant.
3. **VoiceOver speech, Dynamic Type, and contrast are not human-reviewed.** The
   accessibility tree of all six screens is audited automatically; how it sounds, and
   how it renders at accessibility text sizes, is a human judgement not yet made.
4. **No independent security audit.** The threat model remains self-assessed.
5. **The authenticated suite is slow.** `LiveAuthenticated` took ~82 seconds against
   the live API. It passed well inside the 20-second per-request timeout, so this is
   WakaTime's own latency for computing summaries, not a client defect — but it is
   worth knowing before wiring it into anything time-sensitive.
