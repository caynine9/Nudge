---
name: Nudge
description: Quiet native macOS notch companion with one focused context.
colors:
  shell-black: "#000000"
  text-white: "#ffffff"
  secondary: "rgb(60% 60% 60%)"
  muted: "rgb(48% 48% 48%)"
  blue: "rgb(22% 58% 100%)"
  orange: "rgb(100% 57% 20%)"
  cyan: "rgb(20% 78% 87%)"
  green: "rgb(24% 82% 48%)"
  red: "rgb(100% 43% 43%)"
  badge-surface: "rgb(10% 10% 10%)"
  row-hover: "rgb(8% 8% 8%)"
  neutral-button: "rgb(15% 15% 15%)"
  neutral-button-active: "rgb(22% 22% 22%)"
  primary-button: "rgb(90% 90% 90%)"
  primary-button-pressed: "rgb(72% 72% 72%)"
  diff-surface: "rgb(3.5% 3.5% 3.5%)"
  mascot-default: "rgb(48% 79% 100%)"
  mascot-attention: "rgb(100% 71% 36%)"
  mascot-done: "rgb(44% 88% 68%)"
  mascot-failure: "rgb(100% 47% 46%)"
  mascot-interrupted: "rgb(64% 69% 78%)"
  mascot-eyes: "rgb(8% 12% 18%)"
typography:
  title:
    fontFamily: "System (SwiftUI .system)"
    fontSize: "14pt"
    fontWeight: 500
  body:
    fontFamily: "System (SwiftUI .system)"
    fontSize: "13pt"
    fontWeight: 400
  detail:
    fontFamily: "System (SwiftUI .system)"
    fontSize: "12pt"
    fontWeight: 400
  action:
    fontFamily: "System (SwiftUI .system)"
    fontSize: "12pt"
    fontWeight: 500
  metadata:
    fontFamily: "System (SwiftUI .system)"
    fontSize: "11pt"
    fontWeight: 400
  badge:
    fontFamily: "System (SwiftUI .system)"
    fontSize: "10pt"
    fontWeight: 400
  confirmation:
    fontFamily: "System (SwiftUI .system)"
    fontSize: "15pt"
    fontWeight: 500
  code:
    fontFamily: "System monospaced (SF Mono via SwiftUI)"
    fontSize: "12pt"
    fontWeight: 400
  diff:
    fontFamily: "System monospaced (SF Mono via SwiftUI)"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  shortcut: "4pt"
  badge: "5pt"
  diff: "6pt"
  control: "8pt"
  compact-shell-bottom: "10pt"
  expanded-shell-bottom: "18pt"
  fallback-shell: "18pt"
spacing:
  text-stack: "5pt"
  attention-header: "7pt"
  decision-gap: "8pt"
  diff-inset: "9pt"
  attention-stack: "10pt"
  monitor-stack: "12pt"
  content-bottom: "14pt"
  content-top: "16pt"
  notch-content-horizontal: "28pt"
  fallback-content-horizontal: "16pt"
components:
  badge:
    backgroundColor: "{colors.badge-surface}"
    textColor: "{colors.secondary}"
    typography: "{typography.badge}"
    rounded: "{rounded.badge}"
    padding: "2pt 7pt"
  button-row:
    backgroundColor: "{colors.shell-black}"
    rounded: "{rounded.control}"
  button-row-hover:
    backgroundColor: "{colors.row-hover}"
    rounded: "{rounded.control}"
  button-neutral:
    backgroundColor: "{colors.neutral-button}"
    textColor: "rgb(100% 100% 100% / 0.92)"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
    height: "30pt"
  button-neutral-active:
    backgroundColor: "{colors.neutral-button-active}"
    rounded: "{rounded.control}"
  button-primary:
    backgroundColor: "{colors.primary-button}"
    textColor: "{colors.shell-black}"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
    height: "30pt"
  button-primary-hover:
    backgroundColor: "{colors.text-white}"
    rounded: "{rounded.control}"
  button-primary-pressed:
    backgroundColor: "{colors.primary-button-pressed}"
    rounded: "{rounded.control}"
  button-choice:
    backgroundColor: "rgb(20% 78% 87% / 0.12)"
    textColor: "rgb(100% 100% 100% / 0.92)"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0pt 10pt"
    height: "32pt"
  button-choice-active:
    backgroundColor: "rgb(20% 78% 87% / 0.22)"
    rounded: "{rounded.control}"
  diff-preview:
    backgroundColor: "{colors.diff-surface}"
    typography: "{typography.diff}"
    rounded: "{rounded.diff}"
  nudgie:
    width: "31pt"
    height: "28pt"
