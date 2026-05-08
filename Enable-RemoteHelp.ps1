# =============================================================================
# Enable-RemoteHelp.ps1 — v1.1 Optional Remote Command-Line Support
# =============================================================================
#
# PURPOSE:
#   Lets Shands securely connect to Mike's Windows laptop command line
#   for troubleshooting. Uses Tailscale (private network) + Windows OpenSSH
#   Server (shell) + SSH public key auth + firewall restricted to Tailscale
#   IPv4 (100.64.0.0/10).
#
#   Mike must explicitly type ENABLE REMOTE HELP to proceed.
#   Remote Help is OFF by default. Mike controls when it's on.
#
# HOW MIKE RUNS THIS:
#   Only when Shands asks. Right-click this folder, choose
#   "Open in Terminal", then run:
#       .\Enable-RemoteHelp.ps1
#
#   Or if execution policy blocks it:
#       powershell -ExecutionPolicy Bypass -File .\Enable-RemoteHelp.ps1
#
# WHAT THIS DOES NOT DO:
#   - Does NOT let Shands see your screen (use Quick Assist for that)
#   - Does NOT install anything silently
#   - Does NOT change your normal MikeBot setup
#
# The SSH public key below belongs to Shands's machine (SRBComputer).
# This public key is safe to commit — only the private key is secret.
# =============================================================================

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# -----------------------------------------------------------------------------
# CONFIGURATION — Shands: set your SSH public key here
# -----------------------------------------------------------------------------
# Generate with: ssh-keygen -t ed25519 -C "shands-remote-help-mikebot"
# The PUBLIC key (.pub file) goes here. NEVER put the private key here.
$ShandsPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHABc14IazYzt1XV9JVzL+n5x1fOOKFxJuo8nzeak6XF shands-remote-help-mikebot"

# -----------------------------------------------------------------------------
# VERIFY PUBLIC KEY IS SET
# -----------------------------------------------------------------------------
if ($ShandsPublicKey -match 'REPLACE_WITH') {
    Write-Host ""
    Write-Host "  [X] Shands's SSH public key has not been configured." -ForegroundColor Red
    Write-Host "      Open this script and replace REPLACE_WITH_SHANDS_PUBLIC_KEY" -ForegroundColor Red
    Write-Host "      with Shands's actual ed25519 public key." -ForegroundColor Red
    Write-Host ""
    exit 1
}

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
# LOGGING — custom log only, no PowerShell transcript
# -----------------------------------------------------------------------------
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    Add-Content $LogFile "[$ts] $Message" -Encoding UTF8
}

if (-not (Test-Path $ProgressDir)) {
    New-Item -ItemType Directory -Path $ProgressDir -Force | Out-Null
}

Write-Log "START: Enable-RemoteHelp.ps1"

# -----------------------------------------------------------------------------
# PHASE 1 — PREFLIGHT
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  Remote Help Setup — Let Shands connect to your command line" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Host ""

# 1a. Administrator check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail "This script must run as Administrator."
    Write-Plain "Right-click Enable-RemoteHelp.ps1 → Run with PowerShell (as admin)."
    Write-Log "FAIL: not running as Administrator"
    exit 1
}
Write-Success "Running as Administrator."
Write-Log "PREFLIGHT: Administrator OK"

# 1b. Resolvable user profile
if (-not $env:USERPROFILE) {
    Write-Fail "Cannot determine your user profile path."
    Write-Log "FAIL: USERPROFILE not set"
    exit 1
}
Write-Success "User profile: $env:USERPROFILE"
Write-Log "PREFLIGHT: USERPROFILE=$env:USERPROFILE"

# 1c. Windows Firewall service
$fwService = Get-Service -Name MpsSvc -ErrorAction SilentlyContinue
if (-not $fwService -or $fwService.Status -ne 'Running') {
    Write-Fail "Windows Firewall service is not running."
    Write-Plain "Remote Help requires the firewall for security."
    Write-Log "FAIL: Windows Firewall not running"
    exit 1
}
Write-Success "Windows Firewall is running."
Write-Log "PREFLIGHT: Firewall OK"

