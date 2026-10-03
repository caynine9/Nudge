# Nudge M4 — Codex Navigation Contract

Checked: **3 October 2026**. Status: **official URL shape documented; installed Desktop/CLI behavior and hook-ID mapping remain unverified**.

## Official contract and implementation boundary

The [official Codex Commands reference](https://learn.chatgpt.com/docs/reference/commands#deep-links) lists `codex://threads/<thread-id>` as a local chat link. It also lists `codex://threads/new`; Nudge deliberately rejects the reserved `new` segment and never creates a replacement chat during recovery.

The [official Hooks reference](https://learn.chatgpt.com/docs/hooks#common-input-fields) calls `session_id` the current Codex session ID. The reference does not, by itself, prove that each hook ID emitted by every installed Desktop/CLI version is a routeable technical thread ID. Nudge therefore labels the preference experimental and defaults it off. Enabling it opts into trying the observed local session ID; acceptance requires confirming the destination in Codex.

The app targets `com.openai.codex` and asks AppKit to dispatch the URL to that resolved application with activation enabled. Apple documents targeted URL delivery through [`NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`](https://developer.apple.com/documentation/appkit/nsworkspace/open%28_%3Awithapplicationat%3Aconfiguration%3Acompletionhandler%3A%29). A successful native completion is recorded as `threadRouteDispatched`, never as proof that the requested chat exists or is visible.

## Safety and fallback semantics

- Precise routing is a Nudge-only preference stored under `usePreciseCodexThreadNavigation`. Missing value means Off. It does not modify hooks, Codex trust, `CODEX_HOME`, wire schema, or host configuration.
- When Off, when the ID is missing/invalid/reserved, or when targeted delivery fails or times out, Nudge attempts Desktop activation once. A recovery action retries activation without sending a thread URL.
- Only bounded opaque identifiers are accepted. Empty IDs, controls, `new`, `.` and `..` are rejected. Nudge constructs the URL itself and never accepts a URL from a hook.
- The route wait is capped at 2 seconds; total click navigation is capped at 5 seconds. Activation-only has a 5 second cap. Timeout releases Nudge UI state but cannot cancel a native request already handed to macOS; its late callback cannot update the completed request.
- Diagnostics log only finite outcome/reason names and elapsed milliseconds. IDs, URLs, project/config paths, titles, previews, and raw errors are not included.
- Opening or activating Codex never resolves a question/permission or changes reducer state. Only existing hook progress/lifecycle reconciliation can clear pending attention.
- Nudge failure does not enter hook output and cannot pause Codex or approve a permission.

## Host evidence matrix

Record each row independently; historical version candidates in M1 are not current evidence.

| Scenario | Version/build and effective config | Trust | Session ID equals routeable thread ID? | Destination observed | Result |
|---|---|---|---|---|---|
| Desktop, new local thread | Pending developer | Pending | Pending live capture | Pending | Pending |
| Desktop, resumed local thread | Pending developer | Pending | Pending live capture | Pending | Pending |
| CLI, new local thread | Pending developer | Pending | Pending live capture | Pending | Pending |
| CLI, resumed local thread | Pending developer | Pending | Pending live capture | Pending | Pending |
| Desktop not running / multiple windows | Pending developer | N/A | N/A | Pending | Pending |
| Archived or missing local thread | Pending developer | N/A | N/A | Pending | Pending |

Capture only identifiers and event shape required to compare the IDs; remove prompt, transcript, command, workspace path, and account data. If CLI thread visibility in Desktop or ID equality cannot be established, leave the candidate route unsupported for that scenario and use activation-only guidance. Do not infer host origin from the selected hook-installation menu.

## Limitations

Official documentation establishes the route syntax but not a route acknowledgment for thread existence, archive state, exact window/Space selection, or a universal hook-ID mapping. A route accepted by macOS can still lead to an unexpected or unchanged Codex view. M4 manual acceptance must report native delivery and observed destination separately. Desktop new/resumed behavior remains a required acceptance path; CLI evidence does not substitute for it.
