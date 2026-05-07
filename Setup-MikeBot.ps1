# =============================================================================
# Setup-MikeBot.ps1 -- OpenClaw + DeepSeek + Telegram setup for Windows
# =============================================================================
#
# PURPOSE:
#   Walks Mike through getting his OpenClaw bot running on his new Windows
#   laptop, using DeepSeek as the model provider and Telegram (phone + desktop)
#   as the way he talks to the bot.
#
# HOW MIKE RUNS THIS:
#   He doesn't run this directly. He double-clicks Setup-MikeBot.bat, which
#   handles the admin prompt and execution policy, then launches this script.
#
# RESUME:
#   If Mike stops partway through (closes the window, restarts the laptop,
#   loses internet), he just double-clicks Setup-MikeBot.bat again. This
#   script remembers where he left off and offers to resume.
#
# WHO MAINTAINS THIS:
#   Shands. Mike does not edit this file.
# =============================================================================

# Stop on any unhandled error so we don't blow past failures silently.
$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# COLORED OUTPUT HELPERS
# -----------------------------------------------------------------------------
# PowerShell's Write-Host with -ForegroundColor is the cleanest way to do this
# on Windows. No ANSI escape code wrangling needed.

function Write-Info    { param([string]$m) Write-Host "  -> $m" -ForegroundColor Cyan }
function Write-Success { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn    { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Fail    { param([string]$m) Write-Host "  [X] $m" -ForegroundColor Red }
function Write-Plain   { param([string]$m) Write-Host "  $m" }
function Write-Bold    { param([string]$m) Write-Host $m -ForegroundColor White }

function Show-StageHeader {
    param(
        [int]$StageNum,
        [int]$TotalStages,
        [string]$StageName
    )
    $pct = [math]::Round(($StageNum - 1) / $TotalStages * 100)
    Write-Progress -Activity "MikeBot Setup" -Status "Stage $StageNum of $TotalStages : $StageName" `
        -PercentComplete $pct
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor White
    Write-Host "  Stage $StageNum of $TotalStages : $StageName" -ForegroundColor White
    Write-Host "================================================================" -ForegroundColor White
    Write-Host ""
}

function Wait-ForReturn {
    param([string]$Prompt = "Press Enter when you have completed this step...")
    Write-Host ""
    Write-Host "  >> $Prompt" -ForegroundColor Yellow
    Read-Host | Out-Null
}

# -----------------------------------------------------------------------------
# SKIP / CONTINUE PROMPT
# -----------------------------------------------------------------------------
# Renamed from the Mac script's confusingly-inverted ask_skip().
# Returns $true if the user wants to skip this stage, $false to do it.

function Test-UserChoseSkip {
    Write-Host ""
    $choice = Read-Host "  Already done or not applicable? (s = skip, Enter = continue)"
    return ($choice -match '^[Ss]')
}

# -----------------------------------------------------------------------------
# SUPPORT BLOCK -- compact summary Mike can screenshot or text to Shands
# -----------------------------------------------------------------------------

function Show-SupportBlock {
    param(
        [int]$StageNum,
        [string]$StageName,
        [string]$StepName,
        [string]$ErrorDetail
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $setupDir = Join-Path $env:LOCALAPPDATA "MikeBot-Setup"
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Yellow
    Write-Host "   Send this to Shands:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Stage: $StageNum - $StageName" -ForegroundColor White
    Write-Host "   Step: $StepName" -ForegroundColor White
    Write-Host "   Error: $ErrorDetail" -ForegroundColor White
    Write-Host "   Time: $ts" -ForegroundColor White
    Write-Host "   Setup folder: $setupDir" -ForegroundColor White
    Write-Host "  ================================================================" -ForegroundColor Yellow
    Write-Host ""
}

# -----------------------------------------------------------------------------
# GLOBAL ERROR TRAP -- catches unhandled terminating errors
# -----------------------------------------------------------------------------
# Mike never sees a naked stack trace. Instead he gets a support block
# with the stage, error message, and transcript file path.

trap {
    $stageName = if ($Script:CurrentStage -gt 0 -and $Script:CurrentStage -le $Script:TotalStages) {
        $StageNames[$Script:CurrentStage]
    } else { "Setup" }
    Show-SupportBlock -StageNum $Script:CurrentStage -StageName $stageName `
        -StepName "Unexpected error" -ErrorDetail $_.Exception.Message
    Write-Host "  Full details saved to:" -ForegroundColor White
    Write-Host "    $TranscriptFile" -ForegroundColor White
    Write-Host "  Send that file to Shands." -ForegroundColor White
    Write-Host ""
    try { Write-SetupEvent "CRASH: Stage $Script:CurrentStage - $($_.Exception.Message)" } catch { $null }
    try { Stop-Transcript } catch { $null }
    Read-Host "Press Enter to close" | Out-Null
    exit 1
}

# -----------------------------------------------------------------------------
# EVENT LOG -- append-mode timeline for remote diagnosis
# -----------------------------------------------------------------------------

function Write-SetupEvent {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $EventLogFile -Value "[$ts] $Message" -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------------
# SKIP TRACKER -- records which stages/steps were skipped
# -----------------------------------------------------------------------------

function Add-Skip {
    param([int]$StageNum, [string]$StepName)
    $Script:SkippedStages += "${StageNum}: $StepName"
    $Script:StageResults[$StageNum] = "SKIPPED"
    Write-SetupEvent "SKIP: Stage $StageNum - $StepName"
}

# -----------------------------------------------------------------------------
# PROGRESS TRACKING
# -----------------------------------------------------------------------------

# Use LOCALAPPDATA instead of USERPROFILE to avoid OneDrive sync.
# On corporate-managed laptops, USERPROFILE (including Desktop and Documents)
# is often inside a OneDrive-synced folder. LOCALAPPDATA is by Windows
# convention not roamed and not synced by OneDrive -- so secrets stored here
# during setup won't leak to cloud storage.
$ProgressDir  = Join-Path $env:LOCALAPPDATA "MikeBot-Setup"
$ProgressFile = Join-Path $ProgressDir   ".progress"
$EnvFile      = Join-Path $ProgressDir   ".env"  # stores API keys etc. between stages
$LogFile      = Join-Path $ProgressDir   "setup-log.md"
$TokenFile    = Join-Path $ProgressDir   "dashboard-token.txt"  # separate to avoid collision with log
$EventLogFile = Join-Path $ProgressDir   "setup-events.log"
$Script:LastCompleted  = 0
$Script:TotalStages    = 15
$Script:CurrentStage   = 0
$Script:SkippedStages  = @()
$Script:StageResults   = @{}

# Ensure the progress directory exists before transcript/event log start
if (-not (Test-Path $ProgressDir)) {
    New-Item -ItemType Directory -Path $ProgressDir -Force | Out-Null
}

# Start transcript — captures all console output to a timestamped file.
# If the script crashes, the transcript persists on disk for remote diagnosis.
$TranscriptFile = Join-Path $ProgressDir "setup-transcript-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $TranscriptFile -Append | Out-Null

function Save-Progress {
    param([int]$StageNum)
    if (-not (Test-Path $ProgressDir)) {
        New-Item -ItemType Directory -Path $ProgressDir -Force | Out-Null
    }
    @"
LAST_COMPLETED=$StageNum
TIMESTAMP=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
"@ | Set-Content -Path $ProgressFile -Encoding UTF8
    $Script:LastCompleted = $StageNum
    if (-not $Script:StageResults.ContainsKey($StageNum)) {
        $Script:StageResults[$StageNum] = "OK"
    }
    Write-SetupEvent "COMPLETE: Stage $StageNum"
}

function Import-Progress {
    if (Test-Path $ProgressFile) {
        $line = (Get-Content $ProgressFile | Where-Object { $_ -match '^LAST_COMPLETED=' } | Select-Object -First 1)
        if ($line -match '^LAST_COMPLETED=(\d+)$') {
            $val = [int]$matches[1]
            if ($val -ge 0 -and $val -le $Script:TotalStages) {
                $Script:LastCompleted = $val
            }
        }
    }
}

function Test-StageAlreadyComplete {
    param([int]$StageNum)
    return ($StageNum -le $Script:LastCompleted)
}

# -----------------------------------------------------------------------------
# SECRET STORAGE (between stages, on disk, FOR THIS SETUP RUN ONLY)
# -----------------------------------------------------------------------------
# We store the DeepSeek API key and Telegram bot token in a .env file so
# Mike doesn't have to paste them multiple times across stages. After setup
# completes, we tell him where this file is and recommend deleting it once
# he's confirmed the bot works (since OpenClaw will have stored its own
# copy in its config).

function Save-Secret {
    param([string]$Key, [string]$Value)
    if (-not (Test-Path $ProgressDir)) {
        New-Item -ItemType Directory -Path $ProgressDir -Force | Out-Null
    }
    # Read existing, strip any prior line for this key, append new
    $existing = @()
    if (Test-Path $EnvFile) {
        $existing = Get-Content $EnvFile | Where-Object { $_ -notmatch "^$Key=" }
    }
    $existing += "$Key=$Value"
    $existing | Set-Content -Path $EnvFile -Encoding UTF8

    # No explicit ACL hardening here.
    # F1.5 moved all setup state to LOCALAPPDATA, which Windows defaults
    # to user-only permissions. Adding Set-Acl on top would strip inheritance
    # and risk locking out admin recovery without meaningfully improving
    # security over the LOCALAPPDATA baseline.
}

function Get-Secret {
    param([string]$Key)
    if (-not (Test-Path $EnvFile)) { return $null }
    $line = Get-Content $EnvFile | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($line) {
        return ($line -replace "^$Key=", "")
    }
    return $null
}

# -----------------------------------------------------------------------------
# COMMAND-AVAILABILITY HELPERS
# -----------------------------------------------------------------------------

function Test-CommandExists {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

function Update-EnvironmentPath {
    # Pulls the latest PATH from registry so newly-installed tools become visible.
    # winget installs add to PATH but the change doesn't reach the running process.
    # Called after every install stage and at resume.
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Assert-ToolAvailable {
    param(
        [string]$Name,
        [string]$FriendlyName = $Name,
        [string]$NextStage = "the next stage"
    )
    if (Test-CommandExists $Name) {
        return $true
    }
    # One retry after a short pause -- PATH updates can race winget's post-install hooks.
    Write-Info "$FriendlyName not found in PATH yet. Waiting a moment and retrying..."
    Start-Sleep -Seconds 5
    Update-EnvironmentPath
    if (Test-CommandExists $Name) {
        return $true
    }
    Write-Warn "$FriendlyName still not available."
    Write-Plain ""
    Write-Plain "  Close this window, then double-click Setup-MikeBot.bat again."
    Write-Plain "  Your progress is saved -- it will resume from $NextStage."
    Write-Plain ""
    Wait-ForReturn "Press Enter to close..."
    exit 0
}

# -----------------------------------------------------------------------------
# SPINNER — visual feedback during long subprocess waits
# -----------------------------------------------------------------------------

function Wait-ProcessWithSpinner {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Label,
        [int]$TimeoutSeconds = 600
    )
    $frames = @('|','/','-','\')
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $i = 0

    while (-not $Process.HasExited) {
        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            Write-Host "`r  $($frames[$i % 4]) $Label... TIMED OUT                    " -NoNewline
            Write-Host ""
            return $false
        }
        $elapsed = $sw.Elapsed
        $timeStr = if ($elapsed.TotalMinutes -ge 1) {
            "{0}m {1:D2}s" -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        } else {
            "{0}s" -f $elapsed.Seconds
        }
        Write-Host "`r  $($frames[$i % 4]) $Label... ($timeStr)   " -NoNewline
        $i++
        Start-Sleep -Milliseconds 250
    }

    Write-Host "`r                                                                  `r" -NoNewline
    return $true
}

# -----------------------------------------------------------------------------
# WINGET INSTALL HELPER
# -----------------------------------------------------------------------------
# winget exit codes (canonical, from Microsoft winget-cli returnCodes.md):
#   0           = success
#   -1978335189 = APPINSTALLER_CLI_ERROR_NO_APPLICABLE_UPGRADE (already up to date)
#   -1978335206 = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
# Both non-zero codes mean "package already present" -- treat as success.
# All other codes = real failure.

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$DisplayName,
        [int]$TimeoutSeconds = 600
    )
    Write-Info "Installing $DisplayName..."

    $wingetArgs = @("install", "--id", $PackageId, "--exact",
                    "--silent", "--accept-source-agreements", "--accept-package-agreements")

    $proc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -PassThru -NoNewWindow
    $completed = Wait-ProcessWithSpinner -Process $proc -Label "Installing $DisplayName" -TimeoutSeconds $TimeoutSeconds

    if (-not $completed) {
        try { $proc.Kill() } catch { $null }
        Write-Fail "$DisplayName install timed out after $($TimeoutSeconds/60) minutes."
        Write-Plain "  This is a Windows Package Manager issue, not your fault."
        return $false
    }

    $code = $proc.ExitCode
    # Success (0) or already-installed codes
    $alreadyInstalled = @(0, -1978335189, -1978335206)
    if ($code -in $alreadyInstalled) {
        Write-Success "$DisplayName installed (or already present)."
        return $true
    } else {
        Write-Fail "$DisplayName install failed (winget exit code $code)."
        return $false
    }
}

# -----------------------------------------------------------------------------
# RETRY/SKIP/QUIT WRAPPER FOR FAILABLE STEPS
# -----------------------------------------------------------------------------

function Invoke-WithRetrySkipQuit {
    param(
        [scriptblock]$Action,           # returns $true on success, $false on failure
        [string]$StepName,
        [int]$MaxRetries = 3            # after this many failures, retry is removed
    )
    $attempts = 0
    while ($true) {
        $ok = & $Action
        if ($ok) { return $true }

        $attempts++
        Write-Host ""
        Write-Fail "$StepName failed."
        Write-SetupEvent "FAIL: $StepName (attempt $attempts)"

        $capped = ($attempts -ge $MaxRetries)
        if ($capped) {
            Write-Warn "This step has failed $attempts times. Retry is no longer available."
            Write-Plain "If you need help, send Shands a screenshot of this window."
        }

        Write-Host ""
        Write-Plain "Options:"
        if (-not $capped) {
            Write-Plain "    r) Retry this step"
        }
        Write-Plain "    s) Skip and continue to the next step"
        Write-Plain "    q) Quit (your progress is saved -- you can resume later)"
        Write-Host ""
        $choice = Read-Host "  Choose ($(if (-not $capped) {'r/'})s/q)"
        switch -Regex ($choice) {
            '^[Rr]' {
                if ($capped) {
                    Write-Plain "  Retry is no longer available for this step. Choose s or q."
                } else {
                    Write-SetupEvent "RETRY: $StepName (attempt $($attempts+1))"
                    Write-Info "Retrying..."; continue
                }
            }
            '^[Ss]' {
                Add-Skip -StageNum $Script:CurrentStage -StepName $StepName
                return $false
            }
            '^[Qq]' {
                Write-SetupEvent "QUIT: User quit at $StepName"
                Write-Info "Progress saved. Double-click Setup-MikeBot.bat to resume."
                try { Stop-Transcript } catch { $null }
                exit 0
            }
            default {
                if ($capped) {
                    Write-Plain "  Retry is no longer available for this step. Choose s or q."
                } else {
                    Write-SetupEvent "RETRY: $StepName (attempt $($attempts+1))"
                    Write-Info "Retrying..."; continue
                }
            }
        }
    }
}


# =============================================================================
# WELCOME
# =============================================================================

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  Mike's Bot Setup" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Host ""
Write-Plain "Hi Mike. This script sets up your AI bot from scratch on this laptop."
Write-Plain "Here is what to expect:"
Write-Host ""
Write-Bold "  WHAT IT WILL DO:"
Write-Plain "    - Check your Windows version and internet"
Write-Plain "    - Install developer tools (Node.js, Git, Bitwarden, Telegram)"
Write-Plain "    - Walk you through creating a DeepSeek account and API key"
Write-Plain "    - Walk you through creating a Telegram bot"
Write-Plain "    - Install OpenClaw (the AI assistant)"
Write-Plain "    - Connect everything and test it end-to-end"
Write-Host ""
Write-Bold "  WHAT IT WILL NOT DO:"
Write-Plain "    - Touch your email, files, or personal documents"
Write-Plain "    - Install anything you do not need"
Write-Plain "    - Send any data anywhere except DeepSeek's API and Telegram"
Write-Host ""
Write-Bold "  ABOUT YOUR FILES:"
Write-Plain "    - Setup files (including any keys you paste) are stored in a"
Write-Plain "      non-synced folder on this PC -- not in OneDrive or the cloud."
Write-Host ""
Write-Bold "  IF YOU NEED TO STOP:"
Write-Plain "    - Close this window any time -- your progress is saved."
Write-Plain "    - Double-click Setup-MikeBot.bat again to resume where you left off."
Write-Host ""
Write-Bold "  IF SOMETHING GOES WRONG:"
Write-Plain "    - Don't panic. Take a screenshot and text Shands."
Write-Plain "    - Most steps can be retried."
Write-Host ""
Write-Plain "Budget about 1 to 2 hours total. Most of that is waiting for downloads."
Write-Host ""
Write-Plain "Press Enter to begin (or close this window if now isn't a good time)."
Read-Host | Out-Null

# -----------------------------------------------------------------------------
# Internet check (we need this for everything)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Info "Checking your internet connection..."
try {
    $resp = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Success "Internet is working."
} catch {
    Write-Fail "No internet connection detected."
    Write-Plain "Connect to Wi-Fi or Ethernet and try again."
    Write-Plain "If you're connected and still see this, text Shands."
    Wait-ForReturn "Press Enter to close this window..."
    exit 1
}

# -----------------------------------------------------------------------------
# Resume check
# -----------------------------------------------------------------------------
Import-Progress

$StageNames = @(
    "",
    "Windows Version Check",
    "Windows Update",
    "Security Basics",
    "Install Foundation Tools",
    "Install Bitwarden (Password Manager)",
    "Create Telegram Bot",
    "Create DeepSeek Account & API Key",
    "Test the API Key",
    "Install OpenClaw",
    "OpenClaw Onboarding",
    "Gateway Health Check",
    "Dashboard Check",
    "Approve Your Phone with the Bot",
    "End-to-End Test",
    "All Done!"
)

if ($Script:LastCompleted -gt 0 -and $Script:LastCompleted -lt $Script:TotalStages) {
    $next = $Script:LastCompleted + 1
    $nextName = $StageNames[$next]
    Write-Host ""
    Write-Info "Welcome back, Mike. Last time you got through stage $($Script:LastCompleted)."
    Write-Plain "Next up: Stage $next -- $nextName"
    Write-Host ""
    $resumeChoice = Read-Host "  Resume from stage $next ? (Enter = resume, n = start over)"
    if ($resumeChoice -match '^[Nn]') {
        $Script:LastCompleted = 0
        if (Test-Path $ProgressFile) { Remove-Item $ProgressFile -Force }
        Write-Info "Starting from the beginning."
    } else {
        Write-Info "Resuming from stage $next."
    }
} elseif ($Script:LastCompleted -ge $Script:TotalStages) {
    Write-Host ""
    Write-Success "Setup was already completed!"
    Write-Host ""
    $rerun = Read-Host "  Run again from the beginning? (y/n)"
    if ($rerun -notmatch '^[Yy]') { exit 0 }
    $Script:LastCompleted = 0
    if (Test-Path $ProgressFile) { Remove-Item $ProgressFile -Force }
}

# Pick up any tools installed on a previous run that aren't in this shell's PATH yet.
Update-EnvironmentPath


# =============================================================================
# STAGE 1: Windows Version Check
# =============================================================================

if (-not (Test-StageAlreadyComplete 1)) {
    $Script:CurrentStage = 1
    Write-SetupEvent "START: Stage 1 - Windows Version Check"
    Show-StageHeader 1 $Script:TotalStages "Windows Version Check"

    Write-Plain "Checking that your Windows is new enough for OpenClaw."
    Write-Plain "(OpenClaw needs Windows 10 build 19041 or newer, or any Windows 11.)"
    Write-Host ""

    $build = [System.Environment]::OSVersion.Version.Build
    $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue)
    $product = if ($ver) { $ver.ProductName } else { "Windows" }
    $displayVersion = if ($ver -and $ver.DisplayVersion) { $ver.DisplayVersion } else { "unknown" }

    Write-Plain "  Detected: $product (build $build, version $displayVersion)"

    if ($build -lt 19041) {
        Write-Fail "Your Windows is too old (build $build)."
        Write-Plain "  You need at least build 19041 (Windows 10 May 2020 Update)."
        Write-Plain "  Run Windows Update first, then re-run this setup."
        Write-Plain "  If updates aren't fixing it, text Shands."
        Show-SupportBlock -StageNum 1 -StageName "Windows Version Check" `
            -StepName "Build check" -ErrorDetail "Build $build is below 19041"
        Wait-ForReturn "Press Enter to exit..."
        exit 1
    } else {
        Write-Success "Your Windows version is fine."
    }

    Save-Progress 1
}


# =============================================================================
# STAGE 2: Windows Update
# =============================================================================

if (-not (Test-StageAlreadyComplete 2)) {
    $Script:CurrentStage = 2
    Write-SetupEvent "START: Stage 2 - Windows Update"
    Show-StageHeader 2 $Script:TotalStages "Windows Update"

    Write-Plain "Before we install anything, let's make sure Windows is up to date."
    Write-Plain "This prevents weird install errors later."

    if (Test-UserChoseSkip) {
        Write-Info "Skipping Windows Update (you said it's already done)."
    } else {
        Write-Host ""
        Write-Plain "I'll open Windows Update settings for you."
        Write-Plain "When the Settings window opens:"
        Write-Plain "  1. Click 'Check for updates'"
        Write-Plain "  2. Install whatever it finds"
        Write-Plain "  3. If it asks you to restart, do it"
        Write-Plain "  4. After restart, double-click Setup-MikeBot.bat again to resume"
        Write-Host ""
        Write-Plain "Opening Windows Update now..."
        Start-Process "ms-settings:windowsupdate"

        Wait-ForReturn "Press Enter once Windows Update says 'You're up to date' (or you've restarted and resumed)..."
    }

    Save-Progress 2
}


# =============================================================================
# STAGE 3: Security Basics
# =============================================================================

if (-not (Test-StageAlreadyComplete 3)) {
    $Script:CurrentStage = 3
    Write-SetupEvent "START: Stage 3 - Security Basics"
    Show-StageHeader 3 $Script:TotalStages "Security Basics"

    Write-Plain "This laptop will store an API key that costs real money if someone"
    Write-Plain "else gets it. Let's lock it down. Three things, takes about 5 minutes."

    if (Test-UserChoseSkip) {
        Add-Skip -StageNum 3 -StepName "Security basics"
        Write-Info "Skipping security setup (do this later -- text Shands if unsure)."
    } else {
        Write-Host ""
        Write-Bold "  1. SCREEN LOCK"
        Write-Plain "     Settings -> Accounts -> Sign-in options"
        Write-Plain "     Set 'If you've been away, when should Windows require you"
        Write-Plain "     to sign in again?' to '5 minutes' or less."
        Write-Host ""
        $openLock = Read-Host "  Open Sign-in settings now? (Enter = yes, n = skip)"
        if ($openLock -notmatch '^[Nn]') {
            Start-Process "ms-settings:signinoptions"
            Wait-ForReturn "Press Enter once you've set the screen lock..."
        }

        Write-Host ""
        Write-Bold "  2. POWER SETTINGS (so the bot stays running)"
        Write-Plain "     We need Windows to NOT go to sleep, otherwise the bot stops"
        Write-Plain "     answering when the screen turns off."
        Write-Host ""
        Write-Plain "     I'll set this for you automatically. One moment..."

        try {
            # Plugged-in: never sleep, never turn off disk
            powercfg /change standby-timeout-ac 0   2>&1 | Out-Null
            powercfg /change hibernate-timeout-ac 0 2>&1 | Out-Null
            powercfg /change disk-timeout-ac 0      2>&1 | Out-Null
            # Display can still turn off -- that's fine, doesn't affect the bot
            Write-Success "Power settings adjusted: laptop won't sleep when plugged in."
            Write-Plain "  (The screen can still turn off -- that's fine.)"
        } catch {
            Write-Warn "Couldn't adjust power settings automatically."
            Write-Plain "  You can do it manually later: Settings -> System -> Power & Battery"
        }

        Write-Host ""
        Write-Bold "  3. BITLOCKER (disk encryption -- RECOMMENDED but optional)"
        Write-Plain "     This encrypts your hard drive so if someone steals the laptop"
        Write-Plain "     they can't read your API key off the disk."
        Write-Host ""
        Write-Plain "     If your laptop already has BitLocker on (most newer business"
        Write-Plain "     laptops do), you're good -- skip this."
        Write-Host ""
        Write-Plain "     To check or turn on: Control Panel -> BitLocker Drive Encryption"
        Write-Plain "     If you turn it on, SAVE THE RECOVERY KEY somewhere safe"
        Write-Plain "     (your Microsoft account is fine)."
        Write-Host ""
        $skipBL = Read-Host "  Open BitLocker settings? (Enter = yes, n = skip for now)"
        if ($skipBL -notmatch '^[Nn]') {
            Start-Process "control.exe" -ArgumentList "/name", "Microsoft.BitLockerDriveEncryption"
            Wait-ForReturn "Press Enter once BitLocker is on or you've decided to skip..."
        }
    }

    Save-Progress 3
}


# =============================================================================
# STAGE 4: Install Foundation Tools (winget with timeout + manual fallback)
# =============================================================================

if (-not (Test-StageAlreadyComplete 4)) {
    $Script:CurrentStage = 4
    Write-SetupEvent "START: Stage 4 - Install Foundation Tools"
    Show-StageHeader 4 $Script:TotalStages "Install Foundation Tools"

    Write-Plain "Installing the tools the bot needs:"
    Write-Plain "  - Git (version control -- required by OpenClaw's installer)"
    Write-Plain "  - Node.js 22 LTS (the runtime OpenClaw runs on)"
    Write-Plain "  - Telegram Desktop (so you can chat with the bot from this laptop too)"
    Write-Host ""

    # -------------------------------------------------------------------------
    # Check whether tools are already present (manual install, previous run, etc.)
    # -------------------------------------------------------------------------
    Update-EnvironmentPath
    $gitOk  = Test-CommandExists "git"
    $nodeOk = Test-CommandExists "node"

    if ($gitOk -and $nodeOk) {
        Write-Success "Git and Node.js are already available on this laptop."
        $gv = & git --version 2>$null
        $nv = & node --version 2>$null
        Write-Plain "  Git:  $gv"
        Write-Plain "  Node: $nv"
        Write-Host ""
        Write-Plain "  Since the foundation tools are already installed, we can skip"
        Write-Plain "  the Windows Package Manager steps. We just need to confirm"
        Write-Plain "  Telegram Desktop is installed."
        Write-Host ""
        $tgInstalled = Read-Host "  Is Telegram Desktop installed on this laptop? (y = yes, n = not yet)"
        if ($tgInstalled -match '^[Yy]') {
            Write-Success "All foundation tools confirmed."
            Save-Progress 4
            # Skip the rest of Stage 4 and go to next stage
            # (continue script execution below --- PowerShell will fall through
            #  the enclosing if block once we return control)
        } else {
            Write-Plain ""
            Write-Plain "  No problem. You can install Telegram Desktop anytime:"
            Write-Plain "    https://desktop.telegram.org"
            Write-Plain "  It's not required for the bot to work -- just convenient."
            Write-Host ""
            Write-Success "Foundation tools are ready. On to the next stage."
            Save-Progress 4
        }
    } else {
        # -----------------------------------------------------------------
        # Tools not present -- we need winget
        # -----------------------------------------------------------------

        # Verify winget exists. On a brand-new Windows 11 laptop it does.
        # On older Windows 10 it may not.
        if (-not (Test-CommandExists "winget")) {
            Write-Fail "Windows Package Manager (winget) is not available."
            Write-Plain ""
            Write-Plain "  This means we can't install tools automatically."
            Write-Plain "  But you can install them manually from their official websites:"
            Write-Plain ""
            Write-Plain "    Git for Windows:      https://git-scm.com/download/win"
            Write-Plain "    Node.js LTS:          https://nodejs.org  (pick the LTS version)"
            Write-Plain "    Telegram Desktop:     https://desktop.telegram.org"
            Write-Plain ""
            Write-Plain "  After installing them, re-run this setup."
            Write-Plain "  It will detect them and skip the winget steps."
            Show-SupportBlock -StageNum 4 -StageName "Install Foundation Tools" `
                -StepName "winget not found" `
                -ErrorDetail "winget is not installed on this laptop"
            Wait-ForReturn "Press Enter to exit..."
            exit 1
        }

        # -----------------------------------------------------------------
        # Winget source update with real retry loop
        # -----------------------------------------------------------------
        # winget source update refreshes the package catalog. It can hang
        # on first run if the Microsoft Store source needs setup.
        $wsAttempt = 0
        $wsMaxAttempts = 3
        $wsOk = $false
        do {
            $wsAttempt++
            Write-Info "Preparing Windows Package Manager (attempt $wsAttempt)..."
            $sourceProc = Start-Process -FilePath "winget" `
                -ArgumentList @("source", "update") `
                -PassThru -NoNewWindow
            $sourceReady = Wait-ProcessWithSpinner -Process $sourceProc -Label "Updating package catalog" -TimeoutSeconds 120

            if (-not $sourceReady) {
                try { $sourceProc.Kill() } catch { $null }
                Write-Warn "Windows Package Manager did not respond within 2 minutes."
                $wsOk = $false
            } elseif ($sourceProc.ExitCode -ne 0) {
                Write-Warn "Windows Package Manager source update failed (exit code $($sourceProc.ExitCode))."
                $wsOk = $false
            } else {
                Write-Success "Windows Package Manager is ready."
                $wsOk = $true
            }

            if (-not $wsOk) {
                $capped = ($wsAttempt -ge $wsMaxAttempts)
                Write-Plain ""
                Write-Plain "  This is a Windows issue, not your fault."
                Write-Plain "  winget may be doing first-time setup or waiting on the"
                Write-Plain "  Microsoft Store."
                Write-Host ""
                if (-not $capped) {
                    Write-Plain "    r = Retry the winget preparation step"
                }
                Write-Plain "    m = Manual install instructions (Git, Node, Telegram)"
                Write-Plain "    q = Quit and save progress"
                Write-Host ""
                $wsChoice = Read-Host "  Choose ($(if (-not $capped) {'r/'})m/q)"
                if ($wsChoice -match '^[Mm]') {
                    Write-Plain ""
                    Write-Plain "  Install these from their official websites, then re-run this setup:"
                    Write-Plain "    Git for Windows:      https://git-scm.com/download/win"
                    Write-Plain "    Node.js LTS:          https://nodejs.org  (pick the LTS version)"
                    Write-Plain "    Telegram Desktop:     https://desktop.telegram.org"
                    Write-Host ""
                    Write-Plain "  After installing, double-click Setup-MikeBot.bat again."
                    Write-Plain "  The setup will detect Git and Node and skip winget."
                    Show-SupportBlock -StageNum 4 -StageName "Install Foundation Tools" `
                        -StepName "winget source update" `
                        -ErrorDetail "winget source update failed after $wsAttempt attempt(s)"
                    Wait-ForReturn "Press Enter to exit..."
                    exit 0
                } elseif ($wsChoice -match '^[Qq]') {
                    Write-Info "Progress saved. Double-click Setup-MikeBot.bat to resume."
                    exit 0
                }
                # r (retry): loop again if not capped; fall through to retry
            }
        } while (-not $wsOk)
        Write-Host ""

        $installs = @(
            @{ Id = "Git.Git";              Name = "Git" },
            @{ Id = "OpenJS.NodeJS.LTS";    Name = "Node.js 22 LTS" },
            @{ Id = "Telegram.TelegramDesktop"; Name = "Telegram Desktop" }
        )

        # No preflight package-ID verification. winget install itself is the
        # authoritative check. If a package ID has changed, the install will
        # fail with a clear winget error and the retry/skip/quit wrapper gives
        # Mike a path forward. This prevents indefinite hangs on winget search
        # (which can stall on first-run source setup).

        foreach ($pkg in $installs) {
            $null = Invoke-WithRetrySkipQuit -StepName "Installing $($pkg.Name)" -Action {
                return (Install-WithWinget -PackageId $pkg.Id -DisplayName $pkg.Name)
            }
        }

        # Pick up the new tools without restarting the shell
        Update-EnvironmentPath

        # -----------------------------------------------------------------
        # Verify foundation tools: git, node, AND npm are hard gates.
        # Telegram Desktop is optional/convenience.
        # -----------------------------------------------------------------
        Write-Host ""
        Write-Info "Verifying foundation tools..."
        $gitOk  = Test-CommandExists "git"
        $nodeOk = Test-CommandExists "node"
        $npmOk  = Test-CommandExists "npm"
        $allOk  = $gitOk -and $nodeOk -and $npmOk

        if ($gitOk)  { Write-Success "git is available." }
        else         { Write-Fail   "git not found." }
        if ($nodeOk) {
            $nodeVer = & node --version 2>$null
            Write-Success "node is available ($nodeVer)."
        } else {
            Write-Fail "node not found."
        }
        if ($npmOk)  {
            $npmVer = & npm --version 2>$null
            Write-Success "npm is available ($npmVer)."
        } else {
            Write-Fail "npm not found."
        }

        if (-not $allOk) {
            Write-Plain ""
            Write-Warn "One or more required tools are still missing from PATH."
            Write-Plain ""
            Write-Plain "  This is often because the PATH changes from winget"
            Write-Plain "  haven't reached this window yet. A restart usually fixes it."
            Write-Plain ""
            Write-Plain "  r = Restart this script now (you won't lose progress)"
            Write-Plain "  q = Quit, re-run Setup-MikeBot.bat manually after restarting"
            Write-Host ""
            $restartChoice = Read-Host "  Choose (r/q)"
            if ($restartChoice -notmatch '^[Qq]') {
                Write-Info "Restarting..."
                Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`""
                exit 0
            } else {
                Write-Plain "  Close this window, restart, then double-click Setup-MikeBot.bat."
                Wait-ForReturn "Press Enter to close..."
                exit 0
            }
        }

        Write-Success "All foundation tools (Git, Node, npm) are ready."
    }

    Save-Progress 4
}


