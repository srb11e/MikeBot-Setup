# Phase 2 Report — MikeBot Setup

**Date:** 2026-05-06  
**Status:** COMPLETE  
**Investigator:** Neo

---

## Summary

| Item | Description | Status |
|------|-------------|--------|
| F2.1 | pushd in .bat launcher | ✅ Done early (Phase 1) |
| F2.2 | Refresh-EnvironmentPath robustness | ✅ Done |
| F2.3 | Stage 12/15 log file collision | ✅ Done |
| F2.4 | Remove ACL hardening (Option A) | ✅ Done |
| F2.5 | OneDrive informational notice | ✅ Done |
| F2.6 | Real retry cap | ✅ Done |
| F2.7 | Replace Test-NetConnection with TcpClient | ✅ Done |
| F2.8 | Stage 14 message-flow verification | ✅ Done |

---

## F2.1 — pushd (already done)

Completed during Phase 1 interim. `pushd "%~dp0"` added to `Setup-MikeBot.bat` after UAC elevation check.

---

## F2.2 — Refresh-EnvironmentPath robustness

**Change:** Added `Assert-ToolAvailable` function that:
1. Calls `Refresh-EnvironmentPath`
2. If tool still missing, waits 5 seconds and retries once (races winget post-install hooks)
3. If still missing, shows explicit close-and-reopen instruction: "Close this window, then double-click Setup-MikeBot.bat again. Your progress is saved."

**Wired into:** Stage 9 (before npm install), replacing the manual `Test-CommandExists` + exit block.

**Acceptance:** ✅ Stage 9 either succeeds or produces clear close-and-reopen instruction. No silent "command not found" errors.

---

## F2.3 — Log file collision

**Change:**
- Added `$TokenFile` path constant (`dashboard-token.txt` in LOCALAPPDATA\MikeBot-Setup)
- Stage 12: writes dashboard token to `$TokenFile` instead of appending to `$LogFile`
- Stage 15: setup-log.md references `$TokenFile` in its "Files To Know About" section

**Acceptance:** ✅ User gets both the dashboard token (in its own file) and the setup summary — no collision, no overwrite.

---

## F2.4 — ACL hardening removal (Option A)

**Change:** Removed the entire ACL block from `Save-Secret` (the `Get-Acl` / `SetAccessRuleProtection` / `Set-Acl` code). Replaced with a comment explaining the rationale:

> No explicit ACL hardening here. F1.5 moved all setup state to LOCALAPPDATA, which Windows defaults to user-only permissions. Adding Set-Acl on top would strip inheritance and risk locking out admin recovery without meaningfully improving security over the LOCALAPPDATA baseline.

**Why Option A is stronger now:** After F1.5 (`USERPROFILE` → `LOCALAPPDATA`), the directory is already user-only by Windows convention. The old ACL code used `$env:USERNAME` (no domain), called `SetAccessRuleProtection($true, $false)` (strips inheritance), and silently swallowed errors — more risk than benefit.

**Acceptance:** ✅ No ACL hardening code remains. Comment documents the choice.

---

## F2.5 — OneDrive notice

**Change:** Added an "ABOUT YOUR FILES" section to the welcome screen:
```
  ABOUT YOUR FILES:
    - Setup files (including any keys you paste) are stored in a
      non-synced folder on this PC — not in OneDrive or the cloud.
```

**No detection code.** Per Shands' guidance: "Don't ship code you don't trust to work." The notice appears unconditionally — always true (LOCALAPPDATA is never OneDrive-synced), no fragility risk.

**Acceptance:** ✅ Users are informed. No detection code to produce false positives/negatives.

---

## F2.6 — Real retry cap

**Change:** `Invoke-WithRetrySkipQuit` now actually caps retries:
- After `$MaxRetries` failures, the 'r' (retry) option is removed
- User only sees s (skip) and q (quit)
- Prompt string adapts: `Choose (r/s/q)` → `Choose (s/q)`
- Default behavior (Enter without r/s/q): before cap, retries; after cap, re-prompts with "Retry is no longer available."

**Acceptance:** ✅ Non-technical users cannot infinitely retry a stuck step. Variable name matches behavior.

---

## F2.7 — Replace Test-NetConnection with TcpClient

**Change in `Setup-MikeBot-Diagnostic.ps1`:**
```powershell
$client = New-Object System.Net.Sockets.TcpClient
$connect = $client.BeginConnect("127.0.0.1", 18789, $null, $null)
if ($connect.AsyncWaitHandle.WaitOne(3000)) {
    $client.EndConnect($connect)
    $client.Close()
    OK "Port 18789 is listening on localhost."
} else {
    $client.Close()
    Bad "Port 18789 is NOT listening — gateway probably isn't running."
}
```

- 3-second timeout (vs. Test-NetConnection's variable timeout)
- No spurious warnings on locked-down machines
- No dependency on `Test-NetConnection` module

**Acceptance:** ✅ Diagnostic completes quickly. No warning suppression needed.

---

## F2.8 — Stage 14 message-flow verification

**Architecture:**
1. **Before** asking Mike to send a message: captures `$testStartTime = Get-Date`
2. After Mike says "yes" (bot replied): runs `openclaw logs --json --limit 30 --no-color`
3. Filters log lines: only those with `time >= $testStartTime`
4. Does case-insensitive search for "telegram" and "deepseek|api\\.deepseek" in the `message` field
5. **Shows Mike the filtered lines** (first 5 of each, truncated to 120 chars):
   ```
   Lines mentioning 'telegram' (3 found):
     - [log line 1]
     - [log line 2]
   
   Lines mentioning 'deepseek' (2 found):
     - [log line 1]
   ```
6. Asks two yes/no verification questions:
   - "In the lines above, do you see at least one that mentions 'telegram'? (y/n)"
   - "Do you see at least one that mentions 'deepseek' or 'api.deepseek'? (y/n)"
7. If both yes → confirmed. If either no → warns + suggests screenshot to Shands + offers "continue anyway"
8. If `openclaw logs` fails entirely → degrades gracefully: "Your bot replied, so the path is working. Double-check with: openclaw logs"
9. Non-JSON lines are silently skipped (no false failures from meta lines)

**Acceptance:** ✅ Mike verifies, not searches. Genuine "yes" → confirmation. Mistaken "yes" → warning.

---

## New Issues Discovered

None.

## Time Spent

~45 minutes for investigation + implementation across all 8 items.
