# Accessibility Statement

**Effective date:** 28 August 2026
**Last updated:** 28 August 2026
**Applies to:** WakaBoard for macOS, iOS, iPadOS, watchOS, visionOS, and tvOS.

---

## 1. Commitment

WakaBoard is built to be usable by everyone, including people who use VoiceOver,
Switch Control, Voice Control, keyboard-only navigation, large text, or reduced
motion. Accessibility is treated as a correctness property here, not a polish
item: a chart with no text alternative is a bug in the same sense that a wrong
total is a bug.

**Target conformance:** WCAG 2.2 Level AA, and EN 301 549 V3.2.1 where it applies
to native mobile and desktop software.

---

## 2. Conformance status

**Partially conformant with WCAG 2.2 Level AA.**

"Partially conformant" is the accurate word and is used deliberately. Some success
criteria are verified automatically on every commit; some are now verified against the
live accessibility tree of the app running on real macOS hardware; and the remainder —
how VoiceOver sounds, how the interface renders at accessibility text sizes, contrast,
and anything on a physical iPhone or iPad — has **not** been reviewed by a human.
Claiming full conformance before that review would be exactly the kind of unverified
assertion this project avoids elsewhere.

### What is verified automatically

Every commit runs assertions in `Tests/WakaUITests/AccessibilityTests.swift` over
the code that produces what assistive technology actually reads:

| Verified | Criterion |
|---|---|
| Every chart carries a text alternative containing its real content — the daily chart's totals and busiest day, active-day balance and peak/median figures, each share chart's leaders and percentages, the weekday and calendar-week values, the cumulative endpoint, the ribbon's active-day count, and the leaders in each trend — never a description of the picture | **1.1.1 Non-text Content** |
| Chart identity is never carried by colour alone. Three of the eight categorical hues fall below 3:1 against a light background, which the palette method permits only with relief, so every chart also prints its figures and is repeated as a ranked list | **1.4.1 Use of Colour**, **1.4.11 Non-text Contrast** |
| Every load state (signed out, loading, loaded, empty, stale, rate limited, expired, failed) produces a complete spoken sentence, never a leaked enum name | **1.3.1 Info and Relationships**, **4.1.2 Name, Role, Value** |
| Every data row is spoken with its name, duration, and compact `%` share | **1.3.1**, **4.1.2** |
| The period picker is spoken as "Last 7 days", not "7D" | **2.4.6 Headings and Labels** |
| The declared minimum hit-target constant is ≥ 44 pt, exceeding the 24×24 requirement | **2.5.8 Target Size (Minimum)** |
| Error messages are complete sentences that never leak status codes, hosts, or header names | **3.3.1 Error Identification** |
| An authentication failure routes to a recoverable state rather than a dead end | **3.3.3 Error Suggestion** |

### What is now verified on real hardware

`sh scripts/device-check.sh` launches the macOS app on this Mac and walks its **live
accessibility tree** — the same tree VoiceOver reads — via the `AXUIElement` API. It
fails the build on any unlabelled interactive control or any hit target below 44
points.

That pass found and fixed two real violations the unit suite had missed, because the
unit suite could only assert that the 44-point constant existed and was referenced:

| Control | Was | Now |
|---|---|---|
| "Open WakaTime account settings" link | 202×16 pt | `WakaExternalLink`, a button whose label owns the frame |
| Legal document links | 16 pt tall | same fix |
| "Refresh analytics" (Settings) | 128×24 pt | `WakaFormButton`, 44 pt |
| "Clear local cache" (Settings) | 128×24 pt | same fix |
| "Sign out and erase local data" (Settings) | 200×24 pt | same fix |

**Two documented exemptions.** A macOS `SecureField` reports a 16-point accessibility
height, and a segmented `Picker` 28 points, regardless of `.frame(height:)`,
surrounding padding, or `.controlSize(.large)` — measured, not assumed. The elements
exposed to accessibility are AppKit's own controls, which the author cannot size.

This is the WCAG 2.2 SC 2.5.8 **user agent control** exception. It matters that
SC 2.5.8's Level AA minimum is **24×24**, not 44: 44 is Apple's touch guidance and
WCAG's Level AAA (SC 2.5.5). The picker at 28 points therefore *passes* the AA bar
this document claims. The audit script encodes exactly that distinction — anything
below 24 fails outright, anything an author sizes must reach 44, and only
AppKit-sized controls between the two are exempted, with their reason printed on
every run.

The audit walks **all five screens** — Overview, Activity, Breakdown,
Insights, and Settings — by driving the sidebar. Auditing only the screen that
happened to be open missed six real violations, because a fresh launch shows
Overview.

### What is implemented but still requires human or hardware review

| Implemented | Criterion | Status |
|---|---|---|
| Dynamic Type — all text uses relative text styles; no fixed point sizes | **1.4.4 Resize Text** | Rendered at an accessibility size on every screen by `sh scripts/snapshot-check.sh`, which fails if content overflows its width. Not reviewed by a person |
| Reduce Motion — chart transitions disabled when the system setting is on | **2.3.3 Animation from Interactions** | Not reviewed with the setting enabled |
| Colour is never the sole carrier of meaning | **1.4.1 Use of Color** | Every chart prints its figures and repeats as a ranked list; not visually reviewed |
| Contrast in light and dark mode | **1.4.3 Contrast (Minimum)**, **1.4.11 Non-text Contrast** | The chart palette and the accent **are** measured — `swift test --filter Palette` recomputes the WCAG ratio of every hue against both surfaces. System-supplied text and control colours are not measured, and no screen has been reviewed by eye |
| Keyboard operation and focus order on macOS, including ⌘R | **2.1.1**, **2.4.3** | Not reviewed |
| How VoiceOver actually *sounds* reading each screen | **1.3.2 Meaningful Sequence** | Tree is audited; speech is not |
| Widgets on a real Home Screen and Lock Screen | **1.1.1**, **4.1.2** | Requires a physical device |

