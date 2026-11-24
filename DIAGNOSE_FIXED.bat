@echo off
setlocal EnableExtensions

REM ------------------------------------------------------------------
REM Haram Blur - Diagnostic Script (Windows)
REM Creates diagnostic_log_fixed.txt for troubleshooting build issues.
REM Double-click this file, then share diagnostic_log_fixed.txt with support.
REM ------------------------------------------------------------------

set "PROJECT_DIR=C:\haram-blur"
set "FLUTTER_ROOT=C:\flutter"
set "JAVA_HOME=C:\jdk17"
set "ANDROID_HOME=C:\Android\sdk"
set "PUB_CACHE=C:\PubCache"

set "FLUTTER_BAT=%FLUTTER_ROOT%\bin\flutter.bat"
set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

set "LOG_FILE=%PROJECT_DIR%\diagnostic_log_fixed.txt"

REM ------------------------------------------------------------------
REM Step 0: Log file setup
REM ------------------------------------------------------------------
echo Haram Blur Diagnostic Log > "%LOG_FILE%"
echo ======================================== >> "%LOG_FILE%"
echo Date: %date% %time% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM ------------------------------------------------------------------
REM Step 1: Display header on screen
REM ------------------------------------------------------------------
cls
echo.
echo ========================================
echo Haram Blur - Diagnostic Script
echo ========================================
echo.
echo This script collects system information and saves it to:
echo   %LOG_FILE%
echo.
echo Please share diagnostic_log_fixed.txt if you need help with build issues.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM Step 2: Environment variables
REM ------------------------------------------------------------------
echo [ENVIRONMENT VARIABLES] >> "%LOG_FILE%"
echo ------------------------ >> "%LOG_FILE%"
echo PROJECT_DIR=%PROJECT_DIR% >> "%LOG_FILE%"
echo FLUTTER_ROOT=%FLUTTER_ROOT% >> "%LOG_FILE%"
echo JAVA_HOME=%JAVA_HOME% >> "%LOG_FILE%"
echo ANDROID_HOME=%ANDROID_HOME% >> "%LOG_FILE%"
echo PUB_CACHE=%PUB_CACHE% >> "%LOG_FILE%"
echo PATH=%PATH% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

echo [SCREEN] Checking environment variables...
echo PROJECT_DIR   = %PROJECT_DIR%
echo FLUTTER_ROOT  = %FLUTTER_ROOT%
echo JAVA_HOME     = %JAVA_HOME%
echo ANDROID_HOME  = %ANDROID_HOME%
echo PUB_CACHE     = %PUB_CACHE%
echo.

REM ------------------------------------------------------------------
REM Step 3: Verify files exist
REM ------------------------------------------------------------------
echo [FILE CHECKS] >> "%LOG_FILE%"
echo ------------------------ >> "%LOG_FILE%"

echo [SCREEN] Checking required files...

call :check_file "flutter.bat" "%FLUTTER_BAT%"
call :check_file "java.exe" "%JAVA_EXE%"
call :check_file "adb.exe" "%ADB_EXE%"
call :check_file "pubspec.yaml" "%PROJECT_DIR%\pubspec.yaml"
call :check_file "build.gradle.kts" "%PROJECT_DIR%\android\app\build.gradle.kts"
call :check_file "nsfw_classifier.tflite" "%PROJECT_DIR%\assets\models\nsfw_classifier.tflite"

call :print_check "flutter.bat" "%FLUTTER_BAT%"
call :print_check "java.exe" "%JAVA_EXE%"
call :print_check "adb.exe" "%ADB_EXE%"
call :print_check "pubspec.yaml" "%PROJECT_DIR%\pubspec.yaml"
call :print_check "build.gradle.kts" "%PROJECT_DIR%\android\app\build.gradle.kts"
call :print_check "nsfw_classifier.tflite" "%PROJECT_DIR%\assets\models\nsfw_classifier.tflite"
echo.

goto :run_diagnostics

:check_file
set "NAME=%~1"
set "FPATH=%~2"
if exist "%FPATH%" (
    echo [OK]   %NAME% exists: %FPATH% >> "%LOG_FILE%"
) else (
    echo [MISSING] %NAME% NOT found: %FPATH% >> "%LOG_FILE%"
)
goto :eof

:print_check
set "NAME=%~1"
set "FPATH=%~2"
if exist "%FPATH%" (
    echo [OK]   %NAME%
) else (
    echo [MISSING] %NAME% not found
)
goto :eof

:run_diagnostics
REM ------------------------------------------------------------------
REM Step 4: Run diagnostic commands (CALL required for .bat)
REM ------------------------------------------------------------------

echo [SCREEN] Running flutter doctor -v (this may take a moment)...
call "%FLUTTER_BAT%" doctor -v >> "%LOG_FILE%" 2>&1
echo Exit code: %ERRORLEVEL% >> "%LOG_FILE%"

echo [SCREEN] Checking Java version...
"%JAVA_EXE%" -version >> "%LOG_FILE%" 2>&1
echo Exit code: %ERRORLEVEL% >> "%LOG_FILE%"

echo [SCREEN] Checking ADB version...
"%ADB_EXE%" version >> "%LOG_FILE%" 2>&1
echo Exit code: %ERRORLEVEL% >> "%LOG_FILE%"

echo [SCREEN] Listing connected devices...
"%ADB_EXE%" devices >> "%LOG_FILE%" 2>&1
echo Exit code: %ERRORLEVEL% >> "%LOG_FILE%"

echo [SCREEN] Checking Flutter precache...
call "%FLUTTER_BAT%" precache >> "%LOG_FILE%" 2>&1
echo Exit code: %ERRORLEVEL% >> "%LOG_FILE%"

echo [SCREEN] Checking pubspec.yaml assets section...
echo [pubspec.yaml assets] >> "%LOG_FILE%"
findstr /i "assets" "%PROJECT_DIR%\pubspec.yaml" >> "%LOG_FILE%" 2>&1
echo Exit code: %ERRORLEVEL% >> "%LOG_FILE%"

echo [SCREEN] Listing assets/models/ directory...
dir "%PROJECT_DIR%\assets\models\" >> "%LOG_FILE%" 2>&1
echo Exit code: %ERRORLEVEL% >> "%LOG_FILE%"

echo [SCREEN] Checking if APK exists...
if exist "%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk" (
    echo [APK EXISTS] app-debug.apk >> "%LOG_FILE%"
    for %%F in ("%PROJECT_DIR%\build\app\outputs\flutter-apk\app-debug.apk") do (
        echo APK size: %%~zF bytes >> "%LOG_FILE%"
    )
) else (
    echo [APK NOT FOUND] app-debug.apk >> "%LOG_FILE%"
)

REM ------------------------------------------------------------------
REM Step 5: Finish
REM ------------------------------------------------------------------
echo. >> "%LOG_FILE%"
echo ======================================== >> "%LOG_FILE%"
echo End of diagnostic log >> "%LOG_FILE%"
echo Date: %date% %time% >> "%LOG_FILE%"

echo ========================================
echo DIAGNOSTIC LOG COMPLETE
echo ========================================
echo.
echo Log saved to: %LOG_FILE%
echo.
echo Please share diagnostic_log_fixed.txt if you need help with build issues.
echo.
pause
