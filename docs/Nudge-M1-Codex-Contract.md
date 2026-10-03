# Nudge M1 — Codex Hook Contract Record

Date checked: **2 October 2026**
Status: **official hook shapes reviewed; Desktop/CLI host compatibility remains pending**

This record separates published hook behavior from observations against the installed Codex hosts. The repository fixtures are synthetic and are not Desktop or CLI captures.

## Published hook contract used by M1

The official [Hooks guide](https://learn.chatgpt.com/docs/hooks) documents JSON on stdin with common `session_id`, `cwd`, and `hook_event_name` fields. Turn events expose `turn_id`. `SessionStart` also exposes `source`; `PreToolUse` and `PostToolUse` expose `tool_name` and `tool_use_id`, with `tool_input` and `tool_response`; `UserPromptSubmit` exposes `prompt`; `Stop` exposes `stop_hook_active` and `last_assistant_message`; `Interrupt` identifies the interrupted turn.

Nudge's adapter reads only the event name, bounded session/turn/tool IDs, cwd basename, and tool name. It drops prompt, tool input, tool response, assistant text, transcript path, permission mode, and unknown metadata before encoding the local envelope. The initial M1 implementation treated `Stop` with `stop_hook_active: true` as a continuation and dropped it. M2 removes that assumption: the official field only says the turn was already continued by a Stop; it does not identify suggestion metadata or prove this Stop is nonterminal. M2 now delivers the event and relies on session/turn completion idempotency. Whether extra Stop events occur in the installed Desktop/CLI hosts remains pending live verification.

The documented no-op response depends on the hook event. Exit 0 with no stdout is accepted generally; `Stop` expects JSON at exit 0; `Interrupt` permits exit 0 with no stdout. Nudge therefore emits `{}` only for `Stop` and emits no stdout for other event types. No event returns a decision, changed input, or model-visible context. These rules come from the current [Hooks guide](https://learn.chatgpt.com/docs/hooks); the installed host behavior still requires manual verification.

Hooks can be loaded from `hooks.json` and inline `[hooks]` tables in `config.toml`; the guide says Codex loads both and warns when both representations exist in one layer. Nudge mutates only `hooks.json`, preserves handlers it does not own, and displays this compatibility boundary before installation. [Advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced).

Non-managed hooks require review/trust for their exact current definition. The guide describes `/hooks` in the CLI; Nudge does not read or change trust state. A missing event is shown as unverified, not as proof that trust failed. [Hooks trust review](https://learn.chatgpt.com/docs/hooks).

The published environment-variable table lists `CODEX_HOME` for CLI, IDE extension, app-server, and installers. It does not establish which configuration root the macOS Desktop app uses. The resolver labels the environment/default location as a candidate, supports an explicit folder selection per host, and leaves Desktop coverage unverified until tested. [Environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables).

## Host matrix

| Host workflow | Installed version observed during plan research | Effective config | Trust/reload | Live event coverage |
|---|---|---|---|---|
| Codex Desktop, new local thread | `26.928.31416`, build `12553` candidate | Pending developer confirmation | Pending | Pending |
| Codex Desktop, resumed local thread | Same Desktop candidate | Pending developer confirmation | Pending | Pending |
| Codex CLI | `codex 0.154.0` candidate | Pending developer confirmation, including any `CODEX_HOME` | Pending | Pending |

The Desktop app bundle observed during plan research was `/Applications/ChatGPT.app` with bundle identifier `com.openai.codex`. These observations identify test candidates; they do not prove the hook feature or effective configuration is enabled for either installed host.

## Event and fixture provenance

`NudgeIntegrationTests/Fixtures/Codex/desktop/` and `cli/` contain **synthetic** JSON that mirrors documented command-hook fields. Their only differences are labels/IDs that identify the fixture set. Each includes deliberate prompt/command/output/assistant sentinels so tests can prove those values do not reach the wire. None was captured from a live host, and passing fixture tests is not Desktop or CLI evidence.

The six configured event names are `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, and `Interrupt`. Host event coverage, trust UI, startup/reload behavior, and successful monitoring of new/resumed Desktop threads remain pending in [Nudge-M1-Verification.md](Nudge-M1-Verification.md).

## Activity context implementation (3 October 2026)

The local Nudge wire envelope is now version 2. Updated receivers continue to validate and accept v1 envelopes with their legacy exact tool-summary combinations; new helpers emit v2. V2 permits only bounded summaries from Nudge's finite category/symbol allowlist. Unknown fields, categories, symbol combinations, control characters, and oversize values are rejected. V1 remains the generic-summary fallback; v2 does not carry command text, tool input/output, prompt, transcript, or thread title.

Upgrade the installed helper through Nudge's existing Install Codex Hooks action, which replaces the owner-checked helper before its idempotent hook-config step. Existing hook definitions stay unchanged. A previous Nudge app will reject v2 frames from a new helper and the bridge exits without blocking Codex; recovery is to run the matching version's install action so the bundled helper and app agree. A new app accepts an older v1 helper during upgrade but receives generic summaries until the helper is refreshed.

The adapter classifies a small set of simple shell invocations (Swift/Xcode/JavaScript/Python tests, build, Git status/diff, search, read, and basic file mutation) into fixed summaries. Compound or unknown commands use “Running command”. It inspects but never executes hook input; full command arguments do not enter the wire. The hook has no documented conversation-title field. Rows therefore use short session-ID labels and sanitized `cwd` basename as separate project context.

The monitor now publishes a focused snapshot together with ordered active-session rows. Expanded order is attention first, then most recently started/resumed turn; tool updates do not reorder rows. The existing M1 host matrix remains pending live Desktop and CLI developer verification. No application tests or fixtures prove real host coverage.
