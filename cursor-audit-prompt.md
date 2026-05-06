# MikeBot Setup — Read-Only Safety Audit

## What this is

You (Cursor) are auditing a set of Windows setup scripts to verify they are correct before deployment to a non-technical user (Mike). These scripts install OpenClaw with DeepSeek + Telegram on a fresh Windows laptop.

**You are auditing from a machine that ALREADY HAS a production OpenClaw instance running.** Your job is read-only analysis. You must never execute anything that could reconfigure, restart, or uninstall the existing gateway.

## Critical safety rules

The following commands are **FORBIDDEN** during this audit. Do not run them under any circumstances:

- `openclaw onboard` or `openclaw onboard --install-daemon`
- `openclaw gateway install` or `openclaw gateway restart`
- `npm install -g openclaw` or `npm uninstall -g openclaw`
- `Setup-MikeBot.bat` or `.\Setup-MikeBot.ps1` (do not execute the scripts)
- Any command that modifies `%USERPROFILE%\.openclaw\` or `%LOCALAPPDATA%\MikeBot-Setup\`
- Any command that modifies the system PATH, registry, or Windows services

Allowed: reading files, running `Get-Command`, `Get-Process`, `npm view`, `winget search`, static analysis tools, `powershell -Command` for syntax checks.

If you're unsure whether a command is safe, **don't run it — ask me first.**

## Audit scope

The four files under review are in this workspace:

- `Setup-MikeBot.bat` — double-clickable launcher
- `Setup-MikeBot.ps1` — 15-stage guided setup wizard (~1400 lines)
- `Setup-MikeBot-Diagnostic.ps1` — read-only diagnostic script
- `test-plan.md` — end-to-end test plan (reference for what "correct" means)

Also in this workspace: `phase0-findings.md`, `phase1-report.md`, `phase2-report.md`, `phase3-report.md` — these document the remediation history. Read them for context on what was already fixed, but don't re-audit the original findings.

## What to audit

Run these checks in order. For each, report findings — don't just say "looks fine." Show evidence.

### 1. Syntax validation

Run PowerShell's parser and linter on both .ps1 files:

```
# Parse check (catches syntax errors without executing)
$tokens = $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path ".\Setup-MikeBot.ps1"),
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host "ERROR: $_" } }
else { Write-Host "Setup-MikeBot.ps1: No parse errors." }
```

Run the same for `Setup-MikeBot-Diagnostic.ps1`. If any syntax errors exist, list them with line numbers.

Also run `Invoke-ScriptAnalyzer` if installed:

```
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    Invoke-ScriptAnalyzer -Path ".\Setup-MikeBot.ps1", ".\Setup-MikeBot-Diagnostic.ps1"
}
```

### 2. Write action audit

These scripts install software globally, write config, modify the registry (power settings), and register daemons. You must verify that nothing in them could interfere with the existing OpenClaw install on THIS machine.

Scan both .ps1 files for every write action and categorize it:

```
# Find write-capable commands
Select-String -Path ".\Setup-MikeBot.ps1", ".\Setup-MikeBot-Diagnostic.ps1" `
    -Pattern '\b(Start-Process|Invoke-WebRequest|Invoke-RestMethod|New-Item|Set-Content|'
    + 'Add-Content|Out-File|Remove-Item|Set-ItemProperty|Set-Acl|'
    + 'Save-Secret|Save-Progress|openclaw\s+(onboard|gateway\s+install|configure|pairing\s+approve)|'
    + 'npm\s+(install|uninstall)|winget\s+install)\b' `
    -AllMatches | ForEach-Object { $_.LineNumber, $_.Line }
