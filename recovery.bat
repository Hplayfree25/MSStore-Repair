@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "ROOT=%~dp0"
set "SCRIPT=%ROOT%recovery.ps1"

if not exist "%SCRIPT%" (
    color 0C
    echo.
    echo MSStore Repair cannot start because recovery.ps1 was not found.
    echo Expected path: "%SCRIPT%"
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %errorlevel%
