# M0 — Continuous notch motion

Scope: repair minimized ↔ peek/expanded/attention/confirmation motion within M0. One opaque shell stays attached to its top-center anchor, with stable text layout and interruption-safe movement. No live integration changes.

The focal interaction is opening then reversing before settling: SwiftUI will own shell size, radius, and content visibility with one non-bouncing spring. AppKit keeps a stable transparent canvas; it no longer interpolates the window frame on each state change. Pointer routing follows the rendered shell bounds, never the full canvas. Expanded content retains its last open layout while closing; monitor identity survives ordinary phase changes. No permanent animation loop or new dependency.

Boundary: the presentation reducer still chooses semantic mode and hover timers; the view animates that target; geometry supplies canvas and screen coordinates; the controller only positions the canvas and reconciles pointer routing. Display changes, sleep/wake, and Reduce Motion must settle without stale transitions. Main-actor work is UI geometry only. Desktop/CLI event contracts do not change and remain outside M0.

Trade-off: a fixed transparent canvas avoids per-frame native window resizing, but requires explicit click-through outside the visible shell. Test that coordinate mapping at intermediate sizes and keep native click/focus verification in developer QA. Risks: transparent mouse interception, stale hover during collapse, hidden content accessibility, text reflow, and animation interruption. No config, hook, wire, data, or privacy migration; reverting UI changes is sufficient recovery.

File yang disentuh:
- Nudge/UI/NotchPanelController.swift — stable canvas and pointer routing.
- Nudge/UI/NotchRootView.swift — shell ownership and stable content layers.
- Nudge/UI/NotchGeometry.swift — canvas and visible-frame mapping.
- Nudge/UI/NotchComponents.swift — semantic motion tokens.
- NudgeCoreTests/NotchGeometryChecks.swift — canvas/interaction regressions.
- docs/Nudge-M0-Motion-Plan.md and docs/Nudge-M0-Verification.md — scope and evidence.

Validation: Debug build, existing reducer fixtures, geometry fixtures extended for canvas containment, negative origins, fallback and intermediate-size pointer bounds; static endpoints if existing render tools are available. Native smoothness, reversal, focus, menu clicks, display changes and Reduce Motion are developer checks. No claim of runtime smoothness from static renders. Stop within M0.

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

## Follow-up: shell dimension regression

The retained open subtree contributes its minimum size to the ZStack, inflating smaller states despite the outer target frame. Make content an overlay of the size-owning shell so it cannot contribute layout dimensions. Preserve the existing spring, anchor, fixed canvas and pointer observer. Add `NudgeCoreTests/NotchLayoutChecks.swift` to the touched files: render each state on the full native canvas and assert opaque bounds and top-center anchoring for notch and fallback. The pre-fix fixture reproduces a 370 × 164 pt minimized shell instead of 264 × 34 pt. Prior endpoint-cropped renders did not test this invariant. No integration/config changes; manual verification remains with the developer.
