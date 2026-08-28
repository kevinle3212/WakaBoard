# Implementation plan

Each item closes only after its verification command or explicitly named device/human gate succeeds.

## Phase 0 — audit and scaffold

- [x] Confirm the repository is greenfield and record Xcode/SDK versions — verify: `xcodebuild -version`, `xcrun --sdk macosx --show-sdk-version`, `xcrun --sdk iphoneos --show-sdk-version`, `swift --version`.
- [x] Create `Package.swift`, `project.yml`, configurations, app/widget targets, and strict Swift settings — verified: `swift package dump-package` and `xcodegen generate`.
- [x] Add `GATES.md` derived from the original request — verified by source review; device/human gates remain intentionally open.

## Phase 1 — foundation (Terra ownership)

- [ ] Implement normalized `Sendable` models, duration formatter, injected-calendar date ranges, deep links, and mock fixtures — verify: focused Swift tests including DST, zero, long-name, empty, and Unicode cases.
- [ ] Implement typed WakaTime endpoints/DTO mapping and an injected `HTTPClient` with status/error mapping — verify: mocked success, malformed JSON, 401, 403, 404, 429, 500, timeout, and offline tests; no live API calls.
- [ ] Implement Keychain-backed credential store plus OAuth session/state abstractions and advanced API-key auth — verify: credential-store mock and callback-validation tests.
- [ ] Implement actor-backed versioned JSON cache, freshness, offline fallback, and request coalescing — verify: expiry, corruption, atomic replacement, cancellation, and concurrent-call tests.

## Phase 2 — analytics (Terra ownership)

- [ ] Implement comparisons, shares, calendar/active averages, rolling values, best day, 15-minute streak, consistency score, project/language aggregation, and deterministic insights — verify: formula boundary and insufficient-data tests.
- [ ] Build repository orchestration and widget snapshot conversion — verify: cached-first/offline/auth-expired/rate-limited tests and proof snapshots cannot encode credentials.

## Phases 3–6 — apps and widgets (Luna ownership, Sol integration)

- [ ] Build shared design components and dashboard/activity/projects/languages/insights/settings views with realistic previews — verify: app schemes compile and preview fixtures include heavy/light/empty/offline/expired/long-name states.
- [ ] Compose native macOS navigation/commands and adaptive iPhone/iPad navigation — verify: macOS and representative iPhone/iPad simulator builds; UI tests for first launch, auth, dashboard range, project detail, settings, and logout.
- [ ] Build Today, Weekly, Overview, and configurable Project widgets plus useful accessory families — verify: widget extension builds; placeholder/snapshot/timeline/deep-link tests pass; placeholders contain no personal data.
- [ ] Wire App Group cache and targeted WidgetCenter reloads using placeholder identifiers — verify: entitlement/config lint and signed-device handoff remains open until identifiers exist.

## Phase 7 — quality

- [ ] Run `swift test` and all Xcode schemes with strict concurrency warnings as errors; record exact failures.
- [ ] Audit VoiceOver labels, chart summaries, keyboard focus, Dynamic Type, 44-point targets, Increase Contrast, Reduce Motion, light/dark mode, resize, and long/empty/error states — verify automatically where possible and keep human/device checks open.
- [ ] Audit secrets, Keychain, callback/deep-link validation, logs, cache/App Group data, dependency surface, and CI integrity — verify: repository scan plus manual security checklist.
- [ ] Audit duplicate logic, DTO leakage, giant views/models, unnecessary globals, recomputation, and request duplication — verify: source review and targeted tests.

## Phase 8 — open source (Luna ownership)

- [ ] Add concise README, Apache-2.0 license, contributing, code of conduct, security policy, privacy policy, issue/PR templates, Dependabot, and minimal CI — verify: links/commands/paths resolve and YAML/Markdown parse.
- [ ] Document independent status, WakaTime API use, no endorsement, authentication setup, widgets, tests, screenshots placeholder, roadmap, and release checklist — verify: clean-room setup walkthrough without credentials.
- [ ] Produce final report with Built, Architecture, Integration, Platforms, Tests, Security, Remaining Issues, and P0/P1/P2 next steps; never overstate simulator or machine checks as device validation.

## Delegation boundaries

- Terra owns `Package.swift`, `Sources/WakaCore/`, and `Tests/WakaCoreTests/`.
- Luna owns `project.yml`, `Config/`, `Apps/`, `Widgets/`, `Sources/WakaUI/`, open-source root docs, and `.github/`.
- Sol owns plan review, integration fixes, build/test/security/accessibility audits, and the away handoff. Workers must not edit each other’s owned paths or revert concurrent work.