# =============================================================================
# STAGE 5: Install Bitwarden (Password Manager)
# =============================================================================

if (-not (Test-StageAlreadyComplete 5)) {
    $Script:CurrentStage = 5
    Write-SetupEvent "START: Stage 5 - Install Bitwarden"
    Show-StageHeader 5 $Script:TotalStages "Install Bitwarden (Password Manager)"

    Write-Plain "Before you create API keys, you need somewhere safe to keep them."
    Write-Plain "Bitwarden is free and works on Windows, Mac, iPhone, Android."
    Write-Host ""

    # Check if Bitwarden is already installed or user has another password manager
    $bwInstalled = $false
    $bwCheck = Get-Command "Bitwarden" -ErrorAction SilentlyContinue
    if ($bwCheck) {
        Write-Success "Bitwarden appears to be already installed."
        $bwInstalled = $true
    } else {
        # Also check common install path via winget / AppX
        $bwAppx = Get-AppxPackage -Name "*Bitwarden*" -ErrorAction SilentlyContinue
        if ($bwAppx) {
            Write-Success "Bitwarden appears to be already installed."
            $bwInstalled = $true
        }
    }

    if ($bwInstalled) {
        Write-Plain "  Skipping Bitwarden install."
        Write-Plain "  Make sure you're logged in before Stage 7 (creating API keys)."
    } elseif (Test-UserChoseSkip) {
        Add-Skip -StageNum 5 -StepName "Bitwarden install"
        Write-Info "Skipping Bitwarden install."
        Write-Warn "Make sure you have somewhere safe to put your API keys before continuing."
        Write-Plain "  (Any password manager works -- iPhone Notes locked with Face ID, etc.)"
    } else {
        $null = Invoke-WithRetrySkipQuit -StepName "Installing Bitwarden" -Action {
            return (Install-WithWinget -PackageId "Bitwarden.Bitwarden" -DisplayName "Bitwarden")
        }

        # If winget install failed, offer manual fallback
        Write-Host ""
        Write-Plain "  If the install above failed, you can install Bitwarden manually:"
        Write-Plain "    https://bitwarden.com/download"
        Write-Plain "  Or use any password manager you already have (iPhone Notes, etc.)"
        Write-Plain "  The setup just needs you to have somewhere to save your API keys."
        Write-Host ""

        Write-Plain "After installing, create a Bitwarden account:"
        Write-Plain "  1. Open Bitwarden from your Start menu"
        Write-Plain "  2. Click 'Create Account'"
        Write-Plain "  3. Pick a STRONG master password and write it down somewhere safe"
        Write-Plain "     (if you forget it, no one can recover it for you)"
        Write-Plain "  4. Confirm the email they send you"
        Write-Host ""

        Wait-ForReturn "Press Enter once you have a password manager ready..."
    }

    Save-Progress 5
}


