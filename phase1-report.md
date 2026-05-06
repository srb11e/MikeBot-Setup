# Phase 1 Report — MikeBot Setup

**Date:** 2026-05-06  
**Status:** COMPLETE  
**Investigator:** Neo

---

## Completed Items

### F1.1 — Replace deprecated DeepSeek model name ✅

**File:** `Setup-MikeBot.ps1`, Stage 8

**Change:** `deepseek-chat` → `deepseek-v4-flash` with doc comment citing https://api-docs.deepseek.com/ and deprecation date (2026-07-24).

**Acceptance:** ✅ Current model. Comment prevents "fixing it back."

---

### F1.2 — Correct the DeepSeek API endpoint ✅

**File:** `Setup-MikeBot.ps1`, Stage 8

**Change:** Endpoint from `/chat/completions` → `/v1/chat/completions`. Both return 200 per Phase 0 live tests. `/v1/` chosen as canonical OpenAI-compatible path.

**Acceptance:** ✅ Test call returns 200 with valid completion.

---

### F1.3 — Add escape hatches to validation loops ✅

**File:** `Setup-MikeBot.ps1`, Stage 6 (Telegram) and Stage 7 (DeepSeek)

**Change:**
- Attempt counters added to both loops
- Regexes loosened: Telegram `^\d+:[\w\-]+$`, DeepSeek `^sk-\S{16,}$`
- After 3 failures, user sees:

```
  I keep rejecting your [token|key]. Three options:
    r) Try again with a different paste
    a) Accept this [token|key] anyway (use if you're sure it's correct
       and my validation is just being too strict)
    q) Quit and contact Shands

  Choose (r/a/q)
```

- "a" saves without validation and continues
- "q" exits with progress saved
- Default / "r" loops back

**Acceptance:** ✅ User with a valid-but-unusual-format token can either retry (r), force-accept (a), or bail safely (q).

---

### F1.4 — Remove fabricated exit code logic ✅

**File:** `Setup-MikeBot.ps1`, Stage 10

**Change:**
- Removed `if ($proc.ExitCode -eq 401 -or $proc.ExitCode -eq 1)` branch entirely
- OpenClaw does not document specific exit codes for `onboard` — verified via `--help`, docs.openclaw.ai/cli/onboard, and llms.txt
- Replaced with generic guidance listing multiple plausible causes (network, API key, model, port conflict) + diagnostic script reference

**Acceptance:** ✅ No fabricated diagnostic claims. Error guidance lists multiple causes without false confidence.

---

### F1.6 — Fix Start-Process invocation ✅

**File:** `Setup-MikeBot.ps1`, Stage 10

**Change:**
- `Start-Process -FilePath "openclaw" -ArgumentList "onboard","--install-daemon" -Wait -PassThru -NoNewWindow` →
- `& openclaw onboard --install-daemon` with `$LASTEXITCODE` capture
- Comment added explaining why (TUI rendering breakage risk with Start-Process)

**Acceptance:** ✅ Call operator used. Exit code captured correctly.

---

### Also applied (review round 1, validated this round)

| Change | Status |
|--------|--------|
| Env var fallback with key prefix display (Stage 10) | ✅ Carried forward |
| Pairing command dual-format (Stage 13) | ✅ Carried forward |
| Node.js auto-restart on PATH miss (Stage 4) | ✅ Carried forward |

---

## Phase 1 Acceptance Checklist

| Item | Acceptance Met? |
|------|----------------|
| F1.1 — deprecated model replaced, comment exists | ✅ |
| F1.2 — endpoint corrected to `/v1/` | ✅ |
| F1.3 — escape hatches in both validation loops | ✅ |
| F1.4 — no fabricated exit code logic | ✅ |
| F1.5 — secrets in LOCALAPPDATA, not USERPROFILE | ✅ |
| F1.6 — call operator, not Start-Process -NoNewWindow | ✅ |

**Phase 1 is complete.** Awaiting review before Phase 2.
