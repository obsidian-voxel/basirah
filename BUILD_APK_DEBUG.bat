@echo off
echo Starting build script...
pause
echo Script is running...

REM ------------------------------------------------------------------
REM Haram Blur - Debug Build Script
REM Logs everything to build_log.txt and pauses before every exit
REM ------------------------------------------------------------------

set LOGFILE=C:\Users\H P\haram-blur\build_log.txt
echo Build started at %date% %time% > "%LOGFILE%"

echo.
echo ========================================
echo Haram Blur - Debug Build Script
echo ========================================
echo.
echo Log file: %LOGFILE%
echo.

REM ------------------------------------------------------------------
REM Step 1: Set environment paths
REM ------------------------------------------------------------------
echo [1/6] Setting environment paths...
echo Running: set FLUTTER_ROOT >> "%LOGFILE%"
set FLUTTER_ROOT=C:\Users\H P\flutter
echo FLUTTER_ROOT=%FLUTTER_ROOT% >> "%LOGFILE%" 2>&1

echo Running: set JAVA_HOME >> "%LOGFILE%"
set JAVA_HOME=C:\Users\H P\jdk17\jdk-17.0.20+8
echo JAVA_HOME=%JAVA_HOME% >> "%LOGFILE%" 2>&1

echo Running: set ANDROID_HOME >> "%LOGFILE%"
set ANDROID_HOME=C:\Users\H P\Android\sdk
echo ANDROID_HOME=%ANDROID_HOME% >> "%LOGFILE%" 2>&1

echo Running: set PATH >> "%LOGFILE%"
set PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%
echo PATH updated >> "%LOGFILE%" 2>&1

echo [1/6] Environment paths set.
echo.

REM ------------------------------------------------------------------
REM Step 2: Verify Flutter (CALL required for .bat)
REM ------------------------------------------------------------------
echo [2/6] Verifying Flutter...
echo Running: call flutter.bat --version >> "%LOGFILE%"
call "%FLUTTER_ROOT%\bin\flutter.bat" --version >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo ERROR: Command failed with error code %errorlevel%
    echo Command was: flutter --version
    echo.
    echo Check build_log.txt for details
    pause
    exit /b 1
)
echo [2/6] Flutter verified.
echo.

REM ------------------------------------------------------------------
REM Step 3: Verify Java
REM ------------------------------------------------------------------
echo [3/6] Verifying Java...
echo Running: java -version >> "%LOGFILE%"
"%JAVA_HOME%\bin\java.exe" -version >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo ERROR: Command failed with error code %errorlevel%
    echo Command was: java -version
    echo.
    echo Check build_log.txt for details
    pause
    exit /b 1
)
echo [3/6] Java verified.
echo.

REM ------------------------------------------------------------------
REM Step 4: Verify ADB
REM ------------------------------------------------------------------
echo [4/6] Verifying ADB...
echo Running: adb version >> "%LOGFILE%"
"%ANDROID_HOME%\platform-tools\adb.exe" version >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo ERROR: Command failed with error code %errorlevel%
    echo Command was: adb version
    echo.
    echo Check build_log.txt for details
    pause
    exit /b 1
)
echo [4/6] ADB verified.
echo.

REM ------------------------------------------------------------------
REM Step 5: Accept Android licenses (CALL required for .bat)
REM ------------------------------------------------------------------
echo [5/6] Accepting Android SDK licenses...
echo Running: call flutter.bat doctor --android-licenses >> "%LOGFILE%"
echo y | call "%FLUTTER_ROOT%\bin\flutter.bat" doctor --android-licenses >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    echo WARNING: License acceptance may have failed (continuing anyway)
    echo.
)
echo [5/6] License acceptance attempted.
echo.

REM ------------------------------------------------------------------
REM Step 6: Build the APK (CALL required for .bat)
REM ------------------------------------------------------------------
echo [6/6] Building debug APK...
echo.
echo ========================================
echo Starting APK build...
echo This may take 2-5 minutes
echo ========================================
echo.
echo Running: call flutter.bat build apk --debug >> "%LOGFILE%"
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --debug >> "%LOGFILE%" 2>&1
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
    echo Check build_log.txt for full error details
    echo.
    pause
    exit /b 1
)

echo [6/6] Build completed successfully.
echo.

REM ------------------------------------------------------------------
REM Step 7: Report results
REM ------------------------------------------------------------------
echo ========================================
echo BUILD SUCCESSFUL
echo ========================================
echo APK location: build\app\outputs\flutter-apk\app-debug.apk
echo.

if exist "build\app\outputs\flutter-apk\app-debug.apk" (
    echo Found APK file.
    for %%F in ("build\app\outputs\flutter-apk\app-debug.apk") do (
        echo APK size: %%~zF bytes
        set /a APK_SIZE_MB=%%~zF / 1048576
        echo APK size: %APK_SIZE_MB% MB
    )
) else (
    echo WARNING: APK not found at expected location
)

echo.
echo Build log saved to: %LOGFILE%
echo.

REM ------------------------------------------------------------------
REM Final pause - script NEVER exits without pausing
REM ------------------------------------------------------------------
echo.
echo ========================================
echo Build process completed
echo ========================================
echo Check build_log.txt for details
echo.
echo Press any key to close this window...
pause >nul
exit /b 0
