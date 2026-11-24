@echo off
setlocal EnableExtensions

REM ------------------------------------------------------------------
REM Haram Blur - Install and Run Script (Windows)
REM Builds the APK via BUILD_APK_FIXED.bat, then installs on device.
REM ------------------------------------------------------------------

set "PROJECT_DIR=C:\haram-blur"
set "FLUTTER_ROOT=C:\flutter"
set "JAVA_HOME=C:\jdk17"
set "ANDROID_HOME=C:\Android\sdk"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"
set "APK_PATH=%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk"

REM Package name from AndroidManifest.xml / MainActivity.kt
set "APP_PACKAGE=com.haramblur.haram_blur"
set "APP_ACTIVITY=%APP_PACKAGE%/.MainActivity"

REM ------------------------------------------------------------------
REM Step 0: Header
REM ------------------------------------------------------------------
echo.
echo ========================================
echo Haram Blur - Install and Run Script
echo ========================================
echo.
echo PROJECT_DIR   = %PROJECT_DIR%
echo FLUTTER_ROOT  = %FLUTTER_ROOT%
echo JAVA_HOME     = %JAVA_HOME%
echo ANDROID_HOME  = %ANDROID_HOME%
echo APP_PACKAGE   = %APP_PACKAGE%
echo.

REM ------------------------------------------------------------------
REM Step 1: Verify tools
REM ------------------------------------------------------------------
echo [1/4] Verifying tools...
if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
    echo ERROR: Flutter not found at %FLUTTER_ROOT%\bin\flutter.bat
    echo.
    pause
    exit /b 1
)
echo [OK] flutter.bat found

if not exist "%ADB_EXE%" (
    echo ERROR: ADB not found at %ADB_EXE%
    echo.
    pause
    exit /b 1
)
echo [OK] adb.exe found
echo [1/4] Tools verified.
echo.

REM ------------------------------------------------------------------
REM Step 2: Build the APK using BUILD_APK_FIXED.bat (CALL required)
REM ------------------------------------------------------------------
echo [2/4] Building APK via BUILD_APK_FIXED.bat...
echo Running: call "%PROJECT_DIR%\BUILD_APK_FIXED.bat"
call "%PROJECT_DIR%\BUILD_APK_FIXED.bat"
set "BUILD_EXIT=%ERRORLEVEL%"
if %BUILD_EXIT% NEQ 0 (
    echo.
    echo ERROR: BUILD_APK_FIXED.bat failed (exit code %BUILD_EXIT%).
    echo Check "%PROJECT_DIR%\build_log_fixed.txt" for details.
    echo.
    pause
    exit /b 1
)
echo [OK] Build succeeded.
echo.

REM ------------------------------------------------------------------
REM Step 3: Check for connected device
REM ------------------------------------------------------------------
echo [3/4] Checking for connected Android device...
"%ADB_EXE%" devices > "%TEMP%\haram_devices.txt" 2>&1

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
    echo The APK was built at: %APK_PATH%
    echo Install it manually or re-run this script after connecting a device.
    echo.
    pause
    exit /b 0
)
echo [OK] Device detected.
echo.

REM ------------------------------------------------------------------
REM Step 4: Install and launch
REM ------------------------------------------------------------------
if not exist "%APK_PATH%" (
    echo ERROR: APK not found at %APK_PATH%
    echo.
    pause
    exit /b 1
)

echo [4/4] Installing APK on device...
"%ADB_EXE%" install -r "%APK_PATH%"
set "INSTALL_EXIT=%ERRORLEVEL%"
if %INSTALL_EXIT% NEQ 0 (
    echo [WARN] Install failed (exit code %INSTALL_EXIT%).
    echo         You may need to uninstall the existing app first:
    echo         %ADB_EXE% uninstall %APP_PACKAGE%
    echo.
    pause
    exit /b 1
)
echo [OK] App installed successfully.
echo.

echo Launching %APP_PACKAGE%...
"%ADB_EXE%" shell am start -n %APP_ACTIVITY% >nul 2>&1
if errorlevel 1 (
    echo [WARN] Could not auto-launch the app. Open it manually from your app drawer.
) else (
    echo [OK] App launched on device.
)
echo.
echo ========================================
echo INSTALLATION COMPLETE
echo ========================================
echo.

REM ------------------------------------------------------------------
REM Final pause
REM ------------------------------------------------------------------
echo Press any key to close this window...
pause >nul
exit /b 0
