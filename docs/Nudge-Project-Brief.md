# Nudge — Product & Technical Project Brief

> **App name:** Nudge  
> **Platform:** macOS, native Swift / SwiftUI + AppKit  
> **Primary integration:** OpenAI Codex macOS app / Desktop (mandatory) + Codex CLI (also supported)  
> **Product shape:** a focused, animated notch companion for one active coding context  
> **Research snapshot:** 1 October 2026  
> **Status:** architecture / implementation brief

---

## 1. Executive Summary

**Nudge** is a small native macOS companion that turns the MacBook notch into a glanceable, animated status surface for Codex.

It is intentionally **not** a multi-agent operations dashboard.

The primary user workflow is sequential and focus-heavy:

1. choose one project/repository,
2. work on it for a few hours,
3. use ChatGPT for thinking/planning and Codex for implementation,
4. temporarily switch to another app while Codex works,
5. notice when Codex is working, needs attention, asks a question, finishes, fails, or is interrupted,
6. click the notch surface to return to the relevant Codex thread.

The product therefore optimizes for **low cognitive overhead**, not maximum information density.

The notch should feel like a tiny native companion that is:

- useful at a glance,
- quiet when nothing is happening,
- expressive when something changes,
- smooth and polished,
- slightly playful,
- local-first,
- and disposable: if Nudge is closed or broken, normal Codex operation must continue.

The visual identity should include an **original character/mascot** that lives at the left edge of the notch, with the phase icon on the right in minimized presentation (user-confirmed placement). It should have small contextual animations for thinking, tool use, waiting, completion, interruption, and errors.

The recommended architecture is:

```text
Codex lifecycle hooks
        │
        ▼
NudgeBridge
small native helper
        │
        │  JSON envelope
        ▼
per-user Unix domain socket
        │
        ▼
Event Decoder + Canonicalizer
        │
        ▼
Deterministic Session Reducer
        │
        ├─────────────► Pending Permission / Question Queue
        │
        ▼
App State (@MainActor)
        │
        ▼
NSPanel + SwiftUI Notch UI
        │
        ├─────────────► Mascot / Motion Engine
        └─────────────► Codex Jumper
```

Optional enrichment can later use Codex app-server metadata and Codex Desktop deep links, but **hooks should remain the live activity source in the MVP**.

### Mandatory Codex Desktop + CLI support

**Codex Desktop support is mandatory for MVP.** Nudge must monitor local sessions and turns initiated directly in the Codex macOS app, including new and resumed threads. Users must not need to start Codex from a terminal or through a Nudge-owned app-server for Desktop activity to appear.

Codex CLI is also supported, but **CLI-only integration does not satisfy MVP acceptance criteria**. The app name is **Nudge**; Codex identifies the integration, not the product name.

For both supported hosts, verify working/thinking activity, tool progress, questions and permissions where available, successful completion, failure, and interruption. Desktop attention actions must return the user to Codex Desktop, preferably to the relevant thread, with app activation as fallback.

The hook-first architecture is an implementation approach, not proof of Desktop compatibility. Before considering live integration complete, validate the actual lifecycle events emitted by the target Codex Desktop and CLI versions. Synthetic events and CLI tests alone cannot establish Desktop support. If Desktop events are unavailable through the proposed hooks, investigate a supported local integration path and document the limitation; do not silently reduce scope to CLI-only or declare the MVP complete.

The optional app-server enrichment layer does not make Desktop support optional, and a separately launched app-server must not be assumed to observe existing Desktop threads. Remote/cloud execution contexts are outside the initial local macOS MVP unless explicitly added to scope.

---

# 2. Why Build This Instead of Recreating Vibe Island?

The goal is **not**:

> “Make a cheaper Vibe Island.”

The useful goal is:

> “Make a tiny Codex-first utility that fits a single-context workflow better than a multi-agent dashboard.”

A broad tool such as Vibe Island or Code Island has to solve:

- many providers,
- many terminal emulators,
- many concurrent sessions,
- multi-repo monitoring,
- provider-specific permissions,
- quota APIs,
- multiple configuration formats,
- large settings surfaces,
- many edge cases unrelated to the actual user workflow.

Nudge can deliberately avoid most of this.

### Core product advantage

Nudge can be opinionated:

- Codex-first.
- Collapsed gives one **focused session/project** visual priority. Hover opens the expanded session list directly; leaving closes it after a short hysteresis delay. There is no separate hover-peek or persistent pin (user clarification, 3 October 2026).
- Expanded may list every detected active Codex session as direct rows. Keep its viewport compact and fixed at 10 pt above its one-session expanded height, then scroll; this is context glanceability, not a session history/fleet dashboard.
- Native Codex notifications remain useful; Nudge does not have to duplicate every notification feature.
- Usage/quota tracking is optional and can be omitted from MVP.
- No need for session “fleet management” controls or history.
- No requirement to support Claude, Gemini, Cursor, OpenCode, etc. initially.
- A stronger personality and more polished single-session animation can be prioritized instead.

This dramatically reduces surface area.

---

# 3. Reference Project Analysis

Two projects are especially useful:

1. **Vibe Notch** — strongest reference for the original native notch interaction pattern and Claude hook → socket architecture.
2. **Code Island** — strongest reference for Codex-specific lifecycle quirks and cross-provider abstractions.

They should not be treated the same from a licensing perspective.

---

# 4. Vibe Notch — What It Teaches Us

Repository:

- <https://github.com/farouqaldori/vibe-notch>

License:

- **Apache-2.0**

Vibe Notch is a native macOS notch app built around Claude Code. Its public architecture is straightforward:

```text
Claude Code hooks
    │
    ▼
local hook scripts / bridge
    │
    ▼
Unix domain socket
    │
    ▼
native macOS app
    │
    ▼
notch overlay + permission UI + session views
```

Its main value to Nudge is not Claude-specific parsing. The reusable lessons are the **macOS shell**, IPC pattern, lifecycle behavior, and production hardening that accumulated from real users.

## 4.1 Architectural lessons worth adopting

### Native event-driven IPC

A hook should not communicate through:

- polling a file every second,
- scraping a Codex window,
- Accessibility API as the primary event source,
- repeatedly checking running processes.

Instead:

```text
hook fires
→ bridge receives JSON
→ bridge forwards event over local socket
→ app updates immediately
```

This has several benefits:

- almost-zero idle CPU,
- very low latency,
- clean decoupling between Codex and UI,
- app can remain a normal menu-bar process,
- helper can be independently testable.

### `LSUIElement`

Nudge should behave as an accessory/menu-bar style application:

- no normal Dock icon by default,
- no normal app window always visible,
- settings accessible through menu bar / notch controls.

### Notch as a real window, not fake layout inside a menu-bar popover

The notch overlay should be implemented as a custom top-level `NSPanel` / `NSWindow`, with SwiftUI hosted inside it.

This permits:

- precise top-center placement,
- interaction above normal application windows,
- smooth size transitions,
- transparent background,
- hover expansion,
- control over Spaces/full-screen behavior.

---

## 4.2 Vibe Notch production issues we should treat as requirements

Vibe Notch's release history exposes several classes of bugs that are easy to underestimate.

### A. Unix socket permissions matter

An earlier Vibe Notch socket was world-writable (`0777`) and was changed to owner-only (`0600`).

**Nudge requirement:**

- socket owned by current user,
- mode `0600`,
- reject messages from unexpected peers when practical,
- validate event schema before mutation,
- never trust arbitrary JSON simply because it reached the socket.

Recommended path:

```text
/tmp/nudge-<uid>.sock
```

Why `/tmp` instead of a deeply nested Application Support path?

Unix domain socket paths on macOS have relatively short path limits. A per-user `/tmp` socket avoids accidental failures on long home-directory names.

Additional hardening:

- use UID in socket filename,
- remove stale socket on startup only after validating it is actually a socket,
- consider `getpeereid()` / local peer credential validation,
- refuse payloads with unknown schema versions or unknown event types.

---

### B. Sleep / wake is an actual UI lifecycle case

Vibe Notch fixed repeated notch bouncing/retraction after wake from sleep.

Nudge should explicitly handle:

```text
NSWorkspace.willSleepNotification
NSWorkspace.didWakeNotification
```

On sleep:

- pause nonessential animations,
- invalidate auto-collapse timers,
- do not queue animation transitions.

