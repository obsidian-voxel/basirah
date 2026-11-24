@echo off
setlocal EnableExtensions

REM ------------------------------------------------------------------
REM Haram Blur - Diagnostic Build Script (Windows)
REM Ultra-verbose: logs every step and pauses after every command
REM Log file: C:\Users\H P\haram-blur\diagnostic_build_log.txt
REM ------------------------------------------------------------------

set "FLUTTER_ROOT=C:\flutter"
set "JAVA_HOME=C:\jdk17"
set "ANDROID_HOME=C:\Android\sdk"
set "PROJECT_DIR=C:\haram-blur"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

set "FLUTTER_BAT=%FLUTTER_ROOT%\bin\flutter.bat"
set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"

set "LOGFILE=%PROJECT_DIR%\diagnostic_build_log.txt"

REM ------------------------------------------------------------------
REM Step 0: Header and initial pause
REM ------------------------------------------------------------------
echo.
echo ========================================
echo Haram Blur - DIAGNOSTIC Build Script
echo ========================================
echo.
echo This script is ULTRA-VERBOSE and will pause after EVERY step.
echo Press Enter at each pause to continue.
echo.
echo Log file: %LOGFILE%
echo.
echo [%TIME%] Starting diagnostic build script >> "%LOGFILE%" 2>&1
echo [%TIME%] PROJECT_DIR=%PROJECT_DIR% >> "%LOGFILE%" 2>&1
echo [%TIME%] FLUTTER_ROOT=%FLUTTER_ROOT% >> "%LOGFILE%" 2>&1
echo [%TIME%] JAVA_HOME=%JAVA_HOME% >> "%LOGFILE%" 2>&1
echo [%TIME%] ANDROID_HOME=%ANDROID_HOME% >> "%LOGFILE%" 2>&1
echo [%TIME%] LOGFILE=%LOGFILE% >> "%LOGFILE%" 2>&1
echo [%TIME%] APK_PATH=%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk >> "%LOGFILE%" 2>&1
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 1: Verify Flutter exists
REM ------------------------------------------------------------------
echo [%TIME%] Checking if flutter.bat exists at %FLUTTER_ROOT%\bin\flutter.bat >> "%LOGFILE%" 2>&1
if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
    echo [%TIME%] ERROR: Flutter not found at %FLUTTER_ROOT%\bin\flutter.bat >> "%LOGFILE%" 2>&1
    echo ERROR: Flutter not found at %FLUTTER_ROOT%\bin\flutter.bat
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] Flutter found at %FLUTTER_ROOT%\bin\flutter.bat >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter found.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 2: Verify Java exists
REM ------------------------------------------------------------------
echo [%TIME%] Checking if java.exe exists at %JAVA_HOME%\bin\java.exe >> "%LOGFILE%" 2>&1
if not exist "%JAVA_HOME%\bin\java.exe" (
    echo [%TIME%] ERROR: Java not found at %JAVA_HOME%\bin\java.exe >> "%LOGFILE%" 2>&1
    echo ERROR: Java not found at %JAVA_HOME%\bin\java.exe
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] Java found at %JAVA_HOME%\bin\java.exe >> "%LOGFILE%" 2>&1
echo [%TIME%] Java found.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 3: Verify ADB exists
REM ------------------------------------------------------------------
echo [%TIME%] Checking if adb.exe exists at %ANDROID_HOME%\platform-tools\adb.exe >> "%LOGFILE%" 2>&1
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
    echo [%TIME%] ERROR: ADB not found at %ANDROID_HOME%\platform-tools\adb.exe >> "%LOGFILE%" 2>&1
    echo ERROR: ADB not found at %ANDROID_HOME%\platform-tools\adb.exe
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] ADB found at %ANDROID_HOME%\platform-tools\adb.exe >> "%LOGFILE%" 2>&1
echo [%TIME%] ADB found.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 4: Verify pubspec.yaml exists
REM ------------------------------------------------------------------
echo [%TIME%] Checking if pubspec.yaml exists at %PROJECT_DIR%\pubspec.yaml >> "%LOGFILE%" 2>&1
if not exist "%PROJECT_DIR%\pubspec.yaml" (
    echo [%TIME%] ERROR: pubspec.yaml not found at %PROJECT_DIR%\pubspec.yaml >> "%LOGFILE%" 2>&1
    echo ERROR: pubspec.yaml not found at %PROJECT_DIR%\pubspec.yaml
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] pubspec.yaml found at %PROJECT_DIR%\pubspec.yaml >> "%LOGFILE%" 2>&1
echo [%TIME%] pubspec.yaml found.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 5: Verify nsfw_classifier.tflite exists
REM ------------------------------------------------------------------
echo [%TIME%] Checking if nsfw_classifier.tflite exists >> "%LOGFILE%" 2>&1
if not exist "%PROJECT_DIR%\assets\models\nsfw_classifier.tflite" (
    echo [%TIME%] ERROR: nsfw_classifier.tflite not found >> "%LOGFILE%" 2>&1
    echo ERROR: nsfw_classifier.tflite not found at %PROJECT_DIR%\assets\models\nsfw_classifier.tflite
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] nsfw_classifier.tflite found >> "%LOGFILE%" 2>&1
echo [%TIME%] nsfw_classifier.tflite found.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 6: Flutter version check (CALL required)
REM ------------------------------------------------------------------
echo [%TIME%] Running: call "%FLUTTER_BAT%" --version >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter version: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" --version >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter version check completed with errorlevel %errorlevel% >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [%TIME%] ERROR: Flutter version check failed (error code %errorlevel%) >> "%LOGFILE%" 2>&1
    echo ERROR: Flutter version check failed (error code %errorlevel%)
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] Flutter version check passed.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 7: Java version check
REM ------------------------------------------------------------------
echo [%TIME%] Running: "%JAVA_EXE%" -version >> "%LOGFILE%" 2>&1
echo [%TIME%] Java version: >> "%LOGFILE%" 2>&1
"%JAVA_EXE%" -version >> "%LOGFILE%" 2>&1
echo [%TIME%] Java version check completed with errorlevel %errorlevel% >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [%TIME%] ERROR: Java version check failed (error code %errorlevel%) >> "%LOGFILE%" 2>&1
    echo ERROR: Java version check failed (error code %errorlevel%)
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] Java version check passed.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 8: ADB version check
REM ------------------------------------------------------------------
echo [%TIME%] Running: "%ADB_EXE%" version >> "%LOGFILE%" 2>&1
echo [%TIME%] ADB version: >> "%LOGFILE%" 2>&1
"%ADB_EXE%" version >> "%LOGFILE%" 2>&1
echo [%TIME%] ADB version check completed with errorlevel %errorlevel% >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [%TIME%] ERROR: ADB version check failed (error code %errorlevel%) >> "%LOGFILE%" 2>&1
    echo ERROR: ADB version check failed (error code %errorlevel%)
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] ADB version check passed.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 9: Delete old APK
REM ------------------------------------------------------------------
echo [%TIME%] Deleting old APK if it exists >> "%LOGFILE%" 2>&1
if exist "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk" (
    del /f /q "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk"
    echo [%TIME%] Deleted old APK >> "%LOGFILE%" 2>&1
) else (
    echo [%TIME%] No old APK to delete >> "%LOGFILE%" 2>&1
)
echo [%TIME%] Old APK cleanup done.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 10: Flutter clean (CALL required)
REM ------------------------------------------------------------------
echo [%TIME%] Running: call "%FLUTTER_BAT%" clean >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter clean: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" clean >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter clean completed with errorlevel %errorlevel% >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [%TIME%] ERROR: Flutter clean failed (error code %errorlevel%) >> "%LOGFILE%" 2>&1
    echo ERROR: Flutter clean failed (error code %errorlevel%)
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] Flutter clean passed.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 11: Flutter pub get (CALL required)
REM ------------------------------------------------------------------
echo [%TIME%] Running: call "%FLUTTER_BAT%" pub get >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter pub get: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" pub get >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter pub get completed with errorlevel %errorlevel% >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [%TIME%] ERROR: Flutter pub get failed (error code %errorlevel%) >> "%LOGFILE%" 2>&1
    echo ERROR: Flutter pub get failed (error code %errorlevel%)
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] Flutter pub get passed.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 12: Flutter build apk --debug (CALL required)
REM ------------------------------------------------------------------
echo [%TIME%] Running: call "%FLUTTER_BAT%" build apk --debug >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter build apk --debug: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" build apk --debug >> "%LOGFILE%" 2>&1
echo [%TIME%] Flutter build completed with errorlevel %errorlevel% >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo [%TIME%] ERROR: Flutter build failed (error code %errorlevel%) >> "%LOGFILE%" 2>&1
    echo.
    echo ========================================
    echo BUILD FAILED
    echo ========================================
    echo Error code: %errorlevel%
    echo.
    echo Log file: %LOGFILE%
    echo.
    echo [%TIME%] Exiting with error code %errorlevel% >> "%LOGFILE%" 2>&1
    pause
    exit /b %errorlevel%
)
echo [%TIME%] APK built successfully.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 13: Verify APK exists
REM ------------------------------------------------------------------
echo [%TIME%] Checking if APK exists at %PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk >> "%LOGFILE%" 2>&1
if exist "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk" (
    echo [%TIME%] APK found >> "%LOGFILE%" 2>&1
    for %%F in ("%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk") do (
        echo [%TIME%] APK size: %%~zF bytes >> "%LOGFILE%" 2>&1
    )
) else (
    echo [%TIME%] APK NOT found >> "%LOGFILE%" 2>&1
    echo [%TIME%] ERROR: APK not found at expected location >> "%LOGFILE%" 2>&1
    echo ERROR: APK not found at expected location!
    echo.
    echo [%TIME%] Exiting with error code 1 >> "%LOGFILE%" 2>&1
    pause
    exit /b 1
)
echo [%TIME%] APK verified.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 14: Final completion
REM ------------------------------------------------------------------
echo [%TIME%] Build process completed successfully >> "%LOGFILE%" 2>&1
echo.
echo ========================================
echo BUILD SUCCESSFUL
echo ========================================
echo APK location: %PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk
echo.
echo Log file: %LOGFILE%
echo.
echo [%TIME%] All steps completed. Press any key to close... >> "%LOGFILE%" 2>&1
echo ========================================
echo Build process completed
echo ========================================
echo Check "%LOGFILE%" for full details.
echo.
echo Press any key to close this window...
pause >nul
exit /b 0
