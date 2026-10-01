# AGENTS.md

Panduan ini digunakan oleh Codex / Claude Code / agent AI saat bekerja di repository **Nudge** — companion native macOS yang menampilkan aktivitas Codex melalui notch. Struktur panduan diadaptasi dari repository `invoice.swift`; aturan produk, arsitektur, fase, dan pengujian seluruhnya disesuaikan untuk Nudge.

**Dokumen sumber kebenaran:** [`docs/Nudge-Project-Brief.md`](docs/Nudge-Project-Brief.md). Instruksi eksplisit pengguna menjadi prioritas. Jika panduan ini bertabrakan dengan project brief, ikuti project brief lalu perbaiki panduan ini.

## Ringkasan Proyek

**Nama aplikasi adalah Nudge**. Codex adalah integrasi yang didukung. Nama target yang direncanakan: `Nudge`, `NudgeBridge`, `NudgeCoreTests`, dan `NudgeIntegrationTests`. Mascot original memiliki working name **Nudgie**.

Alur utama:

1. Pengguna bekerja pada satu project/repository di Codex macOS app atau Codex CLI.
2. Pengguna berpindah ke aplikasi lain ketika Codex bekerja.
3. Nudge menampilkan project, status, dan ringkasan tool melalui notch.
4. Nudge menarik perhatian ketika Codex bertanya, membutuhkan izin, selesai, gagal, atau terinterupsi.
5. Pengguna membuka Codex dari Nudge untuk melanjutkan konteks yang relevan.
6. Nudge kembali tenang setelah perhatian tidak lagi diperlukan.

Produk harus terasa seperti companion Mac yang kecil, fokus, responsif, dan polished. Satu konteks aktif mendapat prioritas visual; jangan mengubahnya menjadi dashboard operasi multi-agent.

## Status Repository Saat Ini

Saat panduan ini dibuat, repository masih pada tahap dokumentasi:

- `docs/Nudge-Project-Brief.md` — product dan technical brief.
- `AGENTS.md` — panduan pengerjaan repository.
- Belum ada project Xcode, target aplikasi, bridge, atau test suite.

Struktur berikut adalah target bertahap, bukan klaim bahwa kode sudah tersedia. Jangan membuat refactor atau abstraksi besar hanya untuk mencocokkan struktur target.

Saat membuat project, verifikasi platform macOS, target aplikasi dan helper, scheme, deployment target, signing, serta konfigurasi `LSUIElement`. Jangan mengasumsikan scaffold Apple generik sudah memiliki konfigurasi yang tepat.

## Batas Produk yang Mengikat

Produk awal harus:

- mendukung **Codex macOS app / Desktop secara wajib**, termasuk local new dan resumed threads yang dimulai langsung dari app;
- juga mendukung Codex CLI; integrasi CLI saja **tidak memenuhi acceptance criteria MVP**;
- tidak mewajibkan pengguna membuka terminal atau menjalankan app-server milik Nudge untuk memantau aktivitas Desktop;
- menampilkan satu focused context meskipun beberapa session tersedia secara internal;
- menjadi aplikasi menu-bar/accessory dengan notch overlay dan fallback untuk layar tanpa notch;
- memakai lifecycle hooks sebagai jalur aktivitas utama setelah kompatibilitas kedua host diverifikasi;
- tetap membiarkan Codex bekerja normal ketika Nudge tertutup, crash, atau bridge/socket tidak tersedia;
- memproses metadata lokal secukupnya, tanpa account, cloud backend, telemetry, atau penyimpanan transcript penuh secara default;
- memakai mascot original, motion yang tenang, dan dukungan Reduce Motion;
- memasang dan menghapus integrasi secara aman, reversible, dan tanpa merusak konfigurasi pengguna.

Jangan memasukkan provider lain, fleet dashboard, multi-repo command center, conversation browser, prompt editor, persistent allow rules, bypass permissions, quota dashboard, cloud sync, mobile companion, marketplace, atau full terminal tab routing ke MVP. Remote/cloud execution berada di luar MVP lokal awal.

## Teknologi Utama

