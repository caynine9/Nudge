# Nudge M4 — Verification and Developer Handoff

Date: **3 October 2026**.

Implementation status: **source and hermetic test cases implemented and compiled; Debug app/helper build and build-for-testing passed; test execution and live host acceptance pending**. M1–M3 live/manual acceptance remains pending as recorded in [M3 verification](Nudge-M3-Verification.md). The user explicitly instructed Nudge to begin M4; this overrides the phase-order pause for implementation only and does not mark the earlier host gates passed.

The precise route uses the documented local-thread URL, targets the Codex Desktop bundle, reports delivery separately from visible-thread success, and falls back to app activation. The setting defaults Off. No Codex hooks/configuration, thread, permission decision, or live Desktop/CLI session was changed or exercised during implementation.

## Source verification

| Check | Result |
|---|---|
| AppKit API and URL contract review | Reviewed; references recorded in [M4 Codex contract](Nudge-M4-Codex-Contract.md) |
| `git diff --check` | Passed |
| Debug app/helper build | Passed: `xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build` |
| Integration test target compilation | Passed: `xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build-for-testing` |
| Hermetic test execution | Not run; test cases compiled but were not executed |
| Codex Desktop new/resumed session routing | Pending developer |
| Codex CLI new/resumed session mapping and Desktop visibility | Pending developer |
| Archived/missing-thread and multiple-window behavior | Pending developer |
| Attention/pending-state, notch, accessibility and motion behavior | Pending developer |

Hermetic test cases cover URL validation/encoding, opt-in policy, bundle-targeted dispatch, activation fallback, timeout/late completion, finite activation failure, isolated preference persistence, and stale feedback context. The test target compiled successfully, but the cases were not executed. Neither test compilation nor a successful app build proves that Codex displays a destination thread.

## Manual verification by the developer

Use a sandbox project and record Desktop and CLI separately. Preserve pending state and continue to make any real permission/question decision in Codex.

1. Record macOS, Codex Desktop version/build and bundle ID, CLI version, effective config roots/custom `CODEX_HOME`, hook trust, and M1–M3 acceptance status.
2. Start a local thread directly in Desktop, compare the sanitized hook `session_id` with the technical thread ID, enable `Precise thread navigation (experimental)`, and click the matching Nudge session. Confirm the visible destination; record URL delivery separately from the displayed thread.
3. Repeat on a resumed Desktop thread without launching a terminal or Nudge app-server.
4. While a question or permission is pending, use the attention CTA. Confirm the request stays pending after link dispatch/app activation and only relevant native-host progress clears it.
5. Turn precise navigation Off and click attention and session rows. Confirm Codex activates with no thread URL delivery.
6. Close Codex before a click; then test multiple windows, Spaces, full-screen, and displays. Record whether the intended thread/window is visible; do not infer exact window routing from app activation.
7. With a sandbox thread, exercise archived/missing behavior. If macOS accepts the URL but Codex does not show that chat, use the activation-only recovery action and record the route as unverified.
8. Test an unavailable target/failed route safely. Confirm bounded Opening state, one activation fallback, visible error/retry on final failure, and no duplicate action after a late native callback.
9. Repeat new/resumed workflows through CLI, including any custom root. Record whether Desktop can route to those threads. Do not describe Desktop activation as terminal/session routing or a CLI permission decision.
10. Change session/turn/attention while navigation is in flight and test sleep/wake. Confirm stale feedback does not attach to a different request or replay attention/completion.
11. Inspect diagnostic output for ID, URL, path, title, preview, or raw error leakage. Confirm hooks/config remain unchanged and Codex keeps working if Nudge closes.
12. Verify menu accessibility, keyboard/VoiceOver, Reduce Motion, notch and non-notch layouts, and the existing expanded scroll cap.

Record each workflow as **host/version / new or resumed / config + trust / toggle / ID mapping / native delivery / displayed destination / pending-state result / limitation**. Keep unknown or unavailable behavior marked pending/unsupported rather than inferred from fixtures.

Stop after M4 handoff. Do not start optional M5 without a separate user instruction.
