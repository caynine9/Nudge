# Nudge M0 — Build and Developer QA Handoff

Status: **M0 implementation is in place; manual visual verification is pending.** This record separates what was checked from what still requires the developer's Mac and interaction review.

## Automated project checks

- Xcode project parses and exposes the shared `Nudge` scheme.
- `Nudge` is configured as a macOS app with deployment target macOS 15, Swift 6 language mode, and `LSUIElement` enabled.
- Debug build: **passed** with Xcode 27.0, Swift 6.4, macOS 27 SDK.
- Release build: **passed** with the same toolchain.
- Shared `NudgeCoreTests` target is **not present yet**; no Xcode unit test run is claimed here.
- Standalone production-source fixture checks in `NudgeCoreTests/NotchGeometryChecks.swift`: **passed**. Covers compact dimensions, real cutout anchoring, negative screen origin, stable expanded top anchor and full-width shape, inconsistent geometry fallback, and small-screen width bounds. These do not verify native mouse routing or visual layout and are not a shared Xcode test target.
- Standalone reducer fixture checks in `NudgeCoreTests/PresentationChecks.swift`: **passed**, including attention retention, same-turn resolution, duplicate decisions, stale receipt timers, denied/interrupted distinction, sleep/wake and completion dedupe.
- Codex Desktop/CLI hooks and real-session behavior are outside M0 and have not been exercised.

## Developer visual and interaction checks

Record macOS version, built-in display model, external display setup, and result for each item. All items are pending. Latest user UX clarification: minimized preserves menu-bar access; expanded may intentionally cover menu items and must grow from the same notch anchor.

1. [ ] Launch from the shared Xcode scheme. Confirm Nudge appears in the menu bar without a Dock icon or ordinary app window.
2. [ ] Use **Simulate phase** to inspect discovered, idle, thinking, running tests, waiting permission, waiting input, completed, failed, interrupted, and ended.
3. [ ] Hover in/out quickly, re-enter during the exit delay, click the header to pin, and press Escape to collapse. Check for flicker, text snapping, or unexpected expansion.
4. [ ] Resolve attention by choosing a non-waiting phase in **Simulate phase**, or use a Demo decision/option. Confirm clicking/expanding the panel alone does not clear its attention state.
5. [ ] On a physical notch display, check that content clears the camera housing, sits on a stable top anchor, and Nudgie remains visible. Check that the upper shoulders join the screen edge without a floating rounded top. On a non-notch/external display, check the compact island fallback. Switch system appearance between Light and Dark; the outer shell must stay opaque black with readable text in every presentation mode.
6. [ ] Switch Spaces, enter full-screen, invoke Mission Control, and test menu-bar auto-hide. Check that the panel does not steal focus on hover or block a large transparent area.
7. [ ] Toggle Reduce Motion while Nudge is open. Check motion stops while phase and attention meaning remain clear. Also check Increase Contrast, VoiceOver, and keyboard access.
8. [ ] Complete the same simulated turn more than once, then start a new turn. Confirm one completion flourish for the new turn and no success pose for failed/interrupted.
9. [ ] Sleep and wake during work, attention, and after completion. Check for replayed motion, duplicate collapse, or lost attention.
10. [ ] Leave the overlay idle and hidden. Check Activity Monitor for an always-running animation/timer loop.

## Screenshot-based M0 redesign

The latest user instruction preserves the notched minimized geometry: cutout width + 84 pt and cutout height + 2 pt (264 × 34 pt for a 180 × 32 pt housing). Do not add a task row below the camera in this mode. Non-notch compact remains 200 × 38 pt.

Expanded widths follow the supplied reference proportions: monitor 380 pt, permission 380 pt, question 340 pt, and decision feedback at least 260 pt. Actual cutout/screen bounds still take priority. Latest steering removes the upper neck/step and keeps the same top screen-edge anchor for every notched mode. Expanded widens and lengthens directly from minimized/notch; it is not repositioned below the menu bar. The physical camera height is reserved before content. The full-width top may cover nearby menu items while expanded; the compact footprint stays unchanged and Escape/hover exit retracts it. Confirmation is a short simulated decision receipt, not turn completion.

Typography: native system fonts for title, prompt, options, actions and metadata; native SF Mono for filenames, paths, diff, code and diff line numbers. Black remains opaque in both system appearances. Original Nudgie is retained; no artwork/code is copied from the reference.

