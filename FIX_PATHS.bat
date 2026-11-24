@echo off
setlocal EnableExtensions

REM ============================================================
REM Haram Blur - Fix Paths Script (Windows)
REM Creates directory junctions to avoid spaces in paths.
REM MUST be run as Administrator (right-click -> Run as administrator).
REM ============================================================

echo.
echo ========================================
echo Haram Blur - Fix Paths Script
echo ========================================
echo.
echo This script creates directory junctions to move Flutter, Android SDK,
echo Java JDK, Haram Blur project, and Pub Cache out of paths with spaces
echo (like "C:\Users\H P\").
echo.
echo Junctions created:
echo   C:\flutter         -> C:\Users\H P\flutter
echo   C:\Android         -> C:\Users\H P\Android\sdk
echo   C:\haram-blur      -> C:\Users\H P\haram-blur
echo   C:\jdk17           -> C:\Users\H P\jdk17\jdk-17.0.20+8
echo   C:\PubCache        -> C:\Users\H P\AppData\Local\Pub\Cache (or detected Pub Cache)
echo.
echo NOTE: You MUST run this as Administrator.
echo       Right-click Command Prompt -> "Run as administrator".
echo.
echo Press any key to continue...
pause >nul
echo.

REM ------------------------------------------------------------------
REM Helper: create junction if target doesn't exist
REM ------------------------------------------------------------------
:make_junction
set "JUNC=%~1"
set "TARGET=%~2"
if exist "%JUNC%" (
    echo [OK] %JUNC% already exists.
    goto :done_junction
)
echo Creating junction: %JUNC% -> %TARGET%
mklink /J "%JUNC%" "%TARGET%"
if errorlevel 1 (
    echo ERROR: Failed to create %JUNC% junction.
    echo Make sure you are running as Administrator.
    echo.
    pause
    exit /b 1
)
echo [OK] %JUNC% created.
:done_junction
echo.

REM ------------------------------------------------------------------
REM Step 1: Junction for Flutter
REM ------------------------------------------------------------------
echo [1/5] Setting up C:\flutter...
call :make_junction "C:\flutter" "C:\Users\H P\flutter"

REM ------------------------------------------------------------------
REM Step 2: Junction for Android SDK
REM ------------------------------------------------------------------
echo [2/5] Setting up C:\Android\sdk...
call :make_junction "C:\Android" "C:\Users\H P\Android"

REM ------------------------------------------------------------------
REM Step 3: Junction for Haram Blur project
REM ------------------------------------------------------------------
echo [3/5] Setting up C:\haram-blur...
call :make_junction "C:\haram-blur" "C:\Users\H P\haram-blur"

REM ------------------------------------------------------------------
REM Step 4: Junction for Java JDK
REM ------------------------------------------------------------------
echo [4/5] Setting up C:\jdk17...
call :make_junction "C:\jdk17" "C:\Users\H P\jdk17\jdk-17.0.20+8"

REM ------------------------------------------------------------------
REM Step 5: Junction for Pub Cache
REM ------------------------------------------------------------------
echo [5/5] Setting up C:\PubCache...
set "PUB_CACHE_SRC=C:\Users\H P\AppData\Local\Pub\Cache"
if exist "%PUB_CACHE_SRC%" (
    call :make_junction "C:\PubCache" "%PUB_CACHE_SRC%"
) else (
    echo [INFO] Pub Cache not found at %PUB_CACHE_SRC%
    echo Searching for Pub Cache directory...
    set "PUB_CACHE_FOUND="
    for /d %%D in ("C:\Users\H P\AppData\Local\Pub\*") do (
        if exist "%%D\Cache" (
            set "PUB_CACHE_SRC=%%D\Cache"
            set "PUB_CACHE_FOUND=1"
        )
    )
    if defined PUB_CACHE_FOUND (
        echo Found Pub Cache at %PUB_CACHE_SRC%
        call :make_junction "C:\PubCache" "%PUB_CACHE_SRC%"
    ) else (
        echo Creating empty C:\PubCache directory...
        mkdir "C:\PubCache"
        echo [OK] C:\PubCache created (empty).
    )
)

echo.
echo ========================================
echo Paths fixed!
echo ========================================
echo.
echo Junctions created:
echo   C:\flutter         -> C:\Users\H P\flutter
echo   C:\Android         -> C:\Users\H P\Android\sdk
echo   C:\haram-blur      -> C:\Users\H P\haram-blur
echo   C:\jdk17           -> C:\Users\H P\jdk17\jdk-17.0.20+8
echo   C:\PubCache        -> C:\Users\H P\AppData\Local\Pub\Cache (or detected Pub Cache)
echo.
echo You can now run BUILD_APK_FIXED.bat (no administrator needed).
echo.
pause
