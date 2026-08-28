@echo off
setlocal
cd /d "%~dp0"

title Android Root GMS - Cold Boot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Launch-Cold-Boot.ps1" %*
if errorlevel 1 goto error

echo.
echo Emulator ready.
exit /b 0

:error
echo.
echo Cold boot failed. Review the error above and docs\troubleshooting.md.
pause
exit /b 1
