Write-Host "========================================" -ForegroundColor Green
Write-Host "Haram Blur Build Script (PowerShell)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Set paths
$env:FLUTTER_ROOT = "C:\Users\H P\flutter"
$env:JAVA_HOME = "C:\Users\H P\jdk17\jdk-17.0.20+8"
$env:ANDROID_HOME = "C:\Users\H P\Android\sdk"
$env:PATH = "$env:FLUTTER_ROOT\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"

Write-Host "Checking Flutter..." -ForegroundColor Cyan
flutter --version
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Flutter check failed" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Checking Java..." -ForegroundColor Cyan
java -version
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Java check failed" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Checking ADB..." -ForegroundColor Cyan
adb version
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: ADB check failed" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Accepting Android SDK licenses..." -ForegroundColor Cyan
echo y | flutter doctor --android-licenses > $null 2>&1

Write-Host ""
Write-Host "Starting build..." -ForegroundColor Cyan
Write-Host "This may take 2-5 minutes" -ForegroundColor Yellow
Write-Host ""

flutter build apk --debug

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "BUILD FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error code: $LASTEXITCODE" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "BUILD SUCCESSFUL" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$apkPath = "build\app\outputs\flutter-apk\app-debug.apk"
if (Test-Path $apkPath) {
    $apkSize = (Get-Item $apkPath).Length / 1MB
    Write-Host "APK location: $apkPath" -ForegroundColor Green
    Write-Host "APK size: $([math]::Round($apkSize, 2)) MB" -ForegroundColor Green
}

Write-Host ""
Read-Host "Press Enter to exit"
