# Data Retention Policy

**Effective date:** 28 August 2026
**Last updated:** 28 August 2026

This policy states how long WakaBoard keeps each piece of data on your device, and
what deletes it. Every number here is **enforced in code**, not merely promised: the
constants live in `Sources/WakaCore/CacheRepository.swift` (`RetentionPolicy`) and a
test in `Tests/WakaCoreTests/RetentionTests.swift` fails the build if this document
and the code disagree.

**The developer stores nothing.** There is no server, so there is no server-side
retention period to state. Everything below concerns data on your own device, under
your own control.

---

## 1. Retention schedule

| Data | Retention | Enforced by | Deletion trigger |
|---|---|---|---|
| **WakaTime API key** | Until you remove it | System Keychain | Sign out, or delete the app |
| **Cached daily analytics** | **90 days** from the date of the activity | `RetentionPolicy.cachedActivity` | Automatic pruning on every cache read and write; Settings → *Clear local cache*; sign out; delete the app |
| **Widget summary** | **7 days** from when it was generated | `RetentionPolicy.widgetSnapshot` | Automatic discard-and-erase on read; sign out; delete the app |
| **Freshness window** (when the app refetches rather than reusing the cache) | **5 minutes** | `RetentionPolicy.cacheFreshness` | n/a — this is a refresh interval, not a retention period |
| **In-memory view state** | Until the app quits | Process lifetime | Quitting the app |
| **System diagnostic log entries** | Managed by macOS/iOS, typically days | Apple's `OSLog` subsystem | OS log rotation |

---

## 2. Why these periods

**90 days for cached analytics.** The longest period the app can display is three
months, and comparing it against the preceding period requires a little more. Ninety
days covers that with margin. Beyond it, retained data would serve no feature — it
would only be a longer record of when you were working, sitting on your disk. The
cache is a convenience and an offline fallback, not an archive; your WakaTime account
is the archive.

**7 days for the widget summary.** WidgetKit refresh is best-effort — the system,
not the app, decides when a widget updates, and it applies its own budget. A stale
widget is therefore normal and expected. What is not acceptable is a widget
presenting a two-week-old number as if it were today's. After 7 days the snapshot is
treated as absent and erased, and the widget shows its placeholder instead of a
figure it cannot stand behind.

**5 minutes for freshness.** Short enough that the dashboard is current in ordinary
use, long enough that opening and closing the app repeatedly does not hammer
WakaTime's API.

---

## 3. How deletion actually works

**Automatic pruning** runs on every cache read and every cache write. Days older
than the 90-day cutoff are dropped before the data is served to the UI, and dropped
again before it is written back to disk — so an expired day cannot survive by being
re-persisted. If pruning empties the cache entirely, the cache is treated as absent
rather than as stale data, so the app will not show you year-old numbers labelled
"saved data".

**Sign out** (Settings → *Sign out and erase local data*) removes, in this order:

1. The API key from the Keychain — first, so a partial failure cannot leave a usable
   credential behind next to cleared data.
2. The analytics cache file.
3. The widget snapshot from the App Group container.

Every step runs even if an earlier one fails, and the app reports the failure rather
than claiming success. A partial sign-out is worse than a noisy one.

**Clear local cache** (Settings) removes the cache and widget snapshot but keeps you
signed in.

**Deleting the app** removes the container, the App Group data, and — on iOS and
iPadOS — the Keychain item. On macOS, a Keychain item can outlive an app bundle;
signing out before deleting the app is the reliable way to remove it, and you can
always check for and remove an `org.wakaboard.credentials` entry in Keychain Access.

---

## 4. Backups and sync

- The API key is stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and the
  data-protection Keychain enabled. It is **not** synced to iCloud Keychain and is
  **not** included in encrypted device backups.
- The analytics cache is marked `isExcludedFromBackup`, so it is not copied into
  iCloud or a local device backup.
- The cache file is created with `0600` permissions, so on a shared Mac another
  account cannot read your coding history.

The practical effect: restoring a backup onto a new device does **not** carry your
WakaTime credential or coding history with it. You sign in again.

---

## 5. Data held by WakaTime

This policy covers **only** the copy on your device. WakaTime holds the
authoritative record of your coding activity under its own retention policy, which
the developer neither sets nor influences.

Deleting WakaBoard, signing out, or clearing the cache has **no effect** on data
held by WakaTime. To delete that data, use WakaTime's own account controls and
consult <https://wakatime.com/privacy>.

---

## 6. Changing these periods

The retention constants are deliberately not user-configurable. A setting that lets
a user extend retention indefinitely would turn a bounded cache into an unbounded
personal archive, which is exactly what this policy exists to prevent.

If a period changes in a future version, both the code constant and this document
change in the same commit — the test suite enforces that they cannot drift apart.

---

**Contact:** Kevin Le — KevinLe3212@gmail.com
