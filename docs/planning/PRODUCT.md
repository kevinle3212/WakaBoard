# Product

## Promise

WakaBoard is an independent open-source analytics client for WakaTime. It should answer “how am I coding?” in seconds without behaving like a JSON browser or claiming that time equals expertise.

## MVP

- Secure connection through production OAuth architecture and an explicitly advanced personal API-key path.
- Dashboard with today, period totals, calendar-day and active-day averages, streak, top project, top language, active-day balance, peak and median days, and daily activity figures.
- A Breakdown screen carrying all five dimensions — projects, languages, editors, operating systems, and WakaTime's activity categories — behind one picker, each with a daily trend, share ring, ranked comparison chart, and list.
- Activity with daily, cumulative, calendar-week, and weekday figures, plus deterministic Insights.
- Native macOS sidebar/window behavior and adaptive iPhone/iPad navigation.
- Today, weekly, and overview widgets; concise accessory widgets for today/week where legible.
- Cached startup, offline/stale/rate-limited/expired-auth/no-activity states.
- Settings for account state, refresh/cache controls, widget help, privacy, and about.

The MVP does not include organization analytics, editing WakaTime data, multiple accounts, telemetry, a backend beyond an optional OAuth relay, exports, notifications, or LLM summaries.

Two exclusions were lifted on 2026-08-29. **Heartbeats** are now read, but only on an explicit tap and only to answer one question — which file types make up the "Other" language bucket, which no other endpoint can answer. **watchOS, tvOS, and visionOS** now ship as native targets alongside iOS, iPadOS, and macOS.

## Information hierarchy

- Overview: one dominant “Today” value, compact supporting metrics, then active-day,
  daily-activity, density, and language-share figures in scan order.
- Activity: selectable 7D/30D/3M/6M/1Y ranges only when supported by fetched data.
- Breakdown: one dimension at a time, chosen from a picker. A bounded daily trend,
  share ring, ranked comparison chart, then the full list. Languages carry an explicit
  “usage, not proficiency” explanation, and WakaTime's unresolved “Other” bucket opens
  into a file-type breakdown.
- Insights: short, deterministic statements hidden when evidence is insufficient.
- Settings: account, data, widgets, privacy, and about; no decorative preferences.

## Platform UX

- macOS: `NavigationSplitView`, resizable content with a bounded sidebar and a window floor, toolbar range/refresh, keyboard navigation.
- iPhone: split navigation collapsing to a stack, pull to refresh, and touch-first charts.
- iPad: adaptive split navigation and wider dashboard grids, not a separate product.
- Apple Watch: a compact stack over the three data screens. No sign-in — a forty-character secret is not typed on a watch, so the watch reads what the iPhone or Mac already loaded and says so when nothing is there.
- Apple Vision Pro: the split shell with the platform's own glass surfaces.
- Apple TV: a focusable `TabView` with an explicit Refresh control, because tvOS has no pull gesture and no pointer.
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
