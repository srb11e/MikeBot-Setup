# MikeBot Setup — End-to-End Test Run

## What this is

You (Cursor) are helping me run a 10-step test plan against a set of Windows setup scripts. These scripts walk a non-technical user (Mike) through installing OpenClaw on a brand-new Windows laptop, using DeepSeek as the AI model provider and Telegram as the messaging channel. The scripts were audited, remediated, and now need real-Windows verification before being handed to Mike.

The four files under test live in this workspace:

- `Setup-MikeBot.bat` — double-clickable launcher (handles admin elevation)
- `Setup-MikeBot.ps1` — 15-stage guided setup wizard with progress tracking
- `Setup-MikeBot-Diagnostic.ps1` — read-only diagnostic for remote troubleshooting
- `README-FOR-MIKE.pdf` — one-page user guide

A full test plan lives at `test-plan.md` in this workspace. Read it first — it's your reference. This prompt is the operational companion to that plan.

## Your role and boundaries

**You execute commands, capture output, and flag anomalies.** You do NOT declare pass/fail on your own. Several steps require my eyes (visual dialogs, TUI rendering, real phone interactions). When a step says "Shands action," hand control to me and wait for my report before continuing.

**Your scope is this workspace folder and whatever PowerShell can reach.** Some steps touch things outside this folder (winget installs, registry queries, system reboot). You handle the in-scope parts; I handle the out-of-scope parts.

**Credentials are throwaway.** I'm using a separate DeepSeek account and separate Telegram bot for this test — not Mike's credentials. If a script step expects credentials, I'll provide them. Don't assume anything is pre-configured.

**Don't improvise.** If you see something unexpected — an error message you don't recognize, output that doesn't match what a step describes, a prompt that looks different from expectations — stop and ask me. Don't paper over it, don't skip it, don't try alternative commands without asking. A false pass is worse than a flagged anomaly.

## Pre-flight

Before any test steps, do these checks and report results:

```
1. Confirm all four files exist in this workspace:
   ls Setup-MikeBot.bat Setup-MikeBot.ps1 Setup-MikeBot-Diagnostic.ps1 README-FOR-MIKE.pdf

2. Check PowerShell version:  $PSVersionTable.PSVersion
   (Needs 5.1+; anything lower is a blocking issue.)

3. Check winget availability:  winget --version
   (Needs to exist; if missing, machine needs App Installer from Microsoft Store.)

4. Check for OEM AV: list any third-party antivirus present.
   Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct |
     Select-Object displayName, productState

5. Check OneDrive sync state:
   Get-ItemProperty -Path "HKCU:\Software\Microsoft\OneDrive\Accounts\*" -Name "UserFolder" -ErrorAction SilentlyContinue |
     ForEach-Object { $_.UserFolder }

6. Check if Mark-of-the-Web is applied:
   Get-Content -Path ".\Setup-MikeBot.bat" -Stream Zone.Identifier -ErrorAction SilentlyContinue
   If this returns content (a ZoneId), MotW is present — expected if files were browser-downloaded.
```

Report all six results. If anything is missing or unexpected, stop and ask me before proceeding.

## Test steps

For each step, I've labeled [Cursor] and [Shands] to show who does what. Capture everything.

---

### Step 1 — SmartScreen gate

**[Shands]** Download the four files via browser to this workspace. Right-click each .ps1 and .bat → Properties. Describe what you see under the General tab (is there a "This file came from another computer" block? An Unblock checkbox?). Double-click `Setup-MikeBot.bat`. Describe every dialog that appears before the PowerShell window opens. Specifically: does SmartScreen show a "Windows protected your PC" screen? Does it have a "More info" link? Does clicking it reveal a "Run anyway" button? Take screenshots if anything differs from what `README-FOR-MIKE.pdf` describes.

