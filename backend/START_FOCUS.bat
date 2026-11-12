@echo off
cd /d "%~dp0"
python start_focus.py
if errorlevel 1 echo Failed to start. Check Python and the error above.
pause
