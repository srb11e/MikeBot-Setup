# =============================================================================
# Setup-RemoteHelp.ps1 — Tailscale + OpenSSH one-shot installer for Mike
# =============================================================================
#
# WHAT THIS DOES:
#   1. Installs Tailscale and connects it to Shands's tailnet
#   2. Installs OpenSSH Server so Shands can connect to Mike's computer
#   3. Shows Mike the Tailscale IP to text Shands
#
# SHANDS: Replace the placeholder below with a real Tailscale auth key before
# giving this to Mike. Generate it at: https://login.tailscale.com/admin/authkeys
#
#   - Description: MikeBot-RemoteHelp
#   - Reusable: No (one-time use)
#   - Ephemeral: No
#   - Tags: tag:mikebot (or leave blank)
#
# MIKE: Just double-click Setup-RemoteHelp.bat. That's it.
# =============================================================================

$ErrorActionPreference = "Stop"

# =============================================================================
# SHANDS: PUT THE REAL AUTH KEY HERE (between the quotes)
# =============================================================================
$TailscaleAuthKey = "tskey-auth-REPLACE-ME-WITH-REAL-KEY"

# =============================================================================
# COLOR HELPERS
# =============================================================================
function Write-Info    { param([string]$m) Write-Host "  -> $m" -ForegroundColor Cyan }
function Write-Success { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn    { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Fail    { param([string]$m) Write-Host "  [X] $m" -ForegroundColor Red }
function Write-Bold    { param([string]$m) Write-Host $m -ForegroundColor White }

# =============================================================================
# STEP 0: Check internet
# =============================================================================
Write-Host ""
Write-Bold "================================================================"
Write-Bold "  Remote Help Setup — Tailscale + SSH"
Write-Bold "================================================================"
Write-Host ""
Write-Info "Checking internet connection..."

try {
    $test = Invoke-WebRequest -Uri "https://www.google.com" -TimeoutSec 10 -UseBasicParsing
    Write-Success "Internet is working."
} catch {
    Write-Fail "No internet connection. Connect to WiFi and run this again."
    Write-Host ""
    Write-Host "  Press Enter to exit..."
    Read-Host
    exit 1
}

# =============================================================================
# STEP 1: Install Tailscale
# =============================================================================
Write-Host ""
Write-Bold "Step 1 of 4: Install Tailscale"
Write-Host ""

$tsInstalled = Get-Command tailscale -ErrorAction SilentlyContinue

if ($tsInstalled) {
    Write-Success "Tailscale is already installed."
    $tsVer = & tailscale version | Select-Object -First 1
    Write-Info "Version: $tsVer"
} else {
    Write-Info "Installing Tailscale via winget..."
    try {
        winget install --id Tailscale.Tailscale --accept-source-agreements --accept-package-agreements --silent
        Write-Success "Tailscale installed."
    } catch {
        Write-Warn "winget install failed. Trying direct download..."
        $tsUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
        $tsInstaller = "$env:TEMP\tailscale-installer.exe"
        
        try {
            Invoke-WebRequest -Uri $tsUrl -OutFile $tsInstaller -UseBasicParsing
            Start-Process -FilePath $tsInstaller -ArgumentList "/quiet" -Wait
            Write-Success "Tailscale installed from direct download."
            Remove-Item $tsInstaller -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Fail "Could not install Tailscale. Text Shands a screenshot of this window."
            Read-Host
            exit 1
        }
    }

    # Refresh PATH so tailscale.exe is findable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + `
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # winget installs sometimes need a moment for the binary to land
    Write-Info "Waiting for Tailscale to finish installing..."
    $waited = 0
    while (-not (Get-Command tailscale -ErrorAction SilentlyContinue) -and $waited -lt 30) {
        Start-Sleep -Seconds 3
        $waited += 3
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + `
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    if (-not (Get-Command tailscale -ErrorAction SilentlyContinue)) {
        Write-Fail "Tailscale installed but tailscale.exe not found in PATH."
        Write-Info "Try restarting your laptop, then run this script again."
        Read-Host
        exit 1
    }
    Write-Success "Tailscale ready."
}

# =============================================================================
# STEP 2: Connect Tailscale
# =============================================================================
Write-Host ""
Write-Bold "Step 2 of 4: Connect to Shands's network"
Write-Host ""

$tsStatus = & tailscale status 2>$null
$alreadyUp = ($tsStatus -match "Tailscale is stopped") -eq $false

if ($alreadyUp) {
    Write-Success "Tailscale is already running."
} else {
    if ($TailscaleAuthKey -match "REPLACE-ME") {
        Write-Fail "The Tailscale auth key hasn't been set up yet."
        Write-Host ""
        Write-Info "Shands needs to edit this script and replace the auth key placeholder."
        Write-Info "Once he sends you the updated file, replace the one in your setup folder"
        Write-Info "and double-click Setup-RemoteHelp.bat again."
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Info "Connecting Tailscale to Shands's network..."
    try {
        $result = & tailscale up --auth-key $TailscaleAuthKey --accept-routes 2>&1
        Write-Success "Tailscale connected."
    } catch {
        Write-Fail "Tailscale connection failed."
        Write-Info "Error: $result"
        Write-Info "Text Shands a screenshot of this window."
        Read-Host
        exit 1
    }
}

# Get the Tailscale IP
Write-Host ""
$tsIp = & tailscale ip -4 2>$null
if (-not $tsIp) {
    # Fallback: parse from status output
    $tsStatus = & tailscale status 2>$null
    if ($tsStatus -match '(\d+\.\d+\.\d+\.\d+)') {
        $tsIp = $matches[1]
    }
}

if ($tsIp) {
    Write-Success "Your Tailscale IP: $tsIp"
} else {
    Write-Warn "Could not detect Tailscale IP yet. It may appear after a moment."
    $tsIp = "(check Tailscale icon in system tray)"
}

# =============================================================================
# STEP 3: Install OpenSSH Server
# =============================================================================
Write-Host ""
Write-Bold "Step 3 of 4: Install OpenSSH Server"
Write-Host ""

$sshInstalled = Get-WindowsCapability -Online | Where-Object {
    $_.Name -like "OpenSSH.Server*" -and $_.State -eq "Installed"
}

if ($sshInstalled) {
    Write-Success "OpenSSH Server is already installed."
} else {
    Write-Info "Installing OpenSSH Server..."
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Success "OpenSSH Server installed."
    } catch {
        Write-Fail "Could not install OpenSSH Server."
        Write-Info "Error: $_"
        Write-Info "Text Shands a screenshot."
        Read-Host
        exit 1
    }
}

# Configure and start SSH
Write-Info "Starting SSH service..."
try {
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic
    Write-Success "SSH service is running and set to start automatically."
} catch {
    Write-Warn "SSH service config had an issue. It may already be running."
}

# Ensure SSH is allowed through firewall
Write-Info "Checking firewall..."
try {
    $fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $fwRule) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        Write-Success "Firewall rule added for SSH."
    } else {
        Write-Success "Firewall rule already exists for SSH."
    }
} catch {
    Write-Warn "Could not verify firewall rule. If Shands can't connect, this is why."
}

# =============================================================================
# STEP 4: Done — show Mike what to do
# =============================================================================
Write-Host ""
Write-Bold "================================================================"
Write-Bold "  ALL DONE — Text Shands this info:"
Write-Bold "================================================================"
Write-Host ""
Write-Host "  Tailscale IP:  " -NoNewline
Write-Host $tsIp -ForegroundColor Green
Write-Host ""
Write-Host "  Your Windows username:  " -NoNewline
Write-Host $env:USERNAME -ForegroundColor Green
Write-Host ""
Write-Bold "================================================================"
Write-Host ""
Write-Info "Shands will connect to your computer using:"
Write-Info "  ssh $env:USERNAME@$tsIp"
Write-Host ""
Write-Info "When Shands connects from his machine, he'll need your Windows"
Write-Info "password (the one you use to log into this laptop)."
Write-Info ""
Write-Info "Shands can only connect while this laptop is on and Tailscale"
Write-Info "is running (it starts automatically with Windows now)."
Write-Host ""
Write-Host "Press Enter to close this window."
Read-Host
