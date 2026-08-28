@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Setup.ps1" %*
if errorlevel 1 goto error

echo.
echo Setup completed.
exit /b 0

:error
echo.
echo Setup failed. Review the error above and docs\troubleshooting.md.
pause
exit /b 1
