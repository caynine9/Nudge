# Nudge M3 — Codex Attention Contract

Checked: **3 October 2026**. Status: **public hook reference reviewed; installed Desktop/CLI behavior is unverified**.

This record separates the public command-hook contract from Nudge's candidate request_user_input recognizer and from any host evidence. No live Codex config or trust state was changed.

## Public contract used

The [official Hooks guide](https://learn.chatgpt.com/docs/hooks) lists PermissionRequest, PreToolUse, and PostToolUse among command hook events. PermissionRequest receives session_id, turn_id, tool_name, and tool_input; tool_input.description may be present, but must not be assumed. Its documented field table does **not** provide tool_use_id. By comparison, PreToolUse and PostToolUse document tool_use_id.

Nudge therefore accepts an optional tool_use_id on a permission payload as forward-compatible input, but does not require it. Without one, the current candidate correlation binds only when exactly one active tool has the matching tool_name; ambiguous same-name tools remain pending through their finishes. If repeated permission requests share the same session, turn, and tool name and the host provides no request ID, their local derived identity cannot distinguish them and may coalesce them. This is a known limitation, not a host request ID. The singleton rule is a best-effort host-independent heuristic, not evidence that Desktop/CLI order callbacks identically. Live approval, denial, and cancellation reconciliation remains unverified.

The public guide does not mention request_user_input by name and does not define its argument schema. Nudge currently recognizes only a PreToolUse with exact tool_name == "request_user_input", and reads only tool_input.question or the first tool_input.questions[].question. The question preview is bounded and suppressed when it contains obvious path or secret markers. This exact tool name, schema, and event coverage are candidates requiring a sanitized live capture and separate host verification; unknown shapes produce no question card.

The guide says non-managed hook definitions need review/trust at their current hash. PermissionRequest can return an allow/deny decision; Nudge emits neither and leaves the native Codex prompt in charge. The helper reads bounded input, forwards metadata only, and exits without permission decision output. Its failure remains nonblocking to Codex.

## Local envelope and upgrade

Wire V3 adds PermissionRequest, optional tool_name, and the strict bounded interaction object. V1/V2 remain accepted only with their old payload shape. Question identity derives from kind + session + turn + tool_use_id; permission identity derives from kind + session + turn + optional tool ID, otherwise the tool name. The fallback identifies an observed pending permission, not a host request ID. It does not carry command text, question options, permission description, tool input/output, prompt, transcript path, or secrets.

The installer now manages seven exact event handlers, including PermissionRequest. Installing the refreshed helper/config may require reviewing and trusting the changed Nudge hook definition again. Existing foreign hooks are preserved by the current owner-checked installer; malformed config remains untouched. V2 app + V3 helper rejects the frame and returns control to Codex; run the matching app's install/refresh action to restore a compatible pair. A V3 app accepts older V1/V2 events but cannot mirror attention from them.

## Host evidence

| Host scenario | Version at verification | Effective config / custom home | Trust/reload | Question / permission / resolution evidence |
|---|---|---|---|---|
| Codex Desktop, new local thread | Pending developer | Pending developer | Pending developer | Pending live |
| Codex Desktop, resumed local thread | Pending developer | Pending developer | Pending developer | Pending live |
| Codex CLI, new/resumed thread | Pending developer | Pending developer | Pending developer | Pending live |

M1 listed Desktop 26.928.31416 build 12553 and CLI 0.154.0 as historical test candidates, not as checked installed versions. Do not use those values as acceptance evidence. Question support must not be inferred from a successful CLI fixture or from a separate app-server session.

Sanitized live fixtures still need developer-provided provenance: host/version, workflow, field names/types, turn/tool identity, ordering, and the event that follows native answer/approval/denial/cancel. Remove actual question content, command values, paths, transcript fields, and account secrets unless a redacted excerpt is essential to shape validation. Current M3 fixture coverage in the repository is not yet populated with host captures.

## Unresolved limitations

- Desktop and CLI have no observed M3 host version or live event evidence yet.
- The documented hook guide does not establish that a local function-tool hook fires for request_user_input, nor its argument schema.
- Permission hook inputs do not document a request/tool ID. Exact correlation and denial/cancel resolution can vary; unsupported or ambiguous requests may remain pending until valid progress or turn termination.
- Host origin is absent from V3. An attention CTA always activates Desktop and labels the CLI recovery path; it does not claim exact thread or terminal routing.