```

For each write action found, answer: "Would this action break or reconfigure Neo if run on this machine right now?"

Pay special attention to:
- Stage 9: `npm install -g openclaw` (would upgrade/reinstall OpenClaw over the existing install)
- Stage 10: `openclaw onboard --install-daemon` (would reconfigure the gateway)
- Stage 13: `openclaw pairing approve` (would approve a pairing — harmless on its own, but note it)
- Stages 2-3: `powercfg` and `Set-ItemProperty` for power settings (system-wide, but not OpenClaw-specific)

### 3. Conflict check — what would break if both Neos coexisted

OpenClaw doesn't support two gateway instances on the same machine without separate config directories. The setup script uses the default config path (`%USERPROFILE%\.openclaw\`).

Check the existing gateway's port and config location:

```
# What port does the existing gateway use?
openclaw config get gateway.port 2>$null
# Where is the existing config?
echo $env:USERPROFILE\.openclaw\
```

Then check the script's assumptions:

```
# What port does the script expect? Search for 18789 in the script.
Select-String -Path ".\Setup-MikeBot.ps1" -Pattern "18789"
```

Report: does the script use the same port and config directory as the existing install? If so, running it here would overwrite the existing config.

### 4. Path safety — LOCALAPPDATA vs OneDrive

Verify the script's choice of paths:

```
# Search for path constants
Select-String -Path ".\Setup-MikeBot.ps1" -Pattern '\$ProgressDir|\$EnvFile|\$LogFile|\$TokenFile|LOCALAPPDATA|USERPROFILE' | Select-Object -First 20
```

Confirm:
- Setup state files go to LOCALAPPDATA (not USERPROFILE)
- The script never writes secrets to OneDrive-syncable locations
- The cleanup instructions in Stage 15 correctly identify which files to delete

### 5. Secret handling review

Read the `Save-Secret` and `Get-Secret` functions in `Setup-MikeBot.ps1` (search for those function names). Verify:

- API keys are read via `Read-Host -AsSecureString`
- The .env file is in LOCALAPPDATA (confirmed by path check above)
- No secrets are echoed to console in plaintext during the flow
- The cleanup message in Stage 15 tells Mike to delete the .env file

Check specifically: does any stage print the API key or token to the console? Search for patterns where the key/token variable is passed to `Write-*` commands:

```
Select-String -Path ".\Setup-MikeBot.ps1" -Pattern 'Write-.*\$key|Write-.*\$token|Write-Host.*\$key|Write-Host.*\$token' | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
```

### 6. Resume logic trace

The script saves progress to a `.progress` file after each stage. Trace the resume logic:

1. Find `Import-Progress` — this loads the last completed stage
2. Find `Test-StageAlreadyComplete` — this gates whether a stage runs or skips
3. Find all calls to `Save-Progress` — confirm one exists per stage, including inside the Stage 6 and 7 validation loops

```
Select-String -Path ".\Setup-MikeBot.ps1" -Pattern 'Save-Progress \d+' | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }
```

Verify: are there Save-Progress calls for stages 6 and 7 inside the while loops (not just at end-of-block)? The fix for this was applied in commit `d896562`.

### 7. DeepSeek model + endpoint verification

Check Stage 8's API test call:

```
Select-String -Path ".\Setup-MikeBot.ps1" -Pattern "deepseek|api\.deepseek\.com|chat/completions" -Context 1,1
```

Verify:
- Model name is `deepseek-v4-flash` (not the deprecated `deepseek-chat`)
- Endpoint includes `/v1/chat/completions`
- `thinking` is set to `disabled` (so the test call doesn't consume all tokens on reasoning)
- Comment explains why this model was chosen

### 8. Escape hatch verification

Check both validation loops (Stage 6 Telegram token, Stage 7 DeepSeek key):

```
# Find the escape hatch patterns
Select-String -Path ".\Setup-MikeBot.ps1" -Pattern "I keep rejecting|accept this|tgAttempts|dsAttempts" -Context 2,2
```

Verify:
- Both loops have an attempt counter
- After 3 failures, the "I keep rejecting" prompt appears
- The "accept anyway" option saves without further validation
- The "quit" option exits with progress saved

### 9. Diagnostic script completeness

Read `Setup-MikeBot-Diagnostic.ps1` fully. It's ~200 lines. Verify it checks:

- Windows version (build >= 19041)
- Internet connectivity (microsoft.com, DeepSeek API, Telegram API)
- Installed tools (node, npm, git, winget, openclaw)
- OpenClaw gateway health + config (auth token, Telegram bot token)
- Port 18789 listening (TcpClient, not Test-NetConnection)
- Dashboard reachability
- Setup files present in LOCALAPPDATA

Report any subsystem that isn't checked.

### 10. Failure mode coverage

Read `test-plan.md`. For each test step, identify: if this step fails on a real laptop, does the script give Mike a recovery path? Specifically:

- Step 3 (Defender quarantine): what does the script say? Can Mike recover?
- Step 4 (AV interference): is there any script-side handling?
- Step 5 (resume): does the resume prompt work if the .progress file is corrupted?
- Step 8 (end-to-end): if logs show zero matches, what does the script tell Mike?

Answer: which failures have recovery paths in the script, and which require Shands to intervene?

## Output format

Produce a single audit report saved to `audit-report.md` in this workspace. Structure:

```
# MikeBot Setup — Read-Only Audit Report

**Date:** [today]
**Machine:** [hostname]
**Auditor:** Cursor

## 1. Syntax Validation
[parse results, ScriptAnalyzer results, any errors]

## 2. Write Action Audit
[table of write actions with line numbers + "would break Neo?" assessment]

## 3. Conflict Check
[port, config path, conflict assessment]

## 4. Path Safety
[LOCALAPPDATA vs USERPROFILE usage, OneDrive risk]

## 5. Secret Handling
[SecureString usage, plaintext exposure, cleanup instructions]

## 6. Resume Logic
[Save-Progress placement, gap analysis]

## 7. DeepSeek Model + Endpoint
[model name, endpoint, thinking mode]

## 8. Escape Hatches
[validation loop behavior, "accept anyway" paths]

## 9. Diagnostic Completeness
[coverage of all subsystems]

## 10. Failure Mode Coverage
[recovery paths vs Shands-intervention-required]

## Summary
- Critical issues (would break Neo if run):
- Important issues (would confuse Mike):
- Minor issues (cosmetic/documentation):
- Verified safe (no issues found):
```

## Before you start

1. `pwd` — confirm you're in the folder containing all four test files + test-plan.md
2. Read `test-plan.md` for context on what each script does
3. Read `phase0-findings.md`, `phase1-report.md`, `phase2-report.md`, `phase3-report.md` for remediation history
4. Then run audits 1-10 in order
