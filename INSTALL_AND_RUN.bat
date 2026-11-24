@echo off
REM ============================================================
REM Haram Blur - Install and Run Script (Windows)
REM Builds the APK (if needed) and installs it on a connected device.
REM Double-click this file to build + install + launch the app.
REM ============================================================

setlocal enabledelayedexpansion

REM ------------------------------------------------------------------
REM STEP 1: Set environment paths
REM ------------------------------------------------------------------
set "FLUTTER_ROOT=C:\Users\H P\flutter"
set "JAVA_HOME=C:\Users\H P\jdk17\jdk-17.0.20+8"
set "ANDROID_HOME=C:\Users\H P\Android\sdk"

set "FLUTTER_BAT=%FLUTTER_ROOT%\bin\flutter.bat"
set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

REM ------------------------------------------------------------------
REM STEP 2: Display header
REM ------------------------------------------------------------------
cls
echo.
echo ============================================================
echo Haram Blur - Install and Run Script
echo ============================================================
echo.
echo [INFO] FLUTTER_ROOT   = %FLUTTER_ROOT%
echo [INFO] JAVA_HOME      = %JAVA_HOME%
echo [INFO] ANDROID_HOME   = %ANDROID_HOME%
echo.

REM ------------------------------------------------------------------
REM STEP 3: Verify tools
REM ------------------------------------------------------------------
echo [CHECK] Verifying tools...
if not exist "%FLUTTER_BAT%" (
    echo [ERROR] Flutter not found at %FLUTTER_BAT%
    goto :error_pause
)
if not exist "%ADB_EXE%" (
    echo [ERROR] ADB not found at %ADB_EXE%
    goto :error_pause
)
echo [OK]   Tools found.
echo.

REM ------------------------------------------------------------------
REM STEP 4: Build the APK first (CALL required for .bat)
REM ------------------------------------------------------------------
echo [STEP] Building APK (this may take several minutes)...
call "%FLUTTER_BAT%" build apk --debug
set "BUILD_EXIT=%ERRORLEVEL%"
if %BUILD_EXIT% NEQ 0 (
    echo [ERROR] Build failed (exit code %BUILD_EXIT%).
    echo         Run BUILD_APK.bat or DIAGNOSE.bat for more details.
    goto :error_pause
)
echo [OK]   Build succeeded.
echo.

REM ------------------------------------------------------------------
REM STEP 5: Check for connected device
REM ------------------------------------------------------------------
echo [STEP] Checking for connected Android device...
"%ADB_EXE%" devices > "%TEMP%\haram_devices.txt" 2>&1

rem Parse output: look for lines containing "device" but not "List of devices"
set "DEVICE_FOUND=0"
for /f "usebackq tokens=1 delims= " %%A in ("%TEMP%\haram_devices.txt") do (
    if "%%A" NEQ "List" if "%%A" NEQ "devices" if "%%A" NEQ "" (
        set "DEVICE_FOUND=1"
    )
)

if "%DEVICE_FOUND%"=="0" (
    echo [WARN] No Android device detected via ADB.
    echo.
    echo Please:
    echo   1. Connect your Android phone via USB.
    echo   2. Enable Developer Options (tap Build Number 7 times).
    echo   3. Enable USB Debugging.
    echo   4. Authorize this computer when prompted on your phone.
    echo   5. Re-run this script.
    echo.
    echo The APK was built at: %~dp0build\app\outputs\flutter-apk\app-debug.apk
    echo Install it manually or re-run this script after connecting a device.
    goto :end
)

echo [OK]   Device detected.
echo.

REM ------------------------------------------------------------------
REM STEP 6: Install the APK
REM ------------------------------------------------------------------
set "APK_PATH=%~dp0build\app\outputs\flutter-apk\app-debug.apk"
if not exist "%APK_PATH%" (
    echo [ERROR] APK not found: %APK_PATH%
    goto :error_pause
)

echo [STEP] Installing APK on device...
"%ADB_EXE%" install -r "%APK_PATH%"
set "INSTALL_EXIT=%ERRORLEVEL%"
if %INSTALL_EXIT% NEQ 0 (
    echo [WARN] Install failed (exit code %INSTALL_EXIT%).
    echo         You may need to uninstall the existing app first:
    echo         adb uninstall com.haramblur.haram_blur
    goto :end
)
echo [OK]   App installed successfully.
echo.

REM ------------------------------------------------------------------
REM STEP 7: Launch the app
REM ------------------------------------------------------------------
echo [STEP] Launching Haram Blur...
"%ADB_EXE%" shell am start -n com.haramblur.haram_blur/.MainActivity >nul 2>&1
if errorlevel 1 (
    echo [WARN] Could not auto-launch the app. Open it manually from your app drawer.
) else (
    echo [OK]   App launched on device.
)
echo.
echo ============================================================
echo INSTALLATION COMPLETE
echo ============================================================
echo.
goto :end

::error_pause
echo.
echo ============================================================
echo SCRIPT STOPPED DUE TO ERROR
echo ============================================================
echo.

::end
pause
