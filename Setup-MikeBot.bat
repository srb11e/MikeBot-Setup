@echo off
REM ============================================================================
REM Setup-MikeBot.bat — Double-clickable launcher
REM ============================================================================
REM
REM This is the only file Mike needs to double-click. It does three things:
REM   1. Asks Windows for admin permission (UAC prompt)
REM   2. Allows PowerShell to run our setup script (just for this one run)
REM   3. Launches Setup-MikeBot.ps1 in a PowerShell window
REM
REM Mike can double-click this file as many times as he wants. If he stops
REM partway through, double-clicking again resumes where he left off.
REM ============================================================================

setlocal

REM --- Find this script's folder, regardless of where it was double-clicked from ---
set "SCRIPT_DIR=%~dp0"

REM --- Verify the PowerShell script is sitting next to this .bat ---
if not exist "%SCRIPT_DIR%Setup-MikeBot.ps1" (
    echo.
    echo ERROR: Cannot find Setup-MikeBot.ps1 in this folder:
    echo   %SCRIPT_DIR%
    echo.
    echo Make sure both Setup-MikeBot.bat and Setup-MikeBot.ps1 are in
    echo the same folder, then double-click this file again.
    echo.
    pause
    exit /b 1
)

REM --- Check if we're already running as admin ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    REM Not admin — relaunch ourselves with admin rights via PowerShell's Start-Process
    echo.
    echo Asking Windows for permission to run as administrator...
    echo If a Yes/No box appears, click Yes.
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

REM --- We are admin. Change to the script's directory so relative paths work.
REM     After UAC elevation, the working directory is C:\Windows\System32.
REM     Without pushd, any future edit that uses a relative path will fail.
pushd "%~dp0"

REM --- Now run the PowerShell script. ---
REM   -NoProfile           = don't load Mike's PowerShell profile (clean environment)
REM   -ExecutionPolicy Bypass = allow this script to run, just for this session
REM   -File                = run the script file
REM
REM We do NOT change the system-wide execution policy. This stays scoped to
REM this one PowerShell window.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Setup-MikeBot.ps1"

REM --- Keep the window open if PowerShell exited with an error ---
if %errorlevel% neq 0 (
    echo.
    echo The setup script exited with an error. Scroll up to see what happened.
    echo Press any key to close this window.
    pause >nul
)

endlocal