On wake:

- re-read current presentation state,
- reconcile active session,
- rebuild exactly one animation state,
- do not replay stale completion animations.

---

### C. Stable IDs prevent flicker

Vibe Notch fixed chat/message flickering by stabilizing identifiers.

Nudge should never generate random SwiftUI IDs during every render.

Use stable identifiers:

```swift
struct SessionID: Hashable, Codable {
    let rawValue: String
}

struct TurnID: Hashable, Codable {
    let rawValue: String
}
```

For derived UI items:

```text
sessionID + turnID + eventKind + toolCallID
```

should be preferred over random UUID generation when the source already provides stable identity.

---

### D. Heavy parsing must stay off the main actor

Vibe Notch moved image base64 decoding off the main thread.

Nudge should apply the broader rule:

> The main actor renders UI and applies already-normalized state. It should not parse transcripts, decode large JSON blobs, inspect processes, or scan files.

---

### E. Animation geometry needs notch-aware clipping

Vibe Notch fixed spinner/checkmark clipping around the physical notch curve.

For Nudge:

- keep semantic content away from rounded inner shoulders,
- mascot must have a notch-safe bounding box,
- completion/error glyphs need safe inset,
- do not assume the visible rectangle equals the usable rectangle.

---

### F. Version-sensitive hooks can break configuration

Vibe Notch hit a compatibility problem where hook keys unsupported by an older agent version could invalidate a settings file.

For Nudge:

- register only documented/current Codex events,
- unknown future events must not be required for startup,
- installation should be reversible,
- malformed or incompatible configuration must fail safely,
- Nudge should never leave Codex unusable because its own hook install failed.

---

# 5. Code Island — What It Teaches Us

Repository:

- <https://github.com/rifqiakrm/code-island>

License:

- **GNU GPLv3**

Code Island supports many agents including Codex, and its Codex path is particularly useful as a study reference.

Its architecture is approximately:

```text
Agent
  │ hook
  ▼
~/.code-island/bin/code-island-<agent>-bridge
  │
  ▼
CodeIslandBridge
  ├─ normalize event name
  ├─ stamp provider/source
  ├─ collect terminal/app metadata
  └─ normalize tool fields
  │
  ▼
/tmp/code-island.sock
  │
  ▼
SessionStore
  │
  ├─ state machine
  ├─ permission queue
  ├─ question queue
  └─ lifecycle cleanup
  │
  ▼
Notch UI
```

This validates the same broad IPC direction proposed for Nudge.

## 5.1 Licensing consequence

Code Island is GPLv3.

If Nudge might ever be distributed under a proprietary license, **do not copy Code Island implementation code, mascot artwork, or GPL-derived source files** into it.

Use Code Island as:

- behavioral research,
- edge-case research,
- protocol research,
- architecture comparison.

Then write an original implementation.

Vibe Notch's Apache-2.0 code is more permissive, but even there it is cleaner to keep Nudge's architecture explicit and original unless there is a compelling component to reuse.

---

# 6. The Most Important Codex Edge Cases Found in Code Island

This section should be treated as an implementation checklist.

---

## 6.1 Duplicate installed hooks can create duplicate UI events

Code Island removes duplicate copies of its own hooks during installation.

Why?

Because a config file can accumulate duplicate hook entries across upgrades/reinstalls. A single Codex event can then execute the helper multiple times.

Symptom:

```text
one actual Codex event
→ six bridge invocations
→ six completion cards
```

### Nudge solution

Installer must be **idempotent**.

Given any existing configuration:

```text
0 Nudge entries → create exactly 1
1 Nudge entry   → leave exactly 1
N Nudge entries → reduce to exactly 1
```

Also add runtime deduplication as a second defense.

Suggested dedupe key:

```text
(session_id, turn_id, hook_event_name, tool_call_id?, normalized payload hash)
```

with a very short in-memory TTL for identical events.

Installer correctness remains primary; runtime dedupe is a safety net.

---

## 6.2 Codex session lifecycle cannot rely only on PID liveness

A naive app might assume:

```text
Codex process alive = session alive
Codex process dead  = session dead
```

This is unreliable.

Hook subprocess ancestry can include long-lived processes or daemons.

### Nudge solution

Use semantic lifecycle state first.

Possible signals:

1. hook events,
2. current turn status,
3. optional thread/app-server reconciliation,
4. process liveness only as a weak fallback.

If process liveness is ever used, also capture **process start time**.

Why?

PID values can be reused.

```text
old process PID 551 dies
new unrelated process gets PID 551
kill(551, 0) says "alive"
```

So compare:

```text
PID + process start timestamp
```

rather than PID alone.

---

## 6.3 Do not expire a session during a long-running tool

Suppose Codex emits:

```text
PreToolUse
```

and a command runs for seven minutes.

There may be no new event until:

```text
PostToolUse
```

An inactivity cleaner such as:

```text
if no event for 5 minutes:
    kill session
```

would incorrectly declare the session dead.

### Nudge rule

Inactivity cleanup can apply to a session in a calm/idle phase.

It must **not** terminate a session solely because it is quiet while phase is:

```text
.toolUse
.waitingPermission
.waitingInput
.thinking
```

---

## 6.4 A resumed Codex thread may not immediately produce `SessionStart`

Code Island observed an important resume behavior: a resumed thread can exist before the normal hook flow provides a fresh `SessionStart`.

The safe design principle is:

> Never require `SessionStart` to have been observed before accepting another valid event.

### Session creation strategy

Any trusted canonical event can lazily materialize a missing session:

```swift
if sessions[event.sessionID] == nil {
    sessions[event.sessionID] = Session.placeholder(from: event)
}
```

Later events can enrich:

- cwd,
- title,
- thread name,
- project,
- host application.

This is more robust than:

```text
if not SessionStart:
    ignore event
```

---

## 6.5 CWD can be incomplete initially

A session might first appear with little metadata and later provide a reliable working directory.

Use:

```text
unknown / placeholder cwd
```

temporarily, then replace it once a valid path arrives.

Do not lock a session permanently to a bad initial directory.

---

## 6.6 Codex can emit a separate suggestion-style `Stop`

Code Island handles a Codex-specific behavior where a follow-up `Stop` can contain suggestion data rather than a second real assistant completion.

If Nudge treated every `Stop` as a new completion, the user could see:

```text
✓ Finished
✓ Finished
```

for one turn.

### Nudge normalization

A `Stop` should be inspected before presentation.

If its assistant payload represents suggestion metadata rather than a new substantive response:

- update optional suggestion metadata,
- do not replay completion sound,
- do not replay mascot celebration,
- do not create a second completion card.

The reducer should also be state-aware:

```text
already completed/idle for same turn
+ suggestion-only stop
= no new completion transition
```

---

## 6.7 `request_user_input` is not the same as a normal permission

Codex can surface a `request_user_input` tool-style event.

Code Island mirrors the question in the notch but does not attempt to answer it programmatically through a hook.

### Recommended Nudge behavior

For MVP:

```text
Codex asks a question
        │
        ▼
Nudge expands
        │
        ├─ displays a concise question preview
        └─ button: "Answer in Codex"
                         │
                         ▼
                   jump to Codex
```

Do **not** fabricate an unsupported answer-substitution mechanism.

This UX is still valuable because the notch tells the user exactly *why* Codex needs attention.

---

## 6.8 A permission/question can be resolved outside Nudge

A user can see the notch prompt but switch to Codex and answer there instead.

If Nudge does not reconcile this, its UI can remain stuck forever:

```text
"Codex needs approval"
```

even though Codex has already continued.

### Resolution rule

Any later event proving progress has resumed should dismiss obsolete pending interaction state.

For example:

```text
pending request_user_input
→ PostToolUse for same tool/turn
→ dismiss pending question
```

Similarly:

```text
pending permission
→ subsequent tool/turn progress indicating decision occurred elsewhere
→ clear stale permission card
```

This transition should be explicit in tests.

---

## 6.9 Permission hook features are not symmetric with Claude

Do not assume Claude's full permission response schema works in Codex.

Code Island specifically accounts for Codex limitations around persistence.

### MVP recommendation

Support either:

**MVP-A, safest:**

```text
mirror permission request
→ "Open Codex"
→ decision happens natively in Codex
```

or:

