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

Current M0 is a synthetic visual playground, not live monitoring. Desktop and CLI must eventually be proven separately. Codex works independently if Nudge is unavailable. No account, backend, telemetry, transcript persistence, persistent allow, or permission bypass. Initial live attention decisions remain in Codex; buttons in this visual playground are explicitly simulated. User has requested monitor-row app activation; exact thread/tab routing remains unverified.

## Brand Commitments

Name Nudge, original mascot Nudgie. User explicitly selected the five attached Vibe Island-style state screenshots as visual direction and requires black in both light and dark system appearances. Retain a single focused context, with no quota dashboard or multi-provider session list. Do not copy external mascot artwork or GPL implementation.

## Evidence on Hand

Source of truth: docs/Nudge-Project-Brief.md, AGENTS.md. Existing source and docs/Nudge-M0-Verification.md. User supplied five reference screenshots for monitor, approval, question, minimized, and confirmation. Synthetic fixture content must be identified as Demo. No real session ID, terminal tab ID, approval response contract, or question response contract is available to this UI yet.

## Accessibility & Inclusion

Respect Reduce Motion and Increase Contrast, native keyboard focus and VoiceOver. Meaning must not depend on color alone. Preserve camera exclusion. Latest explicit UX clarification: minimized must avoid disrupting menu items; expanded may cover them while the user focuses on Nudge, and must grow from the same notch anchor.
