# Privacy Policy

**Effective date:** 27 August 2026
**Last updated:** 27 August 2026
**Applies to:** WakaBoard for macOS, iOS, and iPadOS, and this source repository.

---

## The short version

**WakaBoard has no server. The developer receives no data about you — none at
all.**

WakaBoard is an app that runs entirely on your device. When you connect your
WakaTime account, your device talks directly to `api.wakatime.com` and nobody
else. Your coding analytics are stored on your device and nowhere else. There is
no WakaBoard backend to send data to, no account to create with us, no
analytics SDK, no advertising SDK, no crash-reporting SDK, and no third-party
runtime dependency of any kind.

This means most of the rights described below — access, deletion, portability —
are things you exercise directly, by using your device, because the developer has
nothing of yours to give you or delete.

---

## 1. Who is responsible

| | |
|---|---|
| **Developer** | Kevin Le, an individual developer |
| **Contact** | KevinLe3212@gmail.com |
| **Role under GDPR** | See §3 — for practical purposes, **not** a controller of your analytics |
| **EU/UK representative** | None appointed — see §9.2 for why |

WakaBoard is an independent open-source project. It is not affiliated with,
endorsed by, or sponsored by WakaTime or Apple.

---

## 2. What data exists, and where it lives

Everything below stays on your device. Nothing is transmitted to the developer.

| Data | Where it is stored | Why | How long |
|---|---|---|---|
| Your WakaTime personal API key | System Keychain, device-only, excluded from iCloud and backups | To authenticate your requests to WakaTime | Until you sign out or delete the app |
| Cached coding analytics (daily totals, project names, language names) | A file in the app's Application Support directory, owner-readable only (`0600`), excluded from backup | To show your dashboard instantly and to work offline | **90 days**, then deleted automatically |
| Widget summary (today's total, this week's total, top project name, last 7 daily totals) | The app's App Group container, shared only with the WakaBoard widget on the same device | To render widgets without giving them your API key | **7 days**, then discarded and erased |
| Your selected time period | In-memory only | To render the screen you are looking at | Until the app closes |

**Diagnostic logs.** WakaBoard writes coarse failure categories (for example,
`transport`, `rateLimited`) to the Apple system log. These contain no
credential, no request URL, no response body, no project name, and no username.
They stay on your device and are never transmitted to the developer.

### What WakaBoard specifically does not do

- No telemetry, product analytics, or usage tracking.
- No advertising, no advertising identifiers, no cross-app or cross-site tracking.
- No crash-reporting SDK.
- No fingerprinting. Requests carry a `User-Agent` of exactly `WakaBoard` — no OS
  version, no device model, no identifier.
- No sale or sharing of personal information, under any definition, ever. There is
  no recipient to sell it to.
- No profiling and no automated decision-making producing legal or similarly
  significant effects.
- No collection of data from children, or from anyone else, because no collection
  occurs.

---

## 3. Your relationship with WakaTime is separate

This is the most important thing to understand about WakaBoard's privacy posture.

WakaBoard is a *client*. When it fetches your analytics, **your device** makes the
request to WakaTime using **your** API key. The developer is not in that path and
cannot see it.

That means:

- **WakaTime is the controller** of your coding activity data. Their privacy
  policy, not this one, governs what they collect and how long they keep it. Read
  it at <https://wakatime.com/privacy>.
- **The developer is not a processor** acting on WakaTime's behalf, and not a
  joint controller. WakaBoard is software you run; the developer operates no
  service that touches your data.
- **Deleting WakaBoard deletes only the local copy.** Your WakaTime account and
  its data are unaffected. To delete data held by WakaTime, use WakaTime's own
  controls.

---

## 4. Legal basis for processing (GDPR Art. 6)

To the limited extent that on-device processing engages the GDPR at all:

- **Art. 6(1)(b) — performance of a contract.** Storing your API key and fetching
  your analytics is the entire function you asked the app to perform. Without it
  the app does nothing.
- **Art. 6(1)(f) — legitimate interests.** Caching analytics for 90 days so the app
  works offline and does not re-request data unnecessarily. This also reduces load
  on WakaTime's API, which is in your interest as their user. The interest is
  balanced by the cache being local-only, owner-readable only, retention-limited,
  and erasable at any time from Settings.

