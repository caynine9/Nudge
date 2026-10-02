# Nudge

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS 15+; this is not an iOS app or a website. The installed Impeccable platform presets currently cover web/iOS/Android; AppKit/SwiftUI and the project brief govern this platform.

## Users

Developers working locally in Codex Desktop or CLI who switch to another Mac app while an agent is working.

## Product Purpose

A small menu-bar companion that presents one focused Codex context through a notch overlay, with a fallback for non-notch displays. Make work, attention, completion, failure, and interruption easy to see, then return the user to Codex.

## Operating Context

Swift 6, SwiftUI composition, AppKit NSPanel windowing; camera exclusion, menu bar, multiple displays, Spaces, full-screen, sleep/wake, keyboard, VoiceOver, and Reduce Motion matter. No always-running idle animation.

## Capabilities and Constraints

M1 now has a local lifecycle-hook event spine, focused live snapshot, helper, Unix socket, safe `hooks.json` installer, and explicit Demo mode. Source and hermetic tests are available; live Codex Desktop new/resumed threads and CLI coverage remain pending developer verification. Nudge shows trust/host status as unverified until evidence arrives, and Codex works independently if Nudge is unavailable. No account, backend, telemetry, transcript persistence, persistent allow, or permission bypass. Demo attention controls remain simulated. Exact thread/tab routing remains unverified.

## Brand Commitments

Name Nudge, original mascot Nudgie. User explicitly selected the five attached Vibe Island-style state screenshots as visual direction and requires black in both light and dark system appearances. Retain a single focused context, with no quota dashboard or multi-provider session list. Do not copy external mascot artwork or GPL implementation.

## Evidence on Hand

Source of truth: docs/Nudge-Project-Brief.md, AGENTS.md. M0 manual verification remains pending in docs/Nudge-M0-Verification.md. M1 implementation status and remaining handoff are in docs/Nudge-M1-Verification.md; published hook contract vs installed-host evidence is separated in docs/Nudge-M1-Codex-Contract.md. User supplied five reference screenshots for monitor, approval, question, minimized, and confirmation. Synthetic fixture content must be identified as Demo. Live question/permission mirroring is not in M1; no approval response contract or precise thread routing is claimed.

## Accessibility & Inclusion

Respect Reduce Motion and Increase Contrast, native keyboard focus and VoiceOver. Meaning must not depend on color alone. Preserve camera exclusion. Latest explicit UX clarification: minimized must avoid disrupting menu items; expanded may cover them while the user focuses on Nudge, and must grow from the same notch anchor.
