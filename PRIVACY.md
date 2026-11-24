# Haram Blur — privacy note

Haram Blur is an offline app. This note describes exactly what it can see and
where that information goes.

## What the app never does

- **No network access.** The release manifest has no `INTERNET` permission, so
  the app cannot open a connection even by mistake. `INTERNET` exists only in
  debug/profile builds, where the Flutter tooling needs it.
- **No account, no sign-in, no cloud.** There is nothing to register for.
- **No telemetry, crash reporting, analytics or advertising SDKs.**
- **No update checks.** The app cannot ask a server whether a new version
  exists.

## What the accessibility service does

Android exposes screen capture only to an enabled accessibility service, so
that is how the app sees what is on screen:

1. When the foreground app changes, the service asks Android for a screenshot
   (`takeScreenshot`, API 30+).
2. The frame is converted in memory and classified **on the device** by models
   bundled inside the APK.
3. If nudity or exposed awrah is detected, a blurred copy of that frame is
   drawn over the screen as a `TYPE_ACCESSIBILITY_OVERLAY` window.
4. The frame is then discarded. Captures are not written to storage.

The service is declared with `canRetrieveWindowContent` only where keyword or
URL rules need the visible text; it does not read passwords, does not type, and
does not keep what it reads. A short diagnostic ring buffer (dimensions, gate
score, decision, timings) can be exported from About → capture log in debug
builds and cleared at any time.

## What is stored on the device

All of this lives in the app's private storage (`SharedPreferences`), readable
only by Haram Blur:

- block lists (packages, sites, keywords), schedules and daily limits;
- calm-mode state and allow list;
- detection history (time, app package, reason, confidence), used for the
  streak, history charts and JSON export;
- the accountability partner's name and contact, and the local alert log;
- the long-sentence password, stored as plain text in the private preferences
  file (it gates UI changes, not encryption);
- your affirmations.

Uninstalling the app deletes all of it. "Reset everything" in Advanced Settings
deletes it without uninstalling.

## Permissions and why

| Permission | Why |
|---|---|
| Accessibility service | See app changes and draw the block/blur screen. Granted in system settings, revocable there at any time. |
| `POST_NOTIFICATIONS` | A warning when protection has stopped. |
| `RECEIVE_BOOT_COMPLETED` | Re-arm that warning after a reboot. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Lets the service survive Doze on aggressive OEM builds. |

Device admin is optional, requests **no** policies (no wipe, lock or password
change), and exists only to make casual uninstalling harder while protection is
on.

## Sharing and export

Export and support actions copy text (JSON history, a diagnostic report, the
accountability log) to the **clipboard**. Nothing is sent automatically; you
decide where it goes.

## Children

The app has no accounts and no network features. It is not directed at
children, and it does not collect personal information from anyone.

## Contact

This build has no server and no support inbox. Questions about the code are
answered by the repository itself.
