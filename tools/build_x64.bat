@echo off
rem Builds the x86_64 debug APK the Phase 1 emulator harness installs.
rem %~dp0 is this tools\ directory, so the project root is its parent.
rem NOTE: this is a debug build for tools/harness only; it is never shipped.
cd /d "%~dp0.."
call C:\flutter\bin\flutter.bat build apk --debug --target-platform android-x64
echo BUILD_EXIT=%ERRORLEVEL%