# 1d. Check for existing Remote Help state
$existingState = $null
if (Test-Path $StateFile) {
    try {
        $existingState = Get-Content $StateFile -Raw | ConvertFrom-Json
        if ($existingState.enabled) {
            Write-Plain ""
            Write-Warn "Remote Help appears to already be enabled."
            Write-Plain "  Enabled at: $($existingState.timestamp)"
            Write-Plain "  Tailscale hostname: $($existingState.tailscaleHostname)"
            Write-Plain ""
            Write-Plain "  Running again will refresh the setup (idempotent)."
            Write-Plain "  Any old MikeBot settings will be replaced with fresh ones."
        }
    } catch {
        Write-Warn "Could not read existing state file. It will be replaced."
    }
}

# -----------------------------------------------------------------------------
# PHASE 2 — EXPLAIN
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "  WHAT REMOTE HELP DOES:" -ForegroundColor White
Write-Host ""
Write-Plain "  This lets Shands connect to your laptop's command line over a"
Write-Plain "  secure, encrypted private network (Tailscale). He can run"
Write-Plain "  diagnostics, check logs, and fix configuration."
Write-Host ""
Write-Plain "  It does NOT let Shands:"
Write-Plain "    - See your screen (use Quick Assist: Ctrl+Windows+Q)"
Write-Plain "    - Connect without you knowing"
Write-Plain "    - Connect when Tailscale is disconnected"
Write-Plain "    - Browse your files without you seeing the commands"
Write-Host ""
Write-Plain "  A Tailscale icon will appear in your system tray."
Write-Plain "  You can disconnect any time by running:"
Write-Plain "    .\Disable-RemoteHelp.ps1"

# -----------------------------------------------------------------------------
# PHASE 3 — CONSENT
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Yellow
Write-Host "   To enable Remote Help, type: ENABLE REMOTE HELP" -ForegroundColor Yellow
Write-Host "  ================================================================" -ForegroundColor Yellow
Write-Host ""
$consent = Read-Host "  Type here"
if ($consent -ne "ENABLE REMOTE HELP") {
    Write-Plain "  Cancelled. Remote Help is NOT enabled."
    Write-Log "CONSENT: denied (user typed something else or pressed Ctrl+C)"
    # Write failure state so disable script sees a clean state
    $state = @{
        enabled = $false
        failureReason = "consentDenied"
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
    }
    $state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8
    exit 0
}
Write-Success "Consent given."
Write-Log "CONSENT: user typed ENABLE REMOTE HELP"

# -----------------------------------------------------------------------------
# PHASE 4 — TAILSCALE
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Tailscale ---" -ForegroundColor White

# 4a. Check if Tailscale is already installed
$tailscaleExe = Get-Command tailscale.exe -ErrorAction SilentlyContinue
$tailscaleWasAlreadyConnected = $false

if ($tailscaleExe) {
    Write-Success "Tailscale is installed."
    # Check if already connected
    try {
        $tsStatus = & tailscale status --json 2>$null | ConvertFrom-Json
        if ($tsStatus.Self.Online) {
            Write-Warn "Tailscale is already connected as: $($tsStatus.Self.HostName)"
            Write-Warn "It may be connected to a different Tailscale network."
            Write-Plain ""
            Write-Plain "  Remote Help requires Tailscale to be connected to Shands's"
            Write-Plain "  tailnet with the tag: mikebot-support"
            Write-Plain ""
            $alreadyChoice = Read-Host "  Continue anyway? Shands can verify the tailnet. (y/n)"
            if ($alreadyChoice -notmatch '^[Yy]') {
                Write-Plain "  Stopping. Disconnect Tailscale from your system tray first,"
                Write-Plain "  then run this script again."
                Write-Log "TAILSCALE: already connected, user chose to stop"
                exit 0
            }
            Write-Info "Proceeding. Shands should verify your Tailscale node is on the right tailnet."
            $tailscaleWasAlreadyConnected = $true
        }
    } catch { $null }
} else {
    Write-Info "Tailscale not found. Installing..."
    try {
        $wingetProc = Start-Process -FilePath "winget" -ArgumentList @("install", "tailscale.tailscale", "--exact", "--silent", "--accept-source-agreements", "--accept-package-agreements") -PassThru -NoNewWindow
        $wingetTimeout = 600
        $wingetExited = $wingetProc.WaitForExit($wingetTimeout * 1000)
        if (-not $wingetExited) {
            $wingetProc.Kill()
            throw "winget timed out after $wingetTimeout seconds"
        }
        if ($wingetProc.ExitCode -eq 0) {
            Write-Success "Tailscale installed via winget."
        } else {
            throw "winget failed with exit code $($wingetProc.ExitCode)"
        }
    } catch {
        Write-Warn "Could not install Tailscale via winget ($($_.Exception.Message))."
        Write-Plain "Opening https://tailscale.com/download/windows in your browser."
        Write-Plain "Download and install Tailscale, then press Enter."
        Start-Process "https://tailscale.com/download/windows"
        Read-Host "Press Enter when Tailscale is installed"
    }

    # Refresh PATH
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"

    $tailscaleExe = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if (-not $tailscaleExe) {
        Write-Fail "Tailscale still not available after install attempt."
        Write-Plain "Remote Help requires Tailscale. Please install it manually."
        Write-Log "FAIL: Tailscale not available after install"
        exit 1
    }
    Write-Success "Tailscale installed."
}