Only screens reachable without a credential are covered by the automated pass; the
signed-in overview, activity, breakdown, insights, and settings screens
have not been walked, because reaching them needs a real WakaTime key.

**watchOS, tvOS, and visionOS have had no accessibility pass at all.** They compile,
their shells are built for their own input models — a compact stack on the watch, a
focus-traversable tab bar on the television — and the shared components they use are
the audited ones. None of that is a substitute for running them: their simulator
runtimes are not installed, so neither the accessibility tree nor the rendering on
those three platforms has been inspected. The deferred-work file at the repository
root records it.

### Known gaps

1. **No physical iOS or iPadOS device.** iOS was verified on the Simulator, which
   proves installability and launch but is not hardware, and cannot show a Lock Screen
   widget. Tracked in [GATES.md](GATES.md).
2. **Charts have no audio graph.** Swift Charts supports `.accessibilityChartDescriptor`
   for audio graphs; WakaBoard currently provides a text summary only. The text
   alternative satisfies 1.1.1; the audio graph would be an improvement beyond it.
3. **No localization.** The interface is English only, which affects users who rely
   on a screen reader in another language. This is a functional gap rather than a
   WCAG failure.

---

## 3. Accessibility features

- **VoiceOver and screen readers.** Every control, metric, chart, and list row has
  an explicit label. Composite elements are combined so VoiceOver reads one
  coherent sentence rather than four fragments.
- **Dynamic Type.** All text scales with the system setting, including the large
  "Today" figure, which uses a relative `.largeTitle` style rather than a fixed
  size.
- **Reduce Motion.** Chart animations are suppressed when the system setting is
  enabled.
- **Target size.** Every control WakaBoard lays out itself is at least 44×44 points,
  verified against the running app's accessibility tree rather than against the
  source. Controls AppKit sizes — the text field and the period picker — meet the
  WCAG 2.2 AA minimum of 24×24 but not Apple's 44-point touch guidance, because their
  height is not the author's to set. Both are re-reported as named exemptions on
  every audit run rather than hidden.
- **Keyboard.** On macOS, the app is navigable by keyboard and ⌘R refreshes.
- **No time limits, no flashing.** Nothing expires under you, and nothing flashes,
  so **2.2.1 Timing Adjustable** and **2.3.1 Three Flashes** are satisfied by
  construction.
- **Honest empty and error states.** Rather than showing a blank screen, the app
  explains what happened and what to do, with a recovery action.

---

## 4. Legal position

**United States — ADA and Section 508.** WakaBoard is a free, independently
published application and is not a place of public accommodation, a federal agency
deliverable, or a federal contractor deliverable, so neither the ADA nor Section
508 imposes a direct legal obligation here. The WCAG 2.2 AA target is adopted
voluntarily, because it is the right standard regardless of whether it is
compulsory. If WakaBoard were ever procured by a US federal agency, the Section 508
/ Revised 508 Standards (which incorporate WCAG 2.0 AA) would apply, and an
ACR/VPAT would be produced.

**European Union — European Accessibility Act (Directive (EU) 2019/882).** The EAA
has applied to products and services placed on the EU market since **28 June 2025**.
The developer is a **microenterprise** — a sole individual, with fewer than 10
employees and turnover far below €2 million — and is therefore **exempt from the
EAA's service-related obligations**. The exemption is claimed accurately, not used
as a reason to skip the work: WakaBoard targets EN 301 549 conformance anyway. Note
that the microenterprise exemption covers services rather than products, and that it
would fall away immediately if the project grew past the thresholds.

**United Kingdom.** The Equality Act 2010 duty to make reasonable adjustments is
directed at service providers. As above, the standard is adopted voluntarily.

**Canada (ACA), Australia (DDA), and elsewhere.** WCAG 2.2 AA is the common
reference point in each and is the standard this project targets.

---

## 5. Feedback

If any part of WakaBoard is difficult or impossible for you to use, please tell me.
Accessibility reports are treated as bug reports, not feature requests.

**Kevin Le — KevinLe3212@gmail.com**

Please include your device, OS version, the assistive technology you use, and what
you were trying to do. I aim to acknowledge within **5 business days** and to give a
substantive response, including a fix or a timeline, within **30 days**.

If you would prefer to report publicly, open an issue in the repository.

---

## 6. Assessment method

This statement is based on **self-evaluation**: automated assertions in the test
suite, an automated audit of the live accessibility tree of the running macOS app, and
code review against WCAG 2.2 AA and EN 301 549. It has **not** been
audited by an independent third party, and no external accessibility evaluation has
been commissioned. That limitation is stated plainly because an accessibility
statement that overclaims is worse than none — a user who relies on it and finds it
untrue has been actively misled.

This statement will be revised when the device-level pass in [GATES.md](GATES.md) is
completed.
