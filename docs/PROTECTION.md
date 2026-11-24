# Protection modes, Device Owner and device controls

This document describes the protection architecture Basirah actually ships, what
each mode can and cannot do, and the exact steps for provisioning, verifying and
reversing the optional Device Owner restrictions. It is the reference for the
code in:

| Concern | File |
|---|---|
| Mode, restriction, health and power decisions (pure logic) | `android/app/src/main/kotlin/com/haramblur/haram_blur/PolicyEvaluator.kt` |
| Device Policy Manager wrapper (read, apply, verify, clear) | `.../DeviceOwner.kt` |
| Anti-tamper monitoring and the protection report | `.../ProtectionHealth.kt` |
| Restart / Turn Off execution | `.../PowerControls.kt` |
| Device admin and Device Owner receiver | `.../DeviceAdmin.kt`, `res/xml/device_admin.xml` |
| Control channel | `.../MainActivity.kt` (`com.haramblur.haram_blur/control`) |
| Report models and controller | `lib/services/protection_service.dart` |
| Dashboard UI | `lib/ui/protection_screen.dart` |
| JVM policy tests | `android/app/src/test/kotlin/.../PolicyEvaluatorTest.kt` |
| Widget/model tests | `test/protection_test.dart` |

There is exactly **one** protection service (`SystemWideBlurService`). Hardened
Protection adds policy, not a second service: the accessibility service stays the
only thing that sees the screen.

## Standard Protection (default)

Works on any Android 11+ phone with the accessibility service enabled. No
Device Owner, no root, no VPN, no network.

| Capability | How | Honest limit |
|---|---|---|
| App, site, keyword and visual blocking | `SystemWideBlurService` | Android exposes only what accessibility does; a secure window (`FLAG_SECURE`) cannot be captured |
| Service interruption monitoring | service bind/unbind hooks + audit | Android does not notify an app when the user revokes accessibility while Basirah is dead; the next observation records it |
| Accessibility revocation detection | `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` read on connect, resume and boot | The app can only *notice*; it cannot re-enable itself |
| Reboot recovery | `BootReceiver` + service re-bind; timestamped `reboot_recovery` audit entry | Android starts the service after unlock, not during boot |
| Protection-health reporting | `ProtectionHealth.report()` | Only state Android exposes is reported |
| Settings escape protection | `guardSettings` in the service | Only the app-info screen naming Basirah with a destructive action; a factory reset from Recovery is not visible |
| Bypass-attempt detection | newly installed apps/browsers, split screen, private mode, Settings escapes, audit log | ADB, Safe Mode, uninstall and Safe Mode boot are outside ordinary permissions |
| Restart / Turn Off | `GLOBAL_ACTION_POWER_DIALOG` through the bound service | The user confirms in Android's UI; Basirah never performs either action |

Standard Protection cannot prevent: Safe Mode, uninstalling the app, disabling
the service in Settings, a factory reset, ADB `pm uninstall`, or a firmware
reflash. Those are the gaps Hardened Protection narrows, and it narrows only
some of them.

## Hardened Protection (optional, Device Owner)

Hardened mode is only reported as active when **both** conditions hold:

1. `DevicePolicyManager.isDeviceOwnerApp(packageName)` returns true, and
2. every requested policy is read back as set (`UserManager.hasUserRestriction`,
   `DevicePolicyManager.isUninstallBlocked`).

The requested mode is stored separately (`hb_protection_tier`) so a user's intent
survives provisioning, but `PolicyEvaluator.effectiveTier()` returns
`standard` until the Device Owner state is verified. The dashboard says
"Hardened protection was requested, but Standard protection is what is actually
running" in that case.

### Policies applied