Write-Log "TAILSCALE: installed, wasAlreadyConnected=$tailscaleWasAlreadyConnected"

# 4b. Connect to tailnet (if not already connected)
$tailscaleJoinedByRemoteHelp = $false
if (-not $tailscaleWasAlreadyConnected) {
    Write-Host ""
    Write-Plain "Shands will give you a one-time Tailscale auth key."
    Write-Plain "This key connects your laptop to Shands's private network."
    Write-Plain "It works ONCE and expires immediately after use."

    $secureKey = Read-Host "Paste the one-time Tailscale auth key from Shands" -AsSecureString

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

        if ($plainKey -notmatch '^tskey-client-') {
            Write-Fail "That doesn't look like a Tailscale auth key (should start with tskey-client-)."
            Write-Log "FAIL: auth key format invalid"
            # Write failure state
            $state = @{
                enabled = $false
                failureReason = "invalidAuthKey"
                timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
            }
            $state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8
            exit 1
        }

        $env:TS_AUTH_KEY = $plainKey
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    # Generate hostname
    $hostname = "mike-laptop-$(Get-Date -Format 'yyyyMMdd')"

    # Connect — capture output for error reporting
    try {
        $tsOutput = & tailscale up --auth-key=$env:TS_AUTH_KEY --hostname $hostname 2>&1
        $tsResult = $LASTEXITCODE
    } catch {
        $tsOutput = $_.Exception.Message
        $tsResult = 1
    }

    # Clear auth key from environment IMMEDIATELY, before logging anything
    Remove-Item Env:\TS_AUTH_KEY -ErrorAction SilentlyContinue
    Remove-Variable plainKey -ErrorAction SilentlyContinue

    if ($tsResult -ne 0) {
        Write-Fail "Tailscale connection failed."
        Write-Fail "The key may have already been used or expired."
        Write-Plain "Ask Shands to generate a new one-time key."
        Write-Log "TAILSCALE: up failed with exit code $tsResult"
        Write-Log "TAILSCALE: output (sanitized): $($tsOutput -replace 'tskey-[^\s]+', '[KEY REDACTED]')"

        # Disconnect if we partially joined
        & tailscale logout 2>$null
        exit 1
    }

    Write-Success "Tailscale connected as: $hostname"
    Write-Log "TAILSCALE: connected as $hostname"
    $tailscaleJoinedByRemoteHelp = $true
} else {
    Write-Info "Tailscale already connected. Skipping auth key step."
    $hostname = $tsStatus.Self.HostName
}

# 4c. Extract Tailscale IPv4 address
$tsIPv4 = $null
try {
    $tsStatus = & tailscale status --json 2>$null | ConvertFrom-Json
    $tsIPv4 = ($tsStatus.Self.TailscaleIPs | Where-Object { $_ -match '^100\.' } | Select-Object -First 1)
} catch { $null }

if ($tsIPv4) {
    Write-Success "Tailscale IPv4 address: $tsIPv4"
} else {
    Write-Warn "Could not determine Tailscale IPv4 address."
    Write-Plain "Shands can find it from the Tailscale admin console."
}
Write-Log "TAILSCALE: IPv4=$tsIPv4"

# -----------------------------------------------------------------------------
# PHASE 5 — WINDOWS OPENSSH SERVER
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Windows OpenSSH Server ---" -ForegroundColor White

$installedByUs = $false
$sshWasAlreadyRunning = $false

