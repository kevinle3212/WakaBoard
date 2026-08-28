# Gates: WakaBoard production readiness

OWNS: Sources/**, Apps/**, Widgets/**, Tests/**, Config/**, docs/**, scripts/**, .github/**, *.md, project.yml, Package.swift

Scope: Audit the Codex-generated scaffold, wire the live WakaTime data path end to
end, add client-side rate limiting, harden security, enforce data retention, and
publish real US/EU/Asia/ADA-compliant legal, privacy, accessibility, and liability
documents — with every outcome proven by a runnable check.

Derived from the original request: *"audit the whole codebase … make everything
production ready, ratelimiting, terms and conditions, accessibility/data retention
policies, legal compliance, liability, add in security, best practices, and strict"*,
plus the later addition *"add in Apache 2.0 LICENSE for this github project"*.

All `CHECK:` commands run under `/bin/sh` from the repository root and require the
Swift 6.3 toolchain, Xcode 26.6, XcodeGen, and Node 20+.

Test counts in `EXPECT:` were measured from an actual run and are recorded so that a
silently dropped test fails the gate rather than passing it.

---

- [x] G1: A severity-ranked audit of the generated code exists, every finding
      anchored to a `file:line` that resolves in the **audited** commit.
  CHECK: node scripts/audit-checks.mjs audit
  EXPECT: AUDIT_OK
  EVIDENCE: exit 0, `AUDIT_OK` — 2026-08-28. 21 anchors verified against commit `031bd50` via `git show`.

- [x] G2: No screen shipped to a user renders fabricated activity. Fixture data is
      reachable only from tests.
  CHECK: node scripts/audit-checks.mjs no-fixture-leak
  EXPECT: NO_FIXTURE_LEAK_OK
  EVIDENCE: exit 0 — 2026-08-28. Detector controlled by `--self-test`; caught the real leak in `Fixtures.swift` before it was removed.

- [x] G3: The app's view model loads real analytics through `AnalyticsRepository` and
      surfaces signed-out, loaded, expired, stale, and signed-out-again states from
      actual outcomes rather than assignment.
  CHECK: swift test --filter LiveDataPath 2>&1
  EXPECT: Test run with 12 tests in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-28. Found timezone defect H6, Keychain-error defect D1, and sign-in defects D4/D5 while being written.

- [x] G4: Outbound requests are rate limited client-side: a token-bucket throttle
      bounds request rate, and retries use bounded exponential backoff with jitter
      that honors `Retry-After` and retries only idempotent reads.
  CHECK: swift test --filter RateLimiting 2>&1
  EXPECT: Test run with 10 tests in 2 suites passed
  EVIDENCE: exit 0 — 2026-08-28.

- [x] G5: `Retry-After` parsing is hostile-input safe — it accepts delta-seconds and
      the RFC 9110 HTTP-date form, and clamps negative, absurd, and malformed values.
  CHECK: swift test --filter RetryAfter 2>&1
  EXPECT: Test run with 2 tests in 2 suites passed
  EVIDENCE: exit 0 — 2026-08-28.

- [x] G6: The `Authorization` header matches the credential kind — a personal API key
      is base64-encoded as `Basic`, and a bearer token is never sent as `Basic`.
  CHECK: swift test --filter Authorization 2>&1
  EXPECT: Test run with 4 tests in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-28. Closes audit finding C2.

- [x] G7: The HTTP transport is hardened: private analytics never touch the shared
      URL cache or cookie store, requests time out, and an oversized response body is
      rejected.
  CHECK: swift test --filter Transport 2>&1
  EXPECT: Test run with 5 tests in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-28.

- [x] G8: Credentials use the data-protection Keychain, carry device-only
      accessibility on create *and* update, and map OSStatus to distinguishable errors.
  CHECK: swift test --filter Keychain 2>&1
  EXPECT: Test run with 10 tests in 2 suites passed
  EVIDENCE: exit 0 — 2026-08-28. Now includes `RealKeychain`, which writes to the **actual** system keychain. A double could not have caught defect D4.

- [x] G9: The published retention policy is enforced in code: cached days past the
      window are pruned on read and write, and sign-out erases the credential, the
      cache, and the widget snapshot.
  CHECK: swift test --filter Retention 2>&1
  EXPECT: Test run with 7 tests in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-28. Includes an assertion that `RETENTION.md` and the code constants agree.

- [x] G10: Untrusted response fields cannot poison analytics — non-finite, negative,
      and impossible durations are rejected or clamped at the decode boundary, and
      names, day counts, and bucket counts are bounded.
  CHECK: swift test --filter Untrusted 2>&1
  EXPECT: Test run with 6 tests in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-28.

- [x] G11: Terms, Privacy, Retention, Accessibility, Disclaimer, and Security policies
      all exist, name a real contact and governing law, and carry no placeholder.
  CHECK: node scripts/audit-checks.mjs legal
  EXPECT: LEGAL_OK
  EVIDENCE: exit 0 — 2026-08-28. Six documents, contact `KevinLe3212@gmail.com`, governing law State of Oregon.

- [x] G12: The privacy documents make the disclosures each regime requires — GDPR,
      UK GDPR, CCPA/CPRA, PIPEDA, LGPD, PIPL, APPI, PIPA, PDPA, DPDP, Australian
      Privacy Act, ePrivacy, CRA, COPPA — with named rights and lawful basis.
  CHECK: node scripts/audit-checks.mjs compliance
  EXPECT: COMPLIANCE_OK
  EVIDENCE: exit 0 — 2026-08-28. Regime dates verified against primary sources on 2026-08-27.

- [x] G13: The accessibility statement claims WCAG 2.2 AA and EN 301 549, qualifies the
      claim as partial, and is backed by assertions over the code that produces spoken
      output.
  CHECK: node scripts/audit-checks.mjs accessibility
  EXPECT: ACCESSIBILITY_OK
  EVIDENCE: exit 0 — 2026-08-28. 8 assertions; oracle also verifies the view layer applies the target-size constant and honors Reduce Motion.

- [x] G14: Apple submission requirements are satisfied — a `PrivacyInfo.xcprivacy` for
      the app and the widget extension, both wired into the generated project, and the
      export-compliance key in both `Info.plist`s.
  CHECK: node scripts/audit-checks.mjs apple
  EXPECT: APPLE_OK
  EVIDENCE: exit 0 — 2026-08-28. Caught that XcodeGen regenerates the plists, so the key had to move into `project.yml`.

- [x] G15: The whole suite passes under Swift 6 strict concurrency with warnings as
      errors.
  CHECK: swift test 2>&1
  EXPECT: Test run with 83 tests in 20 suites passed
  EVIDENCE: exit 0 — 2026-08-28. Up from 10 tests in the audited baseline.

- [x] G16: Both shipping app targets and both widget extensions compile, on macOS and
      for the iOS Simulator, warnings as errors.
  CHECK: sh scripts/build-all.sh
  EXPECT: BUILD_ALL_OK
  EVIDENCE: exit 0 — 2026-08-28. Unsigned builds; signing is covered by G20.

- [x] G17: No committed secret, no force-unwrap in shipping code, and no
      world-writable path in the working tree.
  CHECK: node scripts/audit-checks.mjs hygiene
  EXPECT: HYGIENE_OK
  EVIDENCE: exit 0 — 2026-08-28. `.swiftpm/` corrected from `0777` to `0755`.

- [x] G18: CI enforces the bar it claims — it builds the app targets rather than only
      running `swift test`, pins actions by SHA, runs least-privilege, and gates on
      this ledger.
  CHECK: node scripts/audit-checks.mjs ci
  EXPECT: CI_OK
  EVIDENCE: exit 0 — 2026-08-28. Oracle follows through into `build-all.sh` rather than accepting a mention of it. **CI has not been executed on GitHub** — see G20.

- [x] G19: The project carries the complete, verbatim Apache-2.0 text with the
      copyright appendix filled in, plus a matching `NOTICE`.
  CHECK: node scripts/audit-checks.mjs license
  EXPECT: LICENSE_OK
  EVIDENCE: exit 0 — 2026-08-28. 202 lines fetched from apache.org; all 9 sections asserted present. The audited baseline shipped a truncated stub.

---

## On-device verification

- [x] G20: The macOS app launches on real hardware and its **live accessibility tree**
      — the one VoiceOver reads — contains, across **all six screens**, no unlabelled
      interactive control, nothing below the WCAG 2.2 AA 24pt minimum, and no
      author-sized control below 44pt; and the iOS bundle installs and launches on a
      Simulator.
  CHECK: sh scripts/device-check.sh
  EXPECT: DEVICE_CHECK_OK
  EVIDENCE: exit 0 — 2026-08-28. Ran on this Mac (macOS 26.x, Apple silicon) and
  Simulator `9FAFBA5A…` (iPhone 17 Pro, iOS 26.5). Found three real defects no compile
  or unit test caught: audit finding **C3** (a forbidden `NSExtensionPrincipalClass`
  made the app impossible to install anywhere), **D2** (a `Link` with a 16pt hit
  target), and **D1** (a locked Keychain reported as "not signed in"). Extended to
  drive the sidebar and audit every screen, which then found **D7** (three 24pt
  Settings buttons). Reports two documented WCAG 2.5.8 user-agent-control exemptions
  on every run.

- [x] G21: Real HTTPS requests reach the live WakaTime API and are mapped correctly,
      without needing a credential — a bogus key must produce a genuine `401`.
  CHECK: WAKABOARD_LIVE=1 swift test --filter LiveNetwork 2>&1
  EXPECT: Test run with 3 tests in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-28, against `api.wakatime.com`. Proves DNS, TLS 1.2+, the
  ephemeral session configuration, the host allowlist, endpoint paths, and 401 mapping
  end to end. Skipped by default so the suite stays hermetic and offline-runnable.

- [x] G23: A real WakaTime credential is stored, accepted by the live API, and the
      resulting analytics decode within bounds and produce a credential-free widget
      snapshot.
  CHECK: WAKABOARD_LIVE_AUTH=1 swift test --filter LiveAuthenticated 2>&1
  EXPECT: Test run with 3 tests in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-28, against `api.wakatime.com` with Kevin's own key. The
  first authenticated `200` this codebase has ever received. The app rendered real
  analytics (36h 41m across 7 days, 5 active) and wrote a 202-byte snapshot to the
  App Group suite containing exactly five aggregate fields and no credential.
  Assertions are structural only — no key, project name, or duration is printed.
  Took ~82s: WakaTime's own latency for computing summaries, well inside the
  20-second per-request timeout.

---

## Open gate

- [ ] G22: The parts of on-device verification that need hardware or provisioning this
      session did not have — a physical iPhone or iPad, a provisioning-profile build
      granting the App Group entitlement, Lock Screen widget families, real WidgetKit
      refresh cadence, and a human VoiceOver / Dynamic Type / contrast review.
  EVIDENCE: **not performed.**
  - Kevin's iPhone 17 Pro and iPad Air (M3) are registered but were **offline**; iOS
    was verified on the Simulator only, which cannot show a Lock Screen widget.
  - Xcode has **no signed-in account**, so automatic signing cannot mint a
    provisioning profile. The macOS widget handoff is confirmed working through the
    shared `UserDefaults` suite, but that succeeds because a non-sandboxed app reaches
    the suite without the entitlement — a sandboxed or App Store build needs the real
    grant, and that **remains unverified**.
  - VoiceOver speech, Dynamic Type at accessibility sizes, and contrast are human
    judgements that have not been made. The tree is audited; the experience is not.

ABANDON: G22 Requires a physical iOS device that was offline, an Xcode account able to
issue a provisioning profile, and human sensory review — none of which exist in this
session, and none of which can be substituted for. HANDOFF: Kevin must (1) sign into
Xcode so a profile can be issued and the App Group entitlement verified, (2) connect
an iPhone or iPad and install a signed build, (3) enable VoiceOver and the largest
Dynamic Type size and walk all six screens. Until then WakaBoard must not be described
as fully device-verified, and ACCESSIBILITY.md must keep its "partially conformant"
wording.

The gate is abandoned with a handoff rather than reworded into something the available
hardware could satisfy. What *was* reachable is not folded in here — it is proven
separately by G20, G21, and G23, which are real runnable checks.
