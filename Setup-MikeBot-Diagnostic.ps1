# =============================================================================
# Setup-MikeBot-Diagnostic.ps1
# =============================================================================
#
# PURPOSE:
#   Standalone diagnostic. Mike (or Shands) runs this when something seems
#   broken. It only READS -- it never installs, modifies, or fixes anything.
#   Output is suitable for pasting into a text message to Shands.
#
# HOW TO RUN:
#   Right-click in this folder, choose "Open in Terminal" (or open PowerShell
#   and cd here), then run:
#       .\Setup-MikeBot-Diagnostic.ps1
#
#   Or if execution policy blocks it:
#       powershell -ExecutionPolicy Bypass -File .\Setup-MikeBot-Diagnostic.ps1
# =============================================================================

$ErrorActionPreference = "Continue"  # don't bail on errors -- we want to keep checking

function Section { param([string]$t) Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function OK    { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Bad   { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red   }
function Note  { param([string]$m) Write-Host "  [info] $m" -ForegroundColor Yellow }
function Plain { param([string]$m) Write-Host "  $m" }

Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  Mike's Bot -- Diagnostic Report" -ForegroundColor White
Write-Host "  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White

# -----------------------------------------------------------------------------
Section "System"
# -----------------------------------------------------------------------------
Plain "Computer:    $env:COMPUTERNAME"
Plain "User:        $env:USERNAME"
$os = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
if ($os) {
    Plain "Windows:     $($os.ProductName) build $([System.Environment]::OSVersion.Version.Build) (version $($os.DisplayVersion))"
    if ([System.Environment]::OSVersion.Version.Build -lt 19041) {
        Bad "Windows build is below 19041 -- OpenClaw needs newer."
    } else {
        OK "Windows version is supported."
    }
}
Plain "PowerShell:  $($PSVersionTable.PSVersion)"

# -----------------------------------------------------------------------------
Section "Internet"
# -----------------------------------------------------------------------------
try {
    $r = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    OK "General internet works (microsoft.com $($r.StatusCode))."
} catch {
    Bad "Cannot reach microsoft.com: $($_.Exception.Message)"
}

try {
    $r = Invoke-WebRequest -Uri "https://api.deepseek.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    OK "DeepSeek API is reachable."
} catch {
    if ($_.Exception.Response.StatusCode.value__ -in 401, 403, 404) {
        OK "DeepSeek API responded (auth required, that's expected)."
    } else {
        Bad "Cannot reach DeepSeek API: $($_.Exception.Message)"
    }
}

try {
    $r = Invoke-WebRequest -Uri "https://api.telegram.org" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    OK "Telegram API is reachable."
} catch {
    if ($_.Exception.Response) {
        OK "Telegram API responded (got an HTTP code, network is fine)."
    } else {
        Bad "Cannot reach Telegram API: $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
Section "Installed Tools"
# -----------------------------------------------------------------------------
function ToolCheck {
    param([string]$Cmd, [string]$VersionArg = "--version")
    $found = Get-Command $Cmd -ErrorAction SilentlyContinue
    if ($found) {
        try {
            $v = & $Cmd $VersionArg 2>&1 | Select-Object -First 1
            OK "$Cmd : $v"
        } catch {
            OK "$Cmd : found at $($found.Source) (version unreadable)"
        }
    } else {
        Bad "$Cmd : not found in PATH"
    }
}

ToolCheck "node"
ToolCheck "npm"
ToolCheck "git"
ToolCheck "winget"
ToolCheck "openclaw"

# -----------------------------------------------------------------------------
Section "OpenClaw Health"
# -----------------------------------------------------------------------------
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    try {
        $status = & openclaw gateway status 2>&1
        if ($LASTEXITCODE -eq 0) {
            OK "Gateway status: $status"
        } else {
            Bad "Gateway not healthy. Output: $status"
        }
    } catch {
        Bad "Couldn't run 'openclaw gateway status': $($_.Exception.Message)"
    }

    try {
        $deep = & openclaw status --deep 2>&1
        Note "Deep status:"
        $deep | Select-Object -First 15 | ForEach-Object { Plain "    $_" }
    } catch { $null }

    try {
        $doctor = & openclaw doctor 2>&1
        if ($LASTEXITCODE -eq 0) {
            OK "openclaw doctor passed."
        } else {
            Note "openclaw doctor reported issues:"
            $doctor | Select-Object -First 10 | ForEach-Object { Plain "    $_" }
        }
    } catch {
        Note "Couldn't run openclaw doctor: $($_.Exception.Message)"
    }

    # Config peek (don't print sensitive values)
    try {
        $hasToken = & openclaw config get gateway.auth.token 2>$null
        if ($hasToken -and $hasToken -ne "null") {
            OK "Gateway auth token is set."
        } else {
            Bad "Gateway auth token missing."
        }
    } catch { $null }

    # Telegram bot token check (won't print the value)
    try {
        $tgToken = & openclaw config get plugins.channels.telegram.botToken 2>$null
        if ($tgToken -and $tgToken -ne "null" -and $tgToken.Length -gt 10) {
            OK "Telegram bot token is set."
        } else {
            Bad "Telegram bot token missing -- bot cannot receive messages."
        }
    } catch {
        Note "Couldn't check Telegram bot token: $($_.Exception.Message)"
    }
} else {
    Bad "openclaw command not available -- skipping OpenClaw checks."
}

# -----------------------------------------------------------------------------
Section "Gateway Port (18789)"
# -----------------------------------------------------------------------------
# Raw .NET socket test instead of Test-NetConnection -- faster and avoids
# spurious warnings on locked-down machines.
try {
    $client = New-Object System.Net.Sockets.TcpClient
    $connect = $client.BeginConnect("127.0.0.1", 18789, $null, $null)
    if ($connect.AsyncWaitHandle.WaitOne(3000)) {
        $client.EndConnect($connect)
        $client.Close()
        OK "Port 18789 is listening on localhost."
    } else {
        $client.Close()
        Bad "Port 18789 is NOT listening -- gateway probably isn't running."
    }
} catch {
    Note "Couldn't test port 18789: $($_.Exception.Message)"
}

try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:18789/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    OK "Dashboard responded with HTTP $($r.StatusCode)."
} catch {
    if ($_.Exception.Response) {
        $code = [int]$_.Exception.Response.StatusCode
        if ($code -in 401, 403) {
            OK "Dashboard responded with HTTP $code (auth required, expected)."
        } else {
            Note "Dashboard responded with HTTP $code."
        }
    } else {
        Bad "Dashboard didn't respond at all."
    }
}

# -----------------------------------------------------------------------------
Section "Setup Files"
# -----------------------------------------------------------------------------
$progressDir = Join-Path $env:LOCALAPPDATA "MikeBot-Setup"
if (Test-Path $progressDir) {
    OK "Setup folder exists: $progressDir"
    Get-ChildItem $progressDir -Force | ForEach-Object {
        $size = if ($_.Length -lt 1024) { "$($_.Length) B" } else { "$([math]::Round($_.Length/1024,1)) KB" }
        Plain "    $($_.Name) ($size)"
    }
} else {
    Note "No setup folder found (this is fine if setup never ran)."
}

$ocConfig = Join-Path $env:USERPROFILE ".openclaw"
if (Test-Path $ocConfig) {
    OK "OpenClaw config folder exists: $ocConfig"
} else {
    Bad "OpenClaw config folder missing -- onboarding may not have completed."
}

# -----------------------------------------------------------------------------
Section "Suggested Next Steps"
# -----------------------------------------------------------------------------
Plain "1. If anything above is red, screenshot this whole window and send to Shands."
Plain "2. To see live logs from the bot:        openclaw logs --follow"
Plain "3. To restart the bot:                   openclaw gateway restart"
Plain "4. To re-run setup from where it stopped: double-click Setup-MikeBot.bat"
Write-Host ""

Read-Host "Press Enter to close" | Out-Null
