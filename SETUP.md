# Haram Blur — setup guide

Haram Blur blurs nudity in images and, on Android 11+, across the whole screen.
All detection runs on the device: no account, no API key, no server, and no
network permission in release builds.

## Requirements

- Android 11 (API 30) or newer for **screen protection**. Image blurring works
  on older versions too, but the project targets `minSdk 30`.
- iOS: image blurring only, and it must be built on macOS.

## Install

1. Build or obtain `build/app/outputs/flutter-apk/app-debug.apk`.
   The debug APK is large (~300 MB) because it bundles the 84 MB int8 model for
   every ABI; a release split-per-ABI build is much smaller.
2. Transfer it to the phone, allow "Install unknown apps" for the file manager,
   and install.
3. Open **Haram Blur**.

## Permissions

| Permission | Required? | Why |
|---|---|---|
| Accessibility service | Yes, for screen protection | Lets the app notice window changes and take screenshots (API 30 `takeScreenshot`). It does **not** read window content or text. |
| Notifications | Optional | Only used for the "protection is off after a reboot" reminder. |
| Device admin | Recommended | Makes casual uninstall harder while protection is on; Android then requires deactivation before removal. Offered when you enable protection, and grants no data, lock or wipe policies. |
| Display over other apps | **Not needed** | The blur window is an accessibility overlay. |

To enable screen protection: **Home → toggle protection on → Open settings**,
then enable **Haram Blur** under Accessibility and return to the app. Home shows
*Active* only when Android has actually bound the service.

## Using the app

- **Image lab** — pick or take a photo, see the detected blur, save a blurred
  copy. This runs the full two-stage cascade (nudity gate + awrah bands). On
  Android the system picker and camera app are used directly, so no storage or
  camera permission is requested; iOS uses the photo picker.
- **Settings** — sensitivity (1 lenient … 10 strict), the default "never blur"
  list (camera, gallery, WhatsApp, Signal), and custom package exclusions.
- **Analytics** — blurs per day, per app, JSON export.
- **Partner** — an optional trusted contact and a local alert log. Nothing is
  sent automatically; the app has no messaging backend and says so.

## When the blur cannot be shown

If nudity is detected but the blur window cannot be attached, or Android
removes it while the content is still on screen, Haram Blur sends you to the
home screen and records an **App closed (blur unavailable)** event in
Analytics. That is a home-screen press rather than a force-stop: the app stays
in the recent-apps list, but the detected content is no longer displayed.

## Sensitivity

Lower levels blur less (fewer false positives), higher levels blur more.
Level 5 is the default and is the setting used for the published evaluation
(96.7% recall, 2.5% false positives on the 70-image set).

## If something looks wrong

- **Toggle says "Service not connected"** — enable Haram Blur under
  Accessibility, then pull to refresh on Home.
- **Nothing is blurred in an app** — that app may be on the exclusion list, or
  the screen may be a secure window (banking/DRM) that cannot be captured.
- **Blur stays after leaving the app** — switch apps once; the overlay is
  cleared on every window change.
- **After a reboot** — Android disables accessibility services on some devices.
  Tap the "Haram Blur is off" notification to reopen the app and re-enable it.

## Uninstall

Turn protection off first, then deactivate device admin
(Settings → Security → Device admin apps), then uninstall normally.