No processing relies on consent, so there is no consent to withdraw. No special
category data (Art. 9) is processed. No criminal offence data (Art. 10) is
processed.

---

## 5. International transfers

**None occur by the developer.** No data leaves your device to any destination the
developer controls.

Your device does transmit to WakaTime, which operates in the United States. That
transfer is between you and WakaTime under their terms, and any transfer
safeguards are theirs to provide. WakaBoard neither performs nor mediates it.

---

## 6. Security

- Your API key is held in the system Keychain with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and the data-protection Keychain
  enabled, so it is not synced to iCloud and is not included in device backups.
- All network traffic uses HTTPS with a TLS 1.2 minimum. The app refuses to attach
  your credential to any host other than `api.wakatime.com` or `wakatime.com`.
- Responses are never written to the shared URL cache, and cookies are disabled.
- The local cache file is created with `0600` permissions so another account on a
  shared Mac cannot read your coding history.
- Credentials are structurally incapable of entering the widget container: the
  widget snapshot type has no field that could hold one, and an automated test
  asserts this on every commit.

No system is perfectly secure. See [SECURITY.md](SECURITY.md) to report a
vulnerability.

---

## 7. Your rights, and how to exercise them

Because the developer holds nothing about you, you exercise every right yourself,
immediately, without asking anyone:

| Right | How to exercise it |
|---|---|
| **Access / portability** | Your data is on your device and is plain JSON. Your authoritative copy lives in your WakaTime account, which offers its own export. |
| **Erasure** | Settings → *Sign out and erase local data* removes your key, cache, and widget data. Deleting the app also removes all of it. |
| **Rectification** | Analytics originate from WakaTime; correct them there. |
| **Restriction / objection** | Sign out, or delete the app. Processing stops entirely. |
| **Withdraw consent** | Not applicable; no processing relies on consent. |
| **Non-discrimination** | WakaBoard is free and has no tiers. There is nothing to discriminate with. |
| **Complain to a regulator** | You may lodge a complaint with your supervisory authority. The developer will cooperate with any authority that makes contact. |

If you believe the developer holds data about you and want it deleted, email
**KevinLe3212@gmail.com**. You will receive a substantive response within **30
days**. In practice the answer will be that no such data exists, and you are
entitled to that confirmation in writing.

---

## 8. Children

WakaBoard is not directed at children and collects nothing from anyone. It is
rated for general audiences. Because no data is collected or transmitted, COPPA
(US), the UK Age Appropriate Design Code, and equivalent provisions elsewhere
impose no additional operative obligations here. A parent or guardian with a
concern may contact the address above.

---

## 9. Jurisdiction-specific disclosures

These sections state what each regime requires. In nearly every case the answer is
"no such processing occurs", and that is the honest disclosure rather than a
disclaimer.

### 9.1 United States

**California (CCPA/CPRA).** In the preceding 12 months the developer collected
**no** categories of personal information as defined in Cal. Civ. Code
§1798.140(v), sold **no** personal information, and shared **no** personal
information for cross-context behavioral advertising. No sensitive personal
information is collected, and therefore no right to limit its use arises. You have
the rights to know, delete, correct, opt out, and to non-discrimination; the
developer holds nothing to which they can attach. There is no "Do Not Sell or
Share My Personal Information" link because there is nothing to sell or share.

**Other US state laws.** The same position applies under the Virginia CDPA,
Colorado CPA, Connecticut CTDPA, Utah UCPA, Texas TDPSA, Oregon OCPA, Montana
MCDPA, and every comparable state statute in force: no controller-side collection
occurs. No universal opt-out or Global Privacy Control signal needs to be honored,
because no sale, sharing, or targeted advertising takes place.

**Health and biometric data.** None is collected. Washington's My Health My Data
Act and Illinois BIPA impose no operative obligations here.

### 9.2 European Economic Area and United Kingdom

The GDPR and UK GDPR apply to controllers and processors. As explained in §3, the
developer operates no service that processes your personal data, so the core
controller obligations do not attach.

- **Art. 27 representative:** not appointed. Art. 27 applies to controllers and
  processors that offer goods or services to data subjects in the Union; the
  developer processes no personal data of EU data subjects and therefore falls
  outside its scope. If that position changes, a representative will be appointed
  and named here before the change takes effect.
