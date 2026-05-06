# Phase 0 Findings — MikeBot Setup

**Date:** 2026-05-06  
**Investigator:** Neo  
**Status:** COMPLETE (1 finding requires Windows access)

---

## V0.1 — OpenClaw npm package name

**[CONFIRMED]**

**Package:** `openclaw`  
**Version at time of verification:** `2026.5.6`  
**Description:** "Multi-channel AI gateway with extensible messaging integrations"  
**npm command:** `npm view openclaw` returns valid package metadata.

**Install paths documented at docs.openclaw.ai/install:**

| Method | Command | Status |
|--------|---------|--------|
| Official Windows installer | `iwr -useb https://openclaw.ai/install.ps1 \| iex` | ✅ Recommended |
| npm global install | `npm install -g openclaw@latest` | ✅ Supported alternative |
| npm + git (main) | `npm install -g github:openclaw/openclaw#main` | ✅ Supported |

**Finding for remediation:** The script uses `npm install -g openclaw` (Stage 9), which is a valid alternative path. However, the official recommendation for fresh Windows installs is the `install.ps1` script, which handles Node.js installation, sharp binary compatibility, and daemon setup automatically. The npm path requires Node.js to be already installed and working (which Stage 4 handles).

**Recommendation:** Keep `npm install -g openclaw` — it's documented, supported, and simpler than wrapping `install.ps1` in a scripted flow. No change needed for this finding.

---

## V0.2 — DeepSeek API endpoint and current model name

**[CONFIRMED] — with deprecation warning**

**Source:** `https://api-docs.deepseek.com/` (live docs, fetched 2026-05-06)

### Endpoint
- **Confirmed:** `https://api.deepseek.com/chat/completions` (no `/v1` prefix)
- The curl example on DeepSeek's docs uses `https://api.deepseek.com/chat/completions` directly
- The `base_url` for OpenAI format is documented as `https://api.deepseek.com`
- **Additional verification (2026-05-06):** Both endpoints tested live with `deepseek-v4-pro` + thinking enabled:
  - `/chat/completions` → HTTP 200 ✅
  - `/v1/chat/completions` → HTTP 200 ✅
- **Decision:** Use `/v1/chat/completions` — it is the canonical OpenAI-compatible path and both work.

### Model names
DeepSeek API docs (live) list these models:

| Model | Status |
|-------|--------|
| `deepseek-v4-flash` | ✅ Current default |
| `deepseek-v4-pro` | ✅ Current premium |
| `deepseek-chat` | ⚠️ Deprecated 2026-07-24 → maps to `deepseek-v4-flash` non-thinking |
| `deepseek-reasoner` | ⚠️ Deprecated 2026-07-24 → maps to `deepseek-v4-flash` thinking mode |

### Live API test results
- **Endpoint:** `POST https://api.deepseek.com/chat/completions` → HTTP 200 ✅
- **Model `deepseek-v4-flash`** with `thinking: disabled` → returned `"OK"` ✅

### Critical finding for Stage 8 test call
`deepseek-v4-flash` has **thinking mode enabled by default**. With `max_tokens=5` and no `thinking: disabled`, the model consumed all 5 tokens on reasoning and produced an empty `content` field. This means the current script's test call (`max_tokens = 5`, expecting "OK" in content) will **fail silently** after the model switch.

**Remediation:**
1. Replace `deepseek-chat` with `deepseek-v4-flash` in Stage 8
2. Add `"thinking": {"type": "disabled"}` to the test call body (or increase max_tokens to 500+)
3. Update Stage 10 onboarding guidance to mention `deepseek-v4-flash` as the model to enter

### OpenClaw integration guide (DeepSeek docs)
`https://api-docs.deepseek.com/quick_start/agent_integrations/openclaw` confirms:
- Windows install: `iwr -useb https://openclaw.ai/install.ps1 | iex` (official)
- Onboarding: choose DeepSeek provider → enter API key → enter model name (`deepseek-v4-pro` or `deepseek-v4-flash`)
- Re-entry: `openclaw onboard --install-daemon`

---

## V0.3 — OpenClaw onboarding TUI under Start-Process -NoNewWindow

**[Unknown]** — Cannot verify from Linux/WSL

**Risk:** PowerShell's `Start-Process -NoNewWindow` redirects standard streams in ways that can break TUIs using raw terminal I/O. The OpenClaw onboard wizard is an interactive TUI.

**What the docs say:** `openclaw onboard --install-daemon` is intended for direct invocation. The docs show call-operator usage (`& openclaw onboard --install-daemon`) and direct invocation.

**Recommendation:** Test on Windows before Phase 1 F1.6. If `Start-Process -NoNewWindow` breaks the TUI, replace with `& openclaw onboard --install-daemon` (call operator). Capture exit via `$LASTEXITCODE`.