---
# Design System: Nudge

## Overview

**Creative North Star: "Quiet notch companion"**

Nudge is a quiet Mac companion: opaque black joins the physical camera housing, direct rows carry one focused task, and original Nudgie supplies restrained character. It stays black in both Light and Dark system appearance. Readable text uses native system typography; paths, filenames, code, and diffs use the system monospaced design.

This records the implemented M0 visual playground, derived from SwiftUI/AppKit sources and the user-confirmed screenshot direction. Approval, question, and feedback are explicitly Demo states. Native macOS is not represented by the installed web/iOS/Android presets; Apple frameworks and the project brief govern behavior. Measurements marked pt are native logical points, not CSS point conversions.

**Key Characteristics:**

- Opaque black in both system appearances.
- One focused context, direct rows, compact controls.
- Camera exclusion and one shared screen-edge anchor on notched displays.
- Original Nudgie, state symbols, and restrained semantic accents.
- Short event-driven motion with Reduce Motion support.

Source authority: `Nudge/UI/NotchComponents.swift`, `NotchRootView.swift`, `NotchGeometry.swift`, `NotchPanelController.swift`, `Nudgie.swift`, and `Nudge/Core/PresentationReducer.swift`. `PRODUCT.md` supplies confirmed brand constraints; `.impeccable/surfaces/nudge-ui-notchrootview-swift.md` carries this surface's direction contract. Frontmatter records extracted primitives; native geometry, motion, and documentation-only browser samples live in `.impeccable/design.json`.

## Colors

Black, white, and quiet grays carry the interface; restrained color communicates semantic state.

### Primary

- **Working blue:** thinking and tool use.
- **Permission orange:** permission attention, denied feedback, and navigation issues.
- **Question cyan:** question heading, choices, and shortcut tiles.
- **Success green:** completion, accepted or selected demo feedback, and added diff lines.
- **Failure red:** failures and removed diff lines.

These are semantic peers, not a brand-primary hierarchy. No independent secondary or tertiary brand palette is implemented.

### Neutral

- **Housing black / text white:** opaque shell and readable content.
- **Secondary gray:** metadata, neutral phases, badges, context diff lines, and host action.
- **Muted gray:** diff line numbers.
- **Badge, row, button, and diff surfaces:** small tonal separations inside the shell. Primary actions use pale gray with black text; the other permission action uses a dark gray surface.
- **Nudgie colors:** a separate pose palette for default, attention, done, failure, and interruption; dark eyes remain readable on its body.

**The Black Housing Rule.** Keep the shell opaque black in both Light and Dark system appearance.

White text opacity varies with context: permission paths use 0.90, choice and neutral action text 0.92, shortcut annotation 0.55. Choice fill uses cyan at 0.12, increasing to 0.22 on interaction; its shortcut tile uses 0.15. Added and removed diff rows use their semantic color at 0.08. These overlays supplement, rather than replace, symbols and wording.

## Typography

**Readable Font:** native SwiftUI system font, resolved by macOS.
**Code Font:** native SwiftUI `.monospaced` system design, corresponding to SF Mono on macOS.

The compact type ramp serves short interface text. There is no separate display face or marketing headline system. Font sizes in the frontmatter are native points; weights record the implemented regular (400) and medium (500) roles. The compact phase symbol also uses system semibold (600). Line heights and tracking are framework defaults, not extracted tokens.

- **Title:** task title and question, medium; monitor title truncates to one line.
- **Body:** question choice text, regular.
- **Detail / action:** prompt, phase, attention heading, and permission action.
- **Metadata / badge:** host action, launch issue, Demo and host badges.
- **Confirmation:** centered feedback label, medium.
- **Code / diff:** file path and tool filename; dense diff rows have a smaller code role and 15 pt row height.

**The Readable First Rule.** Use native system typography for readable interface text; reserve the monospaced design for filenames, paths, code, and diffs.

## Layout

This is an adaptive native panel, not a responsive web grid. Geometry derives from `NSScreen` safe areas and auxiliary top regions. The panel centers on the actual cutout; a standard display uses screen center. Notched modes share `screenFrame.maxY`; fallback modes sit 6 pt below `visibleFrame.maxY`.

