@echo off
REM ============================================================================
REM Setup-RemoteHelp.bat — Double-clickable launcher
REM ============================================================================
REM
REM This installs Tailscale and OpenSSH so Shands can connect to Mike's
REM computer and fix things without Mike having to type commands.
REM
REM Mike just double-clicks this file. One run, done.
REM ============================================================================

setlocal

set "SCRIPT_DIR=%~dp0"

if not exist "%SCRIPT_DIR%Setup-RemoteHelp.ps1" (
    echo.
    echo ERROR: Cannot find Setup-RemoteHelp.ps1 in this folder:
    echo   %SCRIPT_DIR%
    echo.
    echo Make sure both Setup-RemoteHelp.bat and Setup-RemoteHelp.ps1 are
    echo in the same folder, then double-click this file again.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo Asking Windows for permission to run as administrator...
    echo If a Yes/No box appears, click Yes.
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

pushd "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Setup-RemoteHelp.ps1"

if %errorlevel% neq 0 (
    echo.
    echo Something didn't finish. Scroll up and send Shands a screenshot.
    pause >nul
)

endlocal
