# Nudge M1 — Verification and Developer Handoff

Date: **2 October 2026**
Implementation status: **source complete for M1; phase acceptance pending manual verification**

The user explicitly instructed Codex to begin M1 while the M0 manual QA record was still pending. That is recorded as an explicit sequencing override; it is not evidence that M0 passed. This implementation did not install, remove, or edit any real Codex configuration and did not run live prompts through either host.

## Automated results

| Check | Result |
|---|---|
| `xcodebuild -list -project Nudge.xcodeproj` | Passed; targets `Nudge`, `NudgeBridge`, `NudgeCoreTests`, and `NudgeIntegrationTests` are listed |
| Debug app/helper/test build | Passed as part of the Debug test action |
| `NudgeCoreTests` | 8 tests passed |
| `NudgeIntegrationTests` | 20 tests passed |
| Combined Debug test action | 28 tests passed, 0 failures |
| Config/socket safety | Tests used temporary directories and socket endpoints only |
| `xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Release -destination platform=macOS build` | Passed |
| M0 standalone checks | Presentation reducer, notch geometry, and notch layout checks passed (static/hermetic only) |
| `git diff --check` | Passed |
| Real Codex Desktop/CLI and native UI manual verification | Pending developer |

The integration tests cover strict envelope/key validation, synthetic privacy fixtures, placeholder-session enrichment, turn/tool reduction, focus priority, safe `hooks.json` merge/backup/uninstall, malformed/duplicate-key preservation, symlink refusal, owner-only sockets, stale/live socket handling, fragmented frames, and bridge no-op output/deadline behavior. They do not establish live host compatibility. Standalone M0 checks are static/hermetic and do not replace the developer's visual and native-window QA.

## Host and UI evidence still needed

1. First run and record the pending M0 visual checklist from [Nudge-M0-Verification.md](Nudge-M0-Verification.md): physical notch, external/no-notch display, Spaces/full screen, hover, Reduce Motion, and sleep/wake behavior.
2. Record current Codex Desktop and CLI versions separately, the app launch method, the effective config location for each, any `CODEX_HOME`, profile/managed restrictions, trust state, and required reload/restart.
3. In a sandbox config, review the Nudge install preview, install hooks, review/trust the exact helper definition in the host, and confirm foreign handlers and the backup remain intact. The app supports selecting a config folder; verify it matches the effective host config.
4. Start a new **local** thread directly from Codex Desktop with a tool call. Confirm Nudge receives project, thinking, tool, and terminal Stop status without launching a terminal or Nudge app-server.
5. Resume a local thread directly in Desktop and repeat the event check, including the case where the first observed event is a tool event before `SessionStart`.
6. Interrupt an active Desktop turn. Confirm the state is interrupted, not completed; then start another turn and confirm it becomes focused.
7. Repeat new/resumed/tool/Stop/interrupt coverage independently in Codex CLI and record differences. Synthetic fixtures do not count for either host.
8. Close Nudge while each host is working. Confirm Codex continues normally without stalls, failed approvals, or silent allow behavior. Reopen Nudge and confirm the next real event restores status without replaying old completion.
9. On a temporary config, repeat install, test duplicate owned hooks, preserve foreign hooks, test a malformed file, and uninstall only Nudge-owned handlers. Confirm backup remains available and malformed bytes remain unchanged.
10. Record host-specific event coverage, trust/reload result, visible status, and any perceived event latency. If no event arrives, record it as unverified and inspect the effective config/trust path rather than assuming the cause.

| Workflow | Version | Effective config | Trust/reload | Event coverage | Result |
|---|---|---|---|---|---|
| Desktop new local | Pending | Pending | Pending | Pending | Pending |
| Desktop resumed local | Pending | Pending | Pending | Pending | Pending |
| Desktop interrupt | Pending | Pending | Pending | Pending | Pending |
| CLI new/resumed/interrupt | Pending | Pending | Pending | Pending | Pending |
| Nudge unavailable: Desktop | Pending | Pending | N/A | Pending | Pending |
| Nudge unavailable: CLI | Pending | Pending | N/A | Pending | Pending |
| Reinstall/uninstall temporary config | N/A | Temporary | N/A | N/A | Automated merge tests passed; developer workflow pending |

M1 acceptance remains pending until the developer completes these checks. The required M1 completion condition is real Desktop new/resumed monitoring plus separately verified CLI monitoring. Do not start M2 until that handoff is reviewed and the user instructs the next phase.
