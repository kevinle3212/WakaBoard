# Attribution and Credit

**Effective date:** 29 August 2026
**Last updated:** 3 September 2026
**Applies to:** WakaBoard for macOS, iOS, iPadOS, watchOS, visionOS, and tvOS, and
this source repository.
**Contact:** KevinLe3212@gmail.com

---

## The short version

**Every number WakaBoard shows you comes from WakaTime.** WakaBoard did not
measure your coding time, does not measure it, and could not measure it. It reads
the analytics your WakaTime account already holds and draws them on an Apple
device. WakaTime does the work; WakaBoard is a window onto it.

WakaBoard is an independent project. It is not affiliated with, endorsed by,
sponsored by, or otherwise associated with WakaTime.

---

## Where the data comes from

WakaBoard is a client for the [WakaTime](https://wakatime.com) public API. Coding
time is measured by the WakaTime plugin installed in your editor, sent to
WakaTime's servers, aggregated by WakaTime, and served to WakaBoard through
`api.wakatime.com`. WakaBoard reads these endpoints and no others:

| Endpoint | What WakaBoard uses it for |
| --- | --- |
| `GET /api/v1/users/current` | Verifying an API key at sign-in |
| `GET /api/v1/users/current/summaries` | Daily totals, projects, languages, editors, operating systems, and categories |
| `GET /api/v1/users/current/heartbeats` | The on-demand file-type breakdown of the "Other" language bucket |

Every request is a read. WakaBoard has no code path that writes to your WakaTime
account, and it holds no scope it does not use.

Everything WakaBoard adds on top — the streak rule, the consistency score, the
insight sentences, the chart shapes — is WakaBoard's own calculation performed on
your device. Those are labelled as WakaBoard's throughout the app, because
presenting a derived figure as a WakaTime metric would misattribute it.

## Trademark

"WakaTime" is a trademark of WakaTime. WakaBoard uses the word nominatively — that
is, only to identify the third-party service this client connects to, which is the
one thing the name cannot be replaced by a description of.

WakaTime publishes a [Logos and Trademark Usage](https://wakatime.com/legal/logos-and-trademark-usage)
policy. Retrieved 3 September 2026, it permits third-party projects to:

> Use the WakaTime name in the description of your project
>
> Use the WakaTime name or logo to link to WakaTime

and asks projects not to:

> Use the WakaTime name or logo in your project's name if your project duplicates
> functionality found in an existing WakaTime software
>
> Create a modified version of the WakaTime logo without approval
>
> Integrate the WakaTime logo into your logo
>
> Use any WakaTime artwork without permission

### How WakaBoard complies

- **No WakaTime artwork is used.** No WakaTime logo, wordmark image, icon, colour
  scheme, or screenshot appears in this repository, in any shipped app bundle, in
  the app icon, or in any store listing. The name appears as plain text only. A
  repository check (`node scripts/audit-checks.mjs trademark`) fails the build if a
  WakaTime image asset is ever added.
- **The name is used to describe and to link, never to brand.** Every occurrence
  identifies the service, credits it as the data source, or links to
  `wakatime.com`.
- **Endorsement is disclaimed everywhere it could be inferred** — in this file, in
  `NOTICE`, in `README.md`, in `TERMS.md`, and on the app's own Settings screen.

### The honest caveat

WakaTime asks that a project not put the WakaTime name in *its own name* when the
project duplicates functionality that existing WakaTime software already provides.
WakaBoard is a dashboard, and WakaTime publishes dashboards of its own — the
wakatime.com web dashboard and the
[`wakatime/wakatime-mobile`](https://github.com/wakatime/wakatime-mobile) app. The
name "WakaBoard" is not the WakaTime mark, and it is not presented as an official
WakaTime product anywhere. It does, however, share the mark's distinctive first
syllable, and a reasonable reading of that clause could object to it.

That is stated here rather than argued away. WakaTime's policy invites projects to
email for approval, and this project will do so before any public release. If
WakaTime objects to the name, the project will be renamed rather than defended.
This paragraph will be updated with the outcome, not quietly deleted.

## Respecting WakaTime's service

Crediting a service you take data from also means not abusing it.

- **Rate limits.** WakaTime documents a limit of ten requests per second averaged
  over any five-minute period. WakaBoard's client-side token bucket sits well below
  that ceiling, applies to every outbound request including the on-demand
  breakdown, and honours a `Retry-After` header when WakaTime sends one. WakaBoard
  slows itself down before WakaTime has to.
- **No unnecessary requests.** Responses are cached on the device, identical
  in-flight requests are coalesced into one, and the file-type breakdown is fetched
  only when you ask for it and only across the days you are looking at.
- **No key on a public surface.** WakaTime's API documentation asks that a secret
  key never be used from a public website. WakaBoard is a native client: the key
  lives in the system Keychain on your own device and is sent only to
  `api.wakatime.com`.
- **No scraping and no reverse engineering.** WakaBoard uses the documented public
  API as published. It does not scrape wakatime.com, does not use undocumented
  endpoints, and does not attempt to work around anything WakaTime does not offer.

## Your agreement with WakaTime is your own

Using WakaBoard does not change your relationship with WakaTime. Your WakaTime
account, the data in it, and your rights over that data are governed by
[WakaTime's Terms of Service](https://wakatime.com/terms) and
[WakaTime's Privacy Policy](https://wakatime.com/privacy), between you and
WakaTime. WakaBoard is not a party to that agreement and cannot vary it. See
[TERMS.md](TERMS.md) and [PRIVACY.md](PRIVACY.md) for what WakaBoard itself does
and does not do.

## Other credit

- **Apple.** WakaBoard is built entirely on frameworks Apple ships with its
  operating systems — SwiftUI, Swift Charts, WidgetKit, Foundation, Security, and
  OSLog. "Apple", "macOS", "iOS", "iPadOS", "watchOS", "visionOS", "tvOS", "Swift",
  "Xcode", "App Store", and "VoiceOver" are trademarks of Apple Inc., used
  nominatively. WakaBoard is not affiliated with or endorsed by Apple Inc.
- **XcodeGen.** [XcodeGen](https://github.com/yonaskolb/XcodeGen) (MIT License)
  generates the Xcode project from `project.yml`. It is a development-time tool
  only; none of its code is compiled into or distributed with WakaBoard.
- **No other third-party code.** WakaBoard ships with no third-party runtime
  dependencies. The full third-party notice is in [NOTICE](NOTICE).

## If something here is wrong

If you are WakaTime, or you believe this attribution is inaccurate, incomplete, or
non-compliant with WakaTime's policies, email **KevinLe3212@gmail.com**. Corrections
are made promptly and without argument, and a request from the trademark owner is
treated as decisive.