- **Platform:** native macOS; baseline yang disarankan brief adalah macOS 15+.
- **Bahasa:** Swift; gunakan Swift 6 mode bila toolchain dan target memungkinkan.
- **UI:** SwiftUI untuk composition; AppKit `NSPanel` untuk windowing/notch, screen geometry, activation, dan lifecycle.
- **IPC:** per-user Unix domain socket dan versioned JSON envelope melalui Foundation `Codable`.
- **Bridge:** command-line helper native kecil bernama `NudgeBridge`.
- **Domain:** deterministic session reducer dan presentation reducer terpisah.
- **Diagnostics:** `OSLog`, bounded dan redacted.
- **Persistence:** preferences, status instalasi, dan metadata minimal; database transcript bukan kebutuhan MVP.
- **Distribusi:** Developer ID, hardened runtime, dan notarized DMG; App Store bukan target awal.
- **Testing:** unit/fixture tests untuk reducer, installer, wire validation, dan failure behavior; verifikasi manual di macOS untuk visual dan integrasi kedua host.

Utamakan Apple frameworks. Dependency baru harus memiliki alasan tertulis dan penilaian maintenance, binary size, privacy, serta manfaatnya. Jangan menambah library atau backend hanya untuk mengikuti pola proyek lain.

## Struktur Folder Target

```text
Nudge.xcodeproj
Nudge/
├── App/
├── Core/
│   ├── Models/
│   ├── Events/
│   └── Reducer/
├── Integration/
│   └── Codex/
│       ├── Hooks/
│       ├── Navigation/
│       ├── AppServer/       # optional enrichment/reconciliation
│       └── Fallback/        # optional assistant preview recovery
├── IPC/
├── UI/
│   ├── Notch/
│   ├── Components/
│   ├── Mascot/
│   └── Motion/
├── Services/
├── Settings/
└── Support/
NudgeBridge/
NudgeCoreTests/
NudgeIntegrationTests/
docs/
```

Arah data dan boundary:

```text
Codex Desktop / CLI lifecycle hooks
    → NudgeBridge → versioned wire envelope → per-user socket
    → Decoder / Canonicalizer → SessionReducer
    → AppState (@MainActor) → PresentationReducer → NSPanel / SwiftUI

Attention action → CodexNavigator → Codex Desktop thread / app activation
```

`Core` tidak boleh bergantung pada SwiftUI views, AppKit windows, atau format raw provider. View tidak boleh memuat parsing hook, config mutation, atau lifecycle business logic. Protocol dibuat untuk boundary yang memberi testability atau replaceability nyata, bukan abstraksi kosong.

## Perintah Penting

Perintah Xcode berikut adalah target setelah project tersedia; sesuaikan dengan scheme aktual:

```bash
xcodebuild -list -project Nudge.xcodeproj
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test
git diff --check
```

Jangan melaporkan build/test berhasil sebelum benar-benar dijalankan. Jika Xcode project, shared test scheme, atau toolchain belum tersedia, jelaskan batas tersebut. Command Line Tools saja mungkin tidak cukup untuk build aplikasi macOS ini.

## Prinsip Desain — Mengikat Seluruh Implementasi

**P1 — Codex Desktop adalah requirement inti.** Aktivitas local thread yang dimulai langsung di app harus terlihat. CLI dan synthetic fixtures tidak membuktikan dukungan Desktop.

**P2 — Codex tetap mandiri.** Nudge tidak boleh menjadi control plane wajib. Bridge menggunakan bounded timeout; app failure tidak menghambat coding dan tidak menyebabkan auto-allow.

**P3 — Satu konteks, sedikit gangguan.** Prioritaskan attention, pilihan pengguna, lalu session aktif sesuai focus policy dalam brief. Jangan memperluas panel atau memainkan suara untuk setiap tool call.

**P4 — State harus deterministik.** Normalisasi provider di boundary. Session phase dan presentation mode memiliki sumber kebenaran terpisah, stable IDs, serta transisi yang dapat diuji.

**P5 — Konfigurasi milik pengguna.** Installer hanya mengelola entry milik Nudge, preserving foreign hooks, dengan backup dan atomic replacement. Parse failure tidak boleh dianggap sebagai config kosong.

**P6 — Keputusan tetap di Codex pada MVP.** Mirror permission/question dan arahkan pengguna ke Codex. Jangan memalsukan jawaban, auto-approval, persistent allow, atau bypass.

**P7 — Lokal dan privat.** Simpan metadata minimal. Jangan persist prompt/transcript penuh, shell output, file contents, atau secrets secara default. Ringkasan tool dan diagnostics harus dibatasi dan direduksi.

