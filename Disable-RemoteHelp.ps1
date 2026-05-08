# =============================================================================
# Disable-RemoteHelp.ps1 — v1.1 Turn Off Remote Command-Line Support
# =============================================================================
#
# PURPOSE:
#   Reverses everything Enable-RemoteHelp.ps1 did. Stops SSH server,
#   removes firewall rule, removes Shands's SSH key, removes MikeBot
#   sshd_config block, and optionally disconnects Tailscale.
#
#   Uses the state file at %LOCALAPPDATA%\MikeBot-Setup\remote-help-state.json
#   to know exactly what was set up and what needs to be rolled back.
#
# HOW MIKE RUNS THIS:
#   Right-click this folder, choose "Open in Terminal", then run:
#       .\Disable-RemoteHelp.ps1
#
#   Or if execution policy blocks it:
#       powershell -ExecutionPolicy Bypass -File .\Disable-RemoteHelp.ps1
# =============================================================================

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# -----------------------------------------------------------------------------
# PATHS
# -----------------------------------------------------------------------------
$ProgressDir  = Join-Path $env:LOCALAPPDATA "MikeBot-Setup"
$LogFile      = Join-Path $ProgressDir   "remote-help.log"
$StateFile    = Join-Path $ProgressDir   "remote-help-state.json"
$SshdConfig   = "$env:ProgramData\ssh\sshd_config"

