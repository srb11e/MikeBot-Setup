# =============================================================================
# Setup-MikeBot.ps1 — OpenClaw + DeepSeek + Telegram setup for Windows
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
# PROGRESS TRACKING
# -----------------------------------------------------------------------------

$ProgressDir  = Join-Path $env:USERPROFILE "MikeBot-Setup"
$ProgressFile = Join-Path $ProgressDir   ".progress"
$EnvFile      = Join-Path $ProgressDir   ".env"  # stores API keys etc. between stages
$LogFile      = Join-Path $ProgressDir   "setup-log.md"
$Script:LastCompleted = 0
$Script:TotalStages   = 15

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
}

function Load-Progress {
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

function Should-Skip {
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

    # Lock the file down to just Mike's account
    try {
        $acl = Get-Acl $EnvFile
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $env:USERNAME, "FullControl", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $EnvFile -AclObject $acl
    } catch {
        # If ACL hardening fails, continue anyway — the file is in his user profile
        Write-Warn "Could not lock secret file permissions. File is still in your user folder: $EnvFile"
    }
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

function Refresh-EnvironmentPath {
    # winget installs add things to PATH but the change doesn't reach the
    # currently-running process. Pull the latest PATH from the registry so
    # newly-installed tools (node, git, openclaw) become visible.
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

# -----------------------------------------------------------------------------
# WINGET INSTALL HELPER
# -----------------------------------------------------------------------------
# winget exit codes:
#   0           = success
#   -1978335189 = already installed (treat as success)
#   anything else = real failure

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )
    Write-Info "Installing $DisplayName (this may take a few minutes — silence is normal)..."

    $args = @("install", "--id", $PackageId, "--exact",
              "--silent", "--accept-source-agreements", "--accept-package-agreements")

    $proc = Start-Process -FilePath "winget" -ArgumentList $args -Wait -PassThru -NoNewWindow
    $code = $proc.ExitCode

    if ($code -eq 0) {
        Write-Success "$DisplayName installed."
        return $true
    } elseif ($code -eq -1978335189) {
        Write-Success "$DisplayName already installed."
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
        [int]$MaxRetries = 3
    )
    $attempts = 0
    while ($true) {
        $ok = & $Action
        if ($ok) { return $true }

        $attempts++
        Write-Host ""
        Write-Fail "$StepName failed."

        if ($attempts -ge $MaxRetries) {
            Write-Warn "This step has failed $attempts times."
            Write-Plain "If you need help, send Shands the contents of:"
            Write-Plain "    $LogFile"
        }

        Write-Host ""
        Write-Plain "Options:"
        Write-Plain "    r) Retry this step"
        Write-Plain "    s) Skip and continue to the next step"
        Write-Plain "    q) Quit (your progress is saved — you can resume later)"
        Write-Host ""
        $choice = Read-Host "  Choose (r/s/q)"
        switch -Regex ($choice) {
            '^[Rr]' { Write-Info "Retrying..."; continue }
            '^[Ss]' { return $false }
            '^[Qq]' {
                Write-Info "Progress saved. Double-click Setup-MikeBot.bat to resume."
                exit 0
            }
            default { Write-Info "Retrying..."; continue }
        }
    }
}

# -----------------------------------------------------------------------------
# CTRL+C HANDLER
# -----------------------------------------------------------------------------
# PowerShell handles Ctrl+C by raising a PipelineStoppedException. We register
# an exit handler that runs no matter how the script ends.

$ExitHandler = {
    if ($Script:LastCompleted -gt 0 -and $Script:LastCompleted -lt $Script:TotalStages) {
        Write-Host ""
        Write-Host "  [!] Setup interrupted. Progress saved through stage $($Script:LastCompleted)." -ForegroundColor Yellow
        Write-Host "  Double-click Setup-MikeBot.bat to resume from where you left off." -ForegroundColor Yellow
        Write-Host ""
    }
}
Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action $ExitHandler | Out-Null


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
Write-Bold "  IF YOU NEED TO STOP:"
Write-Plain "    - Close this window any time. Your progress is saved."
Write-Plain "    - Double-click Setup-MikeBot.bat again to resume."
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
Load-Progress

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
    Write-Plain "Next up: Stage $next — $nextName"
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
Refresh-EnvironmentPath


# =============================================================================
# STAGE 1: Windows Version Check
# =============================================================================

if (-not (Should-Skip 1)) {
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

if (-not (Should-Skip 2)) {
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

if (-not (Should-Skip 3)) {
    Show-StageHeader 3 $Script:TotalStages "Security Basics"

    Write-Plain "This laptop will store an API key that costs real money if someone"
    Write-Plain "else gets it. Let's lock it down. Three things, takes about 5 minutes."

    if (Test-UserChoseSkip) {
        Write-Info "Skipping security setup (do this later — text Shands if unsure)."
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
            # Display can still turn off — that's fine, doesn't affect the bot
            Write-Success "Power settings adjusted: laptop won't sleep when plugged in."
            Write-Plain "  (The screen can still turn off — that's fine.)"
        } catch {
            Write-Warn "Couldn't adjust power settings automatically."
            Write-Plain "  You can do it manually later: Settings -> System -> Power & Battery"
        }

        Write-Host ""
        Write-Bold "  3. BITLOCKER (disk encryption — RECOMMENDED but optional)"
        Write-Plain "     This encrypts your hard drive so if someone steals the laptop"
        Write-Plain "     they can't read your API key off the disk."
        Write-Host ""
        Write-Plain "     If your laptop already has BitLocker on (most newer business"
        Write-Plain "     laptops do), you're good — skip this."
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
# STAGE 4: Install Foundation Tools (winget batch)
# =============================================================================

if (-not (Should-Skip 4)) {
    Show-StageHeader 4 $Script:TotalStages "Install Foundation Tools"

    Write-Plain "Installing the tools the bot needs:"
    Write-Plain "  - Git (version control — required by OpenClaw's installer)"
    Write-Plain "  - Node.js 22 LTS (the runtime OpenClaw runs on)"
    Write-Plain "  - Telegram Desktop (so you can chat with the bot from this laptop too)"
    Write-Host ""
    Write-Plain "Each one takes a couple minutes. Long pauses during downloads are normal."
    Write-Host ""

    # Verify winget exists. On a brand-new Windows 11 laptop it does.
    # On older Windows 10 it may not.
    if (-not (Test-CommandExists "winget")) {
        Write-Fail "winget (Windows Package Manager) is not available on this laptop."
        Write-Plain "  This is unusual on a recent laptop."
        Write-Plain "  Fix: open Microsoft Store, search 'App Installer', install/update it."
        Write-Plain "  Then re-run this setup."
        Wait-ForReturn "Press Enter to exit..."
        exit 1
    }

    $installs = @(
        @{ Id = "Git.Git";              Name = "Git" },
        @{ Id = "OpenJS.NodeJS.LTS";    Name = "Node.js 22 LTS" },
        @{ Id = "Telegram.TelegramDesktop"; Name = "Telegram Desktop" }
    )

    foreach ($pkg in $installs) {
        $stepResult = Invoke-WithRetrySkipQuit -StepName "Installing $($pkg.Name)" -Action {
            return (Install-WithWinget -PackageId $pkg.Id -DisplayName $pkg.Name)
        }
    }

    # Pick up the new tools without restarting the shell
    Refresh-EnvironmentPath

    Write-Host ""
    Write-Info "Verifying installs..."
    if (Test-CommandExists "git")  { Write-Success "git is available."  } else { Write-Warn "git not found in PATH yet — may need a restart." }
    if (Test-CommandExists "node") {
        $nodeVer = & node --version 2>$null
        Write-Success "node is available ($nodeVer)."
    } else {
        Write-Warn "node not found in PATH yet."
        Write-Plain ""
        Write-Plain "  This is common — the PATH changes haven't reached this window yet."
        Write-Plain "  I can restart this script automatically. You won't lose progress."
        Write-Host ""
        $restartChoice = Read-Host "  Restart automatically now? (Enter = yes, n = close and re-run manually)"
        if ($restartChoice -notmatch '^[Nn]') {
            Write-Info "Restarting..."
            Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`""
            exit 0
        } else {
            Write-Plain "  Close this window, then double-click Setup-MikeBot.bat to resume."
            Wait-ForReturn "Press Enter to close..."
            exit 0
        }
    }

    Save-Progress 4
}


# =============================================================================
# STAGE 5: Install Bitwarden (Password Manager)
# =============================================================================

if (-not (Should-Skip 5)) {
    Show-StageHeader 5 $Script:TotalStages "Install Bitwarden (Password Manager)"

    Write-Plain "Before you create API keys, you need somewhere safe to keep them."
    Write-Plain "Bitwarden is free and works on Windows, Mac, iPhone, Android."
    Write-Host ""

    if (Test-UserChoseSkip) {
        Write-Info "Skipping Bitwarden install (you have another password manager)."
        Write-Warn "Make sure you have somewhere safe to put your API keys before continuing."
    } else {
        $bwOk = Invoke-WithRetrySkipQuit -StepName "Installing Bitwarden" -Action {
            return (Install-WithWinget -PackageId "Bitwarden.Bitwarden" -DisplayName "Bitwarden")
        }

        Write-Host ""
        Write-Plain "Now create a Bitwarden account:"
        Write-Plain "  1. Open Bitwarden from your Start menu"
        Write-Plain "  2. Click 'Create Account'"
        Write-Plain "  3. Pick a STRONG master password and write it down somewhere safe"
        Write-Plain "     (if you forget it, no one can recover it for you)"
        Write-Plain "  4. Confirm the email they send you"
        Write-Host ""

        Wait-ForReturn "Press Enter once Bitwarden is open and you're logged in..."
    }

    Save-Progress 5
}


# =============================================================================
# STAGE 6: Create Telegram Bot (BEFORE OpenClaw onboarding so token is ready)
# =============================================================================

if (-not (Should-Skip 6)) {
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
    Write-Plain "       (must end in 'bot' and must be unique — try variations if taken)"
    Write-Plain "    8. BotFather sends you a long token that looks like:"
    Write-Plain "          123456789:ABCdefGHIjklMNOpqrsTUVwxyz-1234567"
    Write-Plain "    9. Copy that ENTIRE token (long press, tap Copy)"
    Write-Host ""
    Write-Bold "  IMPORTANT:"
    Write-Plain "    - Save the token in Bitwarden right now (call it 'Telegram bot token')"
    Write-Plain "    - The token is like a password — anyone with it controls your bot"
    Write-Host ""

    Wait-ForReturn "Press Enter once you've saved the token in Bitwarden..."

    # Ask Mike to paste the token here so we can use it later
    Write-Host ""
    Write-Plain "Now paste the token here so I can use it in the next steps."
    Write-Plain "(Right-click in this window to paste. The token won't be shown as you type.)"
    Write-Host ""

    $tgOk = $false
    while (-not $tgOk) {
        $secureToken = Read-Host "  Paste your Telegram bot token" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        # Telegram tokens look like: <numeric_id>:<35-50 chars of letters/numbers/dashes/underscores>
        if ($token -match '^\d+:[A-Za-z0-9_\-]{30,}$') {
            Save-Secret -Key "TELEGRAM_BOT_TOKEN" -Value $token
            Write-Success "Telegram token saved for the rest of this setup."
            $tgOk = $true
        } elseif ($token -eq 'force') {
            Write-Warn "Forcing acceptance — format doesn't match expected pattern."
            Write-Warn "If this isn't actually your bot token, the rest of setup will fail."
            Save-Secret -Key "TELEGRAM_BOT_TOKEN" -Value $token
            $tgOk = $true
        } else {
            Write-Fail "That doesn't look like a Telegram bot token."
            Write-Plain "  It should look like:  123456789:ABCdef-GHIjkl..."
            Write-Plain "  If you're SURE this is the right token from BotFather,"
            Write-Plain "  type 'force' (without quotes) to accept it anyway."
            Write-Plain "  Otherwise, try pasting again."
        }
    }

    Save-Progress 6
}


# =============================================================================
# STAGE 7: Create DeepSeek Account & API Key
# =============================================================================

if (-not (Should-Skip 7)) {
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
    Write-Plain "    9. The key starts with 'sk-' and is shown ONCE — copy it immediately"
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
    while (-not $dsOk) {
        $secureKey = Read-Host "  Paste your DeepSeek API key" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ($key -match '^sk-[A-Za-z0-9]{20,}$') {
            Save-Secret -Key "DEEPSEEK_API_KEY" -Value $key
            Write-Success "DeepSeek key saved."
            $dsOk = $true
        } else {
            Write-Fail "That doesn't look like a DeepSeek API key."
            Write-Plain "  It should start with 'sk-' followed by letters and numbers."
            Write-Plain "  Try again, or get the key from Bitwarden if you saved it there."
        }
    }

    Save-Progress 7
}


# =============================================================================
# STAGE 8: Test the API Key
# =============================================================================

if (-not (Should-Skip 8)) {
    Show-StageHeader 8 $Script:TotalStages "Test the API Key"

    Write-Plain "Before we set up OpenClaw, let's confirm your DeepSeek key actually works."
    Write-Plain "This makes one tiny test call (costs less than a penny) to DeepSeek."
    Write-Host ""

    $key = Get-Secret -Key "DEEPSEEK_API_KEY"
    if (-not $key) {
        Write-Fail "DeepSeek key not found. Go back to Stage 7."
        Wait-ForReturn "Press Enter to exit..."
        exit 1
    }

    $testResult = Invoke-WithRetrySkipQuit -StepName "Testing DeepSeek API key" -Action {
        try {
            Write-Info "Sending a test message to DeepSeek..."
            $headers = @{
                "Authorization" = "Bearer $key"
                "Content-Type"  = "application/json"
            }
            $body = @{
                model = "deepseek-chat"
                messages = @(
                    @{ role = "user"; content = "Reply with just the word: OK" }
                )
                max_tokens = 5
            } | ConvertTo-Json -Depth 4

            $resp = Invoke-RestMethod -Uri "https://api.deepseek.com/chat/completions" `
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

if (-not (Should-Skip 9)) {
    Show-StageHeader 9 $Script:TotalStages "Install OpenClaw"

    Write-Plain "Now we install OpenClaw itself. This is the AI assistant that runs on"
    Write-Plain "your laptop and routes messages between Telegram and DeepSeek."
    Write-Host ""

    # Make sure node is in PATH from Stage 4
    Refresh-EnvironmentPath

    if (-not (Test-CommandExists "node")) {
        Write-Fail "Node.js isn't available yet. We need to close and reopen this window."
        Write-Plain ""
        Write-Plain "  Close this window, then double-click Setup-MikeBot.bat again."
        Write-Plain "  It will resume from this stage with Node.js available."
        Wait-ForReturn "Press Enter to exit..."
        exit 0
    }

    $installOk = Invoke-WithRetrySkipQuit -StepName "Installing OpenClaw" -Action {
        try {
            Write-Info "Installing OpenClaw via npm (this can take 5-10 minutes)..."
            $proc = Start-Process -FilePath "npm" `
                -ArgumentList "install", "-g", "openclaw" `
                -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0) {
                Refresh-EnvironmentPath
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

if (-not (Should-Skip 10)) {
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
    Write-Plain "    Skills?                     -> Yes (or skip — you can add later)"
    Write-Host ""
    Write-Warn "If anything looks DIFFERENT from this list, take a screenshot and text Shands"
    Write-Warn "BEFORE answering. Don't guess on questions about gateways, ports, or auth."
    Write-Host ""

    # Set the env vars OpenClaw onboarding will pick up
    $dsKey  = Get-Secret -Key "DEEPSEEK_API_KEY"
    $tgToken = Get-Secret -Key "TELEGRAM_BOT_TOKEN"
    $env:DEEPSEEK_API_KEY      = $dsKey
    $env:TELEGRAM_BOT_TOKEN    = $tgToken

    Write-Info "Your saved keys are loaded into this window so the wizard can use them."
    Write-Plain "When the wizard asks for the DeepSeek key or Telegram token, you can:"
    Write-Plain "  - Just press Enter if it offers to use the env var, OR"
    Write-Plain "  - Paste the key manually (right-click in the wizard window)"
    Write-Host ""
    Write-Bold "  FALLBACK — if the wizard DOESN'T pick up the keys automatically:"
    Write-Plain "  DeepSeek key starts with: $($dsKey.Substring(0, [Math]::Min(8, $dsKey.Length)))..."
    Write-Plain "  Telegram token starts with: $($tgToken.Substring(0, [Math]::Min(10, $tgToken.Length)))..."
    Write-Plain "  Copy the full key from Bitwarden if you need to paste manually."
    Write-Host ""

    Wait-ForReturn "Press Enter when ready to start the OpenClaw wizard..."

    # Run onboarding with retry
    $obOk = Invoke-WithRetrySkipQuit -StepName "OpenClaw onboarding" -Action {
        try {
            $proc = Start-Process -FilePath "openclaw" `
                -ArgumentList "onboard", "--install-daemon" `
                -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0) {
                Write-Success "Onboarding complete."
                return $true
            } else {
                Write-Fail "Onboarding exited with code $($proc.ExitCode)."
                if ($proc.ExitCode -eq 401 -or $proc.ExitCode -eq 1) {
                    Write-Plain ""
                    Write-Plain "  This often means the API key wasn't accepted."
                    Write-Plain "  - Go back to platform.deepseek.com and verify the key"
                    Write-Plain "  - Make sure your account has credits"
                }
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

if (-not (Should-Skip 11)) {
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
        Write-Host ""
        $force = Read-Host "  Type 'continue anyway' to proceed (NOT recommended), or anything else to stop"
        if ($force -ne "continue anyway") {
            Write-Info "Stopping. Run Setup-MikeBot.bat again after fixing the gateway."
            exit 0
        }
    }

    Save-Progress 11
}


# =============================================================================
# STAGE 12: Dashboard Check
# =============================================================================

if (-not (Should-Skip 12)) {
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
            Write-Success "Dashboard is reachable (HTTP $code — wants auth, that's expected)."
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

            # Also save to setup log
            "## Dashboard Token`n`n``$token``" | Add-Content -Path $LogFile
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

if (-not (Should-Skip 13)) {
    Show-StageHeader 13 $Script:TotalStages "Approve Your Phone with the Bot"

    Write-Plain "OpenClaw doesn't let just anyone message your bot — you have to approve"
    Write-Plain "your own phone first. Here's how:"
    Write-Host ""
    Write-Bold "  STEP 1: Find your bot in Telegram (on your phone)"
    Write-Plain "    Search for the username you set in Stage 6 (e.g., mikes_assistant_bot)"
    Write-Plain "    Tap it to open the chat."
    Write-Host ""
    Write-Bold "  STEP 2: Send your bot any message"
    Write-Plain "    Just type 'hello' and send. The bot won't reply yet — that's expected."
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
    while (-not $pairOk) {
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
                        $retry = Read-Host "  Try a different code? (y/n)"
                        if ($retry -notmatch '^[Yy]') { break }
                    }
                }
            } catch {
                Write-Fail "Error: $($_.Exception.Message)"
                $retry = Read-Host "  Try again? (y/n)"
                if ($retry -notmatch '^[Yy]') { break }
            }
        } else {
            Write-Warn "That doesn't look like a valid code. Try again."
        }
    }

    Save-Progress 13
}


# =============================================================================
# STAGE 14: End-to-End Test
# =============================================================================

if (-not (Should-Skip 14)) {
    Show-StageHeader 14 $Script:TotalStages "End-to-End Test"

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

    $testOk = $false
    while (-not $testOk) {
        $reply = Read-Host "  Did the bot reply? (y = yes, n = no, s = skip and finish setup)"
        if ($reply -match '^[Yy]') {
            Write-Success "Your bot is alive and answering!"
            $testOk = $true
        } elseif ($reply -match '^[Ss]') {
            Write-Warn "Skipped. You can test later."
            break
        } else {
            Write-Host ""
            Write-Plain "  Troubleshooting:"
            Write-Plain "    1. Wait another 30 seconds — first reply can be slow"
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

Save-Progress 15

Show-StageHeader 15 $Script:TotalStages "All Done!"

Write-Host ""
Write-Host "  Congratulations Mike — your bot is set up." -ForegroundColor Green
Write-Host ""
Write-Plain "What you have now:"
Write-Plain "  - OpenClaw running in the background as a service"
Write-Plain "  - DeepSeek powering the AI brain"
Write-Plain "  - Telegram bot accepting messages from your phone and laptop"
Write-Plain "  - Bitwarden storing all your sensitive keys"
Write-Host ""
Write-Bold "  IMPORTANT — CLEAN UP:"
Write-Plain "  This setup saved your API keys temporarily here:"
Write-Plain "      $EnvFile"
Write-Plain "  Once you've confirmed your bot works for a few days, DELETE that file."
Write-Plain "  OpenClaw has its own copy of the keys in its config — you don't need this one."
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

# Write a setup log Mike (or Shands) can reference later
$logContent = @"
# Mike's Bot Setup Log

**Setup completed:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Laptop:** $env:COMPUTERNAME
**User:** $env:USERNAME
**Windows:** $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName) build $([System.Environment]::OSVersion.Version.Build)

## Installed Components

- Node.js: $(if (Test-CommandExists 'node') { & node --version } else { 'not detected' })
- npm: $(if (Test-CommandExists 'npm') { & npm --version } else { 'not detected' })
- Git: $(if (Test-CommandExists 'git') { (& git --version).Split(' ')[2] } else { 'not detected' })
- OpenClaw: $(if (Test-CommandExists 'openclaw') { & openclaw --version 2>$null } else { 'not detected' })

## Configuration

- Model provider: DeepSeek
- Default model: deepseek-v4-flash (or whatever onboarding selected)
- Channel: Telegram
- Gateway: http://127.0.0.1:18789/

## Files To Know About

- Setup progress (safe to delete): ``$ProgressFile``
- Temporary secrets file (DELETE after a few days): ``$EnvFile``
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

if (-not (Test-Path $ProgressDir)) { New-Item -ItemType Directory -Path $ProgressDir -Force | Out-Null }
$logContent | Set-Content -Path $LogFile -Encoding UTF8
Write-Plain "Setup log saved to: $LogFile"
Write-Host ""
Write-Plain "You can close this window now. Your bot will keep running in the background."
Write-Host ""
Wait-ForReturn "Press Enter to close..."