**P8 — Native window behavior adalah UX inti.** Gunakan safe-area geometry, nonactivating panel bila sesuai, fallback tanpa notch, serta perilaku yang benar untuk Spaces/full-screen dan perubahan layar.

**P9 — Motion harus hemat dan accessible.** Tidak ada permanent idle frame loop. Pause saat sleep, rekonsiliasi saat wake, dan hormati Reduce Motion. Status tetap dipahami tanpa warna saja.

**P10 — Main actor hanya untuk UI.** Parsing, IPC, file operations, transcript fallback, dan pekerjaan berat berjalan di luar main actor; state UI diterapkan di main actor.

**P11 — Reliability dan polish mendahului fitur tambahan.** Mulai dari notch playground dan mascot, lalu event spine, hardening, attention, navigation, dan distribution. App-server enrichment tidak menggantikan kewajiban dukungan Desktop.

## Aturan Wajib Saat Menulis/Mengubah Kode

1. **Pakai nama Nudge secara konsisten.** UI, target, helper, dokumentasi, dan artifact baru menggunakan Nudge. `Codex` tetap valid untuk provider, adapter, payload, dan navigator. Jangan mengganti nama API/event eksternal.
2. **Validasi kontrak integrasi sebelum implementasi live.** Event names, payload, hooks/trust/config, dan deep links dalam brief adalah research snapshot. Periksa sumber resmi dan versi host yang ditargetkan sebelum bergantung pada perilakunya; simpan fixture yang relevan.
3. **Buktikan Desktop dan CLI secara terpisah.** Catat versi, effective config location, trust status, dan event coverage. Jika hooks Desktop tidak menyediakan event yang diperlukan, investigasi jalur lokal yang didukung dan laporkan limitation. Jangan diam-diam mengurangi scope menjadi CLI-only.
4. **Jangan mengasumsikan app-server terpisah memantau Desktop.** App-server optional untuk enrichment/reconciliation. Keberhasilan thread milik app-server sendiri bukan bukti monitoring thread existing di Desktop.
5. **Validasi envelope sebelum state mutation.** Batasi frame/payload size, schema version, event type, dan field wajib. Unknown atau malformed events dibuang dengan diagnostics aman, tanpa phantom session.
6. **Amankan socket per pengguna.** Rancangan path `/tmp/nudge-<uid>.sock`, mode `0600`, ownership current user, dan peer validation bila praktis. Periksa file type serta ownership sebelum membersihkan stale socket; jangan menghapus path sembarang.
7. **Installer wajib idempotent.** Nol entry menjadi satu, satu tetap satu, duplicate milik Nudge menjadi satu. Preserve semua foreign entries. Backup sebelum mutation pertama, parse-before-write, atomic replacement, dan skip write bila tidak berubah.
8. **Hormati effective Codex configuration.** Dukung custom `CODEX_HOME`. Jangan hard-code satu home path atau menganggap Desktop dan CLI memakai config yang sama. Hindari mutation `config.toml` kecuali diperlukan; gunakan parser yang tepat bila diperlukan.
9. **Jangan overwrite malformed config.** Pertahankan bytes original dan tampilkan repair instructions. Uninstall hanya menghapus entry yang ownership-nya teridentifikasi sebagai milik Nudge.
10. **Bridge harus gagal dengan cepat dan aman.** Socket unavailable atau Nudge crash tidak boleh menahan Codex. Permission path mengembalikan kontrol ke native Codex sesuai kontrak yang sudah diverifikasi; jangan silently allow.
11. **Reducer menerima trusted events sebelum `SessionStart`.** Materialisasikan placeholder session bila perlu, lalu enrich cwd/title/thread metadata saat tersedia. Jangan mengunci session pada metadata awal yang tidak lengkap.
12. **Deduplicate completion.** Duplicate hooks, identical events, dan suggestion-only extra `Stop` tidak boleh memutar ulang celebration/sound/card. Subagent completion tidak menyelesaikan main turn.
13. **Jaga lifecycle semantics.** Jangan expire thinking, long-running tool, waitingPermission, atau waitingInput hanya karena tidak ada event baru. PID liveness hanya weak fallback; gunakan process start time untuk mencegah PID reuse salah identifikasi.
14. **Attention harus direkonsiliasi.** Pertahankan pending interaction sampai resolution/progress atau lifecycle termination yang valid. Klik Open Codex sendiri bukan bukti bahwa pertanyaan/permission telah dijawab. Progress yang relevan harus membersihkan card usang.
15. **Pisahkan session dan presentation.** Window size, hover hysteresis, transient completion, dan collapse timers ditangani presentation layer. Waiting state tidak boleh tertutup stale tool label.
16. **Tangani sleep/wake tanpa replay.** Pause motion, invalidate timers, lalu rebuild satu current presentation saat wake. Jangan mengulang completion atau mengantrikan transisi lama.
17. **Isolasi navigation.** Gunakan `CodexNavigator`, precise thread link sebagai path yang perlu diverifikasi, dan app activation fallback. Jangan menanam URL syntax di view atau mengklaim thread terbuka hanya karena URL diterima OS.
18. **Transcript parsing hanya fallback.** Kegagalan pemulihan assistant preview tidak boleh mematikan session detection atau status inti. Jangan menjalankan shell command dari received payload/text.
19. **Mascot dan aset harus original.** Jangan copy code/artwork GPL Code Island ke proyek ini. Gunakan referensi sebagai behavioral research. Jika komponen Apache-2.0 dipakai, dokumentasikan provenance dan penuhi license obligations.
20. **Tambahkan meaningful tests pada boundary kritis.** Prioritaskan reducer, dedupe, installer/config preservation, socket validation, dan timeout/failure behavior. Visual polish diperiksa manual; jangan membuat tests yang hanya menyalin implementation.
21. **Commit message wajib Bahasa Inggris dan mengikuti Conventional Commits.** Gunakan format `<type>(<scope>): <description>` dengan scope opsional, misalnya `feat(ui): add demo usage limits` atau `docs: require conventional commit messages`. Pilih type sesuai perubahan, seperti `feat`, `fix`, `docs`, `refactor`, `test`, atau `chore`. Percakapan dan komentar boleh Bahasa Indonesia. Commit harus singkat, deskriptif, dan sesuai scope perubahan; jangan memasukkan perubahan pengguna yang tidak terkait.

