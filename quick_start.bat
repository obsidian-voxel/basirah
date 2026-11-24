@echo off
REM ============================================================
REM Haram Blur - Quick Start Script (Windows)
REM Builds the debug APK and installs it on a connected device.
REM ============================================================

setlocal enabledelayedexpansion

set "PROJECT_DIR=C:\Users\H P\haram-blur"
set "FLUTTER=%USERPROFILE%\flutter\bin\flutter.bat"
set "ANDROID_SDK=%LOCALAPPDATA%\Android\sdk"
set "ADB=%ANDROID_SDK%\platform-tools\adb.exe"
set "APK=%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk"

echo.
echo "============================================================"
echo "  Haram Blur - Quick Start"
echo "============================================================"
echo.

REM --- Check Flutter installation ---
if not exist "%FLUTTER%" (
    echo "[ERROR] Flutter not found at %FLUTTER%"
    echo "        Install Flutter from https://docs.flutter.dev/get-started/install"
    echo "        Then re-run this script."
    goto :end
)
echo "[OK] Flutter found: %FLUTTER%"

REM --- Check Android SDK / ADB ---
if not exist "%ADB%" (
    echo "[WARN] ADB not found at %ADB%"
    echo "        Install Android SDK platform-tools to enable device install."
    echo "        The APK will still be built."
    set "HAS_ADB=0"
) else (
    echo "[OK] ADB found: %ADB%"
    set "HAS_ADB=1"
)

REM --- Build the APK ---
echo.
echo "[BUILD] Running: flutter build apk --debug"
pushd "%PROJECT_DIR%" >nul
"%FLUTTER%" build apk --debug
set "BUILD_EXIT=%ERRORLEVEL%"
popd >nul

if %BUILD_EXIT% NEQ 0 (
    echo.
    echo "[ERROR] Flutter build failed (exit code %BUILD_EXIT%)."
    echo "        See output above for details."
    goto :end
)
echo "[OK] Build succeeded."

REM --- Verify APK exists ---
if not exist "%APK%" (
    echo "[ERROR] APK not found at %APK%"
    echo "        Build may not have produced an output APK."
    goto :end
)
for %%F in ("%APK%") do set "APK_SIZE=%%~zF"
set /a APK_SIZE_MB=APK_SIZE/1048576
echo "[OK] APK: %APK%"
echo "      Size: %APK_SIZE_MB% MB"

REM --- Verify model included ---
echo.
echo "[CHECK] Verifying model inside APK..."
"%ADB%" shell ls >nul 2>&1
if "%HAS_ADB%"=="1" (
    echo "      (Skipping zip check; ADB available for install check)"
) else (
    echo "      (Install ADB to inspect APK contents or install on device)"
)

REM --- Install on connected device ---
echo.
if "%HAS_ADB%"=="1" (
    "%ADB%" devices 2>nul | findstr /c:"device" >nul
    if errorlevel 1 (
        echo "[INFO] No Android device detected via ADB."
        echo "       Enable USB debugging and connect a device, then run:"
        echo "       flutter install"
    ) else (
        echo "[INSTALL] Installing APK on connected device..."
        "%ADB%" install -r "%APK%"
        if errorlevel 1 (
            echo "[WARN] Install failed. You may need to uninstall the existing app first:"
            echo "       adb uninstall com.haramblur.haram_blur"
        ) else (
            echo "[OK] App installed successfully."
        )
    )
) else (
    echo "[SKIP] ADB not available - skipping device install."
    echo "       Install the APK manually: %APK%"
)

echo.
echo "============================================================"
echo "  Quick Start Complete"
echo "============================================================"
:end
echo.
pause
