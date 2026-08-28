# WakaBoard gates

This ledger tracks the requested MVP outcomes. A checked box requires the
verification named; device and human gates remain open until performed.

- [x] Local `WakaCore` package and strict tests — verified 2026-08-27: `swift test` passed 9 tests
- [x] XcodeGen app, shared `WakaUI`, and widget targets — verified 2026-08-27: `xcodegen generate`
- [x] macOS and iOS/iPadOS app compilation — verified 2026-08-27: unsigned macOS and generic iOS Simulator `xcodebuild` succeeded
- [ ] Dashboard, activity, projects, languages, insights, settings — UI tests
- [ ] Loading, empty, stale/offline, error, and expired-auth states — UI tests
- [ ] Today, weekly, overview, project, and accessory widgets — widget tests/device review
- [x] Cached placeholders contain no private data or credentials — verified 2026-08-27: source scan found only fictional fixture names and no credential values
- [ ] App Group and deep-link wiring — entitlement lint and signed-device review
- [ ] VoiceOver, Dynamic Type, contrast, 44-point targets, keyboard, and Reduce Motion — device review
- [x] Apache-2.0 open-source docs, pinned CI, and Dependabot — verified 2026-08-27: direct source/configuration review
- [x] Security, privacy, callback validation, and no runtime third-party dependencies — verified 2026-08-27: secret scan, callback tests, and package/source review
