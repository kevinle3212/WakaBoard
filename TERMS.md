# Terms of Service

**Effective date:** 28 August 2026
**Last updated:** 28 August 2026

> **Not legal advice.** These terms were drafted with care and reviewed against the
> regimes named in §14, but they have not been reviewed by a licensed attorney. If
> WakaBoard is ever monetized, distributed commercially, or offered to
> organizations under contract, have a lawyer review this document first.

---

## 1. Agreement

These Terms govern your use of **WakaBoard** ("the App"), a free, open-source
analytics client for WakaTime, published by **Kevin Le** ("the Developer",
"I", "me"). By installing or using the App you agree to these Terms. If you do not
agree, do not install or use it.

Contact: **KevinLe3212@gmail.com**

---

## 2. What WakaBoard is, and what it is not

WakaBoard is a **local client application**. It runs on your device, connects
directly to the WakaTime API using credentials you supply, and displays the
results.

**There is no WakaBoard service.** I operate no server, no backend, no API, and no
hosted component of any kind. I therefore make no representation, and can make no
commitment, about uptime, availability, or continuity — there is nothing running
that could be up or down.

**WakaBoard is not affiliated with WakaTime.** It is an independent client that
uses WakaTime's public API. It is not endorsed, sponsored, certified, or supported
by WakaTime. "WakaTime" is a trademark of its owner, used here nominatively to
identify the service the App connects to. Likewise, WakaBoard is not affiliated
with or endorsed by Apple Inc.

---

## 3. Licence

WakaBoard's source code is licensed under the **Apache License, Version 2.0**. The
full text is in [LICENSE](LICENSE); attributions are in [NOTICE](NOTICE).

Where these Terms and the Apache-2.0 licence differ as to the source code, **the
Apache-2.0 licence governs the source code** and these Terms govern your use of the
compiled application and the relationship between us. Nothing in these Terms
purports to restrict a right the Apache-2.0 licence grants you.

---

## 4. Your WakaTime account

To do anything useful, WakaBoard needs a WakaTime personal API key that you
provide.

- **You are responsible for your key.** It is stored in your device's system
  Keychain. Treat it as a password. If you believe it has been exposed, revoke it
  in your WakaTime account settings.
- **Your relationship with WakaTime is yours alone.** You must comply with
  WakaTime's own terms of service and API terms. I am not a party to that
  relationship and cannot act on your behalf within it.
- **WakaBoard only reads.** The App issues read-only `GET` requests. It never
  writes to, modifies, or deletes anything in your WakaTime account, and never
  sends heartbeats.
- **WakaTime can change or withdraw its API at any time.** If it does, WakaBoard
  may stop working, and that is outside my control.

---

## 5. Acceptable use

You agree not to:

1. Use the App to access an account you are not authorized to access.
2. Modify the App to circumvent, disable, or exceed the rate limiting described in
   §6, or otherwise use it to place abusive load on WakaTime's API.
3. Use the App in violation of any applicable law, or of WakaTime's terms.
4. Represent a modified build as the official WakaBoard, or use the project name or
   the Developer's name to endorse a derivative work without permission. (This
   restriction is consistent with Apache-2.0 §6, which does not grant trademark
   rights.)

You may, of course, fork and modify the source under the Apache-2.0 licence. §5.2
and §5.4 concern how you then *use and present* the result, not your right to
create it.

---

## 6. Rate limiting and fair use

The App limits its own request rate to WakaTime — a token-bucket throttle plus
bounded exponential backoff that honours `Retry-After` — and retries only
idempotent reads. This protects your account from being throttled or suspended for
abusive traffic.

Removing or weakening these limits in a fork, and then using that fork against
WakaTime's API, is your responsibility and may violate WakaTime's terms. I accept
no liability for the consequences.

---

## 7. Data and privacy

Your data stays on your device. I receive nothing. The full detail is in
[PRIVACY.md](PRIVACY.md) and [RETENTION.md](RETENTION.md), which are incorporated
into these Terms by reference.

---

## 8. Analytics are approximations, not measurements of you

WakaBoard displays figures derived from WakaTime's data, plus some of its own
calculations. You agree to the following:

- The **15-minute streak threshold** and the **consistency score** are WakaBoard's
  own product conventions, not WakaTime metrics. They are defined in
  `docs/planning/ARCHITECTURE.md` and are computed on your device.
- **Time spent is not a measure of skill, productivity, or worth.** WakaBoard
  deliberately avoids framing it as one, and you should not use it as one.
- **Do not use WakaBoard's output as a system of record.** It must not be used as
  the basis for billing a client, computing payroll, evaluating an employee,
  substantiating a legal or tax claim, or any other consequential decision.
  Figures may be cached, stale, incomplete, rounded, or affected by a bug. For
  anything that matters, use WakaTime's own authoritative data.

---

## 9. No warranty

**THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OR CONDITION OF
ANY KIND, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY WARRANTY OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, ACCURACY, OR
NON-INFRINGEMENT.**

I do not warrant that the App will be uninterrupted, error-free, secure, accurate,
or compatible with any particular device, OS version, or future version of the
WakaTime API.

This mirrors Apache-2.0 §7. See [DISCLAIMER.md](DISCLAIMER.md) for the full
statement and its jurisdictional limits.

---

## 10. Limitation of liability

**TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE DEVELOPER SHALL NOT BE
LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, PUNITIVE, OR
CONSEQUENTIAL DAMAGES, OR FOR ANY LOSS OF PROFITS, REVENUE, DATA, GOODWILL, OR
BUSINESS OPPORTUNITY, ARISING OUT OF OR RELATING TO YOUR USE OF THE APP, ON ANY
THEORY OF LIABILITY, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.**

**THE DEVELOPER'S TOTAL AGGREGATE LIABILITY ARISING OUT OF OR RELATING TO THESE
TERMS OR THE APP SHALL NOT EXCEED THE GREATER OF (A) THE TOTAL AMOUNT YOU PAID FOR
THE APP, WHICH IS ZERO, OR (B) TEN UNITED STATES DOLLARS (US$10.00).**

**Nothing in these Terms limits or excludes liability that cannot lawfully be
limited or excluded.** This includes, without limitation, liability for death or
personal injury caused by negligence, for fraud or fraudulent misrepresentation,
and any liability that applicable consumer protection law does not permit to be
excluded. See [DISCLAIMER.md](DISCLAIMER.md) §4 for the jurisdiction-specific
carve-outs, which prevail over this section wherever they apply.

---

## 11. Indemnity

You agree to indemnify and hold harmless the Developer from any claim arising out
of your **misuse** of the App, your **violation of these Terms**, or your
**violation of WakaTime's terms or of applicable law**.

This indemnity does **not** apply to a claim arising from a defect in the App
itself, from my own negligence or wilful misconduct, or to the extent applicable
consumer law makes such an indemnity unenforceable against a consumer. If you are
a consumer in a jurisdiction that does not permit this indemnity, it does not
apply to you.

---

## 12. Changes and termination

- **Changes to these Terms.** I may revise these Terms. Material changes will
  update the effective date above, and the repository's commit history is the
  authoritative record of every version. Continued use after a change means you
  accept it. If you do not, stop using the App and delete it.
- **Discontinuation.** WakaBoard is a personal project maintained without
  obligation. I may stop maintaining or distributing it at any time, without
  notice. Because it is Apache-2.0 licensed, you may fork and continue it.
- **Termination by you.** Delete the App. That is the whole process; there is no
  account to close.

---

## 13. Third-party services

WakaBoard connects to **WakaTime** (<https://wakatime.com>). Your use of WakaTime
is governed by their terms and privacy policy. I do not control WakaTime and am not
responsible for its availability, accuracy, pricing, security, or conduct.

Distribution may occur through **Apple's App Store**, governed by Apple's terms. If
you obtained WakaBoard through the App Store, §16 also applies.

---

## 14. Governing law and disputes

These Terms are governed by the laws of the **State of Oregon, United States**,
excluding its conflict-of-laws rules. The exclusive venue for any dispute is the
state and federal courts located in **Lane County, Oregon**, and you consent to
personal jurisdiction there.

**Consumer carve-out.** If you are a consumer habitually resident in the European
Union, the United Kingdom, or another jurisdiction whose law grants you a
non-waivable right to the protection of your local mandatory consumer law and to
bring proceedings in your local courts, **that right prevails over this section**.
Nothing here deprives you of it.

There is no arbitration requirement and no class-action waiver in these Terms.

---

## 15. General

- **Severability.** If any provision is held unenforceable, it is modified to the
  minimum extent necessary to be enforceable, or severed, and the remainder stays
  in force.
- **No waiver.** A failure to enforce a provision is not a waiver of it.
- **Entire agreement.** These Terms, together with LICENSE, NOTICE, PRIVACY.md,
  RETENTION.md, ACCESSIBILITY.md, and DISCLAIMER.md, are the entire agreement
  between us regarding the App.
- **Assignment.** You may not assign these Terms. I may assign them in connection
  with a transfer of the project, subject to the Apache-2.0 licence continuing to
  apply to the source.
- **Language.** These Terms are written in English. A translation is provided for
  convenience only; the English text governs.

---

## 16. Apple App Store additional terms

If you obtained WakaBoard from Apple's App Store, the following also apply and
prevail over any conflicting term above:

1. These Terms are between you and the Developer only, **not** with Apple.
2. Apple has **no obligation** to furnish any maintenance or support for the App.
3. In the event of any failure of the App to conform to any applicable warranty,
   you may notify Apple, and Apple will refund the purchase price (which is zero).
   To the maximum extent permitted by law, Apple has **no other warranty
   obligation** with respect to the App.
4. Apple is **not responsible** for addressing any claim by you or a third party
   relating to the App, including product liability, failure to conform to legal or
   regulatory requirements, and consumer protection or privacy claims.
5. In the event of a third-party claim that the App infringes intellectual property
   rights, the **Developer**, not Apple, is solely responsible for its
   investigation, defense, settlement, and discharge.
6. You represent that you are not located in a country subject to a US Government
   embargo or designated as "terrorist supporting", and are not on any US
   Government list of prohibited or restricted parties.
7. **Apple and its subsidiaries are third-party beneficiaries of these Terms** and,
   upon your acceptance, have the right to enforce them against you.

---

## 17. Export compliance

WakaBoard uses only encryption provided by the operating system (HTTPS/TLS via
`URLSession` and the system Keychain) and implements no cryptography of its own. It
qualifies for the exemption in US EAR §740.17(b) / License Exception ENC and is
declared with `ITSAppUsesNonExemptEncryption = false`. You remain responsible for
complying with export and import law in your own jurisdiction.

---

**Kevin Le** — KevinLe3212@gmail.com