# -----------------------------------------------------------------------------
# OUTPUT HELPERS
# -----------------------------------------------------------------------------
function Write-Info    { param([string]$m) Write-Host "  -> $m" -ForegroundColor Cyan }
function Write-Success { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn    { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Fail    { param([string]$m) Write-Host "  [X] $m" -ForegroundColor Red }
function Write-Plain   { param([string]$m) Write-Host "  $m" }

# -----------------------------------------------------------------------------
# LOGGING
# -----------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    Add-Content $LogFile "[$ts] $Message" -Encoding UTF8
}

Write-Log "START: Disable-RemoteHelp.ps1"

# -----------------------------------------------------------------------------
# PHASE 1 — CHECK STATE
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  Remote Help — Turn OFF" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Host ""

if (-not (Test-Path $StateFile)) {
    Write-Info "No Remote Help state file found."
    Write-Plain "Remote Help does not appear to be enabled (or was enabled by an"
    Write-Plain "older version). If you want to clean up manually, check:"
    Write-Plain "  - Windows Settings > Apps > Optional Features > OpenSSH Server"
    Write-Plain "  - Tailscale system tray icon > Disconnect"
    Write-Log "STATE: no state file found, nothing to do"
    exit 0
}

try {
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
} catch {
    Write-Fail "Could not read state file. It may be corrupted."
    Write-Log "FAIL: could not parse state file"
    exit 1
}

if (-not $state.enabled) {
    Write-Success "Remote Help is not currently enabled (state file says enabled=false)."
    if ($state.failureReason) {
        Write-Plain "  Reason: $($state.failureReason)"
    }
    Write-Plain "  Nothing to disable."
    exit 0
}

Write-Info "Remote Help was enabled at: $($state.timestamp)"
if ($state.tailscaleHostname) {
    Write-Info "Tailscale hostname: $($state.tailscaleHostname)"
}

# -----------------------------------------------------------------------------
# PHASE 2 — EXPLAIN + CONSENT
# -----------------------------------------------------------------------------
Write-Host ""
Write-Plain "This will prevent Shands from connecting to your laptop remotely."
Write-Plain "It does NOT uninstall OpenClaw or affect your bot."
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Yellow
Write-Host "   To turn Remote Help OFF, type: DISABLE REMOTE HELP" -ForegroundColor Yellow
Write-Host "  ================================================================" -ForegroundColor Yellow
Write-Host ""
$consent = Read-Host "  Type here"
if ($consent -ne "DISABLE REMOTE HELP") {
    Write-Plain "Cancelled. Remote Help is still enabled."
    Write-Log "CONSENT: denied"
    exit 0
}
Write-Success "Consent given."
Write-Log "CONSENT: user typed DISABLE REMOTE HELP"

$madeChanges = $false

# -----------------------------------------------------------------------------
# PHASE 3 — STOP SSHD (only if WE started it)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- SSH Server ---" -ForegroundColor White

if ($state.sshServiceWasAlreadyRunning -eq $false) {
    try {
        Stop-Service sshd -ErrorAction Stop
        Set-Service sshd -StartupType Disabled
        Write-Success "Stopped and disabled SSH server."
        Write-Log "SSHD: stopped and disabled (was not running before Remote Help)"
        $madeChanges = $true
    } catch {
        Write-Warn "Could not stop sshd service. It may have already been stopped."
        Write-Log "SSHD: stop attempt failed (may be already stopped): $($_.Exception.Message)"
    }
} else {
    Write-Plain "SSH server was already running before Remote Help."
    Write-Plain "  Leaving it running (Remote Help did not start it)."
    Write-Log "SSHD: left running (was already running before Remote Help)"
}

# -----------------------------------------------------------------------------
# PHASE 4 — REMOVE MIKEBOT FIREWALL RULE
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Windows Firewall ---" -ForegroundColor White

if ($state.createdMikeBotFirewallRule -eq $true) {
    Remove-NetFirewallRule -DisplayName "MikeBot-RemoteHelp-SSH-Tailscale-Only" -ErrorAction SilentlyContinue
    Write-Success "Removed MikeBot Tailscale-only firewall rule."
    Write-Log "FIREWALL: removed MikeBot-RemoteHelp-SSH-Tailscale-Only"
    $state.createdMikeBotFirewallRule = $false
    $madeChanges = $true
} else {
    Write-Info "No MikeBot firewall rule found in state. Skipping."
}

# -----------------------------------------------------------------------------
# PHASE 5 — DO NOT RESTORE BROAD MICROSOFT RULE
# -----------------------------------------------------------------------------
if ($state.disabledBroadOpenSshRule -eq $true) {
    Write-Host ""
    Write-Plain "  NOTE: The Windows default OpenSSH firewall rule"
    Write-Plain "  (OpenSSH-Server-In-TCP) was disabled when Remote Help"
    Write-Plain "  was enabled for your safety. It has NOT been re-enabled."
    Write-Host ""
    Write-Plain "  This rule allows SSH from ANY IP address — a security"
    Write-Plain "  risk if you don't intentionally use it."
    Write-Host ""
    Write-Plain "  If you need it, re-enable manually:"
    Write-Plain "    Enable-NetFirewallRule -DisplayName 'OpenSSH-Server-In-TCP'"
    Write-Host ""
    Write-Plain "  If you're not sure, leave it disabled."
    Write-Log "FIREWALL: broad OpenSSH rule remains disabled (intentional, not re-enabled)"
    $state.disabledBroadOpenSshRule = $false
}

# -----------------------------------------------------------------------------
# PHASE 6 — REMOVE MIKEBOT SSHD_CONFIG BLOCK
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- SSH Configuration ---" -ForegroundColor White

if ($state.modifiedSshdConfig -eq $true) {
    if (Test-Path $SshdConfig) {
        $content = Get-Content $SshdConfig -Raw
        $cleaned = $content -replace "(?ms)\r?\n?# BEGIN MIKEBOT REMOTE HELP.*?# END MIKEBOT REMOTE HELP\r?\n?", ""
        $cleaned | Set-Content $SshdConfig -Encoding ASCII -NoNewline
        Write-Success "Removed MikeBot settings from sshd_config."
        Write-Log "SSHD_CONFIG: MikeBot block removed"
        $madeChanges = $true
    } else {
        Write-Warn "sshd_config not found. MikeBot block may have already been removed."
    }
    $state.modifiedSshdConfig = $false
} else {
    Write-Info "sshd_config was not modified by Remote Help. Skipping."
}

# -----------------------------------------------------------------------------
# PHASE 7 — REMOVE SHANDS'S SSH KEY
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- SSH Key ---" -ForegroundColor White

if ($state.addedAuthorizedKey -eq $true) {
    $authPath = $state.authorizedKeysPath
    if ($authPath -and (Test-Path $authPath)) {
        $existing = Get-Content $authPath | Where-Object { $_ -notmatch 'shands-remote-help-mikebot' }
        if ($existing.Count -eq 0) {
            Remove-Item $authPath -Force
            Write-Success "Removed Shands's SSH key (file is now empty, deleted)."
            Write-Log "AUTH_KEYS: file deleted (no keys remaining)"
        } else {
            $existing -join "`r`n" | Set-Content $authPath -Encoding ASCII
            Write-Success "Removed Shands's SSH key from $authPath."
            Write-Log "AUTH_KEYS: Shands's key removed, other keys preserved"
        }
        $madeChanges = $true
    } else {
        Write-Info "Authorized keys file not found. Key may have already been removed."
    }
    $state.addedAuthorizedKey = $false
} else {
    Write-Info "No SSH key was added by Remote Help. Skipping."
}

# -----------------------------------------------------------------------------
# PHASE 8 — TAILSCALE (ASK)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Tailscale ---" -ForegroundColor White

Write-Plain "Remote Help SSH access is now disabled."
Write-Plain ""
$tsChoice = Read-Host "Disconnect Tailscale too? This removes your laptop from Shands's private network entirely. (y/n)"
if ($tsChoice -match '^[Yy]') {
    & tailscale logout 2>$null
    Write-Success "Tailscale disconnected."
    Write-Plain "  The Tailscale icon should disappear from your system tray."
    Write-Plain "  To reconnect later, run Enable-RemoteHelp.ps1 again."
    Write-Log "TAILSCALE: logged out"
    $madeChanges = $true
} else {
    Write-Plain "  Tailscale is still connected."
    Write-Plain "  Shands cannot SSH in (sshd is off and firewall rule removed),"
    Write-Plain "  but your laptop remains on the private network."
    Write-Plain "  The Tailscale icon will stay in your system tray."
    Write-Log "TAILSCALE: left connected"
}

# -----------------------------------------------------------------------------
# PHASE 9 — CLEANUP OPENSSH SERVER INFO
# -----------------------------------------------------------------------------
if ($state.installedOpenSshServer -eq $true) {
    Write-Host ""
    Write-Plain "  NOTE: OpenSSH Server was installed by Remote Help."
    Write-Plain "  It has not been uninstalled (in case other programs use it)."
    Write-Plain "  To uninstall: Windows Settings > Apps > Optional Features >"
    Write-Plain "  OpenSSH Server > Uninstall"
    Write-Log "OPENSSH: installed by Remote Help, not uninstalled"
}

# -----------------------------------------------------------------------------
# PHASE 10 — WRITE FINAL STATE
# -----------------------------------------------------------------------------
$state.enabled = $false
$state.failureReason = ""
$state.timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')

# Clean up state fields that no longer apply
$state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Remote Help is OFF" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "Shands can no longer connect to your laptop remotely."
if ($madeChanges) {
    Write-Success "All Remote Help settings have been removed."
} else {
    Write-Info "No changes were needed (Remote Help was already partially disabled)."
}
Write-Host ""

Write-Log "COMPLETE: Remote Help disabled, state written"

Write-Plain "  Press Enter to close..."
Read-Host | Out-Null