# =============================================================================
# STAGE 6: Create Telegram Bot (BEFORE OpenClaw onboarding so token is ready)
# =============================================================================

if (-not (Test-StageAlreadyComplete 6)) {
    $Script:CurrentStage = 6
    Write-SetupEvent "START: Stage 6 - Create Telegram Bot"
    Show-StageHeader 6 $Script:TotalStages "Create Telegram Bot"

    Write-Plain "Now we'll create your bot's identity in Telegram."
    Write-Plain "You'll do this on your phone (the BotFather is a phone-friendly process)."
    Write-Host ""
    Write-Bold "  ON YOUR PHONE:"
    Write-Plain "    1. Open Telegram"
    Write-Plain "    2. In the search box at the top, type:  BotFather"
    Write-Plain "    3. Tap the BotFather account (it has a BLUE CHECKMARK next to the name)"
    Write-Plain "       IMPORTANT: There are fake BotFathers. The real one has the blue checkmark."
    Write-Plain "    4. Tap 'Start' (or send the message: /start )"
    Write-Plain "    5. Send the message: /newbot"
    Write-Plain "    6. When asked for a name, type something like:  Mike's Assistant"
    Write-Plain "       (this is the display name, you can change it later)"
    Write-Plain "    7. When asked for a username, type something ending in 'bot', like:"
    Write-Plain "          mikes_assistant_bot"
    Write-Plain "       (must end in 'bot' and must be unique -- try variations if taken)"
    Write-Plain "    8. BotFather sends you a long token that looks like:"
    Write-Plain "          123456789:ABCdefGHIjklMNOpqrsTUVwxyz-1234567"
    Write-Plain "    9. Copy that ENTIRE token (long press, tap Copy)"
    Write-Host ""
    Write-Bold "  IMPORTANT:"
    Write-Plain "    - Save the token in Bitwarden right now (call it 'Telegram bot token')"
    Write-Plain "    - The token is like a password -- anyone with it controls your bot"
    Write-Host ""

    Wait-ForReturn "Press Enter once you've saved the token in Bitwarden..."

    # Telegram bot tokens are <numeric_id>:<alphanumeric + dash/underscore>.
    # Validation is intentionally permissive -- real validation happens when OpenClaw connects.
    $tgOk = $false
    $tgAttempts = 0
    while (-not $tgOk) {
        $tgAttempts++
        $secureToken = Read-Host "  Paste your Telegram bot token" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ($token -match '^\d+:[\w\-]+$') {
            Save-Secret -Key "TELEGRAM_BOT_TOKEN" -Value $token
            Write-Success "Telegram token saved for the rest of this setup."
            Save-Progress 6
            $tgOk = $true
        } else {
            Write-Fail "That doesn't look like a Telegram bot token."
            Write-Plain "  It should look like:  123456789:ABCdef-GHIjkl..."

            if ($tgAttempts -ge 3) {
                Write-Host ""
                Write-Plain "  I keep rejecting your token. Three options:"
                Write-Plain "    r) Try again with a different paste"
                Write-Plain "    a) Accept this token anyway (use if you're sure it's correct"
                Write-Plain "       and my validation is just being too strict)"
                Write-Plain "    q) Quit and contact Shands"
                Write-Host ""
                $choice = Read-Host "  Choose (r/a/q)"
                switch -Regex ($choice) {
                    '^[Aa]' {
                        Save-Secret -Key "TELEGRAM_BOT_TOKEN" -Value $token
                        Write-Success "Telegram token accepted."
                        Save-Progress 6
                        $tgOk = $true
                    }
                    '^[Qq]' {
                        Write-Info "Progress saved. Double-click Setup-MikeBot.bat to resume."
                        exit 0
                    }
                    default { Write-Info "Retrying..." }
                }
            } else {
                Write-Plain "  Try pasting again, or close and re-run if you need to find it again."
            }
        }
    }

    # Save-Progress 6 was moved inside the loop -- fires immediately on token save,
    # closing the gap between key-saved and stage-block-end where a window-close
    # could lose progress.
}


