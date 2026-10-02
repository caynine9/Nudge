# Edge-case fixture provenance

These fixtures are **synthetic** examples built from the published Codex hook field shapes reviewed on 2 October 2026. They are not captured from Codex Desktop or Codex CLI and prove no installed-host coverage.

- `stop-after-continuation.jsonl` checks two `Stop` callbacks for one opaque turn, with the documented `stop_hook_active` field changing from false to true. The field does not mark a suggestion-only Stop.
- `resume-without-session-start.jsonl` starts from a valid tool event without `SessionStart` and uses a nonnumeric turn ID.
- `long-tool-duplicate-enrichment.jsonl` repeats one tool event while adding a sanitized cwd basename. It contains no command, prompt, tool input, output, transcript, or personal path.

The adapter whitelists the event/session/turn/tool identifiers, tool name, and a basename-derived project label. Any local Desktop/CLI captures must be separately sanitized, versioned, and identified as developer-observed fixtures before they enter the repository.