**MVP-B:**

```text
Allow Once
Deny
```

if the current Codex hook contract is validated and covered by tests.

Do **not** ship:

```text
Always Allow
Bypass Everything
```

in the first version.

Those actions have larger security semantics and can require manipulating Codex rule files correctly.

---

## 6.10 Persistent Codex allow rules are deceptively complicated

Code Island uses Codex rule persistence for broader allow behavior.

The edge cases include:

- Bash prefix semantics,
- quotes stripped by argument parsing,
- empty prefix invalidity,
- non-Bash tools not mapping cleanly to the same model,
- control characters/newlines potentially corrupting a rules file,
- heredocs,
- non-printable data,
- duplicate rules.

This is not worth owning in Nudge's MVP.

### Product decision

**No persistent permission modification in MVP.**

If implemented later:

- use a dedicated rule writer,
- validate tokens strictly,
- parse existing syntax safely,
- perform atomic writes,
- preserve user-authored rules,
- never broaden a rule silently,
- show the exact rule being added before user confirms.

---

## 6.11 Malformed existing configuration must never be overwritten

If `~/.codex/hooks.json` exists but cannot be parsed:

**Wrong:**

```text
parse fails
→ assume empty
→ overwrite with Nudge config
```

**Correct:**

```text
parse fails
→ abort installation
→ preserve file byte-for-byte
→ show actionable repair instructions
```

No destructive fallback.

---

## 6.12 Configuration merging must preserve foreign hooks

The installer owns only its own entries.

Algorithm:

```text
read existing config
parse
find Nudge-owned entries
remove only Nudge-owned duplicates/outdated variants
insert canonical current Nudge entry
preserve everything else
write only if changed
```

Before first mutation:

```text
hooks.json → hooks.json.nudge.bak
```

Use atomic replacement.

---

## 6.13 Codex feature configuration can exist in multiple TOML shapes

Code Island defensively handles variations of Codex config structure.

String-based “find `[features]` and append a line” editing is brittle.

### Preferred Nudge approach

Best:

1. **avoid modifying `config.toml` if current Codex no longer needs an explicit hooks feature flag**, or
2. use a proper TOML parser if mutation is required.

If an unfamiliar structure is encountered:

```text
bail safely
```

instead of adding a conflicting table.

---

## 6.14 Treat unknown event names as invalid input

Code Island normalizes multiple providers into a canonical event vocabulary, then rejects unknown raw names.

Even though Nudge only supports Codex, the same principle is valuable.

Canonical events should be an enum, not arbitrary strings:

```swift
enum CodexLifecycleEvent: String, Codable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case interrupt = "Interrupt"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
}
```

Unknown event:

```text
log diagnostic
drop payload
do not create phantom session
```

---

## 6.15 Transcript files are not a stable API

Code Island can use Codex transcript files as a fallback for missing assistant text.

OpenAI documentation warns that transcript format/path details should not be treated as a stable integration contract.

### Nudge rule

Transcript reading is **best-effort fallback only**.

Never make core session detection depend on parsing rollout JSONL.

Place behind:

```swift
protocol AssistantMessageFallback {
    func recoverMessage(...) async -> String?
}
```

If parsing stops working after a Codex update:

- Nudge still works,
- only optional completion preview becomes unavailable.

---

## 6.16 Codex Desktop jump navigation has edge cases

Codex Desktop supports `codex://` URLs for thread navigation.

Known behavior in public Codex issues includes:

- `codex://threads/<thread-id>` can open an existing local thread,
- `codex://threads/new?path=...` can create/open a workspace-oriented thread,
- invoking via macOS bundle ID can be more reliable than targeting app path,
- archived thread links can fail,
- deep-link window targeting is not currently a stable documented control,
- message-level/turn-level jump is still an open feature request.

### Recommended navigation layer

```swift
protocol CodexNavigator {
    func openThread(_ id: String) async -> NavigationResult
    func activateCodex() async
}
```

Preferred experimental path:

```bash
open -b com.openai.codex 'codex://threads/<thread-id>'
```

Fallback:

```text
activate app bundle com.openai.codex
```

Do not couple UI code to the deep-link syntax.

Feature flag it:

```text
Use precise Codex thread navigation
[On/Off]
```

If precise navigation fails, app activation should still work.

---

# 7. Product Positioning

## One-line definition

> **Nudge is a tiny native macOS companion that lets you glance at what Codex is doing without leaving your current context.**

Alternative marketing line:

> **Codex is working. Nudge lets you know when it matters.**

---

# 8. Product Principles

## 8.1 One active context first

Nudge should not encourage juggling projects.

The default experience shows:

```text
current focused project
current Codex turn
current state
```

Additional sessions can exist internally, but the UI should stay calm.

---

## 8.2 Attention only when attention is useful

Nudge expands automatically for:

- permission needed,
- user input needed,
- completion,
- failure/interruption that matters.

It should not expand for every tool call.

---

## 8.3 Fun, not noisy

Personality should come from:

- mascot posture,
- micro-motion,
- timing,
- tiny expressions,
- subtle completion flourish.

Not from:

- constant bouncing,
- flashing,
- rainbow effects,
- sounds on every tool invocation.

---

## 8.4 Codex remains fully usable without Nudge

This is a hard architectural invariant.

If:

```text
Nudge crashes
bridge cannot connect
socket disappears
hook times out
```

then normal Codex should continue.

Nudge must never become a mandatory control plane for ordinary coding.

---

## 8.5 Local-first and private

Default:

- no cloud backend,
- no account,
- no telemetry,
- no full prompt history storage,
- no persistent transcript cache.

The app processes only enough local event metadata to render useful state.

---

# 9. Goals

## MVP goals

Nudge should:

1. live naturally around the MacBook notch,
2. detect active local Codex lifecycle activity from both the Codex macOS app and Codex CLI,
3. display project/session identity,
4. show working/thinking state,
5. show current tool in a concise human-friendly form,
6. show “needs attention” state,
7. mirror `request_user_input` prompts,
8. show completion state + concise assistant response,
9. distinguish interrupted/failed state from successful completion,
10. jump back to Codex,
11. have a polished original mascot,
12. survive sleep/wake and Codex restarts cleanly,
13. install/uninstall hooks safely.

---

# 10. Explicit Non-Goals for MVP

Do **not** build these initially:

- Claude support.
- Gemini support.
- Cursor support.
- OpenCode support.
- Fleet dashboard.
- Multi-repository command center.
- Full conversation browser.
- Editing prompts inside the notch.
- Persistent “always allow” Codex rules.
- Bypass-permissions button.
- Built-in ChatGPT client.
- Usage/quota dashboard.
- Cloud sync.
- Mobile companion.
- App Store distribution.
- Custom theme marketplace.
- Full terminal tab routing.

Avoiding these is what keeps the project small enough to polish.

---

# 11. Primary User Journey

## Scenario A — normal work

```text
User opens Detinvite project in Codex
             │
             ▼
Nudge notices SessionStart / turn activity
             │
             ▼
notch:
┌──────────────────────────────┐
│ Detinvite       thinking  ◉  │
└──────────────────────────────┘
                             ^
                           mascot
```

User switches to browser/ChatGPT.

Codex invokes tools:

```text
┌──────────────────────────────┐
│ Detinvite   Running tests ◉  │
└──────────────────────────────┘
```

No notification sound required.

Codex completes:

```text
        expands smoothly
┌────────────────────────────────────────┐
│ ✓ Done                         ✦  ◉     │
│ Detinvite                               │
│ Implemented event configuration...     │
│                              Open Codex │
└────────────────────────────────────────┘
```

Mascot performs one small completion celebration.

After ~3 seconds:

```text
completion card retracts
→ calm idle notch
```

---

## Scenario B — question

```text
Codex calls request_user_input
             │
             ▼
Nudge changes to attention state
             │
             ▼
┌────────────────────────────────────────┐
│ Codex has a question              ? ◉  │
│                                    │    │
│ Which migration strategy should   │    │
│ be used for existing events?      │    │
│                                    │    │
│                    [Answer in Codex]    │
└────────────────────────────────────────┘
```

The pending question stays active until relevant Codex progress proves it was answered, or an explicit lifecycle transition invalidates the request. Opening Codex alone is not proof of resolution. The panel may collapse when navigating to Codex, but pending attention must remain represented until it is resolved.