# =============================================================================
# STAGE 7: Create DeepSeek Account & API Key
# =============================================================================

if (-not (Test-StageAlreadyComplete 7)) {
    $Script:CurrentStage = 7
    Write-SetupEvent "START: Stage 7 - Create DeepSeek Account & API Key"
    Show-StageHeader 7 $Script:TotalStages "Create DeepSeek Account & API Key"

    Write-Plain "DeepSeek is the AI model that will power your bot. It's about 10x cheaper"
    Write-Plain "than the alternatives, and new accounts get free credits to start."
    Write-Host ""
    Write-Bold "  STEP-BY-STEP:"
    Write-Plain "    1. I'll open platform.deepseek.com in your browser"
    Write-Plain "    2. Click 'Sign Up'"
    Write-Plain "    3. Use your email + create a strong password (save it in Bitwarden!)"
    Write-Plain "    4. Verify your email (check your inbox)"
    Write-Plain "    5. You may need to verify a phone number too"
    Write-Plain "    6. Once you're logged into the dashboard, click 'API Keys' on the left"
    Write-Plain "    7. Click 'Create new API key'"
    Write-Plain "    8. Give it a name like 'My laptop bot'"
    Write-Plain "    9. The key starts with 'sk-' and is shown ONCE -- copy it immediately"
    Write-Plain "   10. Save it in Bitwarden (call it 'DeepSeek API key')"
    Write-Host ""
    Write-Bold "  ABOUT BILLING:"
    Write-Plain "    - New accounts get free credits (about 5 million tokens, enough for"
    Write-Plain "      hundreds of conversations)"
    Write-Plain "    - When those run out, you'd add ~$2 to keep going"
    Write-Plain "    - You can set spending limits in the billing section"
    Write-Host ""

    $openDS = Read-Host "  Open platform.deepseek.com now? (Enter = yes, n = skip)"
    if ($openDS -notmatch '^[Nn]') {
        Start-Process "https://platform.deepseek.com"
    }

    Wait-ForReturn "Press Enter once you have your DeepSeek API key saved in Bitwarden..."

    # Get the key
    Write-Host ""
    Write-Plain "Now paste the DeepSeek API key here."
    Write-Plain "(Right-click to paste. It will not show on screen as you type.)"
    Write-Host ""

    $dsOk = $false
    $dsAttempts = 0
    # DeepSeek API keys start with 'sk-' followed by 16+ non-whitespace characters.
    # Validation is intentionally permissive -- real validation happens via the API test.
    while (-not $dsOk) {
        $dsAttempts++
        $secureKey = Read-Host "  Paste your DeepSeek API key" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ($key -match '^sk-\S{16,}$') {
            Save-Secret -Key "DEEPSEEK_API_KEY" -Value $key
            Write-Success "DeepSeek key saved."
            Save-Progress 7
            $dsOk = $true
        } else {
            Write-Fail "That doesn't look like a DeepSeek API key."
            Write-Plain "  It should start with 'sk-' followed by letters and numbers."

            if ($dsAttempts -ge 3) {
                Write-Host ""
                Write-Plain "  I keep rejecting your key. Three options:"
                Write-Plain "    r) Try again with a different paste"
                Write-Plain "    a) Accept this key anyway (use if you're sure it's correct"
                Write-Plain "       and my validation is just being too strict)"
                Write-Plain "    q) Quit and contact Shands"
                Write-Host ""
                $choice = Read-Host "  Choose (r/a/q)"
                switch -Regex ($choice) {
                    '^[Aa]' {
                        Save-Secret -Key "DEEPSEEK_API_KEY" -Value $key
                        Write-Success "DeepSeek key accepted."
                        Save-Progress 7
                        $dsOk = $true
                    }
                    '^[Qq]' {
                        Write-Info "Progress saved. Double-click Setup-MikeBot.bat to resume."
                        exit 0
                    }
                    default { Write-Info "Retrying..." }
                }
            } else {
                Write-Plain "  Try again, or get the key from Bitwarden if you saved it there."
            }
        }
    }

    # Save-Progress 7 was moved inside the loop -- fires immediately on key save.
}