| Key | Android API | Prevents | Does not prevent |
|---|---|---|---|
| `safe_boot` | `UserManager.DISALLOW_SAFE_BOOT` (`addUserRestriction`) | Rebooting into Safe Mode, where third-party services do not run | Recovery-mode commands, flashing, a hardware-level bypass |
| `apps_control` | `UserManager.DISALLOW_APPS_CONTROL` | Uninstalling, disabling or force-stopping apps from Settings | ADB `pm uninstall`, root, OEM management tools |
| `factory_reset` | `UserManager.DISALLOW_FACTORY_RESET` | The factory reset entry in Settings | Recovery-mode wipe, Odin/firmware reflash, Find My Mobile erasure |
| `uninstall_blocked` | `DevicePolicyManager.setUninstallBlocked()` for Basirah's package | Normal uninstall of Basirah | ADB, root, a privileged device-management tool; and it is removed by clearing the policy |

Deliberately **not** restricted: emergency calling, phone calls, system updates,
accessibility services, suspend/wipe/lock policies, password policies, camera,
USB debugging, unknown sources, and anything else with a broad side effect. The
app requests no new Android permission for any of this; Device Owner power comes
from provisioning, not from a manifest permission.

Verification is re-read from Android every time the dashboard asks for a report.
`ok` from `applyHardenedRestrictions` means *Android confirmed the policy*, not
that the call returned without an exception.

## Provisioning requirements

Basirah never provisions, never starts a factory reset, and never applies a
policy without an explicit in-app confirmation. A human must do the provisioning
on a device they are willing to wipe.

### Routes Android supports

1. **Setup wizard with QR code or NFC** (the documented route for a fully
   managed device). Requires a factory-reset phone and a provisioning record
   containing `EXTRA_PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME` (and a download
   location if the APK is not pre-installed). Basirah has no download URL and no
   server, so this route only works with the APK already on the device or
   installed at setup by other means.
2. **ADB on a device that is not yet set up.** Android refuses
   `dpm set-device-owner` once the phone has accounts or a second user, so this
   normally means a freshly reset phone with no account added:

   ```bash
   adb shell dpm set-device-owner \
     com.haramblur.haram_blur/.DeviceAdmin
   ```

   Use a spare or emulator device. Do **not** run this against a personal phone:
   the Device Owner cannot be removed without a factory reset.

### What the app checks

- `isDeviceOwnerApp` (verified owner state);
- `isAdminActive` (ordinary device admin, a weaker state);
- each restriction via `UserManager` and `isUninstallBlocked`;
- API availability (`PolicyEvaluator.apiAvailable`, true from API 21);
- read failures are reported as *degraded*, never as inactive.

There is no public API that says "this phone can become a Device Owner". The
dashboard therefore reports the current verified state and the written
requirements, and refuses to pretend it knows more.

## Recovery

In-app, for every restriction:

1. Open **Protection** (dashboard row *Protection & device controls*).
2. Under **Device restrictions**, choose **Remove restrictions** and confirm.
3. Basirah asks Android to clear each restriction, reads the state back, records
   `policy_removed` in the local audit log, and only then reports success. If
   Android refuses one, the row stays visible and the message names it.
4. Settings can then uninstall apps, force-stop them and start a factory reset
   again. Basirah itself remains Device Owner until step 5.
5. To clear the Device Owner itself: factory reset the phone. Android's
   documented behaviour is that a Device Owner is set at provisioning and cannot
   be removed by the user; `clearDeviceOwnerApp()` is deprecated and documented
   as testing-only (it is best-effort and can leave policies behind), so Basirah
   does not call it. `adb shell dpm remove-active-admin` is refused for a
   non-test-only Device Owner; it works only on a test build installed with
   `android:testOnly="true"`.

Emergency access, hardware shutdown (holding the side button), recovery mode and
network-based device recovery do not depend on Basirah and are never blocked by
it.

## Restart and Turn Off

| Mode | Restart | Turn Off |
|---|---|---|
| Standard | Confirm, then the bound accessibility service calls `GLOBAL_ACTION_POWER_DIALOG`; the user picks **Restart** in Android's UI | Same dialog; the user picks **Power off** |
| Hardened (verified owner) | Confirm, then `DevicePolicyManager.reboot()`; Android may refuse during a call, and the app reports the refusal | Same power dialog: Android exposes no direct shutdown API at any privilege level |