Do not clear an unanswered question solely because time has elapsed.

---

## Scenario C — permission

MVP option:

```text
┌────────────────────────────────────────┐
│ Permission needed                 ! ◉  │
│ Run: rm -rf build/cache                │
│                                        │
│                         [Open Codex]    │
└────────────────────────────────────────┘
```

P1 option after protocol validation:

```text
[Deny] [Allow Once]
```

No “Always Allow” initially.

---

# 12. Interaction States

The internal session lifecycle should be richer than the visible UI.

Recommended domain model:

```swift
enum SessionPhase: Equatable {
    case discovered
    case idle
    case thinking
    case toolUse(ToolActivity)
    case waitingPermission(PendingPermission)
    case waitingInput(PendingQuestion)
    case completed(CompletionSummary)
    case failed(FailureSummary)
    case interrupted
    case ended
}
```

### State priority

If multiple pieces of metadata are present, UI priority is:

```text
waitingPermission
    >
waitingInput
    >
failed
    >
interrupted
    >
toolUse
    >
thinking
    >
completed (transient)
    >
idle
```

A stale tool label must not hide a permission request.

---

# 13. Visible Notch Modes

Separate **session phase** from **presentation mode**.

```swift
enum NotchPresentation {
    case collapsed
    case expanded
    case attention
    case confirmation
}
```

This prevents domain events from directly controlling window dimensions.

Example:

```text
phase = toolUse
presentation = collapsed

phase = completed
presentation = expanded for 3 seconds

phase = waitingInput
presentation = attention until resolved
```

---

# 14. UI Geometry

Starting values, not hard constraints:

### Collapsed

```text
width: 250–300 pt
height: 32–38 pt
```

Contents:

```text
project label
status/tool summary
mascot
```

### Hover / expanded monitor

```text
width: 480 pt
height: 160 pt for one session, 170 pt for multiple sessions
        plus the camera band on notched displays
```

Hover opens the expanded monitor directly, with usage, project groups, active-session rows, and bounded tool detail. Additional sessions scroll within this fixed viewport. Leaving closes it after the hysteresis delay; there is no intermediate peek or persistent pin.

### Completion expanded

```text
width: 500–620 pt
height: content-adaptive, target 180–300 pt
```

### Attention view

```text
width: 520–620 pt
height: 220–380 pt
```

Question UI may need more vertical room.

Avoid huge fixed cards.

---

# 15. The Mascot

## Working mascot concept: “Nudgie”

This should be an **original** character.

Do not reuse:

- Vibe Notch mascot art,
- Code Island pixel mascots,
- their silhouettes,
- their animation frames.

### Visual concept

A tiny rounded “cursor creature” / capsule/blob that sits partly tucked against the **left inner edge of the notch**.

Possible shape:

```text
       notch
┌───────────────────────╮
│                 ◉  •ᴗ•│
╰───────────────────────╯
                         ^
                       Nudgie
```

The body can be:

- rounded square / capsule,
- two expressive eyes,
- tiny optional hands,
- one subtle status accent,
- designed with vectors/SwiftUI Canvas.

It should be recognizable even at ~22–28 pt.

---

# 16. Mascot Personality States

## Idle

Behavior:

- mostly still,
- blink every ~8–14 seconds,
- rare 1–2 pt “breath” motion,
- no perpetual bobbing.

Goal:

> alive, but not distracting.

---

## Thinking

Behavior:

- slight forward/back lean,
- eyes glance toward status text,
- subtle two-step bob,
- optional tiny thought dot.

Cadence should be slow.

No full-body bounce at 60 FPS forever.

---

## Tool use

Tool-specific micro-expression can be generated from category rather than individual commands.

Examples:

```text
Shell       → tiny terminal glyph
Read        → eyes scan left/right
Write/Edit  → tiny pencil/typing gesture
Test        → tiny spinner/spark
Web         → tiny globe
Git         → branch glyph
```

Do not build 50 animations for 50 tool names.

Normalize into ~5–7 categories.

---

## Waiting for permission

Behavior:

- mascot leans slightly out from the left edge,
- performs one “tap” against notch edge,
- eyebrow / alert expression,
- stops animating aggressively after first attention motion.

This state should convey:

> “hey, when you have a second…”

not:

> “EMERGENCY!!!”

---

## Waiting for user input

Behavior:

- small `?` bubble,
- curious face,
- occasional blink.

---

## Completed

One short sequence:

```text
anticipation 100 ms
→ hop 220–280 ms
→ 1–3 micro-sparkles
→ settle 250 ms
```

Total flourish:

```text
< 700 ms
```

Do not loop.

---

## Failed

Behavior:

- one quick shake,
- then slightly tilted / concerned expression.

No continuous red flashing.

---

## Interrupted

Behavior:

- tiny deflate/sigh motion,
- neutral icon,
- return to calm state.

---

# 17. Motion System

A polished animation system should be intentional, not a pile of `.animation(.spring)` modifiers.

Create semantic motion tokens.

```swift
enum MotionToken {
    static let expandResponse: Double = 0.34
    static let expandDamping: Double = 0.82

    static let collapseResponse: Double = 0.28
    static let collapseDamping: Double = 0.88

    static let mascotHopResponse: Double = 0.26
    static let mascotHopDamping: Double = 0.66
}
```

Exact values should be tuned visually.

---

## 17.1 Expansion motion

Desired feel:

- slight anticipation,
- confident expansion,
- no rubber-band overshoot,
- physical attachment to notch.

Use spring-driven frame changes.

Avoid:

```text
fade entire window out
resize
fade entire window in
```

The shell should appear to morph.

---

## 17.2 `matchedGeometryEffect`

Useful for:

- project label moving between collapsed/expanded layouts,
- status icon transitions,
- mascot repositioning,
- tool label becoming detail heading.

This helps the expansion feel like one physical object rather than two unrelated views.

---

## 17.3 Keyframe/phase animation

Use dedicated state for mascot sequences.

Example:

```swift
enum MascotAnimation {
    case resting
    case thinking
    case attentionTap
    case celebrate
    case errorShake
}
```

The reducer should request semantic animation:

```text
turn completed → celebrate once
```

The view decides how that looks.

Do not put business logic inside Canvas draw code.

---

## 17.4 Hover hysteresis

Without hysteresis, top-edge UI feels twitchy.

Suggested:

```text
hover enter:
    wait ~80–120 ms
    then expanded

hover exit:
    wait ~250–400 ms
    then collapse
```

If pointer returns during exit delay:

```text
cancel collapse
```

---

## 17.5 Reduced Motion

Respect macOS accessibility settings.

With Reduce Motion enabled:

- no bounce,
- no mascot hop,
- no shake,
- use opacity + short scale transitions,
- expansion remains functional.

---

# 18. Performance Rules for Animation

Transparent top-level overlays can consume surprising CPU if continuously animated.

Hard rules:

1. **No 60 FPS idle loop.**
2. Only create high-frequency animation while an actual transition is occurring.
3. Idle mascot blink should be scheduled sparsely.
4. Pixel/frame animation, if used, can run ~6–12 FPS rather than display refresh rate.
5. Tool-use animation pauses if the panel is not visible/relevant.
6. Sleep pauses all decorative animation.
7. Completion animation plays once.
8. Off-main decoding/parsing.
9. No `Timer.publish(every: 0.1)` permanently alive for UI cosmetics.

Performance target, not a contractual promise:

```text
idle CPU: effectively ~0%
memory: small native utility footprint
event-to-visible-state latency: subjectively instant
```

---

# 19. Visual Design Direction

## Shell

Base:

- black/dark notch-integrated background,
- rounded lower shoulders,
- no visible top boundary where physical notch begins.

Expanded state can use:

- subtly elevated black,
- optional light material layer,
- very restrained border.

Avoid making it look like a random floating card.

---

## Typography

Primary:

```text
SF Pro
```

Technical tool summaries:

```text
SF Mono
```

Hierarchy:

```text
Project         semibold
Status          regular
Tool metadata   mono / secondary
Assistant text  regular
```

---

## Color

Keep most chrome neutral.

Semantic accents:

```text
working       cool neutral / subtle blue
attention     amber
complete      green
failed        red
interrupted   muted orange/gray
```

Do not repaint the entire notch per state.