# 5a. Check if OpenSSH Server is installed
$sshCap = Get-WindowsCapability -Online | Where-Object {
    $_.Name -like 'OpenSSH.Server*'
}

if ($sshCap -and $sshCap.State -eq 'Installed') {
    Write-Success "OpenSSH Server is already installed."
    Write-Log "OPENSSH: already installed"
} else {
    Write-Info "Installing Windows OpenSSH Server..."
    try {
        $result = Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop
        if ($result.RestartNeeded) {
            Write-Warn "A restart may be required. If SSH doesn't work, restart your laptop."
        }
        Write-Success "OpenSSH Server installed."
        $installedByUs = $true
        Write-Log "OPENSSH: installed by this script"
    } catch {
        Write-Fail "Could not install OpenSSH Server."
        Write-Plain "This can happen on managed, offline, or policy-restricted machines."
        Write-Plain ""
        Write-Plain "Remote Help over command line is not available on this machine."
        Write-Plain "Use Quick Assist instead: Ctrl+Windows+Q, then Get help."
        Write-Log "FAIL: OpenSSH Server install failed: $($_.Exception.Message)"

        # Cleanup Tailscale if we joined it
        if ($tailscaleJoinedByRemoteHelp) {
            Write-Info "Disconnecting Tailscale (setup incomplete)."
            & tailscale logout 2>$null
        }

        $state = @{
            enabled = $false
            failureReason = "openSshInstallFailed"
            timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
        }
        $state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8
        exit 1
    }
}

# 5b. Record sshd service state (do NOT start yet — wait until config is safe)
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
$sshServiceStatusBefore = $null
$sshServiceStartupTypeBefore = $null
if ($sshService) {
    $sshServiceStatusBefore = $sshService.Status.ToString()
    $sshServiceStartupTypeBefore = $sshService.StartType.ToString()
    Write-Info "SSH server current state: $sshServiceStatusBefore (startup: $sshServiceStartupTypeBefore)"
    Write-Log "OPENSSH: sshd status=$sshServiceStatusBefore, startup=$sshServiceStartupTypeBefore"
    if ($sshService.Status -eq 'Running') {
        $sshWasAlreadyRunning = $true
    }
} else {
    Write-Fail "sshd service not found after install. Try restarting your laptop."
    Write-Log "FAIL: sshd service not found"
    exit 1
}

# -----------------------------------------------------------------------------
# PHASE 6 — SSHD_CONFIG
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- SSH Configuration ---" -ForegroundColor White

$modifiedSshdConfig = $false
$sshdConfigBackup = $null

