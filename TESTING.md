# Haram Blur — testing

## Automated (already green on this host)

```bash
export PATH="/c/flutter/bin:$PATH"
flutter analyze                       # No issues found!
flutter test                          # 102 pass, 1 skip
flutter test test/protection_test.dart # dashboard, modes and power confirmations
flutter build apk --debug             # exit 0
python tools/evaluate.py              # exit 0 (recall 0.967, FP 0.025)

# Android policy layer (JVM, no device needed):
cd android && ./gradlew :app:testDebugUnitTest   # 68 tests
```

`PolicyEvaluatorTest` covers the rules the protection dashboard depends on:
health classification, hardened-without-owner, restriction states
(unsupported / requires provisioning / degraded / active), power routing and
policy-removal transitions. These tests cannot be a Device Owner; the Android
wrapper needs a disposable provisioned device.

`tools/evaluate.py` is the regression test for detection quality: it re-runs the
shipped cascade over `tests/eval_set` and fails if recall drops below 0.90 or
benign false positives exceed 0.05. Run it after changing any model or
threshold.

## Manual, on a physical Android 11+ device

Nothing below has been executed in this workspace (no device attached), so
treat it as the acceptance checklist rather than a test report.

### Install and permissions

- [ ] `flutter run` or install the debug APK.
- [ ] Launch: Home renders without an error card.
- [ ] Toggle protection on → accessibility dialog → enable Haram Blur.
- [ ] Return to Home: status shows *Active* and the service row says connected.
- [ ] Deny/disable accessibility: Home shows the warning and never claims active.

### Screen protection

- [ ] Open a browser image that is clearly explicit: screen blurs within ~2 s
      and shows "Blurred by Haram Blur".
- [ ] Analytics records **Nudity detected** for that blur (previously events
      were logged while the overlay was hidden in the same frame).
- [ ] Simulate a missing overlay (e.g. deny it by testing on an OEM build that
      blocks accessibility overlays): the app goes to the home screen and logs
      **App closed (blur unavailable)**.
- [ ] Switch to another app: overlay clears immediately.
- [ ] Open the camera: never blurred (default exclusion).
- [ ] Open Photos/Gallery: never blurred.
- [ ] WhatsApp/Signal: not blurred outside calls (both are on the exclusion
      list); note that call-specific detection is a manual exclusion, not a
      call-state heuristic.
- [ ] Open a banking app (secure window): no crash, no stuck overlay.
- [ ] Turn protection off while blurred: overlay disappears at once.
- [ ] Reboot with protection on: notification appears if accessibility was
      dropped; tapping it opens the app.

### Image lab

- [ ] **From gallery** opens the system picker and processes the chosen image.
- [ ] **Camera** opens the camera app and processes the capture.
- [ ] Cancelling either picker returns to Image lab with no error.
- [ ] Pick a benign portrait: no regions, "no blur needed" state.
- [ ] Pick dressed person outdoors: awrah band only if genuinely skin-heavy;
      confirm no band on headscarf/beard photos.
- [ ] Pick an explicit image: whole frame blurred.
- [ ] Toggle "show original" and back.
- [ ] Save: file appears in the gallery with the blur baked in and no seams.

### History and accountability

- [ ] After a screen blur, Analytics shows today's count and the app name.
- [ ] Export JSON opens/validates and contains the event.
- [ ] Enable protection with admin inactive: the device-admin prompt appears;
      after activating, Home's "Uninstall protection is off" warning disappears
      and an uninstall attempt asks you to deactivate admin first.
- [ ] Deactivating admin shows the warning text instead of silently disabling it.
- [ ] Partner: save a contact, record a test alert, copy log, clear log.
- [ ] Airplane mode: every feature above still works (no network calls).

### Protection dashboard and device controls

- [ ] Dashboard → *Protection & device controls* opens the protection screen.
- [ ] With accessibility granted, the health card says **Protection active** and
      the accessibility, matcher and detector rows agree with the service row on
      the dashboard.
- [ ] Turn accessibility off in Android settings and return: health becomes
      **Protection temporarily unavailable**, never active.
- [ ] Standard mode: the Device Owner row reads **Needs provisioning** and the
      restriction rows never read active.
- [ ] Tapping **Hardened** without provisioning shows the requirements only; no
      policy is applied and the mode is not stored as active.
- [ ] **Restart now** asks for confirmation; cancelling performs no action.
      Confirming opens Android's power menu and the snackbar says the menu is
      open, not that the phone restarted.
- [ ] **Turn off now** does the same and never claims a shutdown.
- [ ] With accessibility revoked, both controls explain the manual power-menu
      fallback.
- [ ] The local security audit gains a `device_control` entry per action and no
      page text, list content or file names appear in it.

### Hardened Protection (disposable provisioned device only)

Never on a personal phone: a Device Owner cannot be removed without a factory
reset. Use a spare device or emulator that was reset and has no accounts.

- [ ] `adb shell dpm set-device-owner com.haramblur.haram_blur/.DeviceAdmin`
      succeeds on the reset device, and the dashboard's Device Owner row turns
      **Active**.
- [ ] **Enable hardened restrictions** asks twice (disclosure + countdown), then
      every restriction row reads **Active** only after Android confirms it.
- [ ] Reboot: Safe Mode is refused; Settings cannot uninstall apps or start a
      factory reset; Basirah cannot be uninstalled normally.
- [ ] Restart uses the Device Owner route; the call-refusal path shows a message
      instead of a false success.
- [ ] **Remove restrictions** returns every row to **Inactive**, an app can be
      uninstalled again, and `policy_removed` is in the audit log.
- [ ] Unsupported or unreadable policies are reported as unsupported/degraded,
      never as active.

### Regression checks after code changes

- [ ] `flutter analyze` and `flutter test` clean.
- [ ] `./gradlew :app:testDebugUnitTest` clean (inside `android/`).
- [ ] `python tools/evaluate.py` exits 0 with recall ≥ 0.90 and FP ≤ 0.05.
- [ ] `flutter build apk --debug` exits 0.
- [ ] No new permissions in `android/app/src/main/AndroidManifest.xml`;
      Device Owner support must not add one.
