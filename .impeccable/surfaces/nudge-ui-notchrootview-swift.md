---
version: 1
slug: "nudge-ui-notchrootview-swift"
primary_target: "Nudge/UI/NotchRootView.swift"
related_targets: ["Nudge/UI/NotchGeometry.swift","Nudge/UI/NotchComponents.swift"]
---

# Nudge notch surface

Scope: M0 redesign from the five user-supplied screenshots. Mode: Operate. User-authorized basic app activation; live hooks and response contracts stay out of scope. All prompts, diff lines, and outcomes are local demo fixtures.

## Direction contract

THESIS: One focused Codex task with quiet, direct rows. Discard nested cards, tiny uppercase labels, gratuitous gradients, and redundant session chrome.

OWN-WORLD: Opaque black matching the physical camera housing, native SF typography, muted metadata, restrained blue/orange/cyan/green for semantic states. Compact radii; original Nudgie; SF Mono only for filenames, paths, diffs and code; all other text uses native system type.

STORY: Glance at minimized status, hover to inspect monitor, click its row to activate the host. Preview approval or question, choose a simulated action, see one short confirmation, return to minimized. No copied quota counters or multi-provider fleet.

FIRST VIEWPORT: The existing minimized wing layout and dimensions retained exactly (cutout width + 84, height + 2). Monitor is one row with title, subtitle, tool and small Codex/host badges. Approval shows file, short diff and two equal actions. Question shows prompt and three full-width choices. Receipt shows centered check and chosen label. Expanded grows from the same screen-edge notch anchor as minimized, in one full-width shell with no narrow neck or stepped card. The physical camera band stays blank and content starts below it. Latest user explicitly rejects moving the whole panel below the menu bar and permits covering menu items while expanded; minimized preserves menu access.

M1 ACTIVITY CONTEXT: Collapsed and peek keep one focused session. Expanded groups all detected active sessions beneath project-folder headings. Indented rows show a bounded title from read-only local `thread.name` metadata, or a short ID fallback; phase and current-tool summary align in one right-side column. Group order follows each group's highest-priority session, and member order follows attention then newest turn start/resume; tool updates and selection do not reorder rows. With multiple sessions, expanded grows by 10 pt (160 to 170 pt below the notch camera band) and then uses native scrolling. Clicking a row sends the documented Codex local-chat deep link; exact destination remains live-host verification. There is no Live badge; Demo remains visibly marked Demo.

FORM: User-pinned screenshot direction, implemented directly in native SwiftUI; no randomized concept round. Current-session code-first from supplied references; no standing build-path preference inferred.

FINISH: Build and fixture checks, one batch of offscreen SwiftUI renders with a bounded correction pass, independent finish review and documentation; physical notch, mouse routing, Spaces and host navigation remain developer QA, never inferred from render images.


## Motion follow-up

User reported jagged/abrupt transitions. AppKit is the sole owner of animated window size, with native deceleration (0.22, 1, 0.36, 1), 380 ms expansion and 280 ms contraction. Hosting view intrinsic sizing is disabled to avoid competing window constraints. SwiftUI content is composed at its destination width, briefly crossfades, and is revealed through the resizing shell; text must not rewrap at intermediate window widths. Rounded shell corners interpolate continuously. No persistent frame loop, no overshoot. Reduce Motion bypasses spatial transitions and crossfade. Runtime smoothness, rapid reversal and focus behavior remain developer QA.
