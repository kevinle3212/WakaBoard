# Security plan

## Data classification and trust boundaries

Access tokens, refresh tokens, and API keys are secrets. Project names, activity times, language/editor/OS usage, and account identity are private analytics. WakaTime responses, callback URLs, deep links, cache files, and widget configuration are untrusted inputs.

## Authentication decision

WakaTime’s current documentation requires `client_id` and `client_secret` for authorization-code exchange, refresh, and revoke; it documents `state` but does not document PKCE ([WakaTime API authentication](https://wakatime.com/developers/)). A secret embedded in an open-source native binary is public, so the production app must not exchange codes with a bundled secret.

Production architecture:

1. Use `ASWebAuthenticationSession` with an unpredictable state value.
2. Send the code to a minimal operator-controlled relay over HTTPS.
3. The relay alone holds the WakaTime client secret, validates the exact redirect, exchanges/revokes tokens, and rate-limits requests.
4. Store returned credentials in Keychain with device-appropriate accessibility; never synchronize unless explicitly designed later.

If WakaTime adds documented PKCE/public-client support, prefer direct native PKCE and remove the relay. Until a relay is configured, the build exposes only an advanced personal API-key flow. The key is entered locally, stored in Keychain, sent only in the `Authorization` header, and never placed in a URL.

## Controls

- Request only read scopes needed for profile, summaries, stats, projects, languages, editors, and operating systems. Never request write or heartbeat scopes.
- Keychain credentials never enter `UserDefaults`, App Group storage, fixtures, previews, logs, crash output, or widget configuration.
- OAuth callbacks allowlist the scheme, host, route, one-time state, and pending session; invalid or replayed callbacks fail closed.
- Deep links allowlist known routes and percent-decode exactly once. Unknown routes are ignored.
- `URLSession` uses HTTPS endpoints fixed by code; request construction rejects non-HTTPS and unexpected hosts.
- `Logger` logs category and coarse failure type only. Authorization values, response bodies, project names, usernames, and query strings remain private or absent.
- Decoders bound dates/durations and sanitize display strings through normal SwiftUI text rendering; no response controls file paths or URLs.
- Cache files use atomic writes, complete-file protection where supported, schema versions, bounded history, and explicit clear/logout deletion.
- Widgets receive only the minimum normalized snapshot and never fetch with app credentials.
- No third-party runtime dependencies, telemetry, analytics, ads, or crash SDKs.
- CI uses mocked network data, least-privilege permissions, pinned actions, and no WakaTime secrets.

## Error and abuse handling

Map 401 to reauthentication, 403 to permission failure, 404 to unavailable resource, 429 to rate limiting with bounded `Retry-After`, 5xx to service unavailability, and transport/decoding failures separately. Coalesce duplicate reads. Retry only idempotent GETs with a small bounded backoff and cancellation support.

## Release gates

- [ ] Unit tests cover state mismatch/replay, callback route rejection, Keychain error mapping, unsafe base URL rejection, 401/403/404/429/5xx, malformed JSON, and secret-redaction behavior.
- [ ] Repository scan finds no token/key/secret, `.env`, private response, owner signing identity, or authorization header literal with a real value.
- [ ] App Group snapshot model cannot encode credentials.
- [ ] Logout removes Keychain credentials and private cache; remote revoke is attempted only when safely configured and local logout still succeeds.
- [ ] Manual review verifies least scopes, Keychain accessibility, OSLog privacy, CI permissions/action pins, and no unreviewed dependency.
- [ ] Device review validates authentication callback and universal/custom link behavior.

## Residual risks

An operator relay introduces availability and trust obligations and must be independently deployed/audited before public OAuth works. The advanced API-key path grants the permissions of that key and relies on device security. Widget snapshots intentionally expose selected aggregate analytics to the signed-in device’s widget surfaces; users are told this before enabling widgets.