# =============================================================================
# STAGE 8: Test the API Key
# =============================================================================

if (-not (Test-StageAlreadyComplete 8)) {
    $Script:CurrentStage = 8
    Write-SetupEvent "START: Stage 8 - Test the API Key"
    Show-StageHeader 8 $Script:TotalStages "Test the API Key"

    Write-Plain "Before we set up OpenClaw, let's confirm your DeepSeek key actually works."
    Write-Plain "This makes one tiny test call (costs less than a penny) to DeepSeek."
    Write-Host ""

    $key = Get-Secret -Key "DEEPSEEK_API_KEY"
    if (-not $key) {
        Write-Fail "DeepSeek key not found. Go back to Stage 7."
        Show-SupportBlock -StageNum 8 -StageName "Test the API Key" `
            -StepName "Load API key" -ErrorDetail "DEEPSEEK_API_KEY not found in .env"
        Wait-ForReturn "Press Enter to exit..."
        exit 1
    }

    $null = Invoke-WithRetrySkipQuit -StepName "Testing DeepSeek API key" -Action {
        try {
            Write-Info "Sending a test message to DeepSeek..."
            $headers = @{
                "Authorization" = "Bearer $key"
                "Content-Type"  = "application/json"
            }
            # deepseek-v4-flash is the current default model.
            # deepseek-chat was deprecated 2026-07-24 (maps to v4-flash non-thinking).
            # See: https://api-docs.deepseek.com/
            # thinking disabled so max_tokens=20 produces content, not just reasoning.
            $body = @{
                model = "deepseek-v4-flash"
                messages = @(
                    @{ role = "user"; content = "Reply with just the word: OK" }
                )
                max_tokens = 20
                thinking = @{ type = "disabled" }
            } | ConvertTo-Json -Depth 4

            # /v1/chat/completions is the canonical OpenAI-compatible path.
            # Both /v1/chat/completions and /chat/completions return 200;
            # we use the /v1 form for forward compatibility with OpenAI SDKs.
            $resp = Invoke-RestMethod -Uri "https://api.deepseek.com/v1/chat/completions" `
                -Method Post -Headers $headers -Body $body -TimeoutSec 30 -ErrorAction Stop

            if ($resp.choices[0].message.content) {
                Write-Success "DeepSeek replied: '$($resp.choices[0].message.content.Trim())'"
                Write-Success "Your API key works!"
                return $true
            } else {
                Write-Fail "Got a response but it was empty."
                return $false
            }
        } catch {
            Write-Fail "API call failed: $($_.Exception.Message)"
            $msg = $_.Exception.Message
            if ($msg -match '401|Unauthorized') {
                Write-Plain ""
                Write-Plain "  This means the API key is wrong, expired, or hasn't activated yet."
                Write-Plain "  Go back to platform.deepseek.com and double-check the key."
            } elseif ($msg -match '402|Payment') {
                Write-Plain ""
                Write-Plain "  This means your account has no credits."
                Write-Plain "  Go to platform.deepseek.com -> Billing -> add credits."
            }
            return $false
        }
    }

    Save-Progress 8
}


