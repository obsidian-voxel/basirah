@echo off
setlocal EnableExtensions

REM ------------------------------------------------------------------
REM Haram Blur - Reliable APK Build Script (Windows)
REM Double-click this file to build the debug APK.
REM ------------------------------------------------------------------

set "PROJECT_DIR=C:\haram-blur"
set "FLUTTER_ROOT=C:\flutter"
set "JAVA_HOME=C:\jdk17"
set "ANDROID_HOME=C:\Android\sdk"
set "PUB_CACHE=C:\PubCache"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PUB_CACHE%\bin;%PATH%"

set "FLUTTER_BAT=%FLUTTER_ROOT%\bin\flutter.bat"
set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"

set "LOGFILE=%PROJECT_DIR%\build_log_fixed.txt"
set "APK_PATH=%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk"

REM ------------------------------------------------------------------
REM Step 0: Pause at beginning so window stays open
REM ------------------------------------------------------------------
echo.
echo ========================================
echo Haram Blur - Reliable APK Build Script
echo ========================================
echo.
echo PROJECT_DIR  = %PROJECT_DIR%
echo FLUTTER_ROOT = %FLUTTER_ROOT%
echo JAVA_HOME    = %JAVA_HOME%
echo ANDROID_HOME = %ANDROID_HOME%
echo PUB_CACHE    = %PUB_CACHE%
echo LOGFILE      = %LOGFILE%
echo.
echo Press any key to start building...
pause >nul
echo.

REM ------------------------------------------------------------------
REM Step 1: Verify required files exist
REM ------------------------------------------------------------------
echo [1/7] Verifying required files...

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
    echo ERROR: Flutter not found at %FLUTTER_ROOT%\bin\flutter.bat
    echo.
    pause
    exit /b 1
)
echo [OK] flutter.bat found

if not exist "%JAVA_HOME%\bin\java.exe" (
    echo ERROR: Java not found at %JAVA_HOME%\bin\java.exe
    echo.
    pause
    exit /b 1
)
echo [OK] java.exe found

if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
    echo ERROR: ADB not found at %ANDROID_HOME%\platform-tools\adb.exe
    echo.
    pause
    exit /b 1
)
echo [OK] adb.exe found

if not exist "%PROJECT_DIR%\pubspec.yaml" (
    echo ERROR: pubspec.yaml not found at %PROJECT_DIR%\pubspec.yaml
    echo.
    pause
    exit /b 1
)
echo [OK] pubspec.yaml found

if not exist "%PROJECT_DIR%\assets\models\nsfw_classifier.tflite" (
    echo ERROR: nsfw_classifier.tflite not found at %PROJECT_DIR%\assets\models\nsfw_classifier.tflite
    echo.
    pause
    exit /b 1
)
echo [OK] nsfw_classifier.tflite found

echo [1/7] All required files verified.
echo.

REM ------------------------------------------------------------------
REM Step 2: Delete old APK so we do not confuse old with new
REM ------------------------------------------------------------------
echo [2/7] Removing old APK (if any)... >> "%LOGFILE%" 2>&1
del /f /q "%APK_PATH%" >> "%LOGFILE%" 2>&1
echo [2/7] APK cleanup complete >> "%LOGFILE%" 2>&1
echo [2/7] Old APK cleanup done.
echo.

REM ------------------------------------------------------------------
REM Step 3: Flutter version (CALL required for .bat)
REM ------------------------------------------------------------------
echo [3/7] Checking Flutter version...
echo Running: call "%FLUTTER_BAT%" --version >> "%LOGFILE%" 2>&1
echo Flutter version: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" --version >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: Flutter version check failed (error code %errorlevel%)
    echo Check "%LOGFILE%" for details.
    echo.
    pause
    exit /b 1
)
echo [OK] Flutter version check passed.
echo.

REM ------------------------------------------------------------------
REM Step 4: Java version
REM ------------------------------------------------------------------
echo [4/7] Checking Java version...
echo Running: "%JAVA_EXE%" -version >> "%LOGFILE%" 2>&1
echo Java version: >> "%LOGFILE%" 2>&1
"%JAVA_EXE%" -version >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: Java version check failed (error code %errorlevel%)
    echo Check "%LOGFILE%" for details.
    echo.
    pause
    exit /b 1
)
echo [OK] Java version check passed.
echo.

REM ------------------------------------------------------------------
REM Step 5: ADB version
REM ------------------------------------------------------------------
echo [5/7] Checking ADB version...
echo Running: "%ADB_EXE%" version >> "%LOGFILE%" 2>&1
echo ADB version: >> "%LOGFILE%" 2>&1
"%ADB_EXE%" version >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: ADB version check failed (error code %errorlevel%)
    echo Check "%LOGFILE%" for details.
    echo.
    pause
    exit /b 1
)
echo [OK] ADB version check passed.
echo.

REM ------------------------------------------------------------------
REM Step 6: Flutter clean + pub get + build apk (CALL required for .bat)
REM ------------------------------------------------------------------
echo [6/7] Building debug APK (this may take several minutes)...
echo Flutter clean: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" clean >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo.
    echo ========================================
    echo BUILD FAILED
    echo ========================================
    echo Error code: %errorlevel%
    echo.
    echo Last 40 lines of log:
    echo ------------------------
    powershell -NoProfile -Command "Get-Content -LiteralPath '%LOGFILE%' -Tail 40" 2>&1 || type "%LOGFILE%"
    echo ------------------------
    echo.
    pause
    exit /b 1
)
echo Flutter pub get: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" pub get >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo.
    echo ========================================
    echo BUILD FAILED
    echo ========================================
    echo Error code: %errorlevel%
    echo.
    echo Last 40 lines of log:
    echo ------------------------
    powershell -NoProfile -Command "Get-Content -LiteralPath '%LOGFILE%' -Tail 40" 2>&1 || type "%LOGFILE%"
    echo ------------------------
    echo.
    pause
    exit /b 1
)
echo Flutter build apk --debug: >> "%LOGFILE%" 2>&1
call "%FLUTTER_BAT%" build apk --debug >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo.
    echo ========================================
    echo BUILD FAILED
    echo ========================================
    echo Error code: %errorlevel%
    echo.
    echo Log file: %LOGFILE%
    echo.
    echo Last 40 lines of log:
    echo ------------------------
    powershell -NoProfile -Command "Get-Content -LiteralPath '%LOGFILE%' -Tail 40" 2>&1 || type "%LOGFILE%"
    echo ------------------------
    echo.
    pause
    exit /b 1
)
echo [6/7] APK built successfully.
echo.

REM ------------------------------------------------------------------
REM Step 7: Report results
REM ------------------------------------------------------------------
echo ========================================
echo BUILD SUCCESSFUL
echo ========================================
echo APK location: %APK_PATH%

if exist "%APK_PATH%" (
    for %%F in ("%APK_PATH%") do (
        echo APK size: %%~zF bytes
        set /a APK_SIZE_MB=%%~zF / 1048576
        echo APK size: %APK_SIZE_MB% MB
    )
) else (
    echo WARNING: APK not found at expected location!
    echo.
    pause
    exit /b 1
)

echo.
echo Log file: %LOGFILE%
echo.

REM ------------------------------------------------------------------
REM Final pause - script NEVER exits without pausing
REM ------------------------------------------------------------------
echo.
echo ========================================
echo Build process completed
echo ========================================
echo Check "%LOGFILE%" for full details.
echo.
echo Press any key to close this window...
pause >nul
exit /b 0
