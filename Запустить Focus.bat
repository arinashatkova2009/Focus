@echo off
setlocal
cd /d "%~dp0"
if exist "%~dp0appfocus.exe" (
    start "" "%~dp0appfocus.exe"
    exit /b 0
)
if exist "%~dp0build-qt\appfocus.exe" (
    start "" "%~dp0build-qt\appfocus.exe"
    exit /b 0
)
echo Open CMakeLists.txt in Qt Creator and press Ctrl+R to build and run Focus.
pause
