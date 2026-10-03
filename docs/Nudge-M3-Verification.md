# Nudge M3 — Verification and Developer Handoff

Date: **3 October 2026**.

Implementation status: **source implemented; Debug build and hermetic test suite passed; manual host acceptance is pending**. M1 and M2 live/manual acceptance remain pending as recorded in Nudge-M2-Verification.md; beginning M3 implementation followed the user's explicit instruction and does not convert those gates to passed.

No Codex Desktop/CLI configuration, hook trust state, live question, or permission decision was changed or exercised while implementing M3.

## Current verification

| Check | Result |
|---|---|
| Debug app/helper build | Passed: xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build |
| Hermetic unit/integration test suite | Passed: xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test |
| git diff --check | Passed |
| Desktop and CLI M3 live event coverage | Pending developer |
| Native attention card, notch/fallback, accessibility and motion | Pending developer |
| Installer trust/reload after PermissionRequest addition | Pending developer |

Public-hook facts, the candidate question shape, V3 compatibility, and unresolved permission correlation are in [M3 Codex contract](Nudge-M3-Codex-Contract.md). Hermetic coverage includes sanitized synthetic question/permission fixtures, matching progress, and conservative handling of ambiguous permission correlation. Source changes and successful build/tests do not prove host event delivery or native display behavior.

## Manual verification by the developer

Use a sandbox Codex project and recoverable temporary config. Record Desktop and CLI separately. These steps remain pending; do not treat synthetic fixtures as live evidence.

1. Record macOS, Codex Desktop version/build, CLI version, effective config roots, any CODEX_HOME, trust/reload state, and M1/M2 acceptance status. Install the matching helper, review the changed event list, and re-trust Nudge where the host requests it.
2. Start a local thread directly in Codex Desktop and trigger request_user_input if that host exposes it through hooks. Record sanitized event name, tool name, input shape, IDs, first/last observed event, and whether the safe bounded preview appeared. Repeat on a resumed local thread without launching a terminal or app-server.
3. Repeat the question scenario independently in Codex CLI. Note whether PreToolUse fires for this tool and which exact input fields are present. A missing hook or unknown schema is a limitation, not a pass.
4. Leave each question unanswered while pointer exits, the panel is collapsed, another session works, the Mac sleeps/wakes, or Desktop is opened. Verify pending remains visible. Answer in the native host; identify the exact matching progress event that clears only this request.
5. Trigger native permission approval and denial/cancel separately on Desktop and CLI. Nudge must issue no decision output. Record PermissionRequest IDs and event ordering. Exercise concurrent same-name tools; ambiguous correlation must stay pending rather than clear on unrelated work. Note whether denial/cancel clears before turn termination.
6. Click Answer in Codex Desktop / Open Codex Desktop from another app. Confirm activation, preserve pending until host progress, and verify visible recovery text when activation fails. For a CLI session, confirm the CTA does not claim to route to its terminal.
7. Create multiple active sessions and multiple pending events where available. Inspect focused/peek context, the expanded session list, attention ordering, selection, scroll, and the 170 pt expanded content cap. Verify stale tool labels cannot cover a question.
8. Test empty/long/multi-question previews and input containing secret/path sentinels. Unsafe preview text must fall back to generic copy. Inspect app logs and local config for leaked prompt, command, tool input, or option text.
9. Verify Nudgie's single attention cue, quiet persistent pose, Reduce Motion, VoiceOver labels, keyboard focus, contrast, narrow fallback display, physical notch, rapid hover, Spaces/full-screen, and menu access.
10. Close or crash Nudge with permission/question pending. Codex must continue through its native flow without allow. Reopen Nudge and confirm the next delivered progress restores a current view without replaying a prior cue or claiming recovery of an event Nudge did not receive.
11. In temporary config roots, test upgrade/reinstall/uninstall, duplicate Nudge entries, foreign hooks, malformed bytes, backup/atomic failure, and custom CODEX_HOME. Confirm seven exact Nudge handlers after install, foreign values preserved, and malformed originals unchanged.

Record each workflow with **host/version / scenario / config + trust / sanitized event chronology / resolution signal / result or limitation**. Values remain pending, passed, failed, or unsupported with evidence; synthetic data never changes host status to passed.

Stop after M3 handoff. Do not begin M4 precise-navigation implementation until the developer records this phase's manual review and the user directs the next phase.