# =============================================================================
# STAGE 9: Install OpenClaw
# =============================================================================

if (-not (Test-StageAlreadyComplete 9)) {
    $Script:CurrentStage = 9
    Write-SetupEvent "START: Stage 9 - Install OpenClaw"
    Show-StageHeader 9 $Script:TotalStages "Install OpenClaw"

    # -------------------------------------------------------------------------
    # Existing OpenClaw guard -- prevent accidental overwrite of another bot
    # -------------------------------------------------------------------------
    $ocCmd = Get-Command "openclaw" -ErrorAction SilentlyContinue
    $ocDir = Join-Path $env:USERPROFILE ".openclaw"
    $ocExists = ($null -ne $ocCmd) -or (Test-Path $ocDir)

    if ($ocExists) {
        Write-Host ""
        Write-Warn "============================================================"
        Write-Warn "  EXISTING OPENCLAW SETUP DETECTED"
        Write-Warn "============================================================"
        Write-Warn ""
        Write-Plain "  OpenClaw (or its configuration) is already on this laptop."
        Write-Plain "  This installer is designed for a fresh laptop."
        Write-Plain "  Running it here may overwrite another bot's configuration."
        Write-Host ""
        Write-Plain "  If this IS Mike's laptop and you're re-running the setup"
        Write-Plain "  after a previous attempt, this is expected -- type the"
        Write-Plain "  override phrase below to continue."
        Write-Host ""
        Write-Bold "  If you are NOT Mike setting up your own bot, STOP NOW."
        Write-Host ""
        $override = Read-Host "  Type SETUP-MIKEBOT to continue anyway"
        if ($override -ne "SETUP-MIKEBOT") {
            Write-Plain ""
            Write-Info "Exiting safely. No changes were made."
            Write-Plain "  If you're re-running the setup on Mike's laptop, re-run"
            Write-Plain "  and type SETUP-MIKEBOT when prompted."
            Wait-ForReturn "Press Enter to close..."
            exit 0
        }
        Write-Info "Override accepted. Continuing with setup..."
    }

    Write-Plain "Now we install OpenClaw itself. This is the AI assistant that runs on"
    Write-Plain "your laptop and routes messages between Telegram and DeepSeek."
    Write-Host ""

    # Make sure node is in PATH from Stage 4
    Update-EnvironmentPath
    Assert-ToolAvailable -Name "node" -FriendlyName "Node.js" -NextStage "Stage 9 (Install OpenClaw)"

    $null = Invoke-WithRetrySkipQuit -StepName "Installing OpenClaw" -Action {
        try {
            Write-Info "Installing OpenClaw via npm..."
            $proc = Start-Process -FilePath "npm" `
                -ArgumentList "install", "-g", "openclaw" `
                -PassThru -NoNewWindow
            $null = Wait-ProcessWithSpinner -Process $proc -Label "Installing OpenClaw (this may take a few minutes)" -TimeoutSeconds 900
            if ($proc.ExitCode -eq 0) {
                Update-EnvironmentPath
                if (Test-CommandExists "openclaw") {
                    $ver = & openclaw --version 2>$null
                    Write-Success "OpenClaw installed: $ver"
                    return $true
                } else {
                    Write-Warn "openclaw command not found after install."
                    Write-Plain "  This usually means npm's global folder isn't in PATH."
                    Write-Plain "  Close this window, reopen, and resume."
                    return $false
                }
            } else {
                Write-Fail "npm install failed (exit code $($proc.ExitCode))."
                return $false
            }
        } catch {
            Write-Fail "Install error: $($_.Exception.Message)"
            return $false
        }
    }

    Save-Progress 9
}


# =============================================================================
# STAGE 10: OpenClaw Onboarding
# =============================================================================

if (-not (Test-StageAlreadyComplete 10)) {
    $Script:CurrentStage = 10
    Write-SetupEvent "START: Stage 10 - OpenClaw Onboarding"
    Show-StageHeader 10 $Script:TotalStages "OpenClaw Onboarding"

    Write-Plain "OpenClaw has its own setup wizard that asks you a series of questions."
    Write-Plain "Here's exactly what to pick at each prompt:"
    Write-Host ""
    Write-Bold "  -- WIZARD ANSWERS --"
    Write-Plain "    Mode?                       -> QuickStart"
    Write-Plain "    Model provider?             -> DeepSeek"
    Write-Plain "                                   (if you don't see DeepSeek listed, text"
    Write-Plain "                                    Shands BEFORE choosing anything else)"
    Write-Plain "    DeepSeek API key?           -> Paste it (we'll set it as an env var first)"
    Write-Plain "    Default model?              -> Accept the default (deepseek-v4-flash)"
    Write-Plain "    Workspace location?         -> Press Enter (use default)"
    Write-Plain "    Gateway port?               -> Press Enter (default 18789)"
    Write-Plain "    Gateway bind?               -> Press Enter (loopback / localhost)"
    Write-Plain "    Gateway auth token?         -> Press Enter (auto-generated)"
    Write-Plain "    Tailscale?                  -> No"
    Write-Plain "    Channel?                    -> Telegram"
    Write-Plain "    Telegram bot token?         -> Paste your token (we have it ready)"
    Write-Plain "    Daemon install?             -> Yes"
    Write-Plain "    Skills?                     -> Yes (or skip -- you can add later)"
    Write-Host ""
    Write-Warn "If anything looks DIFFERENT from this list, take a screenshot and text Shands"
    Write-Warn "BEFORE answering. Don't guess on questions about gateways, ports, or auth."
    Write-Host ""

    # Set the env vars OpenClaw onboarding will pick up
    $dsKey  = Get-Secret -Key "DEEPSEEK_API_KEY"
    $tgToken = Get-Secret -Key "TELEGRAM_BOT_TOKEN"

    if (-not $dsKey -or -not $tgToken) {
        Write-Fail "Could not load your saved keys."
        if (-not $dsKey)  { Write-Plain "  DeepSeek API key not found -- go back to Stage 7." }
        if (-not $tgToken) { Write-Plain "  Telegram bot token not found -- go back to Stage 6." }
        Write-Plain "  If you already saved them, close this window and re-run Setup-MikeBot.bat."
        $missing = if (-not $dsKey -and -not $tgToken) { "Both keys" } elseif (-not $dsKey) { "DeepSeek key" } else { "Telegram token" }
        Show-SupportBlock -StageNum 10 -StageName "OpenClaw Onboarding" `
            -StepName "Load saved keys" -ErrorDetail "$missing not found in .env"
        Wait-ForReturn "Press Enter to exit..."
        exit 1
    }

    $env:DEEPSEEK_API_KEY      = $dsKey
    $env:TELEGRAM_BOT_TOKEN    = $tgToken

    Write-Info "Your saved keys are loaded into this window so the wizard can use them."
    Write-Plain "When the wizard asks for the DeepSeek key or Telegram token, you can:"
    Write-Plain "  - Just press Enter if it offers to use the env var, OR"
    Write-Plain "  - Paste the key manually (right-click in the wizard window)"
    Write-Host ""
    Write-Bold "  FALLBACK -- if the wizard DOESN'T pick up the keys automatically:"
    Write-Plain "  DeepSeek key starts with: $($dsKey.Substring(0, [Math]::Min(8, $dsKey.Length)))..."
    Write-Plain "  Telegram token starts with: $($tgToken.Substring(0, [Math]::Min(10, $tgToken.Length)))..."
    Write-Plain "  Copy the full key from Bitwarden if you need to paste manually."
    Write-Host ""

    Wait-ForReturn "Press Enter when ready to start the OpenClaw wizard..."

    # Run onboarding with retry.
    # Using the call operator (&) instead of Start-Process -NoNewWindow because
    # the latter can break interactive TUI rendering (arrow keys, prompts).
    # Exit code is captured via $LASTEXITCODE.
    $null = Invoke-WithRetrySkipQuit -StepName "OpenClaw onboarding" -Action {
        try {
            & openclaw onboard --install-daemon
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Onboarding complete."
                return $true
            } else {
                Write-Fail "Onboarding exited with code $LASTEXITCODE."
                Write-Plain ""
                Write-Plain "  Onboarding can fail for several reasons:"
                Write-Plain "    - Network interruption during setup"
                Write-Plain "    - API key issue (wrong key, expired, no credits)"
                Write-Plain "    - Model not available on your account"
                Write-Plain "    - Port conflict with another program"
                Write-Plain ""
                Write-Plain "  To diagnose: run Setup-MikeBot-Diagnostic.ps1"
                Write-Plain "    (it's in the same folder as this script)"
                Write-Plain "  Or text Shands with a screenshot of this window."
                return $false
            }
        } catch {
            Write-Fail "Onboarding error: $($_.Exception.Message)"
            return $false
        }
    }

    Save-Progress 10
}


# =============================================================================
# STAGE 11: Gateway Health Check
# =============================================================================

if (-not (Test-StageAlreadyComplete 11)) {
    $Script:CurrentStage = 11
    Write-SetupEvent "START: Stage 11 - Gateway Health Check"
    Show-StageHeader 11 $Script:TotalStages "Gateway Health Check"

    Write-Plain "Checking that the OpenClaw gateway (the brain of the bot) is running..."
    Write-Host ""

    $gwOk = Invoke-WithRetrySkipQuit -StepName "Gateway health check" -MaxRetries 2 -Action {
        try {
            $output = & openclaw gateway status 2>&1
            $exit = $LASTEXITCODE
            if ($exit -eq 0) {
                Write-Success "Gateway is running."
                Write-Plain "  $output"
                return $true
            } else {
                Write-Fail "Gateway is not healthy."
                Write-Plain "  Output: $output"
                Write-Plain ""
                Write-Plain "  Try: openclaw gateway restart"
                return $false
            }
        } catch {
            Write-Fail "Couldn't run 'openclaw gateway status': $($_.Exception.Message)"
            return $false
        }
    }

    if (-not $gwOk) {
        Write-Host ""
        Write-Warn "The gateway is the heart of the bot. The remaining stages will not work"
        Write-Warn "until it's running. Stop here and text Shands."
        Show-SupportBlock -StageNum 11 -StageName "Gateway Health Check" `
            -StepName "Gateway status" -ErrorDetail "Gateway not healthy after retries"
        Write-Host ""
        $force = Read-Host "  Type 'continue anyway' to proceed (NOT recommended), or anything else to stop"
        if ($force -ne "continue anyway") {
            Write-SetupEvent "QUIT: Gateway unhealthy, user stopped"
            Write-Info "Stopping. Run Setup-MikeBot.bat again after fixing the gateway."
            exit 0
        }
        Write-SetupEvent "OVERRIDE: User continued despite gateway failure"
    }

    Save-Progress 11
}