Monitor uses one focused demo task, with Codex/host metadata. No quota or multi-provider session rows are introduced. The entire task row activates the selected Desktop/Terminal app through CodexNavigator; this is app activation only, not verified thread/tab routing. Bundle IDs were read locally from the installed apps (the Codex bundle on this machine is named ChatGPT.app but uses com.openai.codex). No external apps were opened during automated checks.

Approval and question data are authored fixtures labeled Demo. Allow once/Deny and the three question choices only change synthetic state. No real permission or answer is sent, no Codex config is touched, and no transcript/file contents are read.

Motion follow-up: AppKit uses explicit deceleration with 380 ms expansion and 280 ms contraction. SwiftUI uses destination-width content, a brief crossfade, and animatable shell radius; NSHostingView intrinsic window sizing is disabled so it cannot compete with frame interpolation. This is source evidence, not a measured frame-rate or smoothness result.

Developer regression checks (pending):

1. [ ] Relaunch and confirm minimized is the same size. Hover/click to inspect monitor; verify readable title/metadata and SF Mono filenames.
2. [ ] Preview approval and question from the menu. Check path truncation, a continuous diff block, equal-width decision buttons and three full-row options. Tab/focus/click and Cmd-N/Y or Cmd-1/2/3 must work when the panel has explicit keyboard focus.
3. [ ] Choose Allow once/Deny or a question option. Confirm one centered receipt followed by minimized, no turn-completion celebration, and no real provider response. Preview a new attention state during receipt and sleep/wake; old timers must not clear or replay it.
4. [ ] Select Desktop or Terminal in Preview host and click the monitor row. Confirm application activation on the developer's machine. With multiple threads/windows/tabs, record that precise routing is not implemented; native navigation success must not be inferred from static renders.
5. [ ] Confirm Help and neighboring menu items remain visible and clickable while minimized. Expanded/attention intentionally may cover menu items while focus is on Nudge; confirm the top stays attached to the notch and retracts to the original compact footprint. Check physical camera exclusion, hover/pin/Escape, Spaces/full-screen, display reconfiguration, VoiceOver/keyboard, Light/Dark appearance and the non-notch fallback.
6. [ ] Repeat quick hover enter/exit and reverse expand/collapse while it is moving. Check continuity at the notch, no text rewrapping, no double images lingering, no flicker or abrupt geometry snap. Switch approval → question → receipt and toggle Reduce Motion during a transition; reduced motion should update immediately without a stuck panel. Record actual runtime smoothness on the developer’s display.

Fixture checks compile production sources without opening apps. No shared Xcode test target exists yet. To repeat:

```bash
task_checks_dir=$(mktemp -d)
xcrun swiftc -swift-version 6 \
  Nudge/Core/NudgeModels.swift Nudge/Core/PresentationReducer.swift \
  Nudge/Debug/PlaygroundScenario.swift NudgeCoreTests/PresentationChecks.swift \
  -o "$task_checks_dir/presentation"
"$task_checks_dir/presentation"
xcrun swiftc -swift-version 6 \
  Nudge/Core/NudgeModels.swift Nudge/Core/PresentationReducer.swift \
  Nudge/Debug/PlaygroundScenario.swift Nudge/App/AppState.swift \
  Nudge/Integration/Codex/Navigation/CodexNavigator.swift \
  Nudge/UI/NotchGeometry.swift Nudge/UI/NotchRootView.swift \
  Nudge/UI/NotchComponents.swift Nudge/UI/Nudgie.swift \
  NudgeCoreTests/NotchGeometryChecks.swift -o "$task_checks_dir/geometry"
"$task_checks_dir/geometry"
rm -r "$task_checks_dir"
```

Offscreen SwiftUI renders under `.impeccable/review/` cover the five requested states plus navigation-error peek/expanded on both notched and standard display geometry (14 captures). Error copy replaces the prompt/tool region so it fits within the fixed panel height. They are static layout evidence only; window interaction, native mouse routing, physical camera, accessibility interaction and real-host behavior remain developer verification.

Independent Impeccable finish review: **ship** for current source and all 14 static renders. It confirmed the full-width shell, common screen-top notch anchor, camera band, retained compact footprint, typography, and bounded navigation-error layout. A subsequent independent motion review also returned **ship** for updated source and static endpoints, with no material source/static regression found. Physical NSPanel placement, animation smoothness and interruption, mouse routing, focus/keyboard, Spaces and actual host activation remain pending developer checks.

## Handoff

M0 should remain open until the developer records the visual/window results above and the reducer/geometry automated test target is added and run. Correct any issues found here within M0, then stop and wait for the next phase instruction.
