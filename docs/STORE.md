# Shipping Basirah to the stores

Status of every distribution channel, what is already done, and the exact work
that remains. Keep this file honest: a row is only "ready" when the artefact or
the metadata it names exists in this repository and was checked.

| Channel | Artefact | Status |
|---|---|---|
| Play Store | `flutter build appbundle --release` (signed AAB) | **Ready to upload** |
| Play Store | Store listing text | **Ready** — `fastlane/metadata/android/en-US/` |
| Play Store | Data safety form answers | **Ready** — see below |
| Play Store | Accessibility + device admin declarations | **Text ready**, submitted in Play Console |
| Play Store | Screenshots | **Missing** — needs a real device or emulator capture |
| GitHub Releases | Signed APK + AAB per tag | **Ready** — `.github/workflows/release.yml` |
| F-Droid | FOSS build (no proprietary dependencies) | **Blocked** — ML Kit, see below |
| Other stores (Amazon, Samsung, Huawei, IzzyOnDroid) | Same signed APK | **Ready** once F-Droid or Play metadata is reused |

## Signing

Release signing reads `android/key.properties` and
`android/app/haram-blur-release.jks`. Both are git-ignored and exist only on
one machine.

They are the *only* copy of the upload key. Losing them means the app can never
be updated on Play under the same listing (Play App Signing can reset an upload
key, but only after a support round trip; F-Droid and side-loaded users cannot
be helped at all). Back both files up somewhere that is not this laptop before
the first upload, and record the key password in the same safe place.

`docs/RELEASE.md` has the build and versioning procedure.

## Google Play

Upload `build/app/outputs/bundle/release/app-release.aab`.

### Data safety

Answer every question with the truth, which for this app is unusually short:

- **Does your app collect or share any of the required user data types?** No.
  The app has no `INTERNET` permission, so nothing can leave the device.
- **Is all user data encrypted in transit?** Not applicable — no data is
  transmitted.
- **Do you provide a way for users to request data deletion?** The app stores
  data only in private app storage; uninstalling deletes it, and
  *Advanced Settings → Reset everything* deletes it in place.
- **Ads / analytics / crash reporting:** none.
- **Data used to track users:** none.

### Permission declarations

Two permissions need a written justification in Play Console. Both are true
statements about this app, not marketing claims:

- **Accessibility service** (`SystemWideBlurService`). It is the only way
  Android lets an app see the screen, and seeing the screen is the entire
  product. Frames are classified on the device and discarded; nothing is
  stored or transmitted. The service does not type, does not read passwords and
  does not act on other apps' behalf.
- **Device admin** (`DeviceAdmin`). Optional, requests no policies at all (no
  wipe, no lock, no password change) and exists only to make casual uninstall
  harder while protection is on. It is never enabled without an explicit
  in-app confirmation.

### Content rating and audience

Complete the questionnaire as a utility with no user-generated content, no
ads, no purchases, no location and no personal information. Target audience:
13 and over, not designed for children.

## F-Droid

F-Droid builds from source on its own builders and refuses apps that depend on
proprietary libraries or ship non-free assets. Two dependencies currently fail
that test, and no metadata work can work around it:

| Dependency | Problem | Fix |
|---|---|---|
| `com.google.mlkit:face-detection:16.1.7` | Closed source, ships prebuilt native blobs | Bundle an Apache-2.0 detector (BlazeFace short-range is already in `assets/models/`) and delete this dependency |
| `com.google.android.gms:play-services-tasks:18.2.0` | Closed source | Only used to await the ML Kit task; disappears with the fix above |

Everything else already passes: AGPL-3.0 licence, no analytics, no trackers,
no `INTERNET` permission in the release manifest, models under
`assets/models/` (ViT classifier plus MediaPipe selfie multiclass, both
Apache-2.0-derived), Adobe-free fonts (Anek Latin and Amiri, both OFL), and a
blocklist generated from the Unlicense `blocklistproject/Lists` data.

Both models are reached from two call sites: `SystemWideBlurService` line ~966
and `MainActivity` (`detectFaces`). A FOSS detector must keep the
`List<List<Double>>` normalised-box contract in `FaceBoxes`.

`docs/fdroid/com.haramblur.haram_blur.yml` is the recipe to submit as a merge
request to `fdroiddata` *after* the dependency is replaced. F-Droid also needs
a reproducible Flutter build (`flutter precache`, pinned SDK); the recipe notes
what the builder needs.

## Screenshots

Both stores want at least two phone screenshots at 1080x1920 or larger, no
device frame, no added text.

`test/ui_render_test.dart` already renders every screen at 1080x2340 into
`build/ui-review/`. That output is a widget render, not a device capture:
Marketo/Play accept it only if it matches the shipped UI exactly, so verify one
screen on a real device before uploading renders. Nothing here claims that has
been done.
