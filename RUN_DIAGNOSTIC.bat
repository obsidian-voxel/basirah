@echo off
echo Running diagnostics... > C:\Users\H P\haram-blur\diagnostic.txt
echo Date: %DATE% %TIME% >> C:\Users\H P\haram-blur\diagnostic.txt
echo. >> C:\Users\H P\haram-blur\diagnostic.txt

echo Checking Windows version... >> C:\Users\H P\haram-blur\diagnostic.txt
ver >> C:\Users\H P\haram-blur\diagnostic.txt
echo. >> C:\Users\H P\haram-blur\diagnostic.txt

echo Checking if cmd.exe exists... >> C:\Users\H P\haram-blur\diagnostic.txt
where cmd.exe >> C:\Users\H P\haram-blur\diagnostic.txt 2>&1
echo. >> C:\Users\H P\haram-blur\diagnostic.txt

echo Checking current directory... >> C:\Users\H P\haram-blur\diagnostic.txt
echo CD: %CD% >> C:\Users\H P\haram-blur\diagnostic.txt
echo. >> C:\Users\H P\haram-blur\diagnostic.txt

echo Checking if TEST1.bat exists... >> C:\Users\H P\haram-blur\diagnostic.txt
if exist "C:\Users\H P\haram-blur\TEST1.bat" (
    echo TEST1.bat exists >> C:\Users\H P\haram-blur\diagnostic.txt
) else (
    echo TEST1.bat NOT FOUND >> C:\Users\H P\haram-blur\diagnostic.txt
)
echo. >> C:\Users\H P\haram-blur\diagnostic.txt

echo Checking if build_log.txt exists... >> C:\Users\H P\haram-blur\diagnostic.txt
if exist "C:\Users\H P\haram-blur\build_log.txt" (
    echo build_log.txt exists >> C:\Users\H P\haram-blur\diagnostic.txt
    echo Contents: >> C:\Users\H P\haram-blur\diagnostic.txt
    type "C:\Users\H P\haram-blur\build_log.txt" >> C:\Users\H P\haram-blur\diagnostic.txt
) else (
    echo build_log.txt NOT FOUND - script never started >> C:\Users\H P\haram-blur\diagnostic.txt
)
echo. >> C:\Users\H P\haram-blur\diagnostic.txt

echo Diagnostic complete. Check diagnostic.txt
pause