**[Cursor]** After the PowerShell window opens, read the welcome text from the window (I'll describe it or screenshot it). Confirm it matches the structure in `Setup-MikeBot.ps1` lines ~295-330 (should show "WHAT IT WILL DO," "WHAT IT WILL NOT DO," "ABOUT YOUR FILES," "IF YOU NEED TO STOP," "IF SOMETHING GOES WRONG"). Note any discrepancies.

---

### Step 2 — UAC + script launch

**[Shands]** Click Yes on the UAC prompt. Confirm a black PowerShell window opens with colored text. Note whether the window title shows "Administrator" or similar. If the window flashes and closes immediately, tell me.

**[Cursor]** Once I confirm the welcome screen is visible, note that the script has launched successfully. Proceed to Step 3.

---

### Step 3 — Stage 4 winget installs under Defender

**[Shands]** Watch the script run through Stages 1-4. Pay attention during the winget installs (Git, Node.js, Telegram Desktop). Note any Defender popups, any install that takes longer than 3 minutes, any quarantine notification in the system tray. If something gets quarantined, tell me immediately before proceeding.

**[Cursor]** Do nothing — this step is Shands-observation-only. I'll tell you when we reach the end of Stage 4 or if something went wrong.

---

### Step 4 — OEM AV interference check

**[Shands]** Based on the pre-flight AV check, note which third-party AV is active (if any). During Stage 4 and Stage 9 (npm install), watch for: the PowerShell window closing unexpectedly, installs hanging with no progress for 5+ minutes, AV popups about script behavior or network access. If any of these happen, document which AV, which stage, and what the popup said. Do NOT disable AV without telling me first — I'll decide.

**[Cursor]** Run this command periodically during Stage 4 to check if the script process is still alive:
```
Get-Process powershell -ErrorAction SilentlyContinue | Select-Object Id, StartTime
```
If the PowerShell process disappears unexpectedly, flag it immediately.

---

### Step 5 — Resume logic after mid-setup close

**Part A — Stop after Stage 6 token save:**

**[Shands]** Run through Stages 1-6 normally. In Stage 6, create a throwaway Telegram bot via BotFather and paste the token. Once you see "Telegram token saved" in green, close the PowerShell window immediately (click the X). Do not let the script reach Stage 7.

**[Cursor]** After the window is closed, verify that the progress file was written. Run:
```
Get-Content "$env:LOCALAPPDATA\MikeBot-Setup\.progress"
```
It should contain `LAST_COMPLETED=6`. If it doesn't, or if the file doesn't exist, flag it — the progress-save didn't fire.

**Part B — Resume, then stop after Stage 7 key save:**

**[Shands]** Double-click `Setup-MikeBot.bat` again. When the resume prompt appears, confirm it says "Welcome back… Resume from stage 7?" (not stage 6). Press Enter. Let Stage 7 run — paste the throwaway DeepSeek API key. The moment you see "DeepSeek key saved" in green, close the window immediately. Do not let it reach Stage 8.

**[Cursor]** After the window is closed, check the progress file:
```
Get-Content "$env:LOCALAPPDATA\MikeBot-Setup\.progress"
```
It should contain `LAST_COMPLETED=7`. If it says 6 or the file is missing, the Save-Progress move didn't work — flag it.

**Part C — Resume and confirm skip:**

**[Shands]** Double-click `Setup-MikeBot.bat` again. Confirm the resume prompt offers Stage 8 (not Stage 7). If Stage 7 re-prompts for the DeepSeek key, flag it — the fix didn't close the gap.

**[Cursor]** Read the resume prompt output and confirm which stage is being offered.

---

### Step 6 — OneDrive sync verification

**[Shands]** Let the full setup complete through Stage 15. Then: open a browser, log into onedrive.live.com with the same Microsoft account signed into this Windows machine. Navigate the OneDrive file tree. Look for any folder named `MikeBot-Setup`. Look for any folder named `.openclaw`. Report what you find (or don't find).

**[Cursor]** While I'm checking OneDrive in the browser, verify the local state:
```
# Confirm setup files are in LOCALAPPDATA (should be there)
ls "$env:LOCALAPPDATA\MikeBot-Setup\"

# Confirm OneDrive sync root (for reference)
Get-ItemProperty -Path "HKCU:\Software\Microsoft\OneDrive\Accounts\*" -Name "UserFolder" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.UserFolder }

# Check if .openclaw is under OneDrive path
$odPath = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\OneDrive\Accounts\*" -Name "UserFolder" -ErrorAction SilentlyContinue).UserFolder
if ($odPath) {
    $openclawPath = "$env:USERPROFILE\.openclaw"
    Write-Host "OneDrive root : $odPath"
    Write-Host ".openclaw path: $openclawPath"
    Write-Host "Is .openclaw under OneDrive? $($openclawPath.StartsWith($odPath, [StringComparison]::OrdinalIgnoreCase))"
}
```

Report the output. I'll combine this with my browser findings.

---

### Step 7 — Stage 10 onboarding TUI

**[Shands]** During `openclaw onboard` (Stage 10): watch the TUI closely. Can you navigate with arrow keys? Do any prompts appear truncated or garbled? Does every wizard question match the cheat sheet printed by the script (lines ~930-955 of Setup-MikeBot.ps1)? If anything looks wrong, screenshot it. Complete the onboarding with throwaway credentials.

**[Cursor]** Before onboarding starts, check:
```
Get-Command openclaw -ErrorAction SilentlyContinue
openclaw --version
```

After onboarding completes (or I report it's done), check the gateway is running:
```
openclaw gateway status
```

If the gateway isn't running, check for error logs:
```
openclaw logs --limit 20
```

---

### Step 8 — Stage 14 end-to-end with real Telegram

**[Shands]** Open Telegram on your phone. Find the throwaway bot you created in Stage 6. Send the message: "What is 2 + 2?" Wait for a reply. If no reply in 30 seconds, tell me. When the script asks "Did the bot reply?" — answer y. Then the script will show log output and ask two verification questions. Answer based on what you actually see in the displayed lines (not based on whether the bot replied). Tell me what you answered and why.

**[Cursor]** After I report my answers, run an independent log check to compare:
```
$testTime = Get-Date
# Pull recent logs
$logs = openclaw logs --json --limit 100 --no-color 2>&1
$tgCount = 0; $dsCount = 0
foreach ($line in $logs) {
    if ($line -match '"type":"log"') {
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if ($entry.time) { $entryTime = [DateTime]::Parse($entry.time) }
        if ($entry.message) {
            if ($entry.message -match 'telegram') { $tgCount++ }
            if ($entry.message -match 'deepseek|api\.deepseek') { $dsCount++ }
        }
    }
}
Write-Host "Telegram mentions: $tgCount"
Write-Host "DeepSeek mentions:  $dsCount"
```

Report the counts. If both are zero, flag it — the message may not have traveled the full path even if the bot replied.

---

### Step 9 — Diagnostic script post-setup

**[Cursor]** Run the diagnostic script independently (not through the setup flow):
```
powershell -ExecutionPolicy Bypass -File ".\Setup-MikeBot-Diagnostic.ps1"
```

Capture all output. Parse and report:
- Any line containing `[FAIL]` — list each one with its section
- Any line containing `[info]` — note them for awareness
- Count of `[OK]` lines

The script ends with `Read-Host "Press Enter to close"` — after capturing output, you may need to send Enter or kill the process. Don't interpret the results beyond flagging FAIL lines — I'll decide what matters.

---

### Step 10 — Reboot persistence

**[Shands]** Restart the laptop. After login, wait 2 minutes (the gateway's Scheduled Task or Startup-folder fallback needs time to fire). Do not open any setup windows. Then tell me you've rebooted and waited.

**[Cursor]** After I confirm the machine is back up and 2 minutes have passed, check:
```
openclaw gateway status
```

If the gateway is running, run the diagnostic again:
```
powershell -ExecutionPolicy Bypass -File ".\Setup-MikeBot-Diagnostic.ps1"
```

Capture output — specifically the "Gateway Port" and "Dashboard" sections.

**[Shands]** Send another Telegram message to the bot ("Still there?"). Confirm it replies. If no reply in 30 seconds, tell me.

---

## Failure handling

When you encounter something unexpected:

1. **Stop.** Don't skip it, don't try a workaround, don't assume it's fine.
2. **Capture.** Copy the exact error message, exit code, or unexpected output.
3. **Contextualize.** Tell me which step you were on, what you expected, and what you got.
4. **Wait.** I'll tell you whether to retry, skip, or investigate further.

Things that count as "unexpected":
- Any script stage exits with an error the stage's own retry/skip/quit handler can't resolve
- `openclaw` commands return non-zero exit codes where zero is expected
- PowerShell throws terminating errors on commands that should work
- A step's described behavior doesn't match what actually happens (e.g., the resume prompt offers the wrong stage)
- Any new dialog, popup, or system notification not described in the test plan

Things that are NOT unexpected (don't stop for these):
- Long pauses during winget/npm installs (expected)
- The retry/skip/quit prompt appearing after a failed install (that's the script working as designed)
- Colored output, progress messages, stage headers (normal script output)

## Output format

Maintain a running log as we go. After each step, append a block like this:

```
### Step N: [step name] — RESULT: [OK / FLAGGED / SHANDS-DECIDED]

**Time:** [timestamp]
**What happened:** [2-3 sentences]
**Cursor observations:** [anything I noticed that Shands might not have]
**Shands observations:** [anything Shands told me about his manual checks]
**Output captured:** [paste relevant console output, trimmed to ~20 lines max]
```

At the end, produce a summary table:

| Step | Result | Notes |
|------|--------|-------|
| 1 — SmartScreen | OK / FLAGGED | [one-line note] |
| 2 — UAC launch | | |
| ... | | |
| 10 — Reboot persistence | | |

Flagged steps get a brief follow-up after the table: what was flagged, why, and what (if anything) we decided to do about it.

---

## Before you start

1. Read `test-plan.md` first — it's your primary reference for expected vs. failure behavior
2. Read `Setup-MikeBot.ps1` lines ~295-330 (welcome screen text) and lines ~930-955 (wizard answers cheat sheet) so you know what to compare against
3. Confirm all four test files exist in the workspace
4. Run the six pre-flight checks
5. Report pre-flight results, then wait for my go-ahead on Step 1