Status should remain understandable without color alone.

---

# 20. Suggested Component Tree

```text
NotchRootView
├── NotchShell
├── CollapsedStatusView
│   ├── ProjectLabel
│   ├── ActivityLabel
│   └── NudgeMascot
├── PeekView
│   ├── CurrentToolView
│   └── TurnDurationView
├── CompletionView
│   ├── CompletionHeader
│   ├── AssistantPreview
│   └── OpenCodexButton
├── PermissionView
│   ├── ToolSummary
│   └── PermissionActions
├── QuestionView
│   ├── QuestionPreview
│   └── AnswerInCodexButton
└── FailureView
```

---

# 21. Recommended Technical Architecture

## 21.1 Stack

Recommended:

- Swift 6 mode if practical; otherwise current Xcode Swift toolchain,
- SwiftUI for UI composition,
- AppKit for windowing, app lifecycle, activation, screens,
- Foundation Codable for IPC envelope,
- POSIX Unix domain sockets / Network-compatible local IPC,
- OSLog for diagnostics,
- no third-party runtime dependencies unless they clearly reduce risk.

Minimum OS:

### Suggested for personal-first build

```text
macOS 15+
```

Reason:

- fewer compatibility branches,
- modern SwiftUI APIs,
- target machine is modern.

If broader distribution matters later:

```text
macOS 14+
```

can be evaluated.

---

# 22. Xcode Targets

Recommended project shape:

```text
Nudge.xcodeproj

Targets:
├── Nudge
│   macOS application
│
├── NudgeBridge
│   command-line helper
│
├── NudgeCoreTests
│
└── NudgeIntegrationTests
```

Optionally extract domain types into Swift Package modules later.

Do not over-modularize day one.

---

# 23. Suggested Source Tree

```text
Nudge/
├── App/
│   ├── NudgeApp.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
│
├── Core/
│   ├── Models/
│   │   ├── Session.swift
│   │   ├── SessionPhase.swift
│   │   ├── ToolActivity.swift
│   │   ├── PendingPermission.swift
│   │   └── PendingQuestion.swift
│   │
│   ├── Events/
│   │   ├── NudgeEvent.swift
│   │   ├── CodexHookPayload.swift
│   │   └── EventNormalizer.swift
│   │
│   └── Reducer/
│       ├── SessionReducer.swift
│       └── PresentationReducer.swift
│
├── Integration/
│   └── Codex/
│       ├── Hooks/
│       │   ├── CodexHookInstaller.swift
│       │   ├── HookConfigMerger.swift
│       │   └── HookTrustMonitor.swift
│       │
│       ├── Navigation/
│       │   ├── CodexNavigator.swift
│       │   └── CodexDeepLinkNavigator.swift
│       │
│       ├── AppServer/
│       │   └── CodexMetadataReconciler.swift
│       │
│       └── Fallback/
│           └── TranscriptMessageFallback.swift
│
├── IPC/
│   ├── NudgeSocketServer.swift
│   ├── PeerValidator.swift
│   └── WireEnvelope.swift
│
├── UI/
│   ├── Notch/
│   │   ├── NotchPanelController.swift
│   │   ├── NotchGeometry.swift
│   │   ├── NotchRootView.swift
│   │   └── NotchShell.swift
│   │
│   ├── Components/
│   │   ├── ActivityLabel.swift
│   │   ├── AssistantPreview.swift
│   │   └── StatusGlyph.swift
│   │
│   ├── Mascot/
│   │   ├── NudgeMascot.swift
│   │   ├── MascotPose.swift
│   │   ├── MascotAnimation.swift
│   │   └── MascotCanvas.swift
│   │
│   └── Motion/
│       ├── MotionTokens.swift
│       └── ReducedMotionPolicy.swift
│
├── Services/
│   ├── SessionFocusController.swift
│   ├── SleepWakeObserver.swift
│   └── DiagnosticsStore.swift
│
├── Settings/
│   ├── SettingsView.swift
│   └── NudgeSettings.swift
│
└── Support/
    ├── Logging.swift
    └── AtomicFileWriter.swift

NudgeBridge/
├── main.swift
├── HookInputDecoder.swift
├── ToolInputNormalizer.swift
├── SocketClient.swift
└── BridgeDiagnostics.swift
```

---

# 24. IPC Wire Format

Never pass raw provider payloads directly into the UI store.

Bridge should emit a versioned envelope.

Example:

```json
{
  "schema_version": 1,
  "source": "codex",
  "event": "PreToolUse",
  "session_id": "abc",
  "turn_id": "turn-123",
  "timestamp": "2026-10-01T10:20:30Z",
  "cwd": "/Users/me/projects/detinvite",
  "tool": {
    "name": "shell",
    "category": "shell",
    "summary": "npm test"
  },
  "raw_metadata": {}
}
```

Keep `raw_metadata` either:

- absent in release mode,
- or tightly whitelisted.

Do not forward arbitrary large tool payloads to the UI process unless needed.

---

# 25. Event Pipeline

```text
Codex
 │
 │ stdin JSON to lifecycle hook
 ▼
NudgeBridge
 │
 ├─ validate required fields
 ├─ normalize event
 ├─ normalize tool name/category
 ├─ derive project label from cwd
 ├─ redact large/sensitive payloads
 └─ create WireEnvelope v1
 │
 ▼
Unix socket
 │
 ▼
NudgeSocketServer
 │
 ├─ peer validation
 ├─ max payload size
 └─ JSON decode
 │
 ▼
EventNormalizer
 │
 ▼
SessionReducer
 │
 ▼
AppState
 │
 ▼
PresentationReducer
 │
 ▼
Notch UI
```

The reducer should be deterministic:

```text
(previousState, event) → newState
```

This makes event fixture testing straightforward.

---

# 26. Hook Events to Install

Start with:

```text
SessionStart
SessionEnd
UserPromptSubmit
PreToolUse
PostToolUse
PermissionRequest
Stop
Interrupt
```

Optional after MVP:

```text
SubagentStart
SubagentStop
PreCompact
PostCompact
```

Subagents should not dominate the main UI.

A subagent can update tool/activity text without causing:

- completion celebration,
- completion sound,
- main turn done state.

---

# 27. Hook Trust

Current Codex hooks are subject to trust review.

Nudge onboarding must not pretend hook install is always invisible.

Suggested onboarding:

```text
1. Detect Codex
2. Install Nudge hook entries safely
3. Send a test event
4. If no event arrives:
   "Codex has not trusted the Nudge hooks yet."
5. Show a short instruction to review/approve them in Codex
6. Re-test
```

A changed hook definition can require a new trust decision.

Therefore:

- keep launcher command stable across updates where possible,
- avoid rewriting config unnecessarily,
- skip write if canonical configuration already matches.

---

# 28. Hook Installer Contract

`CodexHookInstaller` should expose:

```swift
enum HookInstallResult {
    case installed
    case alreadyInstalled
    case needsTrust
    case malformedExistingConfig(path: URL)
    case unsupportedConfiguration(reason: String)
    case permissionDenied
    case failed(Error)
}
```

It should also support:

```swift
func uninstallPreservingForeignHooks()
```

Uninstall should remove **only Nudge-owned entries**.

---

# 29. Bridge Failure Behavior

For non-blocking events:

```text
socket unavailable
→ bridge exits quickly
→ Codex continues
```

For permission events:

Nudge must avoid a situation where the hook stalls Codex because Nudge is not running.

Recommended behavior:

1. attempt local connection with short timeout,
2. if Nudge is unavailable, do not auto-allow,
3. return control so Codex's native approval UI remains authoritative.

The exact no-decision/decline response should be validated against the current official hook schema before shipping.

**Fail-safe, not fail-open-to-allow.**

---

# 30. Tool Activity Normalization

The notch should not display raw JSON.

Bridge converts tool data to human-readable summaries.

Example categories:

```swift
enum ToolCategory {
    case shell
    case read
    case write
    case search
    case web
    case git
    case test
    case question
    case other
}
```

Examples:

```text
shell command: npm test
→ Running tests

git status
→ Checking Git status

read file
→ Reading EventConfig.ts

apply/edit
→ Editing EventConfig.ts

search
→ Searching codebase

request_user_input
→ Needs your input
```

Raw command can still appear on hover/expanded detail if safe.

---