## Model Domain Minimum

```text
SessionID / TurnID
CodexSession
SessionPhase
ToolActivity
PendingInteraction / PendingPermission / PendingQuestion
CompletionSummary / FailureSummary
NudgeEvent / WireEnvelope
NotchPresentation
NudgeSettings
```

Session setidaknya menampung stable identity, optional thread/turn ID, cwd/project label, semantic phase, current tool, timestamps, optional host metadata, pending interaction, dan lifecycle confidence. Assistant preview bersifat optional dan dibatasi.

Phase mengikuti brief: `discovered`, `idle`, `thinking`, `toolUse`, `waitingPermission`, `waitingInput`, `completed`, `failed`, `interrupted`, `ended`. Presentation: `collapsed`, `peek`, `expanded`, `attention`. Interrupted tidak boleh dipresentasikan sebagai success.

## Notch, Mascot, dan Motion

- SwiftUI dihosting dalam AppKit `NSPanel`; jangan membuat notch tiruan dalam popover biasa.
- Hitung geometry dari layar dan safe area; dimensi dalam brief adalah starting values.
- Jaga konten dan mascot dari inner notch shoulders serta clipping.
- Hover tidak mencuri keyboard focus atau flicker; gunakan hysteresis yang konsisten.
- Dukungan layar tanpa notch berupa compact island di top-center.
- Pose minimum: idle, thinking/tool use, attention, done, failure/interruption.
- Attention noticeable tetapi tenang; completion dimainkan tepat sekali.
- Idle hemat CPU, tanpa bouncing atau flashing konstan; hentikan animasi yang tidak diperlukan.
- Status, tombol, contrast, keyboard access, VoiceOver, dan Reduce Motion merupakan bagian dari kualitas produk.

## Konfigurasi, Privacy, dan Recovery

Gunakan Application Support untuk preferences/diagnostics; socket pendek tetap memakai lokasi per-user yang ditetapkan. Jangan mengandalkan current working directory.

Simpan preferences, hook install status, optional recent project label, dan bounded diagnostics. Jangan menyimpan prompt penuh, transcript cache, shell output, file contents, atau secrets secara default. Redact paths, truncate preview, dan whitelist metadata sebelum IPC/logging.

Installer harus dapat dipulihkan dengan backup. Malformed JSON/TOML, unsupported configuration, permission denied, untrusted hooks, dan bridge unavailable harus memiliki error yang dapat dipahami pengguna. Jangan mengulang config writes tanpa kebutuhan atau menganggap semua event yang hilang berarti hooks belum dipercaya.

