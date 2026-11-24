@echo off
REM ============================================================
REM Haram Blur - Diagnostic Script (Windows)
REM Creates a diagnostic log file for troubleshooting build issues.
REM Double-click this file, then share diagnostic_log.txt with support.
REM ============================================================

setlocal enabledelayedexpansion

REM ------------------------------------------------------------------
REM STEP 1: Set environment paths
REM ------------------------------------------------------------------
set "FLUTTER_ROOT=C:\Users\H P\flutter"
set "JAVA_HOME=C:\Users\H P\jdk17\jdk-17.0.20+8"
set "ANDROID_HOME=C:\Users\H P\Android\sdk"

set "FLUTTER_BAT=%FLUTTER_ROOT%\bin\flutter.bat"
set "JAVA_EXE=%JAVA_HOME%\bin\java.exe"
set "ADB_EXE=%ANDROID_HOME%\platform-tools\adb.exe"

set "PATH=%FLUTTER_ROOT%\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

REM ------------------------------------------------------------------
REM STEP 2: Log file setup
REM ------------------------------------------------------------------
set "LOG_FILE=%~dp0diagnostic_log.txt"

echo Haram Blur Diagnostic Log > "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"
echo Date: %date% %time% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM ------------------------------------------------------------------
REM STEP 3: Display header on screen
REM ------------------------------------------------------------------
cls
echo.
echo ============================================================
echo Haram Blur - Diagnostic Script
echo ============================================================
echo.
echo This script collects system information and saves it to:
echo   %LOG_FILE%
echo.
echo Please share this file if you need help with build issues.
echo.
pause
echo.

REM ------------------------------------------------------------------
REM STEP 4: Environment variables
REM ------------------------------------------------------------------
echo [ENVIRONMENT VARIABLES] >> "%LOG_FILE%"
echo ------------------------ >> "%LOG_FILE%"
echo FLUTTER_ROOT=%FLUTTER_ROOT% >> "%LOG_FILE%"
echo JAVA_HOME=%JAVA_HOME% >> "%LOG_FILE%"
echo ANDROID_HOME=%ANDROID_HOME% >> "%LOG_FILE%"
echo PATH=%PATH% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

echo [SCREEN] Checking environment variables...
echo FLUTTER_ROOT   = %FLUTTER_ROOT%
echo JAVA_HOME      = %JAVA_HOME%
echo ANDROID_HOME   = %ANDROID_HOME%
echo.

REM ------------------------------------------------------------------
REM STEP 5: Verify files exist
REM ------------------------------------------------------------------
echo [FILE CHECKS] >> "%LOG_FILE%"
echo ------------------------ >> "%LOG_FILE%"

call :check_file "flutter.bat" "%FLUTTER_BAT%"
call :check_file "java.exe" "%JAVA_EXE%"
call :check_file "adb.exe" "%ADB_EXE%"
call :check_file "pubspec.yaml" "%~dp0pubspec.yaml"
call :check_file "build.gradle.kts" "%~dp0android\app\build.gradle.kts"
call :check_file "nsfw_classifier.tflite" "%~dp0assets\models\nsfw_classifier.tflite"

echo [SCREEN] Checking required files...
call :print_check "flutter.bat" "%FLUTTER_BAT%"
call :print_check "java.exe" "%JAVA_EXE%"
call :print_check "adb.exe" "%ADB_EXE%"
call :print_check "pubspec.yaml" "%~dp0pubspec.yaml"
call :print_check "build.gradle.kts" "%~dp0android\app\build.gradle.kts"
call :print_check "nsfw_classifier.tflite" "%~dp0assets\models\nsfw_classifier.tflite"
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
REM STEP 6: Run diagnostic commands (CALL required for .bat)
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

REM ------------------------------------------------------------------
REM STEP 7: Finish
REM ------------------------------------------------------------------
echo. >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"
echo End of diagnostic log >> "%LOG_FILE%"
echo Date: %date% %time% >> "%LOG_FILE%"

echo ============================================================
echo DIAGNOSTIC LOG COMPLETE
echo ============================================================
echo.
echo Log saved to: %LOG_FILE%
echo.
echo Please share diagnostic_log.txt if you need help.
echo.
pause
