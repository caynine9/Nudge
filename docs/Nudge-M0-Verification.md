# Nudge M0 — Build and Developer QA Handoff

Status: **M0 implementation is in place; manual visual verification is pending.** This record separates what was checked from what still requires the developer's Mac and interaction review.

## Automated project checks

- Xcode project parses and exposes the shared `Nudge` scheme.
- `Nudge` is configured as a macOS app with deployment target macOS 15, Swift 6 language mode, and `LSUIElement` enabled.
- Debug build: **passed** with Xcode 27.0, Swift 6.4, macOS 27 SDK.
- Release build: **passed** with the same toolchain.
- `NudgeCoreTests` target and reducer/geometry test cases are **not present yet**; no automated unit test run is claimed here.
- Codex Desktop/CLI hooks and real-session behavior are outside M0 and have not been exercised.

## Developer visual and interaction checks

Record macOS version, built-in display model, external display setup, and result for each item. All items are pending.

1. [ ] Launch from the shared Xcode scheme. Confirm Nudge appears in the menu bar without a Dock icon or ordinary app window.
2. [ ] Use **Simulate phase** to inspect discovered, idle, thinking, running tests, waiting permission, waiting input, completed, failed, interrupted, and ended.
3. [ ] Hover in/out quickly, re-enter during the exit delay, click the header to pin, and press Escape to collapse. Check for flicker, text snapping, or unexpected expansion.
4. [ ] Resolve attention with **Simulate progress**. Confirm clicking/expanding the panel alone does not clear its attention state.
5. [ ] On a physical notch display, check that content clears the camera housing, sits on a stable top anchor, and Nudgie remains visible. On a non-notch/external display, check the compact island fallback.
6. [ ] Switch Spaces, enter full-screen, invoke Mission Control, and test menu-bar auto-hide. Check that the panel does not steal focus on hover or block a large transparent area.
7. [ ] Toggle Reduce Motion while Nudge is open. Check motion stops while phase and attention meaning remain clear. Also check Increase Contrast, VoiceOver, and keyboard access.
8. [ ] Complete the same simulated turn more than once, then start a new turn. Confirm one completion flourish for the new turn and no success pose for failed/interrupted.
9. [ ] Sleep and wake during work, attention, and after completion. Check for replayed motion, duplicate collapse, or lost attention.
10. [ ] Leave the overlay idle and hidden. Check Activity Monitor for an always-running animation/timer loop.

## Handoff

M0 should remain open until the developer records the visual/window results above and the reducer/geometry automated test target is added and run. Correct any issues found here within M0, then stop and wait for the next phase instruction.