## Peta Fase Implementasi

Fase mengikuti milestone M0–M6 dalam brief. Kerjakan satu fase per sesi, kemudian serahkan hasil dan verifikasi manual kepada developer sebelum berlanjut. Instruksi eksplisit pengguna tentang scope menjadi prioritas. M5 optional dan tidak menjadi prerequisite M6.

### Fase 1 / M0 — Notch Playground

Ruang lingkup: project macOS, menu-bar accessory shell, NSPanel, notch/non-notch geometry, collapsed/peek/expanded/attention, fake phase picker, original Nudgie, motion, hover hysteresis, dan Reduce Motion. Belum ada live Codex integration.

Kriteria selesai: app dapat menyimulasikan seluruh visible states dengan motion yang halus, tanpa focus steal/clipping, dan fallback tanpa notch berfungsi.

Verifikasi manual oleh developer:

1. Buka app dan ubah fake state melalui working, attention, done, failure, serta interrupted.
2. Uji hover dan expand/collapse berulang; pastikan teks dan mascot tidak melompat/flicker.
3. Uji notch, layar tanpa notch/external display, Spaces, full-screen, dan menu-bar auto-hide yang tersedia.
4. Aktifkan Reduce Motion dan pastikan motion berkurang tanpa menghilangkan makna status.

### Fase 2 / M1 — Codex Event Spine

Ruang lingkup: NudgeBridge, Unix socket, versioned envelope, decoder/normalizer, SessionReducer, safe hook installer, trust diagnostics, dan basic live status. Mulai dari event contract yang telah diverifikasi untuk SessionStart, UserPromptSubmit, tool progress, Stop, dan Interrupt.

Kriteria selesai: turn nyata dari Codex Desktop dan CLI memperbarui Nudge; Desktop new/resumed threads bekerja tanpa terminal launch. Installer aman, foreign hooks utuh, bridge unavailable tidak memblokir Codex, dan versi/event coverage kedua host tercatat. Synthetic-only atau CLI-only tidak menyelesaikan fase ini.

Verifikasi manual oleh developer:

1. Catat versi Desktop/CLI, effective config location, dan trust status masing-masing.
2. Mulai local thread langsung dari Codex app, kirim prompt yang memakai tool, lalu cocokkan status hingga selesai.
3. Resume thread di app dan pastikan aktivitas kembali terlihat tanpa terminal launch.
4. Jalankan workflow setara di CLI dan catat event coverage terpisah.
5. Tutup Nudge saat Codex bekerja dan pastikan Codex tetap melanjutkan; uji instalasi ulang/uninstall pada config uji dengan foreign hooks.

### Fase 3 / M2 — Codex Edge-Case Hardening

Ruang lingkup: duplicate hooks/events, suggestion Stop, resume tanpa SessionStart, metadata enrichment, long tools, stale pending cleanup, sleep/wake, malformed config, dan custom CODEX_HOME.

Kriteria selesai: fixtures mencakup known edge cases; completion tepat sekali; active/waiting session tidak hilang karena quiet interval; config corrupt tidak diubah; wake tidak memutar ulang completion. Custom configuration diverifikasi sesuai kemampuan host.

Verifikasi manual oleh developer:

1. Uji new/resumed turns dan long-running tool pada Desktop serta CLI.
2. Sleep/wake ketika working dan setelah completion; pastikan tidak ada replay atau timer ganda.
3. Pada config sementara, uji duplicate Nudge entries, foreign hooks, malformed file, dan custom CODEX_HOME; pastikan bytes/config yang harus dipertahankan tetap utuh.
4. Cocokkan hasil demo duplicate/suggestion Stop dengan satu completion transition.

### Fase 4 / M3 — Attention UX

Ruang lingkup: request_user_input mirror, permission mirror, persistent attention, mascot attention, basic Codex activation, serta resolution dari luar Nudge. Tidak ada programmatic answer atau permission decision dari notch.

Kriteria selesai: questions/permissions yang tersedia pada kedua host terlihat, tombol Desktop membuka Codex app, dan relevant progress membersihkan pending state. Nudge tidak stuck setelah pengguna menjawab melalui Codex.

Verifikasi manual oleh developer:

1. Picu question dan permission yang tersedia pada Desktop dan CLI; catat perbedaan host.
2. Klik Answer in Codex/Open Codex dari Desktop attention dan pastikan app aktif.
3. Jawab/putuskan langsung di Codex lalu pastikan attention bersih ketika progress berlanjut.
4. Biarkan prompt belum dijawab; pastikan pending state tidak dianggap resolved hanya karena app dibuka atau waktu berlalu.

### Fase 5 / M4 — Precise Navigation

Ruang lingkup: navigator abstraction, experimental thread deep link, bundle-ID launch, app activation fallback, missing/archived thread handling, dan diagnostics.

Kriteria selesai: thread valid terbuka jika jalur yang diverifikasi tersedia; kegagalan tidak menjadi no-op dan beralih ke aktivasi app. Basic monitoring tidak bergantung pada precise navigation.

Verifikasi manual oleh developer:

1. Dari app lain, klik Nudge untuk thread Desktop aktif dan cocokkan thread yang terbuka.
2. Uji thread resumed, missing/archived, dan kondisi Codex app belum terbuka.
3. Nonaktifkan precise navigation dan pastikan activation fallback tetap berfungsi.
4. Uji multiple windows/Spaces dan catat batas routing yang belum dijamin oleh host.

### Fase 6 / M5 — Permission Actions (Optional)

Fase hanya masuk scope bila diminta pengguna, setelah official response contract kedua host divalidasi. Ruang lingkup terbatas pada Allow Once/Deny; persistent allow dan bypass tetap dilarang pada MVP.

Kriteria selesai: decision benar-benar diterapkan sesuai kontrak, request identity/queue aman, external resolution direkonsiliasi, timeout tidak memblokir Codex, dan tidak ada silent auto-allow.

Verifikasi manual oleh developer:

1. Pada sandbox project, uji Allow Once dan Deny untuk host yang kontraknya telah diverifikasi.
2. Uji duplicate requests serta resolution langsung di Codex.
3. Tutup Nudge ketika request pending dan pastikan native approval tetap tersedia tanpa auto-allow.

### Fase 7 / M6 — Distribution Hardening

Ruang lingkup: signing, hardened runtime, notarized DMG, onboarding, reversible installer/uninstaller, diagnostics, update strategy, dan profiling. Updater pihak ketiga hanya ditambahkan dengan alasan dan scope tertulis.

Kriteria selesai: artifact distribusi terverifikasi sesuai akses signing/notarization yang tersedia; fresh installation berjalan; removal menjaga foreign config; CPU idle rendah; privacy defaults dan Desktop/CLI acceptance tetap lolos. Jika credentials/toolchain belum tersedia, laporkan bagian release yang belum terverifikasi.

Verifikasi manual oleh developer:

1. Install artifact pada Mac/test account yang representatif; jalankan onboarding dan hook trust flow.
2. Jalankan workflow nyata Desktop dan CLI setelah install serta setelah upgrade.
3. Uninstall integrasi dan pastikan konfigurasi lain serta Codex tetap usable.
4. Profilkan idle, thinking, long tool, expand/collapse, sleep/wake, dan synthetic event burst dengan Instruments.
5. Uji signing/Gatekeeper/notarization, accessibility, dan diagnostics export sesuai artifact rilis.

## Milestone Pengembangan Pertama

Milestone pertama adalah **M0 — Notch Playground**: accessory app, notch geometry, shell transition, fake phase picker, Nudgie, working/attention/done motion, hover hysteresis, dan Reduce Motion.

Jangan mulai dari hook integration atau membangun semua fase sekaligus. Live integration dimulai di M1 setelah visual playground diverifikasi. Desktop support tetap wajib untuk MVP meskipun M0 menggunakan data simulasi.

## Checklist Sebelum Fase Dianggap Selesai

- [ ] Perubahan sesuai scope fase aktif.
- [ ] Build dan relevant tests dijalankan, atau batas toolchain dijelaskan.
- [ ] Critical invariants memiliki meaningful fixtures/tests sesuai subsystem yang berubah.
- [ ] Desktop dan CLI diverifikasi terpisah jika fase menyentuh live integration.
- [ ] Tidak ada config pengguna/foreign hooks yang terhapus atau overwrite malformed file.
- [ ] Nudge-unavailable behavior tidak memblokir atau auto-approve Codex.
- [ ] Tidak ada prompt/transcript/secrets yang tersimpan atau terkirim tanpa kebutuhan dan aksi eksplisit.
- [ ] Parsing/IPC/file work tidak memblokir main actor.
- [ ] Stable IDs, motion, timers, dan sleep/wake tidak menyebabkan replay/flicker.
- [ ] Verifikasi manual oleh developer dilakukan sesuai fase; bagian yang pending dicatat.
- [ ] Commit terpisah per fase sesuai instruksi pengguna; perubahan yang tidak terkait tidak ikut dimasukkan.