# 31. Session Model

Suggested:

```swift
struct CodexSession: Identifiable, Equatable {
    let id: String

    var threadID: String?
    var currentTurnID: String?

    var cwd: URL?
    var projectName: String?

    var phase: SessionPhase

    var currentTool: ToolActivity?
    var lastAssistantMessage: String?

    var createdAt: Date
    var lastActivityAt: Date

    var hostBundleID: String?
    var pendingInteraction: PendingInteraction?

    var lifecycleConfidence: LifecycleConfidence
}
```

---

# 32. Focus Model for a Sequential Workflow

Even if multiple sessions exist, default UI should pick a single **focused session**.

Selection order:

```text
1. session currently waiting for input/permission
2. session explicitly selected by user
3. most recently active working session
4. most recently completed session within short grace window
5. none
```

Do not present four mini session cards by default.

A tiny secondary indicator can exist later:

```text
+2
```

but it should not turn the product into Code Island.

---

# 33. Presentation Reducer

A separate presentation layer can encode UX timing.

Pseudo-code:

```swift
switch transition {
case .enteredWaitingPermission:
    presentation = .attention

case .enteredWaitingInput:
    presentation = .attention

case .enteredCompleted:
    presentation = .expanded
    scheduleCollapse(after: 3.2)

case .enteredFailed:
    presentation = .expanded
    scheduleCollapse(after: 5.0)

case .toolChanged:
    if presentation == .collapsed {
        remainCollapsed()
    }

case .hoverEntered:
    presentation = .expanded

case .hoverExited:
    delayedCollapse()
}
```

Timers belong here, not in domain state.

---

# 34. Completion Preview

A finished card should answer:

> “What did Codex just do?”

not display the entire conversation.

Render:

```text
max ~3–6 lines
```

with optional expand/click.

If no reliable assistant message is available:

```text
✓ Codex finished
```

is enough.

Do not make transcript scraping mandatory just to fill this card.

---

# 35. Failure and Interruption Semantics

Do not represent all non-working states as “done”.

Visible distinctions:

```text
✓ Done
! Needs attention
× Failed
↩ Interrupted
```

If Codex reports a turn status via a future stable source:

```text
completed
failed
interrupted
```

preserve that semantic difference.

---

# 36. Optional Codex App-Server Layer

Codex app-server has a structured JSON-RPC/event model and can:

- initialize a client,
- start/resume threads,
- start turns,
- emit streaming items,
- emit turn completion statuses.

However, Nudge is **not trying to become a full Codex client**.

Therefore app-server should not be the MVP's mandatory path.

Potential future use:

```text
CodexMetadataReconciler
```

for:

- thread names,
- known thread IDs,
- richer lifecycle reconciliation,
- rate-limit metadata if exposed through a supported path,
- future precise navigation.

Rule:

> Hooks are the hot path. App-server is enrichment/reconciliation.

Do not assume an independently launched app-server is magically subscribed to all internal events of an already-running Codex Desktop instance.

That behavior must be verified before relying on it.

---

# 37. Codex Navigation

Navigation strategy:

```text
if threadID available and precise deep-link enabled:
    try codex://threads/<threadID>
    if launch success:
        done

activate com.openai.codex
```

macOS process invocation should target the **bundle identifier** when possible.

Encapsulate everything in `CodexNavigator`.

If Codex changes URL syntax later, only this service changes.

---

# 38. Non-Notch Macs and External Displays

The app should degrade gracefully.

On a screen without a physical notch:

```text
top-center compact island
```

not:

```text
disable app
```

Display logic:

- identify current target display,
- inspect screen safe-area/notch geometry,
- anchor appropriately,
- recalculate on display configuration changes.

Settings can allow:

```text
Display:
(•) Built-in display
( ) Follow mouse/focused display
( ) Display 2
```

This can be P1.

---

# 39. `NSPanel` Recommendations

Properties to evaluate:

```text
borderless
nonactivatingPanel
transparent background
isOpaque = false
hasShadow = false or custom
collectionBehavior:
  canJoinAllSpaces
  fullScreenAuxiliary
```

Important:

The panel should generally not steal keyboard focus simply because the pointer passed over it.

Interactive controls can intentionally activate as required.

Test:

- Mission Control,
- full-screen apps,
- multiple Spaces,
- menu bar auto-hide,
- external monitors.

---

# 40. Settings — Keep Them Small

MVP settings:

```text
General
├── Launch at login
├── Show completion sound
├── Auto-expand on completion
└── Start at login

Appearance
├── Mascot: On/Off
├── Animation intensity: Normal / Calm
└── Completion preview lines

Codex
├── Hook status
├── Reinstall hooks
├── Remove hooks
└── Precise thread jump (Experimental)

Diagnostics
├── Copy diagnostics
└── Open local log
```

No 12-tab preferences app.

---

# 41. Sounds

Sound should be optional.

Recommended default:

```text
completion        subtle on
attention         subtle on
tool use          off
session start     off
```

Avoid per-tool sound.

If custom synthesized sound is desired later, keep it minimal.

macOS native notification sounds may be enough for MVP.

---

# 42. Privacy

Default persistence:

Store:

- user preferences,
- hook installation status,
- optional most recent project label,
- bounded diagnostics.

Do not store by default:

- entire prompts,
- full assistant transcripts,
- shell output,
- file contents,
- secrets from tool input.

Tool summaries should be redacted/truncated.

Example max IPC sizes:

```text
event envelope: small bounded payload
assistant preview: truncate before wire/storage
tool input: normalized summary only
```

---

# 43. Security Model

## Threats

### Local socket event forgery

Mitigations:

- socket `0600`,
- per-user path,
- peer credentials where practical,
- canonical event enum,
- maximum frame size,
- schema version.

### Malicious / malformed tool input

Mitigations:

- never render as attributed rich HTML,
- escape strings,
- Markdown renderer only for trusted textual completion output,
- no shell execution from received text.

### Accidental config corruption

Mitigations:

- backup,
- parse-before-write,
- atomic replacement,
- preserve foreign hooks,
- refuse malformed source file.

### Accidental broad approval

Mitigations:

- no persistent allow/bypass MVP,
- explicit labels,
- Nudge unavailable → native Codex approval continues,
- never auto-approve silently.

---

# 44. Diagnostics

Use `OSLog`.

Categories:

```text
app
ipc
bridge
hooks
session
ui
navigation
```

Release logs should avoid:

- prompts,
- file contents,
- full commands when they might contain secrets.

Diagnostics export can redact:

```text
/Users/alice/project
→ ~/project
```

---

# 45. Test Strategy

## Unit tests

Highest-value target: `SessionReducer`.

Use fixture tests:

```text
SessionStart
UserPromptSubmit
PreToolUse
PostToolUse
Stop
```

and assert exact phase transitions.

---

## Mandatory edge-case fixtures

### Duplicate stop

```text
Stop(real answer)
Stop(suggestions metadata)
```

Expected:

```text
one completion animation
one completion card
```

### Resume without SessionStart

Input:

```text
PreToolUse(session unknown)
```

Expected:

```text
placeholder session created
phase = toolUse
```

### Long-running tool

Input:

```text
PreToolUse
advance fake clock 10 min
```

Expected:

```text
session still active
```

### Permission resolved elsewhere

Input:

```text
PermissionRequest
then PostToolUse / later progress
```

Expected:

```text
pending card dismissed
```

### Question mirror

Input:

```text
PreToolUse(request_user_input)
```

Expected:

```text
waitingInput
```

Then:

```text
PostToolUse
```

Expected:

```text
pending question cleared
```

### Unknown event

Expected:

```text
drop
no session created
```

### Malformed config

Expected:

```text
installer aborts
original bytes unchanged
```

### Duplicate hooks

Expected:

```text
canonical config contains exactly one Nudge entry
```

### PID reuse

If process fallback exists:

```text
same PID
different process start time
```

Expected:

```text
not treated as original process
```

### Sleep/wake

Expected:

```text
no duplicated completion animation
no duplicated collapse timer
```

---

# 46. Integration Testing

Build a fake bridge tool:

```bash
nudge-debug emit SessionStart
nudge-debug emit ToolUse --name shell --summary "npm test"
nudge-debug emit Question
nudge-debug emit Stop --message "Implemented feature"
```

