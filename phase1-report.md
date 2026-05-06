# Phase 1 Interim Report — MikeBot Setup

**Date:** 2026-05-06  
**Status:** IN PROGRESS (F1.5, F2.1 complete)

---

## Completed Items

### F1.5 — Move secrets out of OneDrive-syncable location ✅

**File:** `Setup-MikeBot.ps1` (path constants), `Setup-MikeBot-Diagnostic.ps1`

**Change:**
- `$ProgressDir`: `$env:USERPROFILE\MikeBot-Setup` → `$env:LOCALAPPDATA\MikeBot-Setup`
- Both scripts updated
- Verbose comment added explaining the OneDrive risk and why LOCALAPPDATA is the correct choice
- Verified: remaining USERPROFILE references are for `%USERPROFILE%\.openclaw\` (OpenClaw's config dir) — correct, unchanged

**Acceptance:** ✅ No path uses `$env:USERPROFILE` for setup state files. Diagnostic script finds files in new location. OpenClaw config references preserved correctly.

---

### F2.1 — Add pushd to elevated .bat launcher ✅

**File:** `Setup-MikeBot.bat`

**Change:** Added `pushd "%~dp0"` immediately after the elevation check passes, with comment explaining why (UAC re-launch sets working dir to `C:\Windows\System32`).

**Acceptance:** ✅ `cd` in the elevated process now resolves to the script's directory. Future edits using relative paths won't fail silently.

---

## Endpoint Verification (Phase 0 follow-up)

Per Shands' instruction, tested both endpoints with `deepseek-v4-pro` + thinking enabled:

| Endpoint | HTTP Code | Result |
|----------|-----------|--------|
| `/chat/completions` | 200 | Valid |
| `/v1/chat/completions` | 200 | Valid |

**Decision:** Phase 1 F1.2 will use `/v1/chat/completions` (canonical OpenAI-compatible path).

Both calls consumed all `max_tokens=20` on reasoning with empty content — reinforces V0.6. Stage 8 test call must use `thinking: disabled`.

---

## Awaiting Go-Ahead

Ready to proceed with remaining Phase 1 items:
- F1.1 — Replace `deepseek-chat` → `deepseek-v4-flash` + `thinking: disabled` in Stage 8
- F1.2 — Endpoint → `/v1/chat/completions`
- F1.3 — Escape hatches in validation loops (Stage 6, 7)
- F1.4 — Remove fabricated exit code logic (Stage 10)
- F1.6 — Replace `Start-Process -NoNewWindow` with `& openclaw onboard --install-daemon`

All five have dependencies resolved. Ready when you are.
