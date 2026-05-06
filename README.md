# MikeBot Setup

Turnkey Windows onboarding scripts that walk a non-technical user through installing OpenClaw with DeepSeek + Telegram on a Windows laptop.

## What's Here

| File | Purpose |
|------|---------|
| `Setup-MikeBot.bat` | Double-clickable launcher — handles admin elevation and execution policy |
| `Setup-MikeBot.ps1` | 15-stage guided setup wizard with progress tracking and resume-from-anywhere |
| `Setup-MikeBot-Diagnostic.ps1` | Read-only diagnostic — collects system info for remote troubleshooting |
| `README-FOR-MIKE.pdf` | One-page printable guide for the end user (Mike) |

## Architecture

The setup script walks through:

1. **Windows version check** — requires build ≥ 19041
2. **Windows Update** — opens Settings, waits for completion
3. **Security basics** — screen lock, power settings (no sleep), BitLocker
4. **Foundation tools** — Node.js 22 LTS, Git, Telegram Desktop (via winget)
5. **Bitwarden** — password manager for API key storage
6. **Telegram bot creation** — BotFather walkthrough on phone
7. **DeepSeek account + API key** — account creation, key generation
8. **API key test** — validates the key with a live API call
9. **OpenClaw install** — npm global install
10. **OpenClaw onboarding** — wizard with exact answer guide for every prompt
11. **Gateway health check** — verifies the service is running
12. **Dashboard check** — confirms web UI is reachable, retrieves auth token
13. **Phone pairing** — approves Telegram DM access
14. **End-to-end test** — sends a message from phone, verifies reply
15. **Wrap-up** — cleanup instructions, log generation, maintenance commands

## Design Decisions

- **Resilience over polish.** Progress saves to `%USERPROFILE%\MikeBot-Setup\.progress` after each stage. If the window closes, power is lost, or internet drops — double-clicking `Setup-MikeBot.bat` resumes from the last completed stage.
- **Secrets handled carefully.** API keys are read via `Read-Host -AsSecureString`, stored temporarily in an ACL-locked file, and cleaned up with explicit instructions after setup completes.
- **Colored, categorized output.** Success/warning/failure/info messages use distinct colors so Mike can scan visually without parsing text.
- **Wizard answers cheat sheet.** Stage 10 prints the exact answer for every `openclaw onboard` prompt, with explicit instructions to STOP and screenshot if anything differs.
- **Retry/skip/quit on every fallible step.** No single failure traps the user. Every operation can be retried, skipped, or the setup can be quit with progress saved.

## For Maintainers

This is a Shands-maintained project. Mike does not edit these files.

### Key operational risks
- The `openclaw onboard` wizard may change its prompts — Stage 10's cheat sheet needs to stay current
- The `openclaw pairing approve` command syntax may differ across OpenClaw versions — Stage 13 tries both old and new formats
- DeepSeek's onboarding flow (account creation, API key UI) could change — Stage 7 instructions may drift
- The Telegram token regex accepts standard BotFather tokens; a `force` override exists for edge cases

### Testing checklist before shipping to Mike
1. Run on a fresh Windows VM (or reset laptop)
2. Verify all 15 stages complete without manual intervention beyond the prompts that require it
3. Verify resume-from-each-stage works (kill the script mid-stage and relaunch)
4. Confirm `openclaw pairing approve` syntax matches installed version
5. Run `Setup-MikeBot-Diagnostic.ps1` and verify all checks pass on a healthy install
6. Send a message from phone and confirm round-trip reply < 15 seconds

## Files Not Tracked

- `*.pdf` — the user-facing README PDF is versioned separately or regenerated from the markdown

## Known Limitations / Accepted Risks (Phase 4)

These were flagged in the red-team audit and consciously accepted or deferred:

- **A4.1 — Bracketed-paste mode may truncate tokens.** Rare on modern terminals. The loosened validation regex (F1.3) and the API test step catch truncated tokens. Mitigation cost exceeds expected harm.
- **A4.2 — Telegram bot privacy settings.** Deferred to a manual post-setup step: once the bot works, send `/setprivacy` to BotFather, select the bot, set to "Disable." This prevents the bot from seeing all group messages.
- **A4.3 — Supply-chain trust on `npm install -g openclaw`.** Accepting risk. Pinning a specific version creates maintenance burden. Mike isn't typing the package name — the script is. Canonical package name confirmed in V0.1.
- **A4.4 — Corporate/managed Windows machines.** Deferred. If Mike's laptop is corporate-managed (MDM, group policy, AV exclusions), the script will fail visibly and Shands can intervene. Pre-detection would require extensive policy enumeration — out of scope.
- **A4.5 — Original .bat window stays open during UAC re-launch.** Accept. Cosmetic only on slow systems.

## Uninstall

If Mike wants to remove this setup, here is what was installed and how to remove it:

| Component | How to Remove |
|-----------|---------------|
| OpenClaw | `npm uninstall -g openclaw` then delete `%USERPROFILE%\.openclaw\` |
| Node.js | Windows Settings → Apps → Uninstall "Node.js" |
| Git | Windows Settings → Apps → Uninstall "Git" |
| Bitwarden | Windows Settings → Apps → Uninstall "Bitwarden" |
| Telegram Desktop | Windows Settings → Apps → Uninstall "Telegram Desktop" |
| Setup files | Delete `%LOCALAPPDATA%\MikeBot-Setup\` |
| Bot (Telegram) | Send `/deletebot` to BotFather and confirm |
| DeepSeek account | Log in at platform.deepseek.com → Account → Delete Account |