## Aturan Pengujian oleh Developer

Verifikasi fungsional dan visual dilakukan **manual oleh developer** di macOS/Xcode, terutama physical notch, window behavior, real Codex Desktop/CLI, hook trust, accessibility, motion, dan release artifact. AI tidak boleh menyebut langkah tersebut sudah lolos hanya berdasarkan source review, fixtures, atau build.

AI boleh membaca repository, melakukan static validation, menjalankan build dan hermetic unit/integration tests bila toolchain tersedia, menambahkan meaningful tests, serta menyiapkan skenario manual. Penelusuran dokumentasi resmi untuk memvalidasi kontrak integrasi diperbolehkan; runtime Nudge tetap local-first.

Tanpa instruksi eksplisit developer, AI tidak boleh mengubah instalasi Codex/config nyata untuk live testing, memicu keputusan permission nyata, menghapus data/config/backup pengguna, menambah backend/telemetry, atau menggantikan verifikasi manual yang menjadi tanggung jawab developer. Gunakan temporary config, socket, fixtures, dan sandbox project untuk automated tests.

Setelah menyelesaikan satu fase, AI menyerahkan langkah **Verifikasi manual oleh developer** yang bernomor dan diturunkan dari kriteria selesai fase tersebut. Developer menjalankan verifikasi dan melaporkan hasil sebelum fase berikutnya dimulai, kecuali instruksi eksplisit pengguna menetapkan scope lain.

## Aturan Wajib di Setiap Implementation Plan

Setiap implementation plan wajib menyertakan blok berikut apa adanya:

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

## Aturan Saat Membuat Implementation Plan

Sebelum mengimplementasikan subsystem besar, plan menjelaskan:

1. tanggung jawab subsystem dan fase aktif;
2. data flow serta boundary dengan domain/UI/IPC/provider;
3. kontrak Desktop/CLI dan versi yang perlu diverifikasi;
4. trade-off penting, termasuk optional enrichment/fallback;
5. expected failure cases dan Nudge-unavailable behavior;
6. file yang disentuh;
7. meaningful automated tests dan manual verification;
8. risiko terhadap config/data, privacy, compatibility, dan recovery.

Plan harus menyelesaikan satu workflow nyata sesuai fase. Jangan membuat banyak screen kosong, speculative abstractions, atau placeholder integration lalu menyebut produk selesai.

## Definition of Done MVP

MVP usable ketika pengguna dapat:

1. Membuka Nudge sebagai menu-bar companion dengan notch/non-notch fallback.
2. Memulai serta melanjutkan local thread langsung di Codex macOS app dan melihat status berubah tanpa terminal launch.
3. Menjalankan Codex CLI dengan lifecycle monitoring yang juga bekerja.
4. Melihat project, thinking/working, tool summary, serta attention yang relevan.
5. Menjawab question/permission melalui Codex dan melihat pending state direkonsiliasi.
6. Melihat completion tepat sekali, dengan failed/interrupted dibedakan dari success.
7. Kembali ke Codex Desktop melalui attention action; precise thread routing memiliki activation fallback.
8. Sleep/wake tanpa stale animation replay atau stuck state.
9. Memasang ulang dan menghapus hooks tanpa merusak foreign config.
10. Tetap memakai Codex normal ketika Nudge tertutup atau gagal.

Acceptance criteria lengkap dalam brief tetap berlaku: owner-only socket, schema validation, low perceived latency, original mascot, negligible idle CPU, Reduce Motion, privacy defaults, serta bukti pengujian Desktop dan CLI terpisah. Optional permission actions atau app-server enrichment bukan syarat MVP.

## Standar Produk Akhir

Nudge harus terasa seperti companion Mac yang kecil, fokus, tenang, dan dapat dipercaya. Benchmark: glanceability, reliability, native interaction, smooth motion, privacy, energy efficiency, dan detail visual.

Banyaknya fitur bukan benchmark utama. Backend defensif dan predictable; notch serta mascot memberi karakter tanpa mengganggu pekerjaan pengguna.