if (Test-Path $SshdConfig) {
    $content = Get-Content $SshdConfig -Raw

    # Step 1: Remove any previous MikeBot block
    $content = $content -replace "(?ms)\r?\n?# BEGIN MIKEBOT REMOTE HELP.*?# END MIKEBOT REMOTE HELP\r?\n?", ""

    # Step 2: Scan for conflicts (on content WITHOUT the old MikeBot block)
    $conflicts = @()

    if ($content -match '(?m)^\s*PubkeyAuthentication\s+no\s*(#.*)?$') {
        $conflicts += "PubkeyAuthentication no"
    }
    if ($content -match '(?m)^\s*PasswordAuthentication\s+yes\s*(#.*)?$') {
        $conflicts += "PasswordAuthentication yes"
    }
    if ($content -match '(?m)^\s*ChallengeResponseAuthentication\s+yes\s*(#.*)?$') {
        $conflicts += "ChallengeResponseAuthentication yes"
    }
    if ($content -match '(?m)^\s*KbdInteractiveAuthentication\s+yes\s*(#.*)?$') {
        $conflicts += "KbdInteractiveAuthentication yes"
    }
    if ($content -match '(?m)^\s*AuthenticationMethods\s+.*password.*$') {
        $conflicts += "AuthenticationMethods includes password"
    }

    # Check for non-default Match blocks
    $matchCount = ([regex]::Matches($content, '(?m)^\s*Match\s+')).Count
    $defaultAdminMatch = ($content -match '(?m)^\s*Match\s+Group\s+administrators')
    $nonDefaultMatches = $matchCount - (if ($defaultAdminMatch) { 1 } else { 0 })
    if ($nonDefaultMatches -gt 0) {
        $conflicts += "Non-standard Match block(s) detected ($nonDefaultMatches beyond default administrators)"
    }

    # Step 3: If conflicts, stop
    if ($conflicts.Count -gt 0) {
        # Still create backup for Shands
        $backup = "$SshdConfig.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $SshdConfig $backup
        Write-Log "SSHD_CONFIG: backup saved to $backup (conflicts found, not modified)"

        Write-Fail "sshd_config has settings that conflict with key-only SSH:"
        foreach ($c in $conflicts) {
            Write-Plain "    - $c"
        }
        Write-Plain ""
        Write-Plain "  Remote Help requires key-based SSH with no password fallback."
        Write-Plain "  These settings would prevent that from working safely."
        Write-Plain ""
        Write-Plain "  A backup of your current sshd_config was saved to:"
        Write-Plain "    $backup"
        Write-Plain ""
        Write-Plain "  Ask Shands to review and resolve these conflicts manually."
        Write-Plain "  In the meantime, use Quick Assist: Ctrl+Windows+Q, Get help."

        # Clean up Tailscale if we joined it
        if ($tailscaleJoinedByRemoteHelp) {
            Write-Info "Disconnecting Tailscale (setup incomplete)."
            & tailscale logout 2>$null
        }

        $state = @{
            enabled = $false
            failureReason = "sshdConfigConflict"
            timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
            sshdConfigBackup = $backup
            sshdConflicts = $conflicts
        }
        $state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8
        Write-Log "FAIL: sshd_config conflicts - $($conflicts -join '; ')"
        exit 1
    }

    # Step 4: No conflicts — insert block near the top
    $backup = "$SshdConfig.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $SshdConfig $backup
    Write-Success "sshd_config backed up to:"
    Write-Plain "  $backup"
    Write-Log "SSHD_CONFIG: backup saved to $backup"

    # Find insertion point: after initial comment block
    $lines = $content -split "`r?`n"
    $insertAt = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -ne "" -and $trimmed -notmatch '^#') {
            $insertAt = $i
            break
        }
    }

    # Build MikeBot block
    $block = @"
# BEGIN MIKEBOT REMOTE HELP
# Inserted by Enable-RemoteHelp.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')
# These directives appear early in the file so they are the FIRST obtained value.
# Do not edit manually. Run Disable-RemoteHelp.ps1 to remove.
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
# END MIKEBOT REMOTE HELP

"@

    $blockLines = $block -split "`r?`n"

    # Safe split/rebuild (avoiding 0..-1 trap)
    $before = if ($insertAt -gt 0) { $lines[0..($insertAt - 1)] } else { @() }
    $after  = if ($insertAt -lt $lines.Count) { $lines[$insertAt..($lines.Count - 1)] } else { @() }
    $newLines = @($before) + @($blockLines) + @($after)

    $newContent = ($newLines -join "`r`n").TrimEnd() + "`r`n"
    try {
        $newContent | Set-Content $SshdConfig -Encoding ASCII -NoNewline -ErrorAction Stop
        Write-Success "MikeBot block inserted into sshd_config."
        Write-Log "SSHD_CONFIG: block inserted at line $insertAt"
        # Config will be picked up when sshd starts in the final phase
        Write-Success "sshd_config updated. SSHD will use new config when started."

        $modifiedSshdConfig = $true
        $sshdConfigBackup = $backup
    } catch {
        Write-Fail "Could not write sshd_config: $($_.Exception.Message)"
        Write-Log "SSHD_CONFIG: write failed: $($_.Exception.Message)"
        Write-Plain "  Your original config was backed up to: $backup"
        
        # Clean up Tailscale if we joined it
        if ($tailscaleJoinedByRemoteHelp) {
            & tailscale logout 2>$null
        }
        exit 1
    }
} else {
    Write-Fail "sshd_config not found at: $SshdConfig"
    Write-Plain "OpenSSH Server may not be installed correctly."
    Write-Log "FAIL: sshd_config not found"
    exit 1
}

# -----------------------------------------------------------------------------
# PHASE 7 — WINDOWS FIREWALL
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Windows Firewall ---" -ForegroundColor White

$disabledBroadOpenSshRule = $false

# 7a. Remove any previous MikeBot rule (idempotent)
Remove-NetFirewallRule -DisplayName "MikeBot-RemoteHelp-SSH-Tailscale-Only" -ErrorAction SilentlyContinue

