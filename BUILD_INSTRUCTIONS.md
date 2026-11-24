# Haram Blur - Build Instructions

These scripts let you build, install, and troubleshoot the Haram Blur Android app
with zero technical knowledge — just double-click the batch files.

## Quick Start

| Goal | Double-click |
|------|-------------|
| Build the debug APK | `BUILD_APK.bat` |
| Build + install on phone + launch | `INSTALL_AND_RUN.bat` |
| Troubleshoot / create support log | `DIAGNOSE.bat` |

All scripts are located in: `C:\Users\H P\haram-blur\`

## Prerequisites

The following must be installed on your Windows PC:

| Requirement | Detected Path | Status |
|-------------|---------------|--------|
| Flutter SDK | `C:\Users\H P\flutter` | ✅ Found |
| Java JDK 17 | `C:\Users\H P\jdk17\jdk-17.0.20+8` | ✅ Found |
| Android SDK | `C:\Users\H P\Android\sdk` | ✅ Found |

If any of these are missing, install them first:
- **Flutter**: https://docs.flutter.dev/get-started/install
- **Java 17**: https://adoptium.net/ (Eclipse Temurin)
- **Android SDK**: https://developer.android.com/studio

For phone installation, also enable **USB Debugging** on your Android device
(Settings → Developer options → USB debugging).

## What Each Script Does

### `BUILD_APK.bat` — Build the debug APK
1. Sets Flutter, Java, and Android SDK paths explicitly.
2. Verifies `flutter`, `java`, and `adb` are all accessible.
3. Auto-accepts Android SDK licenses.
4. Runs `flutter doctor` to verify your setup.
5. Runs `flutter build apk --debug` to build the APK.
6. Reports success/failure, APK location, and file size.
7. Pauses so you can read the output.

**Expected output:** `build/app/outputs/flutter-apk/app-debug.apk` (~40–60 MB)

### `INSTALL_AND_RUN.bat` — Build and install on phone
1. Runs `BUILD_APK.bat` steps internally (builds the APK first).
2. Checks for a connected Android device via `adb devices`.
3. If a device is found: installs the APK and launches the app automatically.
4. If no device: tells you to connect your phone and enable USB debugging.

### `DIAGNOSE.bat` — Create a support log
1. Runs `flutter doctor -v` (verbose).
2. Runs `java -version` and `adb version`.
3. Checks that all required files exist (models, build.gradle.kts, pubspec.yaml).
4. Shows your environment variables (FLUTTER_ROOT, JAVA_HOME, ANDROID_HOME).
5. Saves everything to `diagnostic_log.txt` for sharing with support.

## Expected Output

- **APK location:** `build/app/outputs/flutter-apk/app-debug.apk`
- **APK size:** ~40–60 MB (with the 12 MB NSFW model)
- **Installation:** App launches automatically on your phone

## Common Issues and Fixes

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| `flutter: command not found` | Flutter not installed or path wrong | Install Flutter, or update `FLUTTER_ROOT` in the .bat files |
| `java: command not found` | Java not installed | Install Java 17, or update `JAVA_HOME` in the .bat files |
| `adb: command not found` | Android SDK platform-tools missing | Install Android SDK, or update `ANDROID_HOME` in the .bat files |
| No device found | Phone not connected or USB debugging off | Connect phone via USB, enable Developer options + USB debugging, authorize computer |
| Build failed | Various (licenses, SDK, etc.) | Run `DIAGNOSE.bat` and share `diagnostic_log.txt` |
| Can't uninstall app | Device Admin active | Settings → Security → Device admin apps → deactivate Haram Blur first |

## Model Files

- `assets/models/nsfw_classifier.tflite` — NSFW classifier (**12 MB**, quantized)
- `assets/models/pose_detection.tflite` — pose detection model
- `assets/models/selfie_multiclass_256x256.tflite` — body segmentation model

All inference runs on-device; nothing leaves your phone.

## Getting Help

If the build fails:
1. Double-click `DIAGNOSE.bat`
2. Wait for it to finish (it creates `diagnostic_log.txt`)
3. Share `diagnostic_log.txt` with whoever is helping you
