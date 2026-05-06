# Phase 3 Report — MikeBot Setup

**Date:** 2026-05-06  
**Status:** COMPLETE  
**Investigator:** Neo

---

## Summary

| Item | Description | Status |
|------|-------------|--------|
| F3.1 | Approved-verb cleanup (Load→Import, Refresh→Update) | ✅ Done |
| F3.2 | Disambiguate Should-Skip → Test-StageAlreadyComplete | ✅ Done |
| F3.3 | Remove Ctrl+C handler, update welcome screen | ✅ Done |
| F3.4 | Winget exit code handling — add canonical codes | ✅ Done |
| F3.5 | Uninstall section in README | ✅ Done |
| F3.6 | Pre-flight winget ID check — fail loudly | ✅ Done |
| F2.8 fix | Raise log limit 30→100 to avoid busy-gateway misses | ✅ Done |

---

## F3.1 — Approved-verb cleanup

**Changes:**
- `Load-Progress` → `Import-Progress` (1 definition, 1 caller)
- `Refresh-EnvironmentPath` → `Update-EnvironmentPath` (1 definition, 4 callers)

**Verification:** `grep` for old names returns zero matches. Diagnostic script has no references to these functions (correct — it's standalone).

**PSScriptAnalyzer note:** Cannot run from WSL (Windows PowerShell module). All renames match their PowerShell approved-verb equivalents: `Import` (PSApprovedVerb), `Update` (PSApprovedVerb). Manual verification via grep confirms all callers updated.

---

## F3.2 — Disambiguate function names

**Change:** `Should-Skip` → `Test-StageAlreadyComplete` (1 definition, 14 callers across stages 1-14)

**Rationale:** `Should-Skip` was ambiguous with `Test-UserChoseSkip` (user-elected skip vs. stage-already-complete state). The new name makes the distinction clear.

---

## F3.3 — Remove Ctrl+C handler

**Changes:**
- Removed the entire `Register-EngineEvent` block (the `$ExitHandler` scriptblock and event registration)
- Updated welcome screen "IF YOU NEED TO STOP" section:
  - Old: "Close this window any time. Your progress is saved. Double-click Setup-MikeBot.bat again to resume."
  - New: "Close this window any time — your progress is saved. Double-click Setup-MikeBot.bat again to resume where you left off."

**Rationale:** `Register-EngineEvent` with `PsEngineEvent::Exiting` is unreliable on Ctrl+C in PowerShell — the handler may or may not fire depending on how the signal arrives. Progress is already saved at every stage boundary, so abrupt termination is always recoverable. The welcome text now makes the same promise without depending on fragile event hooks.

---

## F3.4 — Winget exit code handling

**Change:** Added `-1978335206` (`APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED`) to the success codes list.

**Codes treated as success:**

| Code | Symbol | Meaning |
|------|--------|---------|
| `0` | — | Success |
| `-1978335189` | `NO_APPLICABLE_UPGRADE` | Already up to date |
| `-1978335206` | `PACKAGE_ALREADY_INSTALLED` | Already installed |

Source: Microsoft winget-cli `returnCodes.md` (confirmed via web fetch). Codes documented with inline comments.

---

## F3.5 — Uninstall section

**Added to README.md:** Table listing every installed component with its removal method: OpenClaw (npm uninstall + delete config), Node.js, Git, Bitwarden, Telegram Desktop (all via Windows Settings), setup files (delete LOCALAPPDATA folder), Telegram bot (BotFather /deletebot), DeepSeek account (platform.deepseek.com).

---

## F3.6 — Pre-flight winget ID check

**Change:** Added verification loop before Stage 4 installs. For each package, runs `winget search --id <ID> --exact`. If any fails (non-zero exit code), the script fails loudly with:

```
[X] The package ID for 'Git' has changed or is no longer available.
  Expected ID: Git.Git
  This means Microsoft's package registry has changed since the script was written.
  Please contact Shands before continuing — do not try to work around this.
```

Then exits. Per Shands: "fail loudly and stop the script — don't warn-and-continue."

---

## F2.8 fix — Raise log limit

**Change:** `--limit 30` → `--limit 100` in Stage 14's `openclaw logs` invocation. Prevents false negatives when gateway activity pushes the test message's log lines outside the 30-line window.

---

## New Issues Discovered

None.

## Time Spent

~30 minutes for implementation across all 7 items.
