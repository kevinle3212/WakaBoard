# Accessibility Statement

**Effective date:** 28 August 2026
**Last updated:** 28 August 2026
**Applies to:** WakaBoard for macOS, iOS, and iPadOS.

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
| The activity chart carries a text alternative containing its real content — totals, active-day count, and busiest day — not a description of itself | **1.1.1 Non-text Content** |
| Every load state (signed out, loading, loaded, empty, stale, rate limited, expired, failed) produces a complete spoken sentence, never a leaked enum name | **1.3.1 Info and Relationships**, **4.1.2 Name, Role, Value** |
| Every data row is spoken with its name, duration, and share, with "percent" spelled out rather than `%` | **1.3.1**, **4.1.2** |
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
| "Open WakaTime account settings" link | 202×16 pt | replaced with `WakaExternalLink`, a button that owns its frame |
| Legal document links | 16 pt tall | same fix |

**One documented exemption.** A macOS `SecureField` reports a 16-point accessibility
height regardless of `.frame(height:)`, surrounding padding, or
`.controlSize(.extraLarge)` — measured, not assumed. The element exposed to
accessibility is AppKit's inner text control, which the author cannot size. This is
the WCAG 2.2 SC 2.5.8 **user agent control** exception, and SC 2.5.8's own minimum is
24×24 rather than Apple's touch-oriented 44. The audit script reports it as a named
exemption on every run so the exception stays visible rather than being silently
dropped.

### What is implemented but still requires human or hardware review

| Implemented | Criterion | Status |
|---|---|---|
| Dynamic Type — all text uses relative text styles; no fixed point sizes | **1.4.4 Resize Text** | Not reviewed at accessibility text sizes |
| Reduce Motion — chart transitions disabled when the system setting is on | **2.3.3 Animation from Interactions** | Not reviewed with the setting enabled |
| Colour is never the sole carrier of meaning | **1.4.1 Use of Color** | Not visually reviewed |
| Contrast in light and dark mode | **1.4.3 Contrast (Minimum)** | Not measured |
| Keyboard operation and focus order on macOS, including ⌘R | **2.1.1**, **2.4.3** | Not reviewed |
| How VoiceOver actually *sounds* reading each screen | **1.3.2 Meaningful Sequence** | Tree is audited; speech is not |
| Widgets on a real Home Screen and Lock Screen | **1.1.1**, **4.1.2** | Requires a physical device |

Only screens reachable without a credential are covered by the automated pass; the
signed-in dashboard, activity, projects, languages, insights, and settings screens
have not been walked, because reaching them needs a real WakaTime key.

### Known gaps

1. **Only the sign-in screen has been audited on hardware**, because every other
   screen requires a WakaTime credential. The audit is automated and repeatable
   (`sh scripts/device-check.sh`), so extending it is a matter of supplying a key.
2. **No physical iOS or iPadOS device.** iOS was verified on the Simulator, which
   proves installability and launch but is not hardware, and cannot show a Lock Screen
   widget. Tracked in [GATES.md](GATES.md).
3. **Charts have no audio graph.** Swift Charts supports `.accessibilityChartDescriptor`
   for audio graphs; WakaBoard currently provides a text summary only. The text
   alternative satisfies 1.1.1; the audio graph would be an improvement beyond it.
4. **No localization.** The interface is English only, which affects users who rely
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
- **Target size.** Interactive elements are at least 44×44 points, verified against
  the running app's accessibility tree rather than against the source. The one
  exception — a macOS text field, whose height AppKit owns — is documented in §2 and
  re-reported on every audit run.
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