# 7b. Check Microsoft's broad rule
$broadRule = Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if ($broadRule -and $broadRule.Enabled -eq 'True') {
    Write-Warn "Windows default OpenSSH firewall rule allows SSH from ANYWHERE."
    Write-Info "Disabling it for your safety..."
    try {
        Disable-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction Stop
        Write-Success "Broad OpenSSH rule disabled."
        Write-Log "FIREWALL: disabled OpenSSH-Server-In-TCP (broad rule)"
        $disabledBroadOpenSshRule = $true
    } catch {
        Write-Warn "Could not disable broad OpenSSH rule: $($_.Exception.Message)"
        Write-Log "FIREWALL: disable broad rule failed: $($_.Exception.Message)"
    }
} elseif ($broadRule -and $broadRule.Enabled -eq 'False') {
    Write-Info "Broad OpenSSH firewall rule is already disabled."
    Write-Log "FIREWALL: OpenSSH-Server-In-TCP was already disabled"
} else {
    Write-Info "No broad OpenSSH firewall rule found."
    Write-Log "FIREWALL: no broad OpenSSH rule detected"
}

# 7c. Create MikeBot-specific restricted rule
try {
    New-NetFirewallRule `
        -DisplayName "MikeBot-RemoteHelp-SSH-Tailscale-Only" `
        -Description "Allow inbound SSH from Tailscale IPv4 private network only. Created by Enable-RemoteHelp.ps1." `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -RemoteAddress "100.64.0.0/10" `
        -Action Allow `
        -Profile Private,Public `
        -ErrorAction Stop

    Write-Success "Windows Firewall rule created: SSH from Tailscale only (100.64.0.0/10)."
    Write-Log "FIREWALL: created MikeBot-RemoteHelp-SSH-Tailscale-Only (TCP 22 from 100.64.0.0/10)"
    $createdMikeBotFirewallRule = $true
} catch {
    Write-Fail "Could not create firewall rule: $($_.Exception.Message)"
    Write-Log "FIREWALL: New-NetFirewallRule failed: $($_.Exception.Message)"
    $createdMikeBotFirewallRule = $false
}

# -----------------------------------------------------------------------------
# PHASE 8 — AUTHORIZED KEYS
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- SSH Key Setup ---" -ForegroundColor White

# 8a. Determine key file
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal   = [System.Security.Principal.WindowsPrincipal]::new($currentUser)
$isAdminUser = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

$hasAdminMatch = ($content -match '(?m)^\s*Match\s+Group\s+administrators')

if ($isAdminUser -and $hasAdminMatch) {
    $authKeysPath = "$env:ProgramData\ssh\administrators_authorized_keys"
    $authKeyType = "administrators"
    Write-Info "Your account is an administrator. Key will go to:"
    Write-Plain "  $authKeysPath"
} else {
    $authKeysPath = "$env:USERPROFILE\.ssh\authorized_keys"
    $authKeyType = "user"
    if (-not $isAdminUser) {
        Write-Info "Your account is a standard user. Key will go to:"
    } else {
        Write-Info "Administrator Match block not active. Key will go to:"
    }
    Write-Plain "  $authKeysPath"
}

# 8b. Create parent directory if missing
$parentDir = Split-Path $authKeysPath -Parent
if (-not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

# 8c. Read existing keys, remove old MikeBot entry, add fresh
$existing = @()
if (Test-Path $authKeysPath) {
    $existing = Get-Content $authKeysPath | Where-Object { $_ -notmatch 'shands-remote-help-mikebot' }
}
$existing += $ShandsPublicKey
try {
    $existing -join "`r`n" | Set-Content $authKeysPath -Encoding ASCII -ErrorAction Stop
    Write-Success "Shands's SSH public key added."
} catch {
    Write-Fail "Could not write authorized_keys: $($_.Exception.Message)"
    Write-Log "AUTH_KEYS: write failed: $($_.Exception.Message)"
    # Clean up Tailscale if we joined it
    if ($tailscaleJoinedByRemoteHelp) { & tailscale logout 2>$null }
    exit 1
}

# 8d. ACL hardening
if ($authKeyType -eq "administrators") {
    icacls.exe $authKeysPath /inheritance:r /grant "NT AUTHORITY\SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not set ACL on administrators_authorized_keys."
        Write-Plain "  Verify manually if key auth does not work."
    } else {
        Write-Success "ACL set: SYSTEM + Administrators"
    }
} else {
    $userSid = $currentUser.User.Value
    icacls.exe $authKeysPath /inheritance:r /grant "NT AUTHORITY\SYSTEM:(F)" /grant "$userSid`:(M)" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not set ACL on authorized_keys. Ensure only you can read this file."
    } else {
        Write-Success "ACL set: SYSTEM + your account"
    }
}