| Mode | Notched panel | Standard display |
| --- | --- | --- |
| Minimized | cutout width + 84 pt; cutout height + 2 pt | 200 × 38 pt |
| Monitor peek | at least 380 pt wide; cutout height + 132 pt | 380 × 132 pt |
| Expanded monitor | at least 380 pt wide; cutout height + 160 pt for one session, + 170 pt for multiple sessions | 380 × 160 pt; 380 × 170 pt for multiple sessions |
| Approval | at least 380 pt wide; cutout height + 224 pt | 380 × 224 pt |
| Question | at least 340 pt wide; cutout height + 192 pt | 340 × 192 pt |
| Confirmation | at least 260 pt wide; cutout height + 46 pt | 260 × 46 pt |

For a 180 × 32 pt cutout, minimized remains 264 × 34 pt. Width is clamped to the symmetric screen space around the cutout, leaving 24 pt total margin; height is clamped to screen height minus 32 pt. This also supports negative screen origins.

In minimized presentation, Nudgie occupies the left wing and the current phase symbol occupies the right wing for every phase. The standard-display row follows the same order, with the task title between them. This user-confirmed placement preserves the camera exclusion band and existing dimensions.

Expanded notched content starts after a blank band equal to the camera height, then the extracted content-top spacing. Horizontal content insets differ between notched and fallback displays. Monitor content uses a 12 pt vertical stack and a 12 pt mascot-to-text gap. Permission actions share width and an 8 pt gap; question choices occupy full width in a stack with a 5 pt gap. No outer nested task card or separate detached expanded panel is implemented. Expanded notched modes may cover menu items; minimized preserves the chosen compact wing footprint.

Expanded live monitor presents project folder labels as group headings with indented session rows beneath them. A session title from bounded, read-only local metadata is the primary row text; an unavailable title falls back to a short stable ID. Semantic phase and the current tool summary form one right-aligned status column, with the tool detail subdued. Hook activity remains the source of session order: the group with the highest-priority session comes first, and sessions retain their order within each group. Tool updates and selection do not reorder them. At two or more active sessions, the monitor grows by 10 pt, from 160 to 170 pt below the camera band (380 × 170 pt on a standard display, cutout height + 170 pt on a notched display). Further rows scroll inside this fixed viewport with native scroll indicators. Collapsed and peek modes keep one focused session. Live monitor has no Live badge; synthetic content retains its Demo badge.

**The One Anchor Rule.** Keep every notched mode attached to the same screen-top anchor, with a blank camera band before expanded content.

**The Direct Rows Rule.** Place monitor and attention content directly in the full-width black shell; do not reintroduce nested task cards or a stepped neck.

## Elevation & Depth

Depth is primarily tonal. The expanded shell applies one SwiftUI shadow: black at 0.24 opacity, radius 12 pt, vertical offset 5 pt; minimized uses zero shadow opacity. AppKit's own panel shadow is disabled. Controls have no raised or offset shadow. White at 0.75 opacity with a 1 pt stroke indicates focus. Nudgie alone uses a small pose-color gradient and a 0.8 pt white stroke at 0.28 opacity; this is original mascot material, not a general surface gradient.

## Shapes

Notched shells form a continuous top-attached housing with rounded shoulders, not a stepped neck. The shoulder is bounded by 12 pt, one-quarter width, and one-quarter height; bottom radius is bounded by available geometry and the extracted compact or expanded limit. The standard-display shell is a continuous rounded rectangle. Badges, shortcut tiles, buttons, and diff preview use the frontmatter's small radii. Nudgie is an original rounded cursor creature with two capsule eyes, not a stock or copied mascot.

## Components

### Monitor row and host action

Live monitor rows sit below project headings and show a verified local title or a short session ID fallback. Phase and bounded tool summary share the right-hand column. Clicking an active row sends the full session ID through Codex's documented local-chat deep link; actual destination remains live-host verification. No Live badge is shown. Demo preview content remains explicitly marked Demo. Terminal-tab routing is outside the current integration.

### Buttons

