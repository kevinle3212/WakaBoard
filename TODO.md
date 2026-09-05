# TODO

Deferred work whose only unblock is an action Kevin must take outside a coding
session. Nothing else belongs here.

## G22 — on-device and human sensory verification

Relocated from the production-readiness acceptance ledger
(`docs/production-readiness-gates.md`) on 2026-08-28. It was abandoned there with
a handoff rather than a runnable check, because none of what it needs exists
inside a session and none of it can be substituted for.

**Outcome required:** the parts of on-device verification that need real hardware,
a provisioning-profile build granting the App Group entitlement, Lock Screen
widget families, real WidgetKit refresh cadence, and a human VoiceOver / Dynamic
Type / contrast review.

**Not yet performed:**

- Kevin's iPhone 17 Pro and iPad Air (M3) are registered but were offline for the
  audit; iOS was verified on the Simulator only, which cannot show a Lock Screen
  widget. A responsive-design build was later installed on the iPhone 17 Pro via
  `devicectl`, but launch was not confirmed and the entitlement question below is
  unchanged.
- Automatic signing needs an Xcode account that can mint a provisioning profile.
  The macOS widget handoff works through the shared `UserDefaults` suite, but that
  succeeds only because a non-sandboxed app reaches the suite without the
  entitlement — a sandboxed or App Store build needs the real App Group grant, and
  a free Apple ID may not be able to issue it. This remains unverified.
- VoiceOver speech, Dynamic Type at accessibility sizes, and contrast are human
  judgements that have not been made. The accessibility tree is audited; the
  experience is not.

**Handoff — Kevin must:**

1. Sign into Xcode so a provisioning profile can be issued and the App Group
   entitlement verified on a real signed build.
2. Connect an iPhone or iPad, install that signed build, and confirm it launches
   and shares data with the widget.
3. Enable VoiceOver and the largest Dynamic Type size and walk all six screens.

Until all three are done, WakaBoard must not be described as fully
device-verified, and `ACCESSIBILITY.md` must keep its "partially conformant"
wording.

---

## Platforms that compile but have never run

Added 2026-08-29, when watchOS, tvOS, and visionOS gained native targets.

All three build with warnings as errors against their device SDKs. None has been
launched, because their simulator runtimes are not installed — roughly 25 GB against
18 GB free — and Kevin chose compile-only verification over freeing the space.

**Not yet performed:**

- No watchOS, tvOS, or visionOS build has ever executed. Layout, focus order,
  complication rendering, and the watch's "sign in on iPhone" path are all unobserved.
- The watchOS build **excludes its asset catalog**. `actool` refuses to compile one
  without a `watchsimulator` runtime ("No available simulator runtimes for platform
  watchsimulator"), so the watch app icon is wired in the catalog and unverified.
- **tvOS has no app icon at all.** tvOS wants a layered Brand Assets stack rather than
  a flat 1024 image, and inventing one from the existing artwork would produce a worse
  icon than none. This is real, unbuilt work, not an environment problem.
- The visionOS icon is a flat image where the platform expects a layered stack;
  `actool` warns about it on every build.

**Kevin must:** free roughly 25 GB, install the watchOS, tvOS, and visionOS simulator
runtimes, then run `sh scripts/build-all.sh` and launch each app once. Until then,
WakaBoard must not be described as verified on those three platforms — the README and
`ACCESSIBILITY.md` both say so, and both must keep saying so.

## Ask WakaTime about the name

Added 2026-08-29.

WakaTime's [Logos and Trademark Usage](https://wakatime.com/legal/logos-and-trademark-usage) policy
asks projects not to put the WakaTime name in their *own* name when the project
duplicates functionality existing WakaTime software already provides. WakaBoard is a
dashboard; WakaTime publishes dashboards. "WakaBoard" is not the WakaTime mark and is
never presented as an official product, but it shares the mark's distinctive first
syllable, and a reasonable reading of that clause could object.

`ATTRIBUTION.md` states this plainly rather than arguing it away, and commits to
emailing WakaTime for approval before any public release.

**Kevin must:** email WakaTime, describe the project, and ask whether the name is
acceptable. If they object, rename rather than defend. Record the outcome in
`ATTRIBUTION.md` — update the paragraph, do not delete it.
