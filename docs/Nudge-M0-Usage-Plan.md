# M0 — Monitor usage glance

User requested a compact usage strip in expanded Monitor, subsequently included hover peek, and explicitly chose simulated values within M0. Add 5-hour and weekly windows, used percentage, and time until reset above the focused task in both open Monitor modes. Reuse the black shell, native 11 pt metadata type, green usage text, gray reset text, and existing orange symbol; keep Demo visible. This is an ordinary extension of the existing Operate surface, with no new visual system.

Data flow: authored PlaygroundScenario fixtures → Monitor header in NotchRootView. Usage stays outside lifecycle/presentation reducers; it creates no timers or real account reads. Peek and expanded Monitor show the same strip. Minimized, attention, navigation and existing dimensions keep their current behavior. A VoiceOver label and help text clarify that percentages are used and durations are until reset.

Desktop/CLI: this session does not add live monitoring or an account-limit provider. No host versions or config contracts are used by the feature. Missing live data is represented by the explicit Demo fixture, never claimed as real usage. No config/hook/wire mutation, persistence, dependency, credentials or network operations in Nudge. Recovery is reverting these local fixture/view edits.

File yang disentuh:
- Nudge/Debug/PlaygroundScenario.swift — authored usage-window fixtures.
- Nudge/UI/NotchRootView.swift — peek/expanded Monitor header and accessible usage labels.
- docs/Nudge-M0-Usage-Plan.md — scope and required rules.
- docs/Nudge-M0-Verification.md — automated evidence and numbered developer checks.

Verification: Debug build; existing standalone presentation, geometry and full-canvas layout checks; static notch/fallback expanded, peek, attention and navigation-error renders. Native hover, layout during motion, keyboard/VoiceOver and Reduce Motion remain developer verification. No additional implementation-mirroring test is needed for two static fixture labels. No commit unless requested.

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
