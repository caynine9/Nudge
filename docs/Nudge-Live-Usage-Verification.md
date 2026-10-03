# Live Codex usage — verification and handoff

Implementation now connects the existing usage strip to Codex app-server's `account/rateLimits/read` response when the Live monitor is open. It selects the Codex bucket, maps 300 minutes to 5h and 10,080 minutes to 7d, and requires a valid percentage and future reset time for both windows. Incomplete or unavailable data shows muted dashes; Live never falls back to the fixed Demo percentages. The query uses the Desktop-selected CODEX_HOME and existing Codex sign-in through the local Codex process. It does not read auth files directly or persist/log usage values.

The strip refreshes on open and every five minutes while peek/expanded is open. It does not poll while collapsed or during attention. Codex hooks, config, wire data, and session detection are unchanged. The app-server request contacts Codex's authenticated rate-limit service through the existing local Codex runtime; API-key-only or signed-out configurations may return no usage data.

The macOS target build is the source-level validation for this change. Automated tests were not run in this task. Native appearance and account response behavior remain pending developer verification.

## Verifikasi manual oleh developer

1. With Codex Desktop signed in using ChatGPT, open Nudge to peek and expanded. Confirm both 5h and 7d show percentages and reset countdowns from Codex, then compare against Codex's own usage display.
2. Keep the monitor open for at least five minutes while using Codex. Confirm the values refresh, and confirm reset countdowns continue to update.
3. Use a signed-out or API-key-only Codex configuration. Confirm Live shows muted dashes and an unavailable hint, with no fixed Demo values presented as current usage.
4. Collapse Nudge and confirm it stops refreshing; open Demo and confirm the existing fixed usage examples remain labeled Demo.
5. Continue a normal Codex task while rate-limit data is unavailable. Confirm Nudge still reports session activity and Codex continues normally.

Contract references: [Codex app-server account/rate-limit methods](https://learn.chatgpt.com/docs/app-server) and [rate-limit response schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs).