`NotchButtonStyle` supplies row, neutral, primary, and choice tones. Each shares the control radius, native focus stroke, and disabled opacity (0.45). Row hover is a dark gray lift. Neutral actions brighten on hover/press; the primary action brightens on hover and darkens while pressed. Choice actions strengthen cyan tint. Permission actions are 30 pt high with native Command-N / Command-Y shortcuts; question choices are 32 pt high with Command-1 through Command-3. Hit regions span the supplied row rectangles.

### Badges

Small gray-on-dark badges provide Demo, Codex, and selected host context where shown. They are labels rather than chips or filters; the live activity monitor has no Live badge.

### Permission preview

A muted request heading with orange symbol precedes a monospaced file row and compact diff preview. Line numbers, `+`/`−` markers, and tinted additions/removals carry diff meaning. Two equal actions simulate Deny and Allow once. No decision is sent to Codex.

### Question preview

A cyan title and native readable prompt precede three full-width tinted choices with separate shortcut tiles. Each selects a local demo option; no answer is sent to Codex.

### Interaction confirmation

A centered symbol and chosen label display for 1.4 s, then collapse. Denied uses an orange cross; accepted or selected uses a green check. This temporary receipt has its own presentation mode and is not completion.

### Nudgie and motion

Nudgie's base frame is 31 × 28 pt. Compact/fallback presentation scales it to 0.68; monitor scales it to 0.72. Poses distinguish idle, thinking, working, attention, done, failure, and interruption. It has no permanent frame loop. A consumed completion produces one hop of −6 pt, using a spring response of 0.22 s with damping 0.48, then returns after 290 ms with response 0.24 s and damping 0.72. Reduce Motion skips the hop and uses immediate panel placement.

AppKit is the sole owner of animated window size. Expansion uses 380 ms and contraction 280 ms, with `CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)` for deceleration without overshoot. The hosting view has `sizingOptions = []` and the panel has `animationBehavior = .none`, preventing intrinsic sizing and default window animation from competing with the explicit transition.

SwiftUI uses the same timing curve for the shell, with 380 ms on opening and 280 ms on collapse. The notched bottom radius interpolates from 10 to 18 pt within the geometry bounds. Content is laid out at its destination size without intermediate-width reflow, then revealed through the resizing shell. Its asymmetric opacity transition inserts over 180 ms after a 40 ms delay and removes over 100 ms; phase changes use 180 ms ease-out. Reduce Motion makes panel placement immediate and disables shell interpolation and crossfade. These values describe implemented source; physical smoothness, rapid reversal, and keyboard focus still require developer QA. Hover opens after 100 ms and collapses after 320 ms when eligible. Attention persists; time alone does not collapse it. Completed and failed phases show distinct transient durations (3.2 s and 5 s). Sleep cancels presentation timers and clears feedback; wake reconstructs current presentation without replaying old transients. AppKit uses a borderless nonactivating `NSPanel` with status-bar level, joining Spaces and full-screen auxiliary behavior. Its physical focus, pointer routing, and Space behavior require developer verification.

## Do's and Don'ts

### Do:

- **Do** keep the blank camera band and preserve the existing minimized geometry.
- **Do** show Demo on synthetic monitor, permission, question, and confirmation content.
- **Do** use text and symbols alongside semantic color.
- **Do** keep host activation tied to the selected host and report launch failure in the monitor row.
- **Do** preserve native keyboard shortcuts, focus treatment, VoiceOver labels, and Reduce Motion behavior.
- **Do** verify physical NSPanel behavior, hover, focus, menu access, Spaces, and host activation manually on macOS.

### Don't:

- **Don't** switch the shell to a light surface in Light appearance.
- **Don't** move the expanded notched panel below the menu bar or add a narrow neck above its content.
- **Don't** expand the focused surface into a provider fleet, quota dashboard, or conversation history browser. The user explicitly permits an active-session list in the expanded monitor.
- **Don't** represent demo permission actions or question choices as decisions sent to Codex.
- **Don't** treat the short interaction receipt as task completion or promise exact session/tab routing.
- **Don't** copy external mascot artwork or introduce a permanent idle animation.

Documentation scope: fourteen notch/fallback static state renders received an independent ship disposition for source/static review. The motion follow-up received an independent source/static check of fourteen fresh endpoint renders with no static regressions or material source blockers. Physical NSPanel smoothness, rapid reversal, hover, keyboard focus, menu-bar interaction, Spaces/full-screen, and selected-host runtime remain developer QA. No runtime result is inferred from static images. No implementation defect is promoted into a future design rule by this document.