The fake bridge lets animation be developed without repeatedly running a real Codex session. Synthetic bridge scenarios validate the Nudge pipeline and UI; they do not prove that the Codex macOS app emits the required events.

Also perform real end-to-end verification separately for Codex Desktop and Codex CLI. For each host, record the version, effective configuration location, hook trust state, and observed event coverage. Verify new/resumed threads, tool activity, attention where available, normal completion, failure/interruption, and Nudge-unavailable behavior. For Desktop, also verify returning to the app and the relevant thread when precise navigation is enabled.

Add demo scenarios:

```text
Demo: Normal Turn
Demo: Long Tool
Demo: Permission
Demo: Question
Demo: Complete
Demo: Fail
```

---

# 47. Animation QA

Screen-record at high frame rate and inspect:

- shell edge,
- mascot movement,
- text reflow,
- alignment,
- expansion origin,
- hover transitions.

Acceptance:

- no text snapping after shell animation finishes,
- no mascot teleport,
- no clipped sparkles,
- no transparent window flicker,
- no shadow discontinuity,
- no accidental focus steal.

---

# 48. Accessibility QA

Test:

- Reduce Motion,
- Increase Contrast,
- VoiceOver,
- keyboard navigation for actual buttons,
- status text understandable without color,
- hover-only actions also clickable/keyboard reachable.

Mascot is decorative and should not produce noisy VoiceOver descriptions.

---

# 49. Milestones

## M0 — Notch Playground

Build:

- menu-bar app shell,
- NSPanel at notch,
- collapsed/expanded geometry,
- fake status controls,
- original mascot,
- animation playground.

No Codex integration yet.

**Done when:**

The app can simulate all phases and feels visually polished.

---

## M1 — Codex Event Spine

Build:

- bridge target,
- Unix socket server,
- versioned wire envelope,
- hook installer,
- SessionReducer,
- basic live status.

Events:

```text
SessionStart
UserPromptSubmit
PreToolUse
PostToolUse
Stop
Interrupt
```

**Done when:**

Real local turns started directly in the Codex macOS app and separately in Codex CLI update Nudge reliably. New and resumed Desktop threads must work without requiring terminal launch. Record the tested host versions and event coverage; synthetic/CLI-only success does not complete M1.

---

## M2 — Codex Edge-Case Hardening

Implement:

- duplicate hook cleanup,
- duplicate Stop suppression,
- suggestion Stop handling,
- resume without SessionStart,
- stale pending cleanup,
- inactivity rules,
- sleep/wake reconciliation,
- malformed config safety,
- custom `CODEX_HOME`.

**Done when:**

fixture suite covers all known Code Island-derived Codex cases.

---

## M3 — Attention UX

Implement:

- `request_user_input` mirror,
- permission mirror,
- jump to Codex,
- sticky attention state,
- mascot attention behavior.

**Done when:**

Nudge mirrors questions and permissions from both supported hosts where available and never gets permanently stuck after the user resolves them in Codex. Desktop attention actions activate Codex Desktop, with precise thread routing validated in M4.

---

## M4 — Precise Navigation

Implement:

- `codex://threads/<id>` experiment,
- bundle-ID launching,
- fallback activation,
- archived/missing thread handling,
- diagnostics.

**Done when:**

failure degrades to opening Codex rather than doing nothing.

---

## M5 — Permission Actions

Optional.

Implement only after the current official schema is validated:

```text
Allow Once
Deny
```

Still omit persistent/bypass rules.

**Done when:**

- app offline does not block Codex,
- duplicate requests are queued safely,
- external resolution clears pending state,
- no silent auto-allow path exists.

---

## M6 — Distribution Hardening

Build:

- Developer ID signing,
- hardened runtime,
- notarized DMG,
- update strategy,
- clean installer/uninstaller,
- diagnostics.

Possible updater later:

- Sparkle,
- or manual release checks.

---

# 50. MVP Acceptance Criteria

Nudge v0.1 is successful when all are true:

- [ ] launches as a native menu-bar accessory app,
- [ ] aligns correctly with built-in MacBook notch,
- [ ] has a functional non-notch fallback,
- [ ] installer modifies Codex hooks without deleting other hooks,
- [ ] installer is idempotent,
- [ ] malformed existing config is never overwritten,
- [ ] socket is per-user and owner-only,
- [ ] local turns started directly in the Codex macOS app update Nudge without terminal launch or a Nudge-owned app-server,
- [ ] both new and resumed Codex Desktop threads are verified with real lifecycle events,
- [ ] Codex Desktop and Codex CLI have separate recorded end-to-end verification, including tested versions and event coverage,
- [ ] working/thinking, tool progress, attention where available, completion, failure, and interruption are verified for both supported hosts,
- [ ] Desktop attention actions return to Codex Desktop; precise thread navigation has app-activation fallback,
- [ ] valid Codex events appear with low perceived latency,
- [ ] working/thinking state is visually distinct,
- [ ] current tool summary is understandable,
- [ ] `request_user_input` creates a persistent attention state,
- [ ] permission request can at minimum jump to Codex,
- [ ] successful completion plays exactly one completion transition,
- [ ] suggestion-only extra Stop does not replay completion,
- [ ] interruption is not displayed as success,
- [ ] sleep/wake does not replay old animations,
- [ ] app failure does not prevent ordinary Codex use,
- [ ] mascot has idle/thinking/attention/done/failure poses,
- [ ] idle animation consumes negligible CPU,
- [ ] Reduce Motion is respected,
- [ ] no full prompt/transcript history is persisted by default.

---

# 51. What Should Be Built First?

Do **not** start with Codex hook integration.

Start with the thing that will determine whether Nudge is worth using:

> the notch interaction and mascot.

Recommended first implementation week/session:

```text
1. NSPanel anchored to notch
2. collapsed ↔ expanded shell animation
3. fake state picker
4. Nudgie mascot
5. working / attention / done animations
6. hover hysteresis
7. Reduce Motion
```

Use fake data such as:

```swift
@State var debugPhase: DebugPhase = .thinking
```

Once the UI feels excellent, connect real Codex events.

Reason:

If event integration works perfectly but the notch feels stiff or ugly, the product has little reason to exist because native Codex notifications already solve the basic utility problem.

The **polish is part of the product**, not decoration.

---

# 52. Recommended Architectural Decisions — Final

| Area | Decision |
|---|---|
| Product name | Nudge |
| Required integration hosts | Codex macOS app / Desktop + Codex CLI; CLI-only is insufficient |
| Primary event source | Codex lifecycle hooks, verified separately in both hosts |
| IPC | Unix domain socket |
| Bridge | Small native command-line helper |
| UI | SwiftUI hosted in AppKit `NSPanel` |
| Domain logic | Deterministic reducer |
| Main UI philosophy | Single focused context |
| Mascot | Original vector/Canvas character |
| Permission MVP | Mirror + jump; optionally Allow Once/Deny later |
| Persistent allow | Not MVP |
| Usage tracker | Not MVP |
| App-server | Optional enrichment/reconciliation |
| Transcript parsing | Best-effort fallback only |
| Precise thread jump | Experimental abstraction + activation fallback |
| Config merge | Idempotent, backup, preserve foreign entries |
| Security | socket `0600`, peer validation, schema guard |
| Storage | minimal/local |
| Telemetry | none by default |
| Distribution | Developer ID + notarized DMG first |
| Multi-agent support | Explicit non-goal |

---

# 53. One More Important Product Decision

Nudge should **not** compete with Codex's native notification system by producing another copy of every OS notification.

Native notification:

> “Codex is done.”

Nudge's job:

> visually show the live context of the thing you're already working on.

That means the differentiator is:

```text
live presence
+ glanceable state
+ playful personality
+ direct return path
```

not notification duplication.

---

# 54. Proposed v0.1 UI Copy

Collapsed:

```text
Detinvite · Thinking…
Detinvite · Reading routes.ts
Detinvite · Running tests
Detinvite · Needs you
Detinvite · Done
```

Attention:

```text
Codex has a question
Answer in Codex
```

Permission:

```text
Codex needs permission
Open Codex
```

Failure:

```text
Codex hit a problem
Open Codex
```

Interruption:

```text
Codex stopped
```

Keep language human.

Avoid:

```text
PostToolUse received
Turn ID 913782
PermissionRequest blocking
```

