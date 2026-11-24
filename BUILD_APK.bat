@echo off
echo Haram Blur Build Script
echo Press any key to start building...
pause

REM ------------------------------------------------------------------
REM Haram Blur - APK Build Script (Windows)
REM ------------------------------------------------------------------

setlocal enabledelayedexpansion

REM ------------------------------------------------------------------
REM STEP 1: Set environment paths (explicit, not relying on system PATH)
REM ------------------------------------------------------------------
set "FLUTTER_ROOT=C:\Users\H P\flutter"
set "JAVA_HOME=C:\Users\H P\jdk17\jdk-17.0.20+8"
set "ANDROID_HOME=C:\Users\H P\Android\sdk"

set "FLUTTER_BAT=%FLUTTER_ROOT%\bin\flutter.bat"
set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\cmdline-tools\latest\bin;%PATH%"

REM ------------------------------------------------------------------
REM STEP 2: Verify tools are accessible
REM ------------------------------------------------------------------
echo Checking Flutter...
if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
    echo ERROR: Flutter not found at %FLUTTER_ROOT%
    pause
    exit /b 1
)
echo Flutter found: %FLUTTER_ROOT%

echo Checking Java...
if not exist "%JAVA_HOME%\bin\java.exe" (
    echo ERROR: Java not found at %JAVA_HOME%
    pause
    exit /b 1
)
echo Java found: %JAVA_HOME%

echo Checking Android SDK...
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
    echo ERROR: ADB not found at %ANDROID_HOME%
    pause
    exit /b 1
)
echo Android SDK found: %ANDROID_HOME%
echo.

REM ------------------------------------------------------------------
REM STEP 3: Display header
REM ------------------------------------------------------------------
cls
echo.
echo ============================================================
echo Haram Blur - APK Build Script
echo ============================================================
echo.
echo [INFO] FLUTTER_ROOT   = %FLUTTER_ROOT%
echo [INFO] JAVA_HOME      = %JAVA_HOME%
echo [INFO] ANDROID_HOME   = %ANDROID_HOME%
echo.

REM ------------------------------------------------------------------
REM STEP 4: Accept Android licenses (CALL required for .bat)
REM ------------------------------------------------------------------
echo [STEP] Accepting Android SDK licenses (this may take a moment)...
echo y | call "%FLUTTER_BAT%" doctor --android-licenses >nul 2>&1
echo [OK]   License acceptance attempted.
echo.

REM ------------------------------------------------------------------
REM STEP 5: Run flutter doctor (CALL required for .bat)
REM ------------------------------------------------------------------
echo [STEP] Running flutter doctor...
call "%FLUTTER_BAT%" doctor
if errorlevel 1 (
    echo [WARN] flutter doctor reported issues. You may want to fix them first.
    echo         Continuing with build anyway...
)
echo.

REM ------------------------------------------------------------------
REM STEP 6: Build the APK (CALL required for .bat)
REM ------------------------------------------------------------------
echo.
echo ========================================
echo Starting APK build...
echo This may take 2-5 minutes
echo ========================================
echo.

call "%FLUTTER_BAT%" build apk --debug
if errorlevel 1 (
    echo.
    echo ========================================
    echo BUILD FAILED
    echo ========================================
    echo Error code: %errorlevel%
    echo.
    echo Common fixes:
    echo - Run DIAGNOSE.bat to check your setup
    echo - Make sure Android SDK is installed
    echo - Make sure Java 17 is installed
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo BUILD SUCCESSFUL
echo ========================================
echo APK location: build\app\outputs\flutter-apk\app-debug.apk

if exist "build\app\outputs\flutter-apk\app-debug.apk" (
    for %%F in ("build\app\outputs\flutter-apk\app-debug.apk") do (
        echo APK size: %%~zF bytes
        set /a APK_SIZE_MB=%%~zF / 1048576
        echo APK size: %APK_SIZE_MB% MB
    )
)
echo.

REM ------------------------------------------------------------------
REM STEP 7: Final pause
REM ------------------------------------------------------------------
echo Press any key to close this window...
pause >nul
