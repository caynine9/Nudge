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

## Width-first reveal — 2026-10-02

User direction: minimized opens by widening first, then increasing height with overlap, as one continuous motion. Closing follows the same path in reverse. Use one animatable expansion value and a continuous mapping to width/height rather than queued delayed actions; interruptions retarget the same spring. Width reaches its endpoint before height, with a short initial height hold and overlapping travel. Open-to-open size changes still interpolate their destination dimensions. Keep the shell-owned overlay, screen anchor, pointer geometry and Reduce Motion behavior.

Files for this refinement: `Nudge/UI/NotchComponents.swift` (progress mapping and animatable frame), `Nudge/UI/NotchRootView.swift` (frame integration), `NudgeCoreTests/NotchGeometryChecks.swift` (motion-path invariants), and this plan plus `docs/Nudge-M0-Verification.md`. Validate bounded/monotonic geometry, overlap, exact endpoints, reverse-path continuity, full-canvas layout fixtures and Debug build. Developer checks width-first opening, rapid reversals and Reduce Motion. No timers, dependencies, config changes, integration changes or work beyond M0.

## User video reference — 2026-10-02

Reference: the user-provided local `Animation nudge.mp4` (30.117 s, 60 fps), inspected through coarse frames and 50 ms samples around 5.50–6.10 s, 18.70–19.40 s, 26.30–26.95 s and 28.25–28.90 s. The user clarified this is not an official Vibe Island demo; it is their desired motion reference. The opening/closing shell keeps its top anchor while content blurs/fades; expanded permission → question and question → monitor dissolve through a briefly blurred state as shell dimensions morph. Visible transitions span approximately 0.3–0.4 s in those samples; these are observations, not exact source timing constants.

M0 implementation: retain the width-leading reversible shell path and original Nudge visual content. Add a short blur/opacity transition to expanded page replacements, including phase changes within the monitor; keep outgoing pages at their own destination width so text does not reflow during a shell resize. Retain the outgoing page identity through collapse. A bounded blur also softens opening/closing content, without blurring the black shell. Reduce Motion removes blur and spatial movement. SwiftUI owns cancellation; no queued state changes, backend work or new dependencies.

Touched files for this refinement: `Nudge/UI/NotchComponents.swift`, `Nudge/UI/NotchRootView.swift`, `NudgeCoreTests/NotchGeometryChecks.swift`, this plan and `docs/Nudge-M0-Verification.md`. Existing full-canvas layout fixtures verify dimensions; test the reversible motion path, review bounded content effects, then build and inspect static endpoints. Developer checks timing, rapid page changes, outgoing text stability, reversal and Reduce Motion. The separately present M1 plan is outside this work.

Implementation detail: keep the monitor page and Nudgie identity alive across working/done/failure. Apply the same blur dissolve to its text block; replacing the entire mascot subtree would drop an in-flight one-shot celebration. Permission/question/confirmation replacements dissolve the full page. Each outgoing page retains its own layout width inside its identity.

## Reference correction: simultaneous spring — 2026-10-02

The user clarified that both dimensions move together in the reference, followed by a small settling bounce in either direction. This supersedes the earlier width-first path. Remove that remapping and animate the explicit width/height frame with one underdamped SwiftUI spring. Keep the content blur transitions, stable top-center anchor, overlay-owned layout, and Reduce Motion behavior. Reserve a small transparent margin in the native canvas for overshoot so the widest/tallest state does not clip; keep target layout constraints independent from this margin.

Files: `Nudge/UI/NotchComponents.swift`, `Nudge/UI/NotchRootView.swift`, `Nudge/UI/NotchGeometry.swift`, `Nudge/UI/NotchPanelController.swift`, `NudgeCoreTests/NotchGeometryChecks.swift`, this plan and `docs/Nudge-M0-Verification.md`. Geometry/controller changes are necessary because a canvas sized exactly to the final state clips the requested bounce. Replace obsolete width-first assertions with actual SwiftUI spring samples checking small overshoot, settling, and canvas containment. Run full-canvas endpoint fixtures and Debug build. Manual QA: both axes start together, one subtle rebound, quick reversals, clipping, click-through, and Reduce Motion. No integration/config or phase expansion.
