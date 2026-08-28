# Product

## Promise

WakaBoard is an independent open-source analytics client for WakaTime. It should answer “how am I coding?” in seconds without behaving like a JSON browser or claiming that time equals expertise.

## MVP

- Secure connection through production OAuth architecture and an explicitly advanced personal API-key path.
- Dashboard with today, week, calendar-day average, streak, top project, top language, previous-period context, and a daily activity chart.
- Projects and Languages screens with search/sort, duration, share, and defensible trends.
- Activity and deterministic Insights screens.
- Native macOS sidebar/window behavior and adaptive iPhone/iPad navigation.
- Today, weekly, and overview widgets; concise accessory widgets for today/week where legible.
- Cached startup, offline/stale/rate-limited/expired-auth/no-activity states.
- Settings for account state, refresh/cache controls, widget help, privacy, and about.

The MVP does not include heartbeats, organization analytics, editing WakaTime data, multiple accounts, telemetry, a backend beyond an optional OAuth relay, Watch/visionOS, exports, notifications, or LLM summaries.

## Information hierarchy

- Overview: one dominant “Today” value, compact supporting comparison, then at most five secondary metrics and one chart.
- Activity: selectable 7D/30D/3M/6M/1Y ranges only when supported by fetched data.
- Projects: time-first list, search, supported sorting, and detail navigation.
- Languages: usage distribution and history with an explicit “usage, not proficiency” explanation.
- Insights: short, deterministic statements hidden when evidence is insufficient.
- Settings: account, data, widgets, privacy, and about; no decorative preferences.

## Platform UX

- macOS: `NavigationSplitView`, resizable content, toolbar range/refresh, keyboard navigation, hover detail on charts where practical.
- iPhone: tab-based quick checks with `NavigationStack`, pull to refresh, and touch-first charts.
- iPad: adaptive split navigation and wider dashboard grids, not a separate product.
- Widgets: glanceable cached summaries with relevant deep links and privacy-safe placeholders.

## States and copy

Every feature distinguishes loading, no activity, stale cache, offline, expired authentication, rate limiting, server failure, and decoding failure. Errors explain the recovery action. Trend meaning always combines symbol, text, and color.

## Accessibility and visual direction

Use native semantic controls, semantic colors, Dynamic Type, 44-point targets, keyboard focus, Reduce Motion, Increase Contrast, and accessible chart summaries. VoiceOver reads a metric’s label, formatted duration, period, and trend—not decorative marks. The visual system is compact and developer-focused, avoids trademark mimicry, and uses restrained surfaces rather than gradients or glass effects.

## Success gates

- [ ] A new user can reach a populated dashboard after authentication without understanding API endpoints.
- [ ] Cached analytics remain useful without network access.
- [ ] No screen becomes blank for an expected data/error state.
- [ ] Core questions are answerable on macOS and iPhone; iPad layouts remain usable.
- [ ] Widgets contain no credential and no personal data in placeholders.
- [ ] Automated accessibility checks pass where available; device VoiceOver/keyboard/contrast review remains a release gate.