# =============================================================================
# STAGE 12: Dashboard Check
# =============================================================================

if (-not (Test-StageAlreadyComplete 12)) {
    $Script:CurrentStage = 12
    Write-SetupEvent "START: Stage 12 - Dashboard Check"
    Show-StageHeader 12 $Script:TotalStages "Dashboard Check"

    Write-Plain "OpenClaw has a web dashboard you can open in your browser."
    Write-Plain "Let's make sure it's reachable, then save the access token for you."
    Write-Host ""

    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Write-Success "Dashboard is reachable (HTTP $($resp.StatusCode))."
    } catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($code -eq 401 -or $code -eq 403) {
            Write-Success "Dashboard is reachable (HTTP $code -- wants auth, that's expected)."
        } else {
            Write-Warn "Dashboard didn't respond cleanly. Gateway may still be starting."
            Write-Plain "  Wait 30 seconds and try opening http://127.0.0.1:18789/ in your browser."
        }
    }

    # Try to grab the auth token for Mike
    Write-Host ""
    Write-Info "Getting your dashboard access token..."
    try {
        $token = & openclaw config get gateway.auth.token 2>$null
        if ($token -and $token -ne "null" -and $token -ne "undefined") {
            Write-Host ""
            Write-Bold "  YOUR DASHBOARD TOKEN (paste this if the dashboard asks):"
            Write-Host ""
            Write-Host "    $token" -ForegroundColor White
            Write-Host ""
            Write-Plain "  This token is saved in OpenClaw's config."
            Write-Plain "  To retrieve it later, open PowerShell and run:"
            Write-Plain "    openclaw config get gateway.auth.token"

            # Save to a separate file so Stage 15's log overwrite doesn't destroy it.
            $token | Set-Content -Path $TokenFile -Encoding UTF8
            Write-Plain "  Token also saved to: $TokenFile"
        } else {
            Write-Warn "Couldn't read the token automatically. Get it later with:"
            Write-Plain "    openclaw config get gateway.auth.token"
        }
    } catch {
        Write-Warn "Couldn't read the token: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Plain "Open http://127.0.0.1:18789/ in your browser and paste the token if asked."
    Write-Plain "Try sending the dashboard a test message like 'hello'."
    Write-Plain "If you get a reply, the laptop side of the bot is working."
    Write-Host ""

    Wait-ForReturn "Press Enter once you've tested the dashboard (or skipped it)..."

    Save-Progress 12
}


# =============================================================================
# STAGE 13: Approve Your Phone with the Bot
# =============================================================================

if (-not (Test-StageAlreadyComplete 13)) {
    $Script:CurrentStage = 13
    Write-SetupEvent "START: Stage 13 - Approve Your Phone with the Bot"
    Show-StageHeader 13 $Script:TotalStages "Approve Your Phone with the Bot"

    Write-Plain "OpenClaw doesn't let just anyone message your bot -- you have to approve"
    Write-Plain "your own phone first. Here's how:"
    Write-Host ""
    Write-Bold "  STEP 1: Find your bot in Telegram (on your phone)"
    Write-Plain "    Search for the username you set in Stage 6 (e.g., mikes_assistant_bot)"
    Write-Plain "    Tap it to open the chat."
    Write-Host ""
    Write-Bold "  STEP 2: Send your bot any message"
    Write-Plain "    Just type 'hello' and send. The bot won't reply yet -- that's expected."
    Write-Plain "    This puts a 'pairing request' in the queue."
    Write-Host ""

    Wait-ForReturn "Press Enter once you've sent your bot a message from your phone..."

    Write-Host ""
    Write-Bold "  STEP 3: List pending pairings"
    Write-Info "Running: openclaw pairing list --channel telegram"
    Write-Host ""
    try {
        & openclaw pairing list --channel telegram
    } catch {
        Write-Warn "Couldn't list pairings: $($_.Exception.Message)"
        Write-Plain "  Try this command syntax instead: openclaw pairing list"
    }

    Write-Host ""
    Write-Plain "You should see a pairing request with a CODE next to it."
    Write-Plain "Copy that code (just the code, no extra characters)."
    Write-Host ""

    $pairOk = $false
    $pairAttempts = 0
    while (-not $pairOk) {
        $pairAttempts++
        $code = Read-Host "  Paste the pairing code"
        if ($code -match '^[A-Za-z0-9_\-]+$' -and $code.Length -ge 4) {
            try {
                # Try current CLI syntax first (positional code, no channel prefix)
                $result = & openclaw pairing approve $code 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Pairing approved!"
                    $pairOk = $true
                } else {
                    # Fall back to older syntax (channel-prefixed)
                    Write-Info "Trying alternate syntax..."
                    $result = & openclaw pairing approve telegram $code 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Pairing approved!"
                        $pairOk = $true
                    } else {
                        Write-Fail "Approval failed."
                        Write-Plain "  Output: $result"
                        Write-Plain "  If you see 'unknown command', the pairing system may"
                        Write-Plain "  have changed. Take a screenshot and text Shands."
                    }
                }
            } catch {
                Write-Fail "Error: $($_.Exception.Message)"
            }
        } else {
            Write-Warn "That doesn't look like a valid code. Try again."
        }

        if (-not $pairOk) {
            if ($pairAttempts -ge 3) {
                Write-Host ""
                Write-Plain "  Pairing has failed $pairAttempts times. Three options:"
                Write-Plain "    r) Try again with a different code"
                Write-Plain "    s) Skip pairing for now (you can do it manually later)"
                Write-Plain "    q) Quit and contact Shands"
                Write-Host ""
                $choice = Read-Host "  Choose (r/s/q)"
                switch -Regex ($choice) {
                    '^[Ss]' { break }
                    '^[Qq]' {
                        Write-SetupEvent "QUIT: User quit at pairing"
                        Write-Info "Progress saved. Double-click Setup-MikeBot.bat to resume."
                        try { Stop-Transcript } catch { $null }
                        exit 0
                    }
                    default { Write-Info "Retrying..." }
                }
                if ($choice -match '^[Ss]') {
                    Add-Skip -StageNum 13 -StepName "Phone pairing"
                    break
                }
            } else {
                $retry = Read-Host "  Try a different code? (y/n)"
                if ($retry -notmatch '^[Yy]') { break }
            }
        }
    }

    Save-Progress 13
}


# =============================================================================
# STAGE 14: End-to-End Test
# =============================================================================