If the accessibility service is not bound, both controls explain how to open the
power menu with the hardware button instead. Every use is audited as
`device_control` with the route and whether Android accepted it. The app never
says the phone "has restarted" before Android does.

## Anti-tamper and protection health

`PolicyEvaluator.health()` maps observed facts to exactly one of five answers:

| State | Meaning |
|---|---|
| `active` | Protection is on, accessibility is granted and connected, rules and detector are running, and (in Hardened mode) every policy is verified |
| `temporarily_unavailable` | Protection is on but accessibility is off or the service is not connected |
| `degraded` | Something is running but incomplete: detector starting or failed, Hardened requested without an owner, or a policy missing/unreadable |
| `disabled` | The user switched protection off |
| `unsupported` | The platform cannot run the accessibility service |

Transitions are recorded once each in the local `SecurityAudit` log (capped at
100 entries): `accessibility_granted`, `accessibility_revoked`,
`service_interrupted`, `reboot`, `reboot_recovery`, `detector_failed`,
`detector_recovered`, `device_owner`, `policy_applied`, `policy_removed`,
`policy_changed`, `protection_health`, `protection_tier`, `device_control`.

What Android does **not** expose to an ordinary app, and Basirah therefore does
not claim to detect: a factory reset triggered from recovery, an uninstall that
happens while the app is gone, ADB commands, root, a screenshot taken by another
process, and the exact moment the user toggles a policy in a vendor settings UI.

## Samsung Galaxy A56 compatibility

Facts, with dates, as of November 2026:

- The Galaxy A56 5G launched on **One UI 7 / Android 15**, has received **One UI
  8 / Android 16**, and Samsung's One UI 9 (Android 17) rollout for the A56 began
  in October 2026. Samsung lists six generations of OS upgrades for it.
- Its `targetSdk` 36 build therefore runs on the A56's current Android 16/17
  releases. `minSdk` is 30.
- Samsung supports standard Android enterprise Device Owner provisioning; Knox is
  Samsung's own management layer and is not required for the AOSP device-policy
  APIs Basirah uses. Knox-specific behaviour (Knox Guard, OEM unlock restrictions)
  is not used or relied on.
- Safe Mode on One UI is reached by holding the side button and long-pressing
  **Power off**. `DISALLOW_SAFE_BOOT` is documented by Google as a device-owner
  restriction; Samsung's firmware is expected to honour it, but Basirah has not
  observed it on a physical A56.
- Samsung's battery management is aggressive. Basirah already asks for the
  battery-optimisation exemption; if One UI puts the app to sleep, the
  accessibility service can be unbound, which the dashboard reports as
  *temporarily unavailable* rather than success.
- One UI's power menu also offers Emergency mode and Samsung Wallet; the app
  opens that menu and does not alter its contents.

**Not validated:** Basirah has not been run on a physical Galaxy A56 in this
workspace. AOSP emulator results do not prove One UI behaviour, and none of the
above is a claim of vendor validation.

## Tests

- `android/app/src/test/kotlin/.../PolicyEvaluatorTest.kt` — health
  classification, tier gating, restriction states (unsupported / needs
  provisioning / degraded / active), power routing, policy transitions. Runs on
  the JVM and needs no device.
- `test/protection_test.dart` — report parsing, tier/state honesty, dashboard
  content, provisioning dialog without activation, restart/turn-off confirmation
  and cancellation. Uses a fake native bridge.
- A Device Owner test requires a disposable provisioned device or emulator: the
  JVM tests cannot be a Device Owner, and no test in this repository acts as one.
  Procedure: reset a spare device, provision with the ADB command above, open
  Protection, enable the restrictions, check each row reads *Active*, reboot and
  confirm Safe Mode is refused, then remove the restrictions and confirm they
  read *Inactive* and an uninstall works. Never perform this on a personal phone.
