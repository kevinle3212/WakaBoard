# Security Policy

**Last updated:** 28 August 2026

## Reporting a vulnerability

**Email: KevinLe3212@gmail.com** with `[WakaBoard Security]` in the subject line.

Please report privately first. Do **not** open a public issue for a vulnerability,
and do not disclose it publicly until a fix is available or 90 days have passed,
whichever comes first.

If the repository has GitHub Security Advisories enabled, *Report a vulnerability*
on the Security tab is preferred over email, since it creates a private thread.

**Never include a real API key, access token, or private WakaTime response in a
report.** Redact them. If you accidentally send one, say so and revoke it
immediately at <https://wakatime.com/settings/account>.

### What to include

- What the vulnerability lets an attacker do, and what they need in order to do it.
- A minimal reproduction — ideally a failing test against this repository.
- Affected version or commit, and platform.
- Any suggested fix.

### What to expect

| | |
|---|---|
| Acknowledgement | Within **5 business days** |
| Initial assessment | Within **10 business days** |
| Fix or mitigation plan | Within **90 days** for confirmed issues |
| Credit | Offered in the release notes unless you prefer otherwise |

This is a personal open-source project maintained without commercial backing.
There is **no bug bounty** and no monetary reward. Timelines are commitments of
good-faith effort, not a contractual SLA.

### Safe harbour

Good-faith security research on your own installation and your own WakaTime account
is welcome, and no legal action will be pursued for it. This does **not** extend to
attacking WakaTime's infrastructure, accessing another person's account or data, or
any denial-of-service testing. WakaTime's systems are not mine to authorize testing
against — direct anything concerning them to WakaTime.

---

## Supported versions

Only the latest commit on `main` is supported. There are no long-term support
branches. Fixes ship on `main`; older builds are not patched.

---

## Threat model

### Assets

| Asset | Sensitivity |
|---|---|
| WakaTime personal API key | **Secret** — grants read access to the account |
| Coding analytics: project names, language names, daily totals | **Private** — reveals what you work on and when |
| Widget summary | **Private**, reduced — aggregates and one project name |

### Trust boundaries

Everything crossing one of these is treated as hostile until validated:

1. **WakaTime API responses** — untrusted. Bounded and validated at decode: durations
   must be finite and are clamped to a real day, names are length-limited, day and
   bucket counts are capped, and response bodies over 8 MB are rejected before
   buffering.
2. **Deep links and URL callbacks** — untrusted. Routes are allowlisted; any query
   string, unknown route, or wrong scheme fails closed.
3. **The App Group container** — shared with the widget. Contains only aggregates.
   The snapshot type has no field capable of holding a credential, and a test asserts
   the encoded form contains no credential-shaped key.
4. **The local cache file** — could be modified by another process running as the
   same user. Corruption and version mismatch are distinguished and handled; a bad
   cache degrades to "refetch", never to a crash.
5. **The Keychain item** — stored data is tagged with its credential kind, so a
   personal API key can never be replayed as a bearer token or the reverse.

### Controls

- **Credentials** live only in the data-protection Keychain, with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` applied on both create and update.
  Never in `UserDefaults`, App Group storage, the cache, logs, previews, fixtures, or
  source control.
- **Transport** is HTTPS with a TLS 1.2 floor, to an allowlisted host only. The
  session is ephemeral with no URL cache and no cookies, so private analytics are
  never persisted by the networking stack. Requests time out at 20 seconds.
- **Authorization headers** are constructed from a typed credential. A personal API
  key is base64-encoded as `Basic`; a bearer token is sent as `Bearer`. A credential
  containing control characters or CRLF is rejected before it can reach a header.
- **Rate limiting** is client-side and mandatory: a token bucket bounds request rate,
  and only idempotent `GET`s are retried, with bounded exponential backoff, full
  jitter, and a clamped `Retry-After`.
- **Logging** records failure categories only. No credential, URL, query string,
  response body, project name, or username reaches the system log.
- **Cache files** are written atomically with complete file protection where the
  platform supports it, and `0600` permissions everywhere.
- **Retention** is enforced, not merely documented — see [RETENTION.md](RETENTION.md).
- **Dependencies**: there are none at runtime. The shipping binary links only Apple
  system frameworks. XcodeGen is a build-time tool and is not distributed.
- **CI** runs with least-privilege permissions, pins every action by commit SHA, and
  never receives a WakaTime credential.

### Residual risks

These are accepted and stated rather than hidden:

1. **A compromised device compromises everything.** The Keychain protects a key at
   rest on a locked device; it cannot protect against malware running as you on an
   unlocked one.
2. **The personal API key is coarse.** It carries whatever permissions WakaTime
   attaches to it. WakaBoard only ever issues read requests, but the key itself is
   not scoped down by the app, and cannot be.
3. **Widget surfaces show aggregates on a locked screen** if the user adds a Lock
   Screen widget. That is the user's choice, and Settings says so before it is made.
4. **OAuth is not implemented.** WakaTime documents an authorization-code exchange
   requiring a client secret and does not document PKCE. A secret embedded in an
   open-source native binary is a public secret, so none is embedded. Public OAuth
   would require an operator-controlled relay, which is not deployed. The
   `OAuthSession` and `OAuthCallbackValidator` types exist, are tested, and validate
   state and replay correctly, but no runtime path reaches them in this build.
5. **No independent security audit has been performed.** This threat model is
   self-assessed.

---

## Coordinated disclosure

On a confirmed vulnerability I will: acknowledge it, fix it on `main`, publish a
GitHub Security Advisory describing impact and affected versions, and credit the
reporter unless they decline. If a fix will take longer than 90 days, I will say so
and agree a timeline with the reporter rather than let it lapse silently.