if (-not (Test-StageAlreadyComplete 14)) {
    $Script:CurrentStage = 14
    Write-SetupEvent "START: Stage 14 - End-to-End Test"
    Show-StageHeader 14 $Script:TotalStages "End-to-End Test"

    if ($Script:SkippedStages -match "^13:") {
        Write-Warn "NOTE: You skipped phone pairing in Stage 13."
        Write-Warn "The bot will NOT reply until pairing is done."
        Write-Plain "  To pair later, run:  openclaw pairing list --channel telegram"
        Write-Plain "  Then:                openclaw pairing approve <code>"
        Write-Host ""
    }

    Write-Plain "Moment of truth. Send your bot a real message from Telegram."
    Write-Host ""
    Write-Bold "  ON YOUR PHONE:"
    Write-Plain "    Open the chat with your bot and send: 'What is 2 + 2?'"
    Write-Host ""
    Write-Plain "  Within 5-15 seconds you should get a reply from DeepSeek."
    Write-Host ""
    Write-Plain "  Try Telegram Desktop too:"
    Write-Plain "    Open Telegram Desktop on this laptop, log in if needed,"
    Write-Plain "    you should see the same conversation."
    Write-Host ""

    # Capture a timestamp BEFORE the user sends the test message.
    # We'll use this to filter log lines so we only check messages from this test.
    $testStartTime = Get-Date

    $testOk = $false
    while (-not $testOk) {
        $reply = Read-Host "  Did the bot reply? (y = yes, n = no, s = skip and finish setup)"
        if ($reply -match '^[Yy]') {
            # Verify the message actually traveled the full path by checking logs.
            # This converts Mike's job from "search" to "verification" -- we do the
            # filtering; he confirms what he sees.
            Write-Host ""
            Write-Info "Checking the bot's logs to confirm the message traveled the full path..."
            Write-Host ""

            try {
                $logOutput = & openclaw logs --json --limit 100 --no-color 2>&1
                $telegramLines = @()
                $deepseekLines = @()

                foreach ($line in $logOutput) {
                    try {
                        $entry = $line | ConvertFrom-Json
                        # Only consider log entries after the test started
                        if ($entry.time) {
                            $entryTime = [DateTime]::Parse($entry.time)
                            if ($entryTime -lt $testStartTime) { continue }
                        }
                        $msg = if ($entry.message) { $entry.message } else { "$entry" }
                        if ($msg -match 'telegram') {
                            $telegramLines += $msg
                        }
                        if ($msg -match 'deepseek|api\.deepseek') {
                            $deepseekLines += $msg
                        }
                    } catch { $null }
                }

                # Show Mike what we found so he can verify, not search.
                if ($telegramLines.Count -gt 0) {
                    Write-Plain "  Lines mentioning 'telegram' ($($telegramLines.Count) found):"
                    $telegramLines | Select-Object -First 5 | ForEach-Object {
                        $short = if ($_.Length -gt 120) { $_.Substring(0, 117) + "..." } else { $_ }
                        Write-Plain "    - $short"
                    }
                } else {
                    Write-Plain "  No lines mentioning 'telegram' were found in recent logs."
                }

                Write-Host ""
                if ($deepseekLines.Count -gt 0) {
                    Write-Plain "  Lines mentioning 'deepseek' ($($deepseekLines.Count) found):"
                    $deepseekLines | Select-Object -First 5 | ForEach-Object {
                        $short = if ($_.Length -gt 120) { $_.Substring(0, 117) + "..." } else { $_ }
                        Write-Plain "    - $short"
                    }
                } else {
                    Write-Plain "  No lines mentioning 'deepseek' were found in recent logs."
                }

                Write-Host ""
                $tgSeen = Read-Host "  In the lines above, do you see at least one that mentions 'telegram'? (y/n)"
                $dsSeen = Read-Host "  Do you see at least one that mentions 'deepseek' or 'api.deepseek'? (y/n)"

                if (($tgSeen -match '^[Yy]') -and ($dsSeen -match '^[Yy]')) {
                    Write-Success "Logs confirm the message traveled the full path: Telegram -> DeepSeek -> Telegram."
                    $testOk = $true
                } else {
                    Write-Warn "The logs don't clearly show the full message path."
                    Write-Plain "  Your bot may still be working -- the log messages can vary."
                    Write-Plain "  But to be safe, take a screenshot of this window and text it to Shands."
                    Write-Plain "  He can check whether everything is actually connected."
                    Write-Host ""
                    $forceOk = Read-Host "  Continue anyway? (y = yes, finish setup / n = test again)"
                    if ($forceOk -match '^[Yy]') {
                        $testOk = $true
                    }
                }
            } catch {
                Write-Warn "Couldn't check the logs: $($_.Exception.Message)"
                Write-Plain "  This is usually fine -- your bot replied, so the path is working."
                Write-Plain "  If you want to double-check, run: openclaw logs"
                $testOk = $true
            }
        } elseif ($reply -match '^[Ss]') {
            Write-Warn "Skipped. You can test later."
            break
        } else {
            Write-Host ""
            Write-Plain "  Troubleshooting:"
            Write-Plain "    1. Wait another 30 seconds -- first reply can be slow"
            Write-Plain "    2. Check the gateway: open PowerShell, run 'openclaw gateway status'"
            Write-Plain "    3. Check the logs: 'openclaw logs --follow' (Ctrl+C to stop)"
            Write-Plain "    4. Make sure pairing was approved in Stage 13"
            Write-Plain "    5. Take a screenshot and text Shands"
            Write-Host ""
            $retry = Read-Host "  Try again? (y = test again, n = skip)"
            if ($retry -notmatch '^[Yy]') { break }
        }
    }

    Save-Progress 14
}


# =============================================================================
# STAGE 15: All Done!
# =============================================================================

$Script:CurrentStage = 15
Write-SetupEvent "START: Stage 15 - All Done!"
Save-Progress 15

Show-StageHeader 15 $Script:TotalStages "All Done!"
Write-Progress -Activity "MikeBot Setup" -Completed

# -------------------------------------------------------------------------
# Summary dashboard — show each stage's status at a glance
# -------------------------------------------------------------------------
Write-Host ""
Write-Host "  Setup Summary:" -ForegroundColor White
Write-Host "  --------------" -ForegroundColor White
for ($i = 1; $i -le $Script:TotalStages; $i++) {
    $name = $StageNames[$i].PadRight(38)
    $status = if ($Script:StageResults.ContainsKey($i)) { $Script:StageResults[$i] } else { "OK" }
    $color = switch ($status) {
        "OK"      { "Green" }
        "SKIPPED" { "Yellow" }
        default   { "Red" }
    }
    Write-Host "  Stage $($i.ToString().PadLeft(2)): $name" -NoNewline
    Write-Host "[$status]" -ForegroundColor $color
}
Write-Host ""

if ($Script:SkippedStages.Count -gt 0) {
    Write-Warn "Some steps were skipped:"
    foreach ($skip in $Script:SkippedStages) {
        Write-Plain "  - Stage $skip"
    }
    Write-Host ""
}

Write-Host ""
Write-Host "  Congratulations Mike -- your bot is set up." -ForegroundColor Green
Write-Host ""
Write-Plain "What you have now:"
Write-Plain "  - OpenClaw running in the background as a service"
Write-Plain "  - DeepSeek powering the AI brain"
Write-Plain "  - Telegram bot accepting messages from your phone and laptop"
Write-Plain "  - Bitwarden storing all your sensitive keys"
Write-Host ""
Write-Bold "  IMPORTANT -- CLEAN UP:"
Write-Plain "  This setup saved your API keys temporarily here:"
Write-Plain "      $EnvFile"
Write-Plain "  Once you've confirmed your bot works for a few days, DELETE that file."
Write-Plain "  OpenClaw has its own copy of the keys in its config -- you don't need this one."
Write-Host ""
Write-Bold "  IF SOMETHING BREAKS LATER:"
Write-Plain "  - First check: open PowerShell, run 'openclaw gateway status'"
Write-Plain "  - If it's not running: 'openclaw gateway restart'"
Write-Plain "  - Still broken? Run Setup-MikeBot-Diagnostic.ps1 (next to this script)"
Write-Plain "  - Or just text Shands"
Write-Host ""
Write-Bold "  WHAT NOT TO DO:"
Write-Plain "  - Do not share your DeepSeek API key with anyone"
Write-Plain "  - Do not share your Telegram bot token with anyone"
Write-Plain "  - Do not paste either one into random websites"
Write-Plain "  - Do not turn off the laptop if you want the bot to keep working"
Write-Host ""

# -------------------------------------------------------------------------
# Capture versions for the setup log
# -------------------------------------------------------------------------
function Get-VersionSafe {
    param(
        [string]$Command,
        [string]$VersionFlag = "--version"
    )
    try {
        $result = & $Command $VersionFlag 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -eq 0 -and $result) {
            return $result.ToString().Trim()
        }
    } catch { $null }
    return "not detected"
}

$verGit      = Get-VersionSafe "git"
$verNode     = Get-VersionSafe "node"
$verNpm      = Get-VersionSafe "npm"
$verOpenClaw = Get-VersionSafe "openclaw"
$verWinget   = Get-VersionSafe "winget" "--version"

# Write a setup log Mike (or Shands) can reference later
$logContent = @"
# Mike's Bot Setup Log

**Setup completed:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Laptop:** $env:COMPUTERNAME
**User:** $env:USERNAME
**Windows:** $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName) build $([System.Environment]::OSVersion.Version.Build)

## Installed Components

- Git:      $verGit
- Node.js:  $verNode
- npm:      $verNpm
- OpenClaw: $verOpenClaw
- winget:   $verWinget

## Configuration

- Model provider: DeepSeek
- Default model: deepseek-v4-flash (or whatever onboarding selected)
- Channel: Telegram
- Gateway: http://127.0.0.1:18789/

## Files To Know About

- Setup progress (safe to delete): ``$ProgressFile``
- Temporary secrets file (DELETE after a few days): ``$EnvFile``
- Dashboard token (keep this one): ``$TokenFile``
- Setup transcript (full console log): ``$TranscriptFile``
- Setup event log (timeline): ``$EventLogFile``
- OpenClaw config: ``%USERPROFILE%\.openclaw\``

## To Get Dashboard Token

Open PowerShell and run:

    openclaw config get gateway.auth.token

## Common Commands

    openclaw gateway status     # is the bot running?
    openclaw gateway restart    # restart it
    openclaw logs --follow      # watch live logs (Ctrl+C to stop)
    openclaw doctor             # health check

"@

if ($Script:SkippedStages.Count -gt 0) {
    $logContent += "`n## Skipped Steps`n`n"
    foreach ($skip in $Script:SkippedStages) {
        $logContent += "- Stage $skip`n"
    }
}

if (-not (Test-Path $ProgressDir)) { New-Item -ItemType Directory -Path $ProgressDir -Force | Out-Null }
$logContent | Set-Content -Path $LogFile -Encoding UTF8
Write-Plain "Setup log saved to: $LogFile"
Write-Plain "Full transcript saved to: $TranscriptFile"
Write-Host ""
Write-Plain "You can close this window now. Your bot will keep running in the background."
Write-Host ""
try { Stop-Transcript } catch { $null }
Wait-ForReturn "Press Enter to close..."
