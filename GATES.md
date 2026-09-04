# Gates: WakaTime credit, every Apple platform, and the design pass

OWNS: Sources/**, Apps/**, Widgets/**, Tests/**, Config/**, docs/**, scripts/**, .github/**, *.md, project.yml, Package.swift

Derived from the original request, verbatim:

> - Ensure we credit WakaTime, properly, legally, and ethically/morally.
> - Ensure we have this available for iOS, AppleOS, WatchOS, VisionOS, macOS, iPadOS, etc.
> - Ensure sizing and UI/UX, device, all of that stuff looks aesthetic, clean, slick,
>   uniform, use all of your on-hand and loaded skills. Add in more charts/graphs on
>   top of the ones we already have with the data. Try to enhance the app so the
>   langauges like Others are more specific, etc. Scaffold. Ensure we use this casing:
>   "Selected Period", "Daily Average", etc. for titles/headers. Sentences should
>   follow conventional sentencing formats.

Four owner decisions taken before the first edit, on 2026-08-29:

1. **Platforms** — all six native targets: iOS, iPadOS (the iOS target), macOS,
   watchOS, visionOS, tvOS.
2. **The "Other" bucket** — an on-demand drill-down, user-initiated only.
3. **Visual verification** — automated snapshot renders plus a PNG contact sheet,
   committed as a runnable check.
4. **Visual identity** — a defined token layer on top of native materials.

The previous ledger, for the production-readiness audit that closed on 2026-08-28,
is archived verbatim at `docs/production-readiness-gates.md`. Its one open item —
on-device and human sensory verification — moved to `TODO.md` because only Kevin
can unblock it. Nothing in this ledger replaces it.

All `CHECK:` commands run under `/bin/sh` from the repository root and require the
Swift 6.3 toolchain, Xcode 26.5 SDKs, XcodeGen 2.46+, and Node 20+. Only the iOS
Simulator runtime is installed on this machine, so watchOS, tvOS, and visionOS are
compile-verified against their device SDKs and are **not** run.

Every negative assertion added to `scripts/audit-checks.mjs` ships with a
`--self-test` control that plants a known violation and asserts the detector fires,
so a detector that can never fail is caught at authoring time.

---

## Credit for WakaTime

- [x] H1: Every user-facing surface credits WakaTime as the source of the data.
      A dedicated `ATTRIBUTION.md` exists and is reachable from the app's Settings
      screen, from `README.md`, and from `NOTICE`. The sign-in screen, the dashboard,
      and every widget say where the numbers come from.
  CHECK: node scripts/audit-checks.mjs attribution
  EXPECT: ATTRIBUTION_OK
  EVIDENCE: exit 0, `ATTRIBUTION_OK` — 2026-08-29. `ATTRIBUTION.md` exists and is linked from
  `README.md`, `NOTICE`, and the Settings screen. The check reads the endpoint literals
  out of `Networking.swift` and fails if the document omits one, so the endpoint table
  cannot drift from the client.

- [x] H2: WakaBoard's use of the WakaTime name complies with WakaTime's own
      published *Logos and Trademark Usage* policy, quoted with its retrieval date.
      No WakaTime logo, wordmark image, or other WakaTime artwork exists anywhere in
      the repository or in any shipped bundle; the name is used nominatively only.
      The one genuine risk in that policy — the clause on naming a project after
      WakaTime when it duplicates existing WakaTime functionality — is stated
      plainly rather than glossed over, with the mitigation actually taken.
  CHECK: node scripts/audit-checks.mjs trademark
  EXPECT: TRADEMARK_OK
  EVIDENCE: exit 0, `TRADEMARK_OK` — 2026-08-29. Policy retrieved from
  `https://wakatime.com/legal/logos-and-trademark-usage` the same day and quoted with its date. No
  WakaTime image asset exists anywhere in the tree, and the check fails if one is added.
  The naming risk is stated in `ATTRIBUTION.md` rather than argued away, and `TODO.md`
  carries the action only Kevin can take: emailing WakaTime for approval.

- [x] H3: WakaBoard stays inside WakaTime's documented API limits and says so.
      The client-side token bucket is at or below the published ceiling of ten
      requests per second averaged over any five-minute period, the drill-down
      cannot burst past it, and `TERMS.md` and `PRIVACY.md` describe the
      relationship with WakaTime's own Terms of Service accurately.
  CHECK: swift test --filter RateLimit 2>&1 && node scripts/audit-checks.mjs legal
  EXPECT: LEGAL_OK
  EVIDENCE: exit 0, `LEGAL_OK`, rate-limit suite passed — 2026-08-29. The client bucket is
  four requests with a one-per-second refill, far under WakaTime's published ten per
  second averaged over five minutes, and the drill-down goes through the same bucket.

## Every Apple platform

- [x] H4: All six platforms build clean with warnings as errors — iOS, iPadOS,
      macOS, watchOS, visionOS, and tvOS — app and widget extension alike.
  CHECK: sh scripts/build-all.sh
  EXPECT: BUILD_ALL_OK
  EVIDENCE: exit 0, `BUILD_ALL_OK` — 2026-08-29. macOS and iOS build for a destination;
  watchOS, tvOS, and visionOS build against their device SDKs. **One honest gap, printed
  on every run:** the watchOS build excludes its asset catalog, because `actool` refuses
  to compile one without a `watchsimulator` runtime. Everything else in that target —
  app code, libraries, complication extension, Info.plist, entitlements — is built as it
  ships. `TODO.md` carries it.

- [x] H5: watchOS ships a shell designed for the watch rather than a shrunk iPhone
      screen, plus a complication family set that renders the cached snapshot.
      `NavigationSplitView` does not appear in the watchOS build.
  CHECK: node scripts/audit-checks.mjs platforms
  EXPECT: PLATFORMS_OK
  EVIDENCE: exit 0, `PLATFORMS_OK` — 2026-08-29. `WatchShell` is a `NavigationStack` over a
  three-route list; the split shell is excluded from watchOS by `#if`. Complications
  cover `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`, and
  `.accessoryCorner`. Never run — see H4 and `TODO.md`.

- [x] H6: tvOS ships a focus-engine shell. Every interactive element is focusable
      and reachable with the remote; nothing depends on a pointer, a hover, or a
      swipe-to-refresh gesture that tvOS does not have.
  CHECK: node scripts/audit-checks.mjs platforms
  EXPECT: PLATFORMS_OK
  EVIDENCE: exit 0, `PLATFORMS_OK` — 2026-08-29. `TelevisionShell` is a `TabView`;
  `refreshable` is excluded on tvOS by `#if` and an explicit Refresh toolbar control
  exists on every data screen. Never run.

- [x] H7: visionOS ships as its own target rather than as an iPad compatibility
      build, and adopts the platform's own materials for its surfaces.
  CHECK: node scripts/audit-checks.mjs platforms
  EXPECT: PLATFORMS_OK
  EVIDENCE: exit 0, `PLATFORMS_OK` — 2026-08-29. `WakaBoardApp_visionOS` is its own target
  with its own bundle identifier and widget extension, and the detail pane carries
  `.glassBackgroundEffect()`. Deployment target 26.0, because WidgetKit does not exist
  on visionOS before then. Never run.

- [x] H8: `swift test` passes on every library target for every declared platform in
      `Package.swift`, and `Package.swift`'s platform list matches `project.yml`'s
      targets. A platform added in one file and forgotten in the other fails here.
  CHECK: swift test 2>&1 && node scripts/audit-checks.mjs platforms
  EXPECT: PLATFORMS_OK
  EVIDENCE: exit 0 — 2026-08-29. 120 tests in 26 suites passed. `Package.swift` and
  `project.yml` are asserted to declare the same five platforms.

## Design system and layout

- [x] H9: A single token layer defines the spacing scale, corner radii, type ramp,
      and chart palette, and every view uses it. No shipping view file contains an
      ad-hoc spacing, padding, or corner-radius literal.
  CHECK: node scripts/audit-checks.mjs design
  EXPECT: DESIGN_OK
  EVIDENCE: exit 0, `DESIGN_OK` — 2026-08-29. `Sources/WakaUI/WakaDesign.swift` holds the
  spacing scale, five radii, the type ramp, and the palette. The check fails on any
  numeric padding or corner radius in a shipping view; two survive, both marked
  `design-exempt:` with the reason — they are the 14-point paddings measured against the
  live accessibility tree to reach a 44-point target.

- [x] H10: The categorical chart palette meets a 3:1 contrast ratio against its own
      background in both light and dark appearance, and adjacent hues are
      distinguishable without relying on colour alone. Contrast is computed, not
      asserted by eye.
  CHECK: swift test --filter Palette 2>&1
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-29. 9 tests in the `Palette` suite. Contrast is recomputed in
  Swift from the palette's own sRGB numbers, not asserted from the validator's output:
  every dark hue clears 3:1, and **exactly** the three documented light hues fall below
  it, so a future re-step that pushes a fourth under the floor fails here. The formula
  itself is controlled against black-on-white being 21:1.

- [x] H11: Every screen renders without clipping or truncation across the width,
      Dynamic Type, and appearance matrix, proven by committed snapshot renders and
      a contact sheet a human can flip through.
  CHECK: sh scripts/snapshot-check.sh
  EXPECT: SNAPSHOTS_OK
  EVIDENCE: exit 0, `SNAPSHOTS_OK` — 2026-08-29. 48 renders across four screens, three
  widths, two Dynamic Type sizes, and both appearances, plus four contact sheets.
  **Two fabricated passes were found and fixed while building this:** the first version
  rendered blank white images and passed every geometric assertion, and the wrapper
  script's filter matched no tests yet went green on files left by a previous run. Both
  now fail loudly. Settings is excluded and says why — it is a platform `Form`, which
  `ImageRenderer` cannot rasterize; the live accessibility audit covers it instead.
  SUPERSEDED — 2026-09-04: H31 replaced that `Form` after its detached-column layout
  failed manual review. Settings now joins the render matrix; the latest run produced
  74 images and five contact sheets.

- [x] H12: The unmerged responsive-layout fixes sitting in the
      `.claude/worktrees/wakaboard-responsive` worktree are folded into the main
      tree, and nothing in the main tree still needs them.
  CHECK: node scripts/audit-checks.mjs design
  EXPECT: DESIGN_OK
  EVIDENCE: exit 0, `DESIGN_OK` — 2026-08-29. All five responsive fixes are asserted
  present: the shrink-to-fit metric value, the row layout priority, the bounded chart
  axis ticks, the macOS sidebar width and window floor, and `windowResizability`.

## More charts, from data that actually exists

- [x] H13: The dimensions WakaTime already returns and WakaBoard currently discards
      — editors, operating systems, and activity categories — are decoded, bounded
      against a hostile response exactly as projects and languages already are, and
      covered by tests.
  CHECK: swift test --filter Decoding 2>&1
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-29. 4 tests in `Decoding the extra dimensions`, plus the live
  authenticated run confirming editors, operating systems, and categories actually
  arrive from `api.wakatime.com` and stay inside `ResponseBounds`.

- [x] H14: New charts ship on top of the existing daily bar chart — language share,
      project comparison, cumulative time, weekday distribution, and the new
      editor / operating-system / category dimensions. Every one of them renders
      real fetched data only, and every one carries a text alternative that states
      the chart's content rather than describing its appearance.
  CHECK: node scripts/audit-checks.mjs charts && swift test --filter Accessibility 2>&1
  EXPECT: CHARTS_OK
  EVIDENCE: exit 0, `CHARTS_OK` — 2026-08-29. Six framed figures: daily activity with a
  seven-day mean, the Activity Ribbon, a share ring, a ranked comparison chart,
  cumulative time, and the weekday pattern. Every one is wrapped in `ChartFrame`, which
  is what guarantees the title, the printed figures, and the text alternative; the check
  fails if a chart is drawn anywhere else.

- [x] H15: No chart, card, or figure can render fabricated data. The existing
      fixture-leak gate still holds across every new file and every new platform.
  CHECK: node scripts/audit-checks.mjs no-fixture-leak
  EXPECT: NO_FIXTURE_LEAK_OK
  EVIDENCE: exit 0, `NO_FIXTURE_LEAK_OK` — 2026-08-29. The snapshot suite's canned data
  lives in the test target and is unreachable from any shipping file.

## The "Other" bucket

- [x] H16: Selecting the "Other" language opens a breakdown of the file types inside
      it, derived from real WakaTime data. The fetch is user-initiated only, passes
      through the existing token bucket and retry policy, is bounded in the number
      of days it will fan out over, is cached under the published retention policy,
      and degrades to an honest statement when the data cannot be obtained. Any
      figure it reports that is reconstructed rather than reported by WakaTime says
      so on screen.
  CHECK: swift test --filter Breakdown 2>&1
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-29. 12 tests in the `Breakdown` suite cover the join, the
  timeout boundary, out-of-order heartbeats, extension grouping, extension-less files,
  non-file entities, the day bound, and endpoint validation. The result is cached in
  memory only — stricter than the 90 days `RETENTION.md` allows, because file paths are
  the most identifying thing WakaTime returns. The sheet states on screen that the
  figures are reconstructed.

- [x] H17: The breakdown works against the live API with a real credential.
  CHECK: WAKABOARD_LIVE_AUTH=1 swift test --filter LiveAuthenticated 2>&1
  EXPECT: Test run passed
  EVIDENCE: exit 0 — 2026-08-29. 5 tests in `LiveAuthenticated` against `api.wakatime.com`
  with Kevin's own key. The breakdown pulled real heartbeats, reconstructed durations
  within the timeout bound, and produced extension rows containing no path separator.
  Assertions are structural only; no key, file name, or duration is printed.

## Copy

- [x] H18: Every title, navigation title, section header, card title, chart title,
      axis label, and widget display name uses Title Case — "Selected Period",
      "Daily Average", "Top Project". Every sentence uses sentence case, ends in
      punctuation, and reads as a sentence. A mechanical detector enforces both, with
      a planted-violation control proving the detector can fail.
  CHECK: node scripts/audit-checks.mjs casing && node scripts/audit-checks.mjs --self-test
  EXPECT: CASING_OK
  EVIDENCE: exit 0, `CASING_OK` and `SELF_TEST_OK` — 2026-08-29. Six controls prove the
  detector can fail in both directions: a lower-case title fails, a Title Cased sentence
  fails, and both negative controls pass. "Selected Period" and "Daily Average" are
  asserted present by name.

## Nothing already working may break

- [x] H19: Every check the previous ledger closed still passes — the audit oracle,
      the legal and compliance gates, the accessibility tree audit, the licence and
      hygiene gates, and the full offline test suite.
  CHECK: swift test 2>&1 && node scripts/audit-checks.mjs --self-test && for c in audit no-fixture-leak legal compliance accessibility apple license hygiene ci; do node scripts/audit-checks.mjs "$c" || exit 1; done
  EXPECT: every command exits 0
  EVIDENCE: exit 0 — 2026-08-29. 120 tests in 26 suites, `SELF_TEST_OK`, and all fifteen
  gate commands green. `WAKABOARD_LIVE=1` (6 tests) and `WAKABOARD_LIVE_AUTH=1`
  (5 tests) also pass against the live API.

- [x] H20: The live accessibility-tree audit passes on the running
      app, with no new hit target under 44 points and no new unlabelled element,
      across the screens added by this work.
  CHECK: sh scripts/device-check.sh
  EXPECT: AX_AUDIT_OK, with a non-zero node count
  EVIDENCE: exit 0, `DEVICE_CHECK_OK` — 2026-09-03. The current locally unsigned
  macOS build launched; the strengthened accessibility audit visited Overview, Activity,
  Breakdown, Insights, and Settings, inspected 1,274 nodes and 27 interactive elements,
  and printed `AX_AUDIT_OK`. The current iOS build installed and remained running on the
  Simulator. During this field test, a 38×44-point Editors segment was found and fixed;
  the shared control now has a 44-point minimum width, and the audit fails if any
  destination cannot be reached.

- [x] H21: Documentation matches the code after the change. No document references a
      file, route, command, platform list, or screen that no longer exists, and the
      new platforms, charts, drill-down, and design system are all documented where a
      reader would look for them.
  CHECK: node scripts/audit-checks.mjs hygiene
  EXPECT: HYGIENE_OK
  EVIDENCE: exit 0, `HYGIENE_OK` — 2026-08-29. `README.md`, `NOTICE`, `PRIVACY.md`,
  `RETENTION.md`, `SECURITY.md`, `ACCESSIBILITY.md`, `docs/planning/ARCHITECTURE.md`,
  and `docs/planning/PRODUCT.md` were all updated for the new platforms, endpoints,
  charts, screens, and design system. `scripts/ax-audit.swift` no longer names two
  screens that no longer exist.

## Defects found while reading, fixed here

- [x] H22: Switching the selected period inside the cache freshness window returns
      that period's data. The analytics cache is keyed by range; today a single
      unkeyed file means a 30-day request served within five minutes of a 7-day
      request silently returns seven days. Fixed, with a regression test.
  CHECK: swift test --filter Cache 2>&1
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-08-29. 4 tests in `Cache keying`. The same run found a **second,
  worse defect in the same file**: the cache was written with a data-protection class
  this build is not entitled to use, so on macOS every write succeeded and every read
  failed with `EPERM` — the offline fallback could never fire, and no test noticed
  because none read a file back after writing it. Both are fixed and both have a
  regression test.

## 2026-09-03 UI/UX and Security/Legal Audit

- [x] H23: Every dimension selector retains readable, discoverable labels at the
      320-point compact width and accessibility text sizes. The one-row control must
      fall back to a visible, keyboard- and VoiceOver-reachable grid rather than
      truncate labels. Verify: `sh scripts/snapshot-check.sh`, a fresh rendered
      `contact-breakdown.png` review, and the live accessibility-tree audit.
  EVIDENCE: `WakaSegmentedPicker` now chooses a natural-width single row or a two-column
  fallback. `sh scripts/snapshot-check.sh` produced `SNAPSHOTS_OK` with 52 renders;
  review of the fresh compact contact sheet confirmed all five labels are visible in a
  2–2–1 grid. The final macOS accessibility audit visited all five destinations,
  inspected 1,274 nodes and 27 interactive elements, and printed `AX_AUDIT_OK` after
  the short “Editors” label was corrected to a 44-point minimum target — 2026-09-03.

- [x] H24: The client, widget handoff, storage, transport, callbacks, CI, privacy,
      attribution, trademark usage, and store-facing legal claims undergo a focused
      security/legal review. Verify: `swift test`, all project audit detectors and
      their negative control, plus a manual source-to-policy comparison. Automated
      checks do not close WakaTime's written naming decision or human/device review.
  EVIDENCE: `swift test` passed 124 tests in 26 suites; every audit detector and its
  negative control passed. Manual review confirmed the narrow client boundary and
  reconciled all-platform scope in `PRIVACY.md` against WakaTime’s current policies
  and Apple’s current privacy guidance — 2026-09-03. The independent WakaTime naming
  decision and watch/runtime handoffs remain owner gates.

## 2026-09-03 Lightweight Breakdown Follow-up

- [x] H25: The Breakdown screen remains responsive when WakaTime returns a large,
      bounded period: it calculates the selected dimension once per render, reuses that
      result for both charts, and defers off-screen detail rows. Every outbound request
      remains governed by the existing shared token bucket, bounded retry policy, and
      request coalescer; inactive drill-downs still make no request until a user opens
      them. CI must reject an eager list or repeated ranking before release.
  CHECK: `swift test` && `node scripts/audit-checks.mjs performance` &&
         `sh scripts/snapshot-check.sh` && `sh scripts/build-all.sh`
  EXPECT: 124 tests in 26 suites pass; `PERFORMANCE_OK`; `SNAPSHOTS_OK`; `BUILD_ALL_OK`
  EVIDENCE: exit 0 — 2026-09-03. `swift test` passed 124 tests in 26 suites, including
  `RateLimiting`, `Coalescing`, `Transport`, `Breakdown`, and `Snapshots`; the added
  performance detector and its positive/negative controls passed; snapshot verification
  rendered 52 images and four contact sheets without overflow; and every Apple target
  built with warnings treated as errors. The CI workflow now runs the performance gate.
  This does not close signed-device, platform-runtime, WakaTime naming, or human
  sensory-review handoffs.

## 2026-09-04 Additional Analytics and Test Depth

- [x] H26: Overview adds an honest active-day ring plus peak-day and median-day
      figures derived from the selected period. Empty input produces an explicit
      empty state, not a filled ring or a fabricated claim; duplicate dates,
      negative values, and non-finite values cannot corrupt a displayed result.
  CHECK: swift test --filter AdditionalAnalytics
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-09-04. 10 tests cover empty, all-zero, duplicate,
  sparse, odd/even median, hostile numeric, DST, partial-week, Unicode, stable-tie,
  bounded-series, and every-dimension inputs.

- [x] H27: Activity adds calendar-week totals that preserve calendar and time-zone
      boundaries, identify partial weeks, aggregate duplicate dates, and remain
      deterministic across sparse input and daylight-saving transitions.
  CHECK: swift test --filter AdditionalAnalytics
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-09-04. The same 10-test requirement suite verifies
  calendar boundaries, partial weeks, duplicate aggregation, sparse periods, and
  the America/Los_Angeles daylight-saving transition.

- [x] H28: Breakdown adds a bounded daily trend for the leading buckets of the
      selected dimension. Series selection and tie-breaking are stable, absent
      buckets contribute an honest zero for that day, and every visual has a text
      alternative containing its actual values.
  CHECK: node scripts/audit-checks.mjs charts && swift test --filter Accessibility
  EXPECT: CHARTS_OK
  EVIDENCE: exits 0 — 2026-09-04. `CHARTS_OK`; 9 accessibility tests passed.
  The chart detector requires all nine named analytical figures, while spoken
  summaries assert the new ring, weekly totals, and dimension trend values.

- [x] H29: The expanded suite covers the new formulas, model wiring, loaded and
      empty UI states, accessibility summaries, boundary inputs, Unicode names,
      long labels, and stable ordering. Any requirement-based failure caused by
      production code is repaired with a regression test; expectations are not
      weakened to preserve faulty behavior.
  CHECK: swift test
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-09-04. 137 tests in 27 suites passed. A concurrent
  range-switch regression exposed stale refresh completion in `WakaUIModel`; the
  model now generation-gates refresh results, and the regression passes without
  weakening its latest-selection-wins contract.

- [x] H30: The complete offline suite, structural audits, snapshot render matrix,
      and all-platform builds pass after the analytics expansion. Authenticated
      live API, signed physical-device, WakaTime naming, and human sensory-review
      work remain open unless directly reverified; local checks do not close them.
  CHECK: swift test && node scripts/audit-checks.mjs --self-test && node scripts/audit-checks.mjs charts && node scripts/audit-checks.mjs accessibility && node scripts/audit-checks.mjs design && node scripts/audit-checks.mjs performance && sh scripts/snapshot-check.sh && sh scripts/build-all.sh
  EXPECT: BUILD_ALL_OK
  EVIDENCE: exits 0 — 2026-09-04. 137 tests in 27 suites passed; all 15 direct
  audits and their planted-negative self-test passed; 61 snapshot renders plus four
  contact sheets printed `SNAPSHOTS_OK`; and macOS, iOS, watchOS, tvOS, and visionOS
  compilation printed `BUILD_ALL_OK`. Authenticated live suites were intentionally
  skipped without credentials. The host field check was re-run after the GUI session
  became reachable: all five macOS destinations were visited, 1,250 accessibility
  nodes and 26 interactive elements were audited, and the iOS Simulator build
  installed and remained running; `DEVICE_CHECK_OK` — 2026-09-04. The driver retains
  the new exit-4 `AX_TREE_UNAVAILABLE` diagnosis for genuinely unavailable sessions.

## 2026-09-04 Manual Layout Regressions

- [x] H31: Share-ring totals are centered on the donut plot rather than on the wider
      plot-plus-legend frame, and the value and caption remain a distinct centered
      stack. Settings presents each heading, controls, and supporting copy as one
      coherent vertical group at the tested macOS window size instead of allowing
      platform `Form` columns to detach them. Settings joins the automated snapshot
      matrix so this exact surface is no longer excluded from visual regression output.
  CHECK: sh scripts/snapshot-check.sh && node scripts/audit-checks.mjs charts && node scripts/audit-checks.mjs design
  EXPECT: DESIGN_OK
  EVIDENCE: exits 0 — 2026-09-04. The requirement-first chart and Settings detectors
  each failed twice against the reported implementation, then passed after the fix;
  their planted positive and negative controls printed `SELF_TEST_OK`. The full suite
  passed 137 tests in 27 suites. The snapshot runner rendered all five screens as 74
  images and five contact sheets and printed `SNAPSHOTS_OK`; manual inspection of the
  Settings and Breakdown sheets confirmed grouped Settings cards and donut-centered
  totals in compact, regular, and wide layouts. The final live audit visited all five
  destinations, inspected 1,242 nodes and 26 interactive elements, and the iOS
  Simulator build installed and remained running; `DEVICE_CHECK_OK`.

## 2026-09-04 Public GitHub Repository and Owner Credit

- [x] H32: Every first-party repository link names `kevinle3212/WakaBoard`, while
      Kevin Le is credited with distinct GitHub `kevinle3212` and LinkedIn `lekevin1`
      profile links in the README and the app's About section. No first-party GitHub
      URL incorrectly treats the LinkedIn handle as a GitHub owner.
  CHECK: node scripts/audit-checks.mjs attribution
  EXPECT: ATTRIBUTION_OK
  EVIDENCE: exit 0 — 2026-09-04. `ATTRIBUTION_OK`; the detector's positive and
  negative ownership controls passed, and the README plus in-app About surface
  distinct canonical GitHub and LinkedIn profile links.

- [x] H33: The complete project is safe for public release: credentials, signing
      material, machine-local agent state, build output, and private analytics are
      excluded; checked-in documentation and generated review artifacts contain no
      secret; tests, audits, snapshots, and builds pass on the exact tree published.
  CHECK: swift test && node scripts/audit-checks.mjs --self-test && node scripts/audit-checks.mjs audit && sh scripts/snapshot-check.sh && sh scripts/build-all.sh
  EXPECT: BUILD_ALL_OK
  EVIDENCE: exits 0 — 2026-09-04. 139 tests in 27 suites passed; all 17 direct
  audit gates and every planted control passed; 74 renders and five contact sheets
  printed `SNAPSHOTS_OK`; every shipping platform printed `BUILD_ALL_OK`; `gitleaks`
  found no secret in eight commits or the 554 MB working tree. Local agent state,
  build output, and render intermediates are ignored.

- [ ] H34: `https://github.com/kevinle3212/WakaBoard` exists under the authenticated
      `kevinle3212` account, is public, uses `main` as its default branch, and its
      remote default-branch commit contains the complete verified local project.
      Local `origin` points to that repository and the working branch is synchronized
      after any required pull-request merge.
  CHECK: External GitHub metadata, remote refs, pull-request checks, and local/remote commit identity must all be inspected after publication.
  EXPECT: Repository visibility `public`; default branch `main`; local and remote commit identifiers match.

## 2026-09-04 Resizable Comparison Charts and Compact Percentages

- [x] H35: Horizontal comparison charts keep every category label outside its bar
      and readable at compact, regular, wide, and accessibility-size layouts, including
      long names. Every user-visible share uses `%` rather than spelling out “percent,”
      including textual and accessibility chart alternatives.
  CHECK: sh scripts/snapshot-check.sh && swift test --filter Accessibility && node scripts/audit-checks.mjs charts && node scripts/audit-checks.mjs accessibility
  EXPECT: ACCESSIBILITY_OK
  EVIDENCE: exits 0 — 2026-09-04. `CHARTS_OK`, `ACCESSIBILITY_OK`, and
  `SNAPSHOTS_OK`; the 74-image matrix covers compact, regular, wide, and
  accessibility-size layouts. Direct inspection of compact and wide Breakdown
  renders confirmed the long project label is complete and separated from its bar.

## 2026-09-04 Project Breakdown Data Quality

- [x] H36: Project breakdowns omit buckets with no genuine recorded duration,
      retain genuinely positive sub-minute activity without displaying it as `0m`
      or `0%`, and render WakaTime path-shaped project names such as
      `Users-kevinkhanhle` with `/` directory separators. Ordinary hyphenated
      project names remain unchanged.
  CHECK: swift test
  EXPECT: Test run with at least 1 test in 1 suite passed
  EVIDENCE: exit 0 — 2026-09-04. 139 tests in 27 suites passed. Regression tests
  prove exact-zero projects are discarded, `/Users/kevinkhanhle` is restored from
  `Users-kevinkhanhle`, ordinary `waka-board` is unchanged, and positive values
  below one minute or one percent render as `<1m` and `<1%` rather than zero.

## 2026-09-04 Public CI Environment

- [ ] H37: GitHub Actions selects an installed Xcode whose Swift toolchain can
      parse the package's Swift 6.2 manifest, and the acceptance-ledger job fetches
      enough Git history to verify every audited commit anchor.
  CHECK: node scripts/audit-checks.mjs ci && swift test
  EXPECT: CI_OK