- **Art. 30 records of processing:** none maintained, as no processing occurs.
- **Art. 35 data protection impact assessment:** not required; no high-risk
  processing occurs.
- **Data protection officer:** not required under Art. 37 and not appointed.
- **Art. 33/34 breach notification:** the developer holds no personal data that
  could be breached. A vulnerability in the app that could expose *your local* data
  will be disclosed publicly and promptly under [SECURITY.md](SECURITY.md).
- **ePrivacy Directive / PECR:** WakaBoard stores information on your device only
  as strictly necessary to provide the service you explicitly requested, which
  falls within the Art. 5(3) exemption. No cookies, no trackers, no consent banner
  is required — and none is shown, because showing a consent banner for
  non-existent tracking would itself be misleading.

**EU Cyber Resilience Act (Regulation (EU) 2024/2847).** WakaBoard is free and
open-source software that is not monetized. Under Art. 24 and Recital 18 such
software falls outside the CRA's obligations for manufacturers. Should WakaBoard
ever be monetized, the manufacturer obligations apply from **11 December 2027**,
with vulnerability and incident reporting from **11 September 2026**, and this
section will be revised before any such change.

**European Accessibility Act (Directive (EU) 2019/882).** See
[ACCESSIBILITY.md](ACCESSIBILITY.md) §4 for the microenterprise position and the
conformance commitment made regardless of it.

### 9.3 Canada

**PIPEDA** applies to organizations collecting personal information in the course
of commercial activity. WakaBoard is non-commercial and collects nothing. Quebec's
Law 25 obligations — privacy officer, breach register, transfer assessments — are
likewise not engaged, as no collection occurs.

### 9.4 Latin America

**Brazil (LGPD).** No `tratamento` of personal data is carried out by the
developer, so the controller and operator obligations of Arts. 37–41, including
appointment of an `encarregado`, are not engaged.

### 9.5 Asia-Pacific

**China (PIPL).** No personal information is handled by the developer, and none is
transferred out of China by the developer. The Art. 38 cross-border mechanisms
(CAC security assessment, standard contract, or certification) are therefore not
engaged. WakaBoard is not distributed on mainland Chinese app stores.

**Japan (APPI).** The developer is not a `personal information handling business
operator` with respect to your data, as no personal information database is
maintained. No third-party provision under Art. 27 occurs.

**South Korea (PIPA).** No collection, use, or provision of personal information
occurs, so the consent requirements of Arts. 15–17 and the destruction obligations
of Art. 21 do not attach to the developer. Your device's local copy is under your
control and erasable from Settings.

**Singapore (PDPA).** No collection, use, or disclosure occurs. No Data Protection
Officer is required under §11(3), as the developer is not an organization
collecting personal data.

**India (DPDP Act 2023 and DPDP Rules 2025).** The developer is not a Data
Fiduciary with respect to your data, as no personal data is determined or
processed by them. The Act's substantive obligations take full effect on
**13 May 2027**; this section will be reviewed before that date and revised if
WakaBoard's architecture ever changes.

**Australia (Privacy Act 1988).** The developer is a small-business operator with
turnover below the AUD 3 million threshold and, separately, collects no personal
information, so the Australian Privacy Principles are not engaged.

---

## 10. Apple platform disclosures

WakaBoard ships a `PrivacyInfo.xcprivacy` manifest in both the app and the widget
extension. It declares:

- **Data collected: none.** `NSPrivacyCollectedDataTypes` is an empty array.
- **Tracking: none.** `NSPrivacyTracking` is `false` and there are no tracking
  domains.
- **Required-reason API:** `UserDefaults`, declared with reason code `CA92.1` —
  accessing information from the same app group, which is exactly what the widget
  handoff does.

The corresponding App Store privacy label is **Data Not Collected**.

---

## 11. Changes to this policy

Material changes will be reflected in the effective date above and in the
repository's commit history, which is the authoritative record of what this
document said and when. Because there is no user account, there is no mailing list
to notify; checking this file, or the app's Settings screen, is the reliable way to
see the current version.

---

## 12. Contact

**Kevin Le** — KevinLe3212@gmail.com

For security vulnerabilities specifically, please follow
[SECURITY.md](SECURITY.md) rather than opening a public issue.
