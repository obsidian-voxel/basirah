# Release procedure

## Version bump

`pubspec.yaml` holds both numbers in one line:

```yaml
version: 1.0.0+1     # versionName + versionCode
```

`versionCode` must strictly increase for every Play upload and every F-Droid
tag. `Gradle` reads both through the Flutter Gradle plugin, so nothing else
needs editing.

Then add `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt` — both
F-Droid and Play show that file as the "what's new" text.

## Build a signed release

```bash
cd "C:/Users/H P/haram-blur"
flutter analyze
flutter test
flutter build appbundle --release --target-platform android-arm,android-arm64
flutter build apk       --release --target-platform android-arm,android-arm64
```

Outputs:

- `build/app/outputs/bundle/release/app-release.aab` — upload this to Play.
- `build/app/outputs/flutter-apk/app-release.apk` — GitHub Releases, F-Droid,
  side-loading and every secondary store.

`--target-platform android-arm,android-arm64` is deliberate: it drops the x86
and x86_64 emulator libraries, which are several tens of megabytes and useless
on a phone.

## Signing

`android/app/build.gradle.kts` reads `android/key.properties` when it exists and
falls back to the debug key when it does not, so a fresh clone still builds.
Never commit either:

- `android/key.properties` — `storePassword`, `keyPassword`, `keyAlias`,
  `storeFile`
- `android/app/haram-blur-release.jks` — the keystore itself

Signature scheme is v2 + v3, v1 off (minSdk is 30, so v1 would only add bytes).
v3 matters: it is what carries a key-rotation lineage.

### CI signing

`.github/workflows/release.yml` signs from repository secrets. Set them once
with `gh secret set` from a machine that has the keystore:

| Secret | Content |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 android/app/haram-blur-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | value of `storePassword` |
| `ANDROID_KEY_ALIAS` | value of `keyAlias` |
| `ANDROID_KEY_PASSWORD` | value of `keyPassword` |

Without those secrets the workflow still runs analyze and test on every push,
and the release job is skipped instead of producing an unsigned artefact that
looks like a release.

## Tagging

```bash
git tag -a v1.0.0 -m "Basirah 1.0.0"
git push origin v1.0.0
```

The tag triggers the release workflow. Check the run, then the GitHub Release,
before announcing anything: a tag that exists is not a build that succeeded.