**To verify:** Launch from PowerShell on a Windows machine with OpenClaw installed:
```
Start-Process -FilePath "openclaw" -ArgumentList "onboard","--install-daemon" -Wait -NoNewWindow
```
Verify: arrow-key navigation works, characters are not garbled, prompts display fully.

---

## V0.4 — OpenClaw pairing command syntax

**[CONFIRMED]**

**Source:** `openclaw pairing --help` (live CLI, v2026.4.29)

### `openclaw pairing list`
```
Usage: openclaw pairing list [options] [channel]
Arguments:
  channel                Channel (optional positional)
Options:
  --account <accountId>  Account id (for multi-account channels)
  --channel <channel>    Channel (flag form)
  --json                 Print JSON (default: false)
```

Both forms work:
- `openclaw pairing list --channel telegram` ✅
- `openclaw pairing list telegram` ✅
- `openclaw pairing list` (lists all channels) ✅

### `openclaw pairing approve`
```
Usage: openclaw pairing approve [options] <codeOrChannel> [code]
Arguments:
  codeOrChannel          Pairing code (or channel when using 2 args)
  code                   Pairing code (when channel is passed as the 1st arg)
Options:
  --channel <channel>    Channel (flag form)
  --notify               Notify the requester (default: false)
```

Valid syntaxes:
- `openclaw pairing approve <code>` ✅ (code-only, no channel)
- `openclaw pairing approve telegram <code>` ✅ (channel as 1st arg, code as 2nd)
- `openclaw pairing approve <code> --channel telegram` ✅ (flag form)

**Finding for remediation:** The script's current dual-format approach (added in initial review) is redundant — both `openclaw pairing approve $code` and `openclaw pairing approve telegram $code` are valid and work identically. Either form works. The fallback logic is harmless but unnecessary. Recommend simplifying to just `openclaw pairing approve $code` (code-only, simplest).

---

## V0.5 — winget package IDs

**[CONFIRMED]**

All four package IDs verified against winget.run, Microsoft Learn, and downstream confirmations:

| Package ID | Status |
|------------|--------|
| `Git.Git` | ✅ Confirmed |
| `OpenJS.NodeJS.LTS` | ✅ Confirmed |
| `Telegram.TelegramDesktop` | ✅ Confirmed |
| `Bitwarden.Bitwarden` | ✅ Confirmed |

No drift detected. All IDs are stable and canonical.

---

## V0.6 (Bonus) — DeepSeek v4-flash thinking mode default

**[CONFIRMED] — New finding, not in original brief**

`deepseek-v4-flash` has thinking/reasoning mode **enabled by default**. This is a behavioral change from `deepseek-chat` which had no thinking mode.

Impact on the script:
1. **Stage 8 test call:** Must add `"thinking":{"type":"disabled"}` or increase `max_tokens` substantially (thinking tokens + content tokens). Currently `max_tokens=5` means all tokens can be consumed by reasoning, producing empty content.
2. **OpenClaw config:** May need to specify thinking preferences. OpenClaw's DeepSeek integration likely handles this, but worth noting.

**Recommendation:** Add `thinking: disabled` to the Stage 8 test call body. This is the simpler fix and preserves the "expect exactly OK" assertion.

---

## Phase 0 Exit Status

| Finding | Status | Blocks Phase 1? |
|---------|--------|-----------------|
| V0.1 — npm package name | ✅ [CONFIRMED] | No |
| V0.2 — DeepSeek endpoint + model | ✅ [CONFIRMED] | Yes — model deprecation requires F1.1/F1.2 |
| V0.3 — Start-Process TUI behavior | ⚠️ [UNKNOWN] | Yes — blocks F1.6 |
| V0.4 — Pairing command syntax | ✅ [CONFIRMED] | No |
| V0.5 — winget package IDs | ✅ [CONFIRMED] | No |
| V0.6 — thinking mode default | ✅ [CONFIRMED] | Yes — affects F1.1 |

### Items that MUST be resolved before Phase 1 code changes:
1. **V0.3 — Windows TUI test** — Needs a Windows machine. Either Shands tests manually or we accept the risk and replace `Start-Process` with call operator unconditionally (the safer default).
2. **V0.2/V0.6 model + thinking mode** — Confirmed facts, ready for fixes, but the findings are material enough that Shands should approve the specific model choice before we proceed.

### Recommendation
Proceed to Phase 1 on all items EXCEPT F1.6 (TUI invocation). For F1.6, present Shands with the V0.3 unknown and ask whether to:
- (A) Test on Windows first, then fix based on results
- (B) Replace `Start-Process -NoNewWindow` with `& openclaw onboard` unconditionally (safer default, likely correct)