Write-Log "AUTH_KEYS: key added to $authKeysPath ($authKeyType)"

$addedAuthorizedKey = $true

# -----------------------------------------------------------------------------
# PHASE 9 — START SSHD (only after all config is safe)
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Starting SSH Server ---" -ForegroundColor White

if ($sshService.Status -ne 'Running') {
    Write-Info "Starting SSH server..."
    try {
        Start-Service sshd -ErrorAction Stop
        Write-Success "SSH server started."
    } catch {
        Write-Fail "Could not start SSH server: $($_.Exception.Message)"
        Write-Log "SSHD: Start-Service failed: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Info "SSH server was already running. Restarting to pick up config changes."
    try {
        Restart-Service sshd -ErrorAction Stop
        Write-Success "SSH server restarted with new config."
    } catch {
        Write-Fail "Could not restart SSH server: $($_.Exception.Message)"
        Write-Log "SSHD: Restart-Service failed: $($_.Exception.Message)"
        exit 1
    }
}

try {
    Set-Service sshd -StartupType Automatic -ErrorAction Stop
    Write-Success "SSH server startup set to Automatic."
    Write-Log "OPENSSH: sshd started, StartupType set to Automatic"
} catch {
    Write-Warn "SSH server started but could not set startup type: $($_.Exception.Message)"
    Write-Log "SSHD: Set-Service failed: $($_.Exception.Message)"
}

# -----------------------------------------------------------------------------
# PHASE 10 — REPORT
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Remote Help is ENABLED" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "Shands can now connect to your laptop's command line."
Write-Host ""
Write-Plain "  Connection info (text this to Shands):"
Write-Host ""
Write-Host "    Hostname: $hostname" -ForegroundColor White
if ($tsIPv4) {
    Write-Host "    IP:       $tsIPv4" -ForegroundColor White
}
Write-Host "    User:     $env:USERNAME" -ForegroundColor White
Write-Host "    Key type: $authKeyType" -ForegroundColor White
Write-Host ""
Write-Plain "  To turn Remote Help OFF:"
Write-Plain "    Right-click this folder, open PowerShell, run:"
Write-Plain "      .\Disable-RemoteHelp.ps1"
Write-Host ""
Write-Plain "  Tailscale will show an icon in your system tray."
Write-Plain "  The connection is active while Tailscale is connected."
Write-Host ""

# -----------------------------------------------------------------------------
# PHASE 11 — WRITE STATE FILE
# -----------------------------------------------------------------------------
$state = @{
    enabled                       = $true
    failureReason                 = ""
    timestamp                     = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
    tailscaleHostname             = $hostname
    tailscaleIpv4                 = $tsIPv4
    tailscaleWasAlreadyConnected  = $tailscaleWasAlreadyConnected
    tailscaleJoinedByRemoteHelp   = $tailscaleJoinedByRemoteHelp
    createdMikeBotFirewallRule    = $createdMikeBotFirewallRule
    disabledBroadOpenSshRule      = $disabledBroadOpenSshRule
    modifiedSshdConfig            = $modifiedSshdConfig
    sshdConfigBackup              = $sshdConfigBackup
    sshdConflicts                 = @()
    addedAuthorizedKey            = $addedAuthorizedKey
    addedAuthorizedKeyTo          = $authKeyType
    authorizedKeysPath            = $authKeysPath
    installedOpenSshServer        = $installedByUs
    sshServiceWasAlreadyRunning   = $sshWasAlreadyRunning
    sshServiceStatusBefore        = $sshServiceStatusBefore
    sshServiceStartupTypeBefore   = $sshServiceStartupTypeBefore
}
$state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8
Write-Log "COMPLETE: Remote Help enabled, state written"

Write-Plain "  Press Enter to close..."
Read-Host | Out-Null