unless Diagnostics mode is enabled.

---

# 55. Original Character Direction — More Concrete

Recommended silhouette:

```text
small rounded cube/blob
+ two eyes
+ optional single-pixel/line mouth
+ tiny “ear” or cursor-notch detail
```

The identifying feature could be a little **chevron/cursor-tail** on one side, linking the character visually to coding without looking like an OpenAI/Codex logo.

Example conceptual states:

```text
IDLE
  ◉  [•‿•]

THINKING
  ◉  [•_•]  · ·

TOOL
  ◉  [•⌄•]  ▸_

WAITING
  ◉  [•︿•]  ?

DONE
  ✦ [^‿^] ✦

ERROR
  ◉  [x_x]
```

These are mood references, not final art.

The final asset should be drawn from scratch.

---

# 56. Potential Future Features

Only after v0.1 is genuinely useful:

## v0.2

- Allow Once / Deny from notch.
- richer completion markdown.
- exact thread title.
- better deep-link routing.
- session elapsed time.
- optional Launch at Login.

## v0.3

- optional Codex quota glance.
- session history limited to recent local metadata.
- multiple mascot skins drawn originally.
- external-display preference.

## v1.0

- signed/notarized release,
- updater,
- polished onboarding,
- robust hook trust repair,
- public documentation.

Only then consider:

```text
Claude adapter
```

if there is a real need.

The core architecture already allows another event adapter without redesigning the UI.

---

# 57. If Multi-Agent Support Ever Happens

Preserve this abstraction now:

```swift
protocol AgentEventSource {
    var providerID: String { get }

    func install() async throws
    func uninstall() async throws
}
```

But do **not** build multiple concrete providers yet.

Current:

```text
CodexEventSource
```

Future:

```text
ClaudeEventSource
```

The UI should render semantic state, not Codex-specific strings.

This is enough future-proofing.

---

# 58. Key Technical Risks

## Risk 1 — Codex hook schema changes

Mitigation:

- canonical adapter,
- schema fixtures,
- versioned bridge envelope,
- graceful unknown-event handling.

## Risk 2 — trust/config changes

Mitigation:

- install only minimal hooks,
- onboarding diagnostics,
- preserve configs,
- do not repeatedly rewrite definitions.

## Risk 3 — deep-link behavior changes

Mitigation:

- navigator abstraction,
- feature flag,
- fallback to app activation.

## Risk 4 — permission path blocks Codex

Mitigation:

- permission actions deferred,
- bounded socket timeout,
- no silent allow,
- native Codex remains fallback.

## Risk 5 — notch animations consume power

Mitigation:

- event-driven motion,
- no idle frame loop,
- pause on sleep,
- Instruments profiling before release.

## Risk 6 — product becomes another “AI dashboard”

Mitigation:

- maintain single-context product principle,
- reject feature creep,
- optimize for one focused current task.

---

# 59. Instruments / Profiling Checklist

Before shipping:

Use Instruments for:

- Time Profiler,
- Allocations,
- SwiftUI rendering,
- Energy Log.

Measure:

```text
idle for 10 minutes
thinking for 10 minutes
long tool execution
repeated expand/collapse
sleep/wake
1000 synthetic events
```

Watch for:

- permanent animation timers,
- repeated JSON decoder allocation hotspots,
- state updates causing entire view tree redraw,
- leaked NSPanel observers,
- socket read loop spin.

---

# 60. Recommended Logging for Edge-Case Debugging

A bounded local diagnostic event can look like:

```text
2026-10-01T17:20:01Z
session=8f…
turn=33…
event=Stop
phase_before=toolUse
phase_after=completed
presentation=expanded
reason=normal_completion
```

For duplicate suppression:

```text
drop event=Stop
reason=duplicate_suggestion_stop
```

For lazy session materialization:

```text
create_placeholder_session
reason=event_before_session_start
```

This will save enormous time when Codex behavior changes.

---

# 61. Definition of “Polished”

Nudge should not be considered done merely because events appear.

A polished v0.1 means:

- the shell visually feels attached to the physical notch,
- text never jumps awkwardly,
- hover does not flicker,
- mascot is charming but quiet,
- completion feels satisfying,
- attention feels noticeable without being annoying,
- the app can be left running all day without perceptible CPU drain,
- the app never traps the user into needing it,
- a broken integration has an understandable diagnostic path.

---

# 62. Recommended First Engineering Ticket Sequence

```text
ND-001  Create accessory app + NSPanel
ND-002  Detect notch-safe screen geometry
ND-003  Collapsed/expanded shell
ND-004  Presentation reducer
ND-005  Original Nudgie Canvas mascot
ND-006  Motion tokens + Reduce Motion
ND-007  Fake lifecycle debug panel
ND-008  Unix socket server
ND-009  NudgeBridge helper
ND-010  Versioned wire envelope
ND-011  Session reducer
ND-012  Codex hook installer
ND-013  Hook merge/idempotency tests
ND-014  Real PreToolUse/PostToolUse status
ND-015  Stop/completion handling
ND-016  Codex duplicate/suggestion Stop fixtures
ND-017  request_user_input mirror
ND-018  Codex activation/deep-link navigator
ND-019  sleep/wake reconciliation
ND-020  security hardening + peer validation
ND-021  onboarding + hook trust diagnostics
ND-022  notarized development release
```

This sequence deliberately puts **design feel before provider complexity**.

---

# 63. Sources / Research References

## Vibe Notch

- Repository / README:  
  <https://github.com/farouqaldori/vibe-notch>
- Releases:  
  <https://github.com/farouqaldori/vibe-notch/releases>
- Apache-2.0 license is declared by the repository.

Key lessons researched from the project include hook-to-Unix-socket architecture, native notch UI, permission surfaces, and production fixes involving socket permissions, sleep/wake behavior, stable message IDs, rendering work off the main thread, and hook compatibility.

---

## Code Island

- Repository / README:  
  <https://github.com/rifqiakrm/code-island>
- Architecture notes:  
  <https://github.com/rifqiakrm/code-island/blob/main/CLAUDE.md>

Important Codex implementation areas inspected during research:

- Codex hook installation/config merging,
- canonical event normalization,
- Codex PermissionRequest behavior,
- `request_user_input` mirroring,
- session lifecycle cleanup,
- duplicate/suggestion Stop handling,
- terminal/app detection,
- Codex jump behavior,
- permission persistence/rule edge cases.

Code Island is GPLv3. Treat its implementation and mascot artwork as GPL-covered source; do not copy them into a proprietary derivative.

---

## OpenAI Codex hooks

- Current hooks documentation:  
  <https://developers.openai.com/codex/hooks>

Key integration rules used in this brief:

- lifecycle events such as `SessionStart`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `Interrupt`, etc.,
- common hook payload fields such as `session_id`, `cwd`, event name, and related turn metadata,
- non-managed hook trust,
- event-specific response contracts,
- transcript data should not be treated as a permanent stable public schema.

Always validate the current hook schema again immediately before implementing blocking permission actions.

---

## OpenAI Codex app-server

- App-server integration documentation:  
  <https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server>

App-server provides structured thread/turn control and event streams. For Nudge, it is intentionally considered an optional enrichment layer rather than a requirement for the MVP.

---

## Codex Desktop deep-link behavior

Public Codex repository discussions/issues demonstrate the `codex://` deep-link family, including existing-thread and new-thread/workspace navigation:

- <https://github.com/openai/codex/issues/25863>
- <https://github.com/openai/codex/issues/29605>
- <https://github.com/openai/codex/issues/30790>

These are useful evidence but should not be mistaken for a permanent versioned navigation API contract. Keep precise navigation behind an abstraction and retain a simple app-activation fallback.

---

# 64. Final Recommendation

Build **Nudge**, but keep it deliberately narrow.

The best version is not:

```text
Vibe Island
minus $20
```

and not:

```text
Code Island
but only Codex
```

It is:

```text
a tiny native companion
for one focused Codex context
that feels alive in the notch
```

The product's moat, even as a personal utility, is the combination of:

```text
reliable Codex lifecycle handling
        +
almost-zero-friction glanceability
        +
beautiful native motion
        +
a memorable original character
        +
low cognitive noise
```

The backend/event plumbing should be boring and defensive.

The frontend should be the fun part.

That is the right balance for **Nudge**.
