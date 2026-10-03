# Live Codex usage glance

Implement the existing 5-hour and weekly usage strip for the Live monitor. The source is the local Codex app-server `account/rateLimits/read` request, which uses the selected Codex configuration and existing Codex authentication. Nudge maps `windowDurationMins` 300 to 5h and 10080 to 7d, and shows used percentage plus reset time. The strip remains visible in Demo with its labeled fixture values.

Data flow: Live monitor enters peek/expanded → AppState asks a bounded metadata reader → bundled Codex CLI app-server, with the Desktop-selected CODEX_HOME → parse only the `codex` bucket → publish two complete windows → reuse the existing UI strip. Refresh on open and every five minutes while the monitor stays open. No request while collapsed or on attention pages. Local app-server makes the authenticated service request; Nudge never reads token files directly, writes config, sends usage to another backend, or persists account values.

Contract: use the official `account/rateLimits/read` response, preferring `rateLimitsByLimitId.codex` and falling back to legacy `rateLimits` only if the new bucket map is absent. Identify windows by duration rather than primary/secondary position. Require both windows, valid 0–100 percentages, and future reset timestamps; incomplete, unsupported-auth, and failed responses display unavailable, never simulated or stale data. No wire schema or hook changes.

Failure behavior: app-server missing, request timeout, sign-in/API-key-only auth, absent rate windows, malformed response, or unavailable CODEX_HOME all result in a muted `5h — · 7d —` strip. These conditions do not affect hook monitoring or Codex operation. Positive results are cached briefly in memory to avoid duplicate local processes and usage reads.

Files touched:
- `Nudge/Integration/Codex/AppServer/CodexThreadMetadataReader.swift` — bounded rate-limit request and strict snapshot parsing, sharing the existing local app-server transport.
- `Nudge/App/AppState.swift` — refresh status and in-memory result.
- `Nudge/App/NudgeAppDelegate.swift` — configure the existing bundled/local CLI reader.
- `Nudge/UI/NotchRootView.swift` — connect Live and Demo to the existing 5h/7d strip.
- `docs/Nudge-Live-Usage-Plan.md` and `docs/Nudge-Live-Usage-Verification.md` — contract, limits, and handoff.

Validation: compile the macOS target and review the diff. Do not read a real account during implementation. Manual verification by the developer covers signed-in ChatGPT usage, API-key-only or signed-out state, fresh reset values, and Demo fixtures, plus confirming Codex still works when usage is unavailable.

```text
ATURAN PENGERJAAN — WAJIB DIBACA
JANGAN KERJAKAN SEMUA FASE SEKALIGUS.
Kerjakan SATU FASE PER SESI. Setelah satu fase selesai dan diverifikasi, berhenti dan laporkan. Tunggu instruksi sebelum lanjut ke fase berikutnya.
Fase aktif harus mengikuti scope dan Kriteria Selesai yang tertulis di AGENTS.md dan project brief, dengan instruksi eksplisit pengguna sebagai prioritas.
Kalau plan mengubah hook/config/wire schema, jelaskan compatibility, backup, dan recovery strategy sebelum implementasi.
Checklist di akhir SETIAP fase

1. Build dan tests yang relevan berhasil, atau kegagalan toolchain dijelaskan
2. Reducer, installer, dan IPC mempertahankan invariants serta test yang relevan
3. Dukungan Codex Desktop dan CLI dibuktikan terpisah untuk live integration; CLI-only tidak cukup
4. AI tidak mengubah config/data nyata atau menjalankan verifikasi manual milik developer tanpa instruksi eksplisit
5. Developer menjalankan Verifikasi manual oleh developer sesuai Kriteria Selesai fase tersebut
6. Commit terpisah per fase sesuai instruksi pengguna

Larangan umum

* Jangan mengerjakan fase berikutnya dalam sesi fase aktif tanpa instruksi eksplisit pengguna
* Jangan refactor file di luar daftar "File yang disentuh" tanpa alasan tertulis
* Jangan menganggap synthetic events atau CLI tests sebagai bukti dukungan Codex Desktop
* Jangan menganggap app-server terpisah otomatis memantau thread Desktop yang sudah berjalan
* Jangan overwrite malformed config, menghapus foreign hooks, atau memakai destructive fallback
* Jangan memblokir Codex ketika Nudge gagal atau melakukan silent auto-allow
* Jangan menambah persistent allow, bypass, atau programmatic question answering ke MVP
* Jangan persist prompt/transcript penuh atau secrets secara default
* Jangan melakukan heavy parsing/IPC/file work di main actor
* Jangan menambah dependency, provider, backend, telemetry, atau dashboard di luar scope
* Jangan copy code/artwork GPL dari Code Island
* Jangan "sekalian merapikan" kode yang tidak diminta
```
