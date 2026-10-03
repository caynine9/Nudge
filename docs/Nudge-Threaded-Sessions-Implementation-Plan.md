# Threaded Active Sessions — Implementation Plan

Tanggal: 3 Oktober 2026. Fase aktif: follow-up terbatas M1 untuk metadata judul lokal dan tampilan expanded. Permintaan pengguna mendahulukan pengelompokan project → sesi, judul chat, serta satu kolom status/aktivitas di kanan. Collapsed dan peek tetap satu konteks; expanded tetap dibatasi tinggi incumbent + 10 pt dengan scroll.

## Kontrak dan aliran data

Hooks tetap sumber aktivitas dan identitas `session_id`. Kontrak hook memberi `cwd`, tetapi tidak memberi judul chat. Codex app-server mendokumentasikan `thread/read` dengan `includeTurns: false` dan `thread.name` bila judul tersedia. Probe read-only pada CLI 0.154.0 dan binary Codex Desktop yang dibundel (0.160.0) berhasil membaca metadata untuk satu thread lokal yang ID-nya cocok; ini belum membuktikan seluruh workflow Desktop new/resumed atau CLI. Nudge memanggil app-server hanya untuk ID yang sudah terlihat dari hooks, tidak memulai/resume thread, tidak subscribe aktivitas, dan tidak membaca turns. [Hooks](https://learn.chatgpt.com/docs/hooks) · [App-server](https://learn.chatgpt.com/docs/app-server)

```text
Hook envelope → CodexEventIngress → CodexEventMonitor → AppState → expanded UI
                         └→ bounded, read-only title lookup by session_id
                              → verified thread.id + bounded thread.name
                              → AppState in-memory title overlay
```

Kegagalan binary, timeout, malformed response, absent title, atau ID mismatch memakai short session ID. Lookup di luar main actor, dibatasi ukuran/waktu, serta dideduplikasi dan di-cache singkat. Judul hanya dalam memori UI; tidak dikirim melalui wire, tidak disimpan, dan tidak dicatat pada diagnostics. URL deep link row tetap memakai full session ID. Hook/config/wire schema tidak berubah; tidak ada backup atau migrasi yang diperlukan. Nudge dan Codex tetap berjalan normal bila lookup gagal.

## Desain expanded

Project label menjadi header tiap kelompok. Sesi yang terdeteksi tampil sebagai row berindentasi di bawah project; judul chat menjadi teks utama, ID pendek menjadi fallback bila judul belum tersedia. Setiap row memiliki kolom kiri untuk identitas dan kolom kanan yang rata kanan untuk phase (`Working`, `Thinking`, attention) serta detail tool (`Editing files`, dll.) bila ada. Detail tool lebih tenang daripada phase sehingga keduanya terbaca sebagai status dan aktivitas, bukan dua headline. Urutan kelompok mengikuti sesi berprioritas tertinggi menurut FocusPolicy; urutan sesi di dalam kelompok tetap urutan aktif semula. Nama folder sama dari dua cwd berbeda belum dapat dibedakan oleh wire saat ini, sehingga pengelompokan memakai project label yang tersedia dan tidak mengklaim Git remote/root.

## File yang disentuh

- `Nudge/Integration/Codex/AppServer/CodexThreadMetadataReader.swift` (baru)
- `Nudge/Services/CodexEventIngress.swift`, `Nudge/App/NudgeAppDelegate.swift`, `Nudge/App/AppState.swift`
- `Nudge/Core/Reducer/ActivityProjectGroups.swift` (baru), `Nudge/UI/NotchRootView.swift`
- `NudgeIntegrationTests/CodexEventIngressTests.swift`, `NudgeIntegrationTests/CodexThreadMetadataReaderTests.swift` (baru), `NudgeCoreTests/ActivityProjectGroupsTests.swift` (baru), `NudgeCoreTests/NotchLayoutChecks.swift` (fixture visual)
- `Nudge.xcodeproj/project.pbxproj`, `PRODUCT.md`, `DESIGN.md`, `.impeccable/surfaces/nudge-ui-notchrootview-swift.md`
- Plan ini dan `docs/Nudge-Threaded-Sessions-Verification.md` (baru)

## Verifikasi

Tes yang bermakna: parser menolak ID lain/malformed/oversized title dan tidak mengambil turns; timeout/failure kembali ke fallback; grouping menjaga urutan serta semua sesi sekali; ingress tetap berurutan. Build/test Xcode dan `git diff --check`. Render statis untuk satu dan banyak project/sesi, long title, fallback tanpa title, serta layar tanpa notch. Developer memverifikasi manual Desktop new/resumed dan CLI secara terpisah, judul yang berubah, click-through ke chat benar, scroll + cap tinggi, keyboard/VoiceOver, dan sleep/wake. Probe metadata tunggal tidak menggantikan verifikasi tersebut.

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
