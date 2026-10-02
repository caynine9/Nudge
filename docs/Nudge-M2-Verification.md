# Nudge M2 — Verification and Developer Handoff

Date: **2 October 2026**

Implementation status: **M2 source and hermetic fixtures are implemented; manual host acceptance is pending.** The user explicitly instructed work to begin on M2 while the M1 Desktop/CLI manual record was still pending. This is a sequencing override, not evidence that M1 or M2 live-host criteria passed.

No Codex Desktop/CLI configuration was installed, removed, or edited for this implementation. Tests use temporary config roots, synthetic hook JSON, in-memory reducers, and local test sockets. No live prompts or permission decisions were run.

## Automated verification

| Check | Result |
|---|---|
| Xcode/project scheme discovery | Passed; targets `Nudge`, `NudgeBridge`, `NudgeCoreTests`, and `NudgeIntegrationTests` are available |
| Debug app, helper, and test build | Passed as part of the shared `Nudge` test action |
| Debug `Nudge` scheme tests | Passed; both `NudgeCoreTests` and `NudgeIntegrationTests`, 47 tests total, 0 failures, 0 skipped (result bundle: `/tmp/nudge-m2-verified-final4.xcresult`) |
| Release app/helper build | Passed with `xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Release -destination 'platform=macOS' build` |
| `git diff --check` | Passed |
| Live Codex Desktop and CLI | Pending developer; fixture results do not count as host evidence |
| Native notch, sleep/wake, accessibility, and Reduce Motion | Pending developer |

Coverage includes opaque turn IDs and resumed turns without `SessionStart`, late tool events, concurrent tools, pending-interaction reconciliation, long-running quiet tool retention, same-turn Stop deduplication after the TTL, project metadata enrichment, ordered event ingress and socket flush before wake snapshots, sleep-time completion suppression, focus A/B/A replay prevention, malformed configuration preservation, duplicate hook cleanup, restrictive matcher repair, uninstall backups, and custom `CODEX_HOME` validation. Edge-case fixture provenance is documented in `NudgeIntegrationTests/Fixtures/Codex/edge-cases/README.md`; all fixtures there are synthetic.

Passing automated tests do not prove the installed Desktop or CLI versions deliver the documented hook events. The extra suggestion-style Stop behavior remains unverified by live captures because the published hook shape has no suggestion-only discriminator. M2 accepts Stop callbacks, suppresses repeated completion using session/turn identity, and does not inspect assistant prose. Review the test result bundle if a detailed test listing is needed.

## Manual verification by the developer

All items below are **pending**. Use a sandbox Codex project and a recoverable temporary configuration. Record actual version/build and observed behavior; do not mark unsupported paths as passed.

1. Record macOS, Codex Desktop version/build, CLI version, launch method, effective config root for each host, any `CODEX_HOME`, trust/reload state, and the M1 verification status. Keep Desktop and CLI records separate.
2. Start a new local thread directly in Codex Desktop, then resume an existing local thread. Confirm Nudge follows project, thinking, tool, and terminal status without launching a terminal or Nudge app-server.
3. Repeat new/resumed/tool/completion/interrupt scenarios independently in Codex CLI. Record first event, IDs, trust state, and any event differences.
4. Run a tool for longer than ten minutes on each host. Confirm Nudge remains in working state throughout the quiet interval, then updates after the tool finishes.
5. Review the automated synthetic Stop/duplicate and A → B → A tests. If the installed host emits an extra suggestion Stop, capture a sanitized fixture with host version and scenario provenance, then verify it produces one completion. Do not treat a synthetic replay as host evidence.
6. Sleep the Mac during working, after completion, and around a completion event. Wake it and confirm one current presentation, no replayed celebration, no stale collapse timer, and no delayed mascot hop. Repeat with Reduce Motion enabled.
7. Seed a question/permission pending state in the canonical test harness. Confirm unrelated progress, opening Codex, collapse, quiet time, and sleep do not clear it; matching progress or valid turn termination does. Live question/permission mirroring remains M3 work.
8. In a temporary config, install/reinstall with duplicate Nudge handlers and foreign hooks, then uninstall. Confirm one canonical Nudge handler, foreign values remain, each mutation has an exact private backup, and a no-op does not rewrite the file.
9. On a temporary config, test malformed JSON, duplicate keys, unsupported shapes, symlink target, backup failure, and simulated concurrent edit. Confirm the original remains unchanged on abort and repair guidance identifies the chosen target.
10. Test an existing CLI custom `CODEX_HOME`, separate host roots, an invalid relative value, a missing directory, and a selected folder. Confirm invalid values do not fall back and write to `~/.codex`; establish Desktop custom-root behavior only through a supported host path.
11. Close Nudge while Desktop and CLI workflows run. Confirm Codex continues normally; reopen Nudge and confirm subsequent events restore current status without replaying terminal effects. Also inspect notch/fallback display, Spaces/full-screen, hover, VoiceOver, and idle motion.

| Workflow | Version / effective config / trust | Event or fixture provenance | Result |
|---|---|---|---|
| Desktop new local thread | Pending | Pending live | Pending |
| Desktop resumed local thread | Pending | Pending live | Pending |
| Desktop interrupt and next turn | Pending | Pending live | Pending |
| CLI new/resumed/interrupt | Pending | Pending live | Pending |
| Long-running tool, Desktop | Pending | Pending live | Pending |
| Long-running tool, CLI | Pending | Pending live | Pending |
| Duplicate/suggestion Stop | Pending | Synthetic fixture; live capture pending | Pending |
| Sleep/wake, focus change, Reduce Motion | Pending | Native/manual | Pending |
| Pending question/permission resolution | N/A for M2 UI | Canonical fixture; live mirror M3 | Pending |
| Installer recovery and uninstall | Temporary only | Config test/manual | Pending |
| Custom home, CLI / Desktop | Pending per host | Synthetic resolver test; live path pending | Pending |
| Nudge unavailable, Desktop / CLI | Pending per host | Pending live | Pending |

M2 source completion is ready for developer review. **M2 acceptance remains pending until the live Desktop and CLI checks and native sleep/wake review above are recorded.** Stop after this handoff; do not begin M3 until the user instructs the next phase.
