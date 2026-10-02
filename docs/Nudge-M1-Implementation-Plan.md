# Nudge — Implementation Plan M1: Codex Event Spine

Tanggal: **2 Oktober 2026**. Status: **implementasi source M1 tersedia; hasil automated ada di [Nudge-M1-Verification.md](Nudge-M1-Verification.md), verifikasi host/manual masih pending**.

Sumber kebenaran: [project brief](Nudge-Project-Brief.md), khususnya bagian 24–32 dan milestone M1, serta [AGENTS.md](../AGENTS.md). Scope sesi implementasi berikutnya adalah **M1 saja**. Permintaan membuat plan ini tidak memberi izin mengubah konfigurasi Codex nyata atau menjalankan pengujian live milik developer.

## 1. Hasil dan batas fase

Satu workflow selesai dari awal ke akhir: **developer memasang integrasi melalui Nudge → meninjau trust di host → memulai local thread langsung di Codex Desktop → Nudge menampilkan project dan thinking/tool activity → turn selesai atau diinterupsi → Nudge kembali tenang**. Workflow harus bekerja juga untuk resumed Desktop thread dan, secara terpisah, Codex CLI. Desktop tidak membutuhkan terminal launch atau app-server milik Nudge.

Deliverable M1: helper native `NudgeBridge`, socket per pengguna, envelope v1, normalisasi provider, deterministic `SessionReducer`, safe installer/uninstaller, diagnostics instalasi/trust, dan satu focused live context pada UI M0 yang sudah ada.

Event awal mengikuti milestone M1: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `Interrupt`. Bagian 26 brief adalah cakupan integrasi keseluruhan; `PermissionRequest`/question mirror dan `SessionEnd` tidak otomatis ditambahkan ke instalasi M1. Tambahkan `SessionEnd` hanya jika hasil validasi menunjukkan diperlukan untuk lifecycle M1, dengan alasan dan fixture tertulis. Jangan mendaftarkan event yang belum didukung release host.

Ditunda: attention live beserta resolution (M3), precise thread navigation (M4), permission decisions (M5), app-server/transcript enrichment, quota live, suara, updater, signing/notarization distribusi (M6). M2 tetap mengurus hardening lengkap; M1 wajib sudah menjaga invariants dasar seperti config preservation, placeholder session, completion dedupe, dan bounded failure. Ini syarat keamanan fondasi, bukan izin membangun seluruh M2.

## 2. Kondisi repository dan gate sebelum implementasi

Pada pemeriksaan plan, 2 Oktober 2026:

| Area | Bukti saat ini | Implikasi |
|---|---|---|
| Project | `Nudge.xcodeproj`, target/scheme `Nudge`; macOS 15, Swift 6, accessory app | Tambahkan helper dan test targets ke project ini; tidak membuat scaffold ulang |
| Toolchain | `xcodebuild -version`: Xcode 27.0 (27A266a); Swift 6.4 | Toolchain tersedia; plan ini tidak menjalankan build/test aplikasi |
| Domain/UI | `SessionPhase`, `ActivitySnapshot`, `PresentationReducer`, `AppState` sudah ada | Tambahkan session lifecycle terpisah; pertahankan window geometry, mascot, motion |
| Tests | Tiga standalone `*Checks.swift`; belum ada Xcode test bundle, `TestAction` kosong | Buat `NudgeCoreTests` dan `NudgeIntegrationTests` sungguhan |
| Demo | AppState mulai dari fixture; root view memakai judul/prompt/diff/question/usage demo | Live mode harus membaca snapshot nyata dan tidak menampilkan fixture sebagai aktivitas nyata |
| M0 | [handoff M0](Nudge-M0-Verification.md) masih menandai QA manual pending | Developer mencatat hasil M0 sebelum mulai implementasi M1, atau memberi instruksi eksplisit tentang scope |
| CLI lokal | `codex --version`: **0.154.0** | Kandidat versi pengujian, belum bukti event coverage |
| Desktop lokal | `/Applications/ChatGPT.app`, bundle `com.openai.codex`, version **26.928.31416**, build **12553** | Kandidat host Desktop; nama file app bukan penentu identitas integrasi |

**Gate A — M0:** plan boleh disiapkan sekarang. Jangan menandai M0 selesai berdasarkan source/build sebelumnya. Status gate harus tercatat ketika implementasi dimulai.

**Catatan saat implementasi:** QA manual M0 masih pending. Pengguna kemudian secara eksplisit menginstruksikan Codex untuk mulai implementasi M1. Pekerjaan M1 diteruskan atas instruksi itu; instruksi tersebut tidak dianggap sebagai bukti M0 lulus dan verifikasi visual M0/M1 tetap menjadi pekerjaan developer.

**Gate B — kontrak host:** sebelum mengunci adapter dan memasang hooks live, buat matriks kontrak Desktop/CLI dengan versi, sumber config efektif, trust flow, raw event shape yang sudah disanitasi, output no-op, dan coverage new/resumed/tool/stop/interrupt. Dokumentasi adalah referensi; dukungan versi terpasang tetap pending sampai developer membuktikannya.

Jika Desktop gagal gate B, kerjakan analisis gap serta investigasi jalur lokal yang didukung dan laporkan. Komponen hermetic tetap dapat diverifikasi, tetapi **M1 tidak selesai** dan tidak beralih diam-diam ke CLI-only, UI scraping, private database, atau app-server terpisah.

## 3. Snapshot kontrak resmi dan hal yang perlu dibuktikan

Dokumentasi resmi mendeskripsikan input JSON pada stdin, field bersama `session_id`, `cwd`, `hook_event_name`, dan `turn_id` untuk event turn. Tool hooks memakai `tool_name`, `tool_use_id`, `tool_input`; `PostToolUse` juga membawa `tool_response`. `Stop` membawa `stop_hook_active` dan `last_assistant_message`. Non-managed hook harus direview dan dipercaya pada definisi/hash tepat yang sedang aktif; CLI menyediakan `/hooks` untuk review. `Stop` mengharapkan JSON di stdout pada exit 0, sedangkan exit 0 tanpa output diterima untuk event umum dan `Interrupt`. Karena itu helper v1 hanya menulis `{}` untuk `Stop`; event lain keluar tanpa stdout. Hook tidak pernah mengembalikan decision/context. [OpenAI Hooks](https://learn.chatgpt.com/docs/hooks).

`CODEX_HOME` didokumentasikan untuk CLI, IDE extension, app-server dan installer, bukan sebagai jaminan konfigurasi macOS Desktop. Resolver menampilkan lokasi default/environment sebagai kandidat, menyimpan folder eksplisit yang dipilih developer per host, dan secara jelas menandai Desktop environment sebagai belum diverifikasi. Ini tidak membuktikan config efektif; Desktop/CLI masih perlu dicatat terpisah. [Environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables).

Codex memuat hook dari `hooks.json` dan inline `[hooks]` di `config.toml`; jika kedua bentuk muncul pada layer yang sama, ia menggabungkannya dan mengeluarkan warning. Nudge hanya mengubah `hooks.json` serta menampilkan batas ini sebelum install; tidak memutasi TOML atau managed/project layers. [Advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced).

Berikut adalah **keputusan desain Nudge yang direncanakan**, bukan klaim bahwa semua field sudah terlihat pada host lokal:

| Event | Data yang dipakai adapter | Hasil domain M1 |
|---|---|---|
| `SessionStart` | identity, cwd, source startup/resume jika tersedia | Materialisasi/enrich session; tidak mereset turn yang sedang aktif |
| `UserPromptSubmit` | session dan turn identity; prompt dibuang | Mulai turn, phase thinking; metadata prompt tidak disimpan |
| `PreToolUse` | turn, tool-call identity dan kategori aman | Tambah tool aktif, phase toolUse |
| `PostToolUse` | turn/tool-call identity; hanya indikator hasil yang tervalidasi | Hapus tool terkait; tetap toolUse jika tool lain aktif, selain itu thinking |
| `Stop` | turn identity, continuation metadata tervalidasi | Tandai selesai sekali jika terminal completion terbukti; jangan menyimpulkan kualitas hasil |
| `Interrupt` | session dan interrupted turn | interrupted; tidak mengirim celebration |

Contract record wajib menjawab:

1. Apakah enam event tersedia pada **Desktop new, Desktop resumed, dan CLI**? Apakah first resumed event bisa datang sebelum SessionStart?
2. Apakah hook subprocess mendapatkan identity/turn/tool-call yang stabil? Jangan menganggap `session_id` pasti thread ID atau memakai PID sebagai identity.
3. Bagaimana membedakan main turn, subagent, continuation dan suggestion-only Stop? Bila metadata tidak cukup, pilih perilaku konservatif dan catat gap; jangan mengklaim semantik yang tidak terbukti.
4. Bagaimana host discovery hooks, trust, reload/restart dan feature restrictions bekerja? CLI trust instructions tidak boleh diasumsikan sama dengan Desktop.
5. Apakah `{}` + exit 0 pada Stop dan no-output + exit 0 pada event lain diterima oleh release host terpasang, termasuk saat socket unavailable? Dokumentasi mendukung bentuk tersebut secara umum, tetapi compatibility host tetap harus diuji; tidak ada `allow`, `deny`, `block`, input rewrite, atau additional context dari Nudge.
6. Tool mana yang benar-benar tercakup, termasuk long command yang selesai setelah poll? Jangan mengklaim coverage semua tools dari satu contoh shell.

Hasil disimpan di `docs/Nudge-M1-Codex-Contract.md` saat implementasi, dengan tanggal/versi/sumber/fixture provenance. Fixture buatan diberi label synthetic; fixture hasil host disanitasi sebelum masuk repository. Jangan menyimpan capture raw prompt, transcript, secret, diff, atau shell output.

## 4. Arsitektur dan ownership

```text
Codex Desktop / CLI, local lifecycle hooks
    → NudgeBridge: bounded stdin, provider adapter, privacy allowlist
    → WireEnvelope v1: length-prefixed JSON
    → NudgeSocketServer: filesystem/peer/frame validation
    → WireDecoder → EventNormalizer → canonical NudgeEvent
    → CodexEventMonitor: serial session store + SessionReducer + FocusPolicy
    → ActivitySnapshot untuk satu context
    → AppState (@MainActor) → PresentationReducer → NSPanel / SwiftUI

Install/remove intent
    → configuration resolver → CodexHookInstaller, di background
    → hasil/status immutable → AppState → menu-bar integration controls
```

`Core` hanya berisi value types dan pure reducers/policy. Jangan memasukkan raw hook dictionary, AppKit, SwiftUI, IO, atau URL navigation di SessionReducer. Model tetap memuat stable `SessionID`, optional provider `TurnID`/thread ID, project label, phase, tool-call set, timestamps dan lifecycle confidence; preview assistant tidak diperlukan M1.

`CodexEventMonitor` menjadi satu actor pemilik in-memory session store. Socket IO berjalan pada dispatch queue khusus dengan nonblocking descriptors; decode/normalize/reduce berada di luar main actor. UI hanya menerima snapshot dan status integrasi yang sudah dibatasi. Clock dan canonical events diinjeksikan untuk fixture deterministik. Protocol tambahan hanya untuk boundary IO/clock yang benar-benar diuji.

Gunakan target membership untuk berbagi wire codec/provider adapter antara app, bridge dan unhosted tests; jangan membuat framework/package baru. Swift 6 `Sendable` diterapkan pada data yang melintasi actor. Tidak ada dependency baru: Foundation/Codable, Darwin, Dispatch, OSLog, serta AppKit/SwiftUI yang sudah dipakai UI.

## 5. Envelope, privacy dan compatibility

Desain awal v1, dikunci setelah gate B:

| Field | Aturan |
|---|---|
| `schema_version`, `source`, `event` | Version 1, source codex, event allowlist M1 |
| `session_id` | String nonempty dan bounded; tidak mengubah session sebelum valid |
| `turn_id` | Optional untuk lifecycle session; wajib pada turn event jika kontrak target menjaminnya |
| `tool_call_id` | Wajib untuk pasangan tool event sesuai kontrak target |
| `observed_at_ms` | Bridge observation time; tidak diklaim sebagai provider sequence |
| `project_label` | Turunan terakhir cwd yang dibatasi, atau label generic; full cwd tidak dikirim default |
| `host` | Tidak dikirim pada wire v1. Shared configuration tidak cukup untuk mengatribusikan event ke host |
| `tool` | Canonical name/category/summary aman; tidak berisi raw command/arguments/output |
| `metadata` | Hanya field lifecycle yang dibutuhkan dan tervalidasi; tidak menerima arbitrary raw_metadata |

Decoder menolak duplicate/unknown JSON keys, unsupported version/event/source, tipe salah, identity kosong, field wajib hilang, oversized frame/string/nesting serta timestamp invalid. Semua penolakan terjadi **sebelum placeholder session dibuat**. Field optional baru dapat ditambahkan setelah compatibility test; perubahan makna/framing memerlukan schema baru.

Jangan membuat random turn ID setiap bridge invocation. Jika release target tidak punya identity yang cukup, catat unsupported contract dan selesaikan strategi korelasi lewat fixture sebelum live wiring. SessionStart tanpa turn tetap dapat diterima. Untuk presentasi, identitas completion adalah pasangan session+turn, bukan turn saja.

Input raw hanya hidup selama satu bridge invocation. Abaikan prompt, transcript path, assistant text, tool_response body dan unknown metadata. Ringkasan default generik seperti “Running command”, “Editing files” atau “Using tool”; optional basename hanya bila allowlist adapter bisa menurunkannya dengan aman. Jangan memakai regex truncation sebagai satu-satunya secret protection. Tidak ada transcript/file read maupun eksekusi teks payload.

**Batas awal Nudge (harus diukur saat implementasi):** raw stdin maksimum 1 MiB, wire frame maksimum 64 KiB, identifier maksimum 256 UTF-8 bytes, project/tool summary maksimum 120 karakter. Terlalu besar berarti event dibuang, tanpa truncation JSON yang menghasilkan phantom event. Diagnostics hanya reason code/counter; ID/path diperlakukan private, payload tidak dicetak.

## 6. Bridge dan socket failure behavior

`NudgeBridge` dibangun sebagai macOS command-line helper dan di-embed di `Nudge.app/Contents/MacOS/NudgeBridge`. Setelah developer meninjau preview perubahan dan menyetujui aksi Install, app memasang salinan atomik di stable path `~/Library/Application Support/Nudge/bin/NudgeBridge`; tidak memakai DerivedData atau cwd sebagai hook command. Directory `Nudge/bin` dibatasi ke pemiliknya (0700). Command memakai absolute path dengan shell quoting yang benar untuk spasi/apostrof; payload hanya lewat stdin, tidak diinterpolasi ke shell.

Bridge punya satu monotonic deadline untuk **stdin + parse + connect + send**, target awal 250 ms di luar biaya process launch. Pakai bounded nonblocking read/write/poll, tangani partial writes, `EINTR`, closed peer dan `SIGPIPE`. Tidak menunggu approval, response UI, atau reconnect retry. Kandidat konfigurasi hook synchronous dengan timeout 1 detik, agar lifecycle ordering lebih mudah dikendalikan; penerimaan timeout tetap diverifikasi untuk release host. Hindari background-hook ordering sebagai asumsi fondasi.

Bridge selalu exit 0 dan tidak mengeluarkan payload/diagnostics provider; ia menulis `{}` hanya untuk `Stop`, sesuai dokumentasi hook. Socket unavailable, input invalid, atau timeout tidak membuat Codex berhenti, auto-allow, atau gagal menerima prompt. Hilangnya event dilaporkan sebagai keterbatasan monitoring, bukan dipulihkan dengan transcript scraping.

Server memakai `/tmp/nudge-<uid>.sock`, socket mode **0600**, ownership current user. Gunakan per-socket permission setup sebelum listen; jangan mengubah process-wide umask aplikasi multithread tanpa kontrol. Validasi peer UID dengan `getpeereid`; client juga memvalidasi path/peer server. User lokal yang sama masih dapat mengirim data, sehingga schema validation tetap wajib; ini bukan authentication antarproses milik UID yang sama.

Framing: uint32 big-endian length + satu UTF-8 JSON envelope per connection, lalu close. Baca length sebelum alokasi, batasi connections awal 16 dan deadline frame 500 ms. Receiver tidak mengandalkan satu `read` menghasilkan satu event. Koneksi tambahan/slow clients gagal bounded; tidak ada per-connection Task tanpa batas atau polling saat idle.

Saat path sudah ada, `lstat` harus membuktikan socket owned current UID; regular file, symlink atau ownership lain berarti refuse startup. Probe bounded untuk membedakan live listener dari stale socket. Jangan unlink live socket, socket yang tidak dapat dibuktikan stale, atau path yang identity/inode-nya berubah. Saat shutdown hanya bersihkan endpoint yang dibuat instance ini. Instance kedua menampilkan diagnostics, tidak mengambil alih listener pertama. Tests memakai path temporary pendek; tidak menyentuh `/tmp/nudge-<uid>.sock` nyata.

## 7. Installer, backup dan recovery

Resolver menghasilkan konfigurasi target **per host**, asal pemilihannya, path dan compatibility status. Urutan Nudge: folder pilihan pengguna yang tersimpan → `CODEX_HOME` environment candidate bila tersedia → `~/.codex` sebagai default candidate. GUI Nudge tidak menganggap `CODEX_HOME` Nudge sebagai bukti Desktop. UI menampilkan target dan membuka pemilih folder config yang sudah ada sebelum perubahan. Jika dua host ternyata memakai path sama, installer idempotent; jika berbeda, installer mengelola masing-masing tanpa saling overwrite.

Utamakan `hooks.json` yang didukung target host. `config.toml`, project hooks, profiles, managed settings dan trust store tidak dimutasi M1. Jika inline/managed config membuat compatibility ambigu, tampilkan unsupported/needs-review dan preservation instructions. Jika kelak dibutuhkan mutation TOML, tulis revisi plan dengan parser, backup dan compatibility strategy sebelum mengubah file; regex mutation bukan opsi.

Workflow installer:

1. Resolve target dan tampilkan perubahan konkret: enam event, absolute helper command, lokasi config/backup. Aksi Install di aplikasi adalah intent pengguna; app launch/build/test tidak menginstal otomatis.
2. Validate filesystem target/parent; tolak symlink/ownership tak sesuai. Parse JSON lengkap, termasuk root dan hook-group shape; tolak duplicate JSON keys yang ambigu. Parse failure/unsupported shape tidak dianggap config kosong.
3. Tentukan ownership dari exact Nudge helper command dan salah satu enam argumen event yang dikenal. Jangan menghapus command hanya karena substring “Nudge”. Foreign handlers dalam group yang sama, matchers dan unknown keys harus dipertahankan. Edited commands tidak dihapus.
4. Hitung merge: nol menjadi satu, satu tetap satu, duplicate teridentifikasi menjadi satu **per event/target file**. No-op mempertahankan bytes/mtime, tidak membuat backup ulang atau memicu trust churn.
5. Sebelum mutation, backup bytes original dengan filename unik, mode 0600 dan provenance/hash; backup lama tidak ditimpa. Config yang belum ada dicatat sebagai absent. Backup config dapat mengandung data foreign sensitif: hanya lokal, tidak ikut diagnostics export/fixture.
6. Serialize ke sibling temporary file, pertahankan permissions yang relevan, flush lalu atomic replace. Gunakan lock untuk operasi installer Nudge, recheck identity/content hash sebelum replace, abort jika ada perubahan eksternal. Tidak mengklaim lock Nudge mengendalikan editor lain; dokumentasikan batas race dan simpan recovery bytes.
7. Laporkan installed/alreadyInstalled/malformed/unsupported/permissionDenied/conflict/failed. Trust dan aktivitas host merupakan status terpisah; Nudge menandai status host/trust belum terverifikasi sampai developer memeriksa Codex dan event diterima.

Uninstall parse-before-write dan menghapus **hanya** owned handlers. Group dibuang jika benar-benar menjadi kosong tanpa foreign metadata; file existing tidak dihapus sembarang. Jangan otomatis restore backup seluruh file karena dapat menghapus perubahan pengguna setelah install.

Recovery manual: tunjukkan nama backup dan perubahan yang perlu dipulihkan; pertahankan config current serta backup. Jika config malformed/conflict, jangan replace. Helper baru diganti atomically setelah digest diverifikasi; command path tetap. Uninstall hanya menghapus handlers yang match exact command/event; file helper serta backup tetap tersedia.

## 8. SessionReducer, focus dan presentation

Reducer memproses canonical event dengan stable identity dan clock yang diinjeksi. Event valid sebelum SessionStart membuat placeholder yang kemudian dienrich. SessionStart yang terlambat tidak mengubah thinking/toolUse menjadi idle. Turn baru membersihkan tool/completion state turn sebelumnya; event turn lama tidak boleh mengubah current turn.

Simpan set tool calls aktif, bukan satu label tanpa identity. PostToolUse tool A tidak menghapus tool B yang masih berjalan. Tool error sendiri bukan kegagalan seluruh turn karena Codex masih bisa memperbaikinya. Phase failed memerlukan terminal failure signal yang benar-benar terverifikasi; M1 tidak mengarang failed dari missing event atau shell exit nonzero. Completion copy netral (“Turn finished”), bukan klaim tests berhasil.

Stop untuk turn terminal yang sama tidak menghasilkan transition/effect baru. Completion consumption disimpan per session+turn dan tidak hilang ketika fokus pindah lalu kembali. Identical hook dedupe menggunakan bounded semantic key yang mengecualikan observation timestamp dan random invocation IDs; bukan timestamp bridge. `Stop` dengan `stop_hook_active: true` dibuang sebagai continuation, bukan completion. SubagentStop tidak masuk completion allowlist; subagent event yang dikenali tidak menyelesaikan main turn.

Setelah terminal Stop/Interrupt, late tool events pada turn itu tidak menghidupkan kembali UI. Genuine continuation harus dikenali dari bukti kontrak turn/progress; bila tidak ada ordering/identity memadai, catat limitation dan fixture untuk M2. Tidak ada idle timeout yang mengakhiri thinking/toolUse; liveness PID dan transcript fallback tidak digunakan M1.

FocusPolicy mengikuti brief: pending attention yang kelak tersedia → explicit selection yang valid → most recent working session → recent terminal state (completed/interrupted/failed) dalam grace window → none. M1 tidak membangun session picker/fleet UI. Gunakan stable tie-break ID dan clock yang diinjeksi. None berarti snapshot kosong/idle tanpa identitas demo.

AppState menerima snapshot live lalu memakai PresentationReducer yang ada. Perubahan focus/metadata tidak boleh merayakan completed turn lama. Presentation timers tidak mengubah semantic session phase. Sleep menggunakan lifecycle M0; snapshot live saat sleeping tidak menjalankan flourish/timer baru, dan wake menerapkan satu latest snapshot tanpa replay. Recovery/reconciliation kompleks tetap M2; kehilangan event saat app tertutup dinyatakan unknown sampai event baru, bukan direkonstruksi secara spekulatif.

## 9. Live UI dan diagnostics minimum

Tambahkan mode **Live** default dan **Demo** eksplisit di Debug. Demo memiliki store terpisah; tidak mengubah session live atau install status. Monitor live memakai project label dan tool summary snapshot; `PlaygroundScenario.taskTitle`, prompt, diff, question/options dan usage tidak ditampilkan sebagai data live. Usage demo yang sudah diminta pengguna tetap ada dalam Demo, tanpa quota API atau polling baru.

Pertahankan geometry, warna, mascot placement, hover dan Reduce Motion M0. Tidak perlu redesign. Demo Allow/Deny/question controls tidak pernah muncul sebagai keputusan live M1. Pending interaction live belum dipromosikan sebagai fitur selesai. Navigation tetap boundary navigator M0; fallback “Open Codex” boleh mengaktifkan Desktop tetapi tidak mengklaim exact thread/terminal tab atau menganggap host unknown sebagai Terminal.app.

Menu integrasi menampilkan provenance/path config, Install/Remove, listener status, waktu hook terakhir dan petunjuk repair/trust. Tidak adanya event tetap unverified; tidak ada test connection yang membuat fake session/celebration. Synthetic self-test hanya membuktikan helper/socket, bukan host event.

Pisahkan status instalasi, listener, dan last event. Tidak adanya event dapat berarti hooks disabled, config salah, managed restriction, reload belum dilakukan, atau tidak ada aktivitas; jangan otomatis menyatakan untrusted. Nudge tidak membaca/menulis trust hashes atau melewati review host.

## 10. File yang disentuh saat implementasi

Nama file baru berikut adalah daftar scope M1, bukan instruksi membuat folder kosong. Perubahan di luar daftar harus memiliki alasan tertulis sebelum dikerjakan.

| File | Perubahan/tanggung jawab |
|---|---|
| `Nudge.xcodeproj/project.pbxproj` | Target helper/tests, source memberships, embed helper, dependencies, build/signing lokal |
| `Nudge.xcodeproj/xcshareddata/xcschemes/Nudge.xcscheme` | Build helper dan jalankan kedua test bundles |
| `Nudge/Core/NudgeModels.swift` | Stable identities, live/empty snapshot, codable/sendable domain types; reuse phase/tool models |
| `Nudge/Core/Events/NudgeEvent.swift` | Canonical event dan validation-independent domain fields |
| `Nudge/Core/Reducer/SessionReducer.swift` | Pure session transitions/dedupe |
| `Nudge/Core/Reducer/FocusPolicy.swift` | Satu focused context, deterministic priority/grace |
| `Nudge/Core/PresentationReducer.swift` | Session+turn completion consumption, live empty state, sleep effect guard |
| `Nudge/IPC/WireEnvelope.swift` | Shared v1 contract, strict JSON validation, framing codec |
| `Nudge/IPC/UnixSocketTransport.swift` | Bounded POSIX client/server, peer/stale path checks |
| `Nudge/Integration/Codex/Hooks/CodexHookAdapter.swift`, `BridgeProcessor.swift` | Raw parsing, whitelist/redaction dan canonicalization |
| `Nudge/Integration/Codex/Hooks/CodexConfigurationResolver.swift` | Explicit host/config targets dan compatibility diagnostics |
| `Nudge/Integration/Codex/Hooks/CodexHookInstaller.swift` | Parse/merge/backup/atomic install-uninstall, exact ownership |
| `Nudge/Services/CodexEventMonitor.swift` | Actor session store dan focus snapshot |
| `Nudge/Services/BridgeHelperInstaller.swift` | Verifikasi digest, mode private, atomic helper install |
| `Nudge/IPC/UnixSocketTransport.swift` | OSLog reason codes dibatasi waktu; tidak log payload/identity/path |
| `NudgeBridge/main.swift` | Hook entry point dan deadline/no-op contract |
| `Nudge/App/AppState.swift`, `NudgeAppDelegate.swift` | Live snapshot application, start/shutdown listener, mode/install intents |
| `Nudge/App/NudgeApp.swift`, `Nudge/UI/PlaygroundMenuView.swift` | Integrasi controls dan eksplisit Debug Demo mode |
| `Nudge/UI/NotchRootView.swift` | Rendering snapshot live; fixture-only content gated ke Demo |
| `Nudge/Debug/PlaygroundScenario.swift` | Fixture isolation; konten demo dipertahankan |
| `NudgeCoreTests/SessionReducerTests.swift`, `FocusPolicyTests.swift`, `WireValidationTests.swift`, `PresentationReducerTests.swift` | Unit tests unhosted atas production sources |
| `NudgeIntegrationTests/HookInstallerTests.swift`, `SocketTransportTests.swift`, `BridgeFailureTests.swift` | Temporary config/socket dan helper subprocess tests |
| `NudgeIntegrationTests/Fixtures/Codex/` | Synthetic JSON per host/event + provenance note; bukan live host capture |
| `docs/Nudge-M1-Codex-Contract.md`, `docs/Nudge-M1-Verification.md` | Evidence kontrak dan handoff hasil implementasi/manual |
| `PRODUCT.md` | Update kemampuan live yang benar-benar dibangun, batas demo/M1 |

Pada sesi implementasi M1, folder di tabel telah disentuh dan file Contract/Verification ditambahkan. Tidak ada konfigurasi Codex nyata yang diubah. Mascot, panel controller/geometry, design tokens, navigation URL syntax dan seluruh struktur Core tidak dirombak. M0 standalone `*Checks.swift` tetap dipisahkan dari Xcode test bundles.

## 11. Urutan implementasi dalam M1

1. **Catat M0 override dan dokumentasikan gate B.** Pengguna memberi instruksi eksplisit untuk mulai M1 sementara QA M0 masih pending. Kontrak official dan synthetic fixtures sudah disiapkan; bukti versi host terpasang tetap tugas developer.
2. **Bangun contract/model dan tests.** Tambahkan test bundles/shared scheme, envelope v1, canonical events, SessionReducer dan FocusPolicy. Jalankan fixture workflow prompt → tools → stop/interrupt, termasuk resumed placeholder.
3. **Bangun transport dan bridge.** Embed helper, implementasikan framing, peer/permission checks dan deadline. Buktikan round-trip serta app-unavailable failure dengan temporary endpoints. Diagnostic test bukan SessionStart palsu.
4. **Bangun installer/resolver.** Temp-config saja untuk AI tests. UI menampilkan target/file/efek/preservation dan meminta konfirmasi sebelum helper/config mutation; exact ownership, backup/recovery diuji terpisah.
5. **Hubungkan live snapshot ke shell M0.** Default idle/empty, mode Demo terisolasi, tampilkan project/tool aman. Guard completion dan sleep effects. Jangan menambah attention/navigation/usage live di luar M1.
6. **Build, hermetic tests dan developer handoff.** Catat hasil, limitations serta matrix pending. Developer menjalankan verifikasi kedua host; perbaiki hanya M1 bila ada kegagalan, lalu berhenti setelah fase selesai.

Setiap langkah menghasilkan bagian workflow yang dapat diuji; jangan menyebut langkah 2 atau round-trip synthetic sebagai live integration selesai.

## 12. Automated verification

| Boundary | Skenario bermakna yang wajib lolos |
|---|---|
| Adapter/wire | Synthetic six-event fixtures, duplicate/unknown/version rejection, missing identity, oversized frame/string dan sentinel prompt/command/output yang tidak muncul pada envelope |
| Session | First tool sebelum SessionStart dan enrichment cwd, dua tools concurrent, duplicate Stop, ignored continued Stop, late old-turn event, delayed duplicate prompt, interrupted tanpa completion |
| Focus/presentation | Attention dan explicit selection priority, stable tie, new working session menang atas stale interruption, completion identity mencakup session+turn |
| Installer | Foreign hook preservation, duplicate owned entry collapse, no-op bytes/inode, private backup, malformed duplicate-key bytes unchanged, custom-home resolver, symlink refusal, safe uninstall |
| Socket | Mode 0600, own UID, fragmented frame, regular-file/symlink refusal, live second instance, stale owned socket replacement |
| Helper | Real subprocess pada socket unavailable/stalled stdin; `Stop` menghasilkan `{}` dan hook lain tidak menulis stdout; bounded completion diukur dari launch |

Not covered hermetically: different UID peer process, external editor race injection, 1 MiB oversize subprocess, all slow-client saturation patterns, or real Codex host output. Socket peer UID is checked in production with `getpeereid`; desktop/CLI config, trust and event behavior are pending manual verification. Synthetic fixtures never count as live-host evidence.

Perintah setelah targets/scheme tersedia:

```bash
xcodebuild -list -project Nudge.xcodeproj
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Release -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test
git diff --check
```

Ulangi M0 standalone checks yang relevan bila shared model/presentation berubah. Build/test reports wajib menunjukkan executed tests dan failures; test action kosong bukan keberhasilan. Signing lokal helper/build tidak membuktikan Developer ID/Gatekeeper/notarization.

## 13. Verifikasi manual oleh developer

Semua item awalnya **pending**. Gunakan sandbox project dan config yang dapat dipulihkan; developer memilih aksi Install/trust nyata. AI tidak mengubah instalasi/config Codex pengguna, mengirim prompt live, atau memutus permission tanpa instruksi eksplisit.

1. Catat versi/build Desktop, CLI, macOS, app launch method, config efektif per host, override/profile/managed restrictions dan trust status. Konfirmasikan QA M0 sudah dilaporkan atau scope exception eksplisit tercatat.
2. Dari Nudge, review preview dan install integrasi pada target yang dipilih. Periksa backup dan foreign hooks. Tinjau/trust melalui UI resmi masing-masing host; catat reload/restart yang diperlukan. Jangan memakai trust bypass sebagai bukti onboarding.
3. **Desktop new:** buka Codex dari GUI, buat local thread langsung di app, kirim tugas sandbox dengan tool, lalu pindah ke app lain. Cocokkan project → thinking → tool summary → turn finished dengan urutan host; rekam coverage event dan perceived latency. Tidak memakai terminal/app-server Nudge.
4. **Desktop resumed:** lanjutkan thread existing langsung di app. Pastikan context aktif muncul kembali, termasuk bila event pertama bukan SessionStart; tidak perlu terminal launch. Pastikan completion sekali dan judul/prompt/usage demo tidak muncul.
5. **Desktop interrupt:** hentikan active turn melalui Codex. Nudge harus interrupted, tanpa success flourish; memulai turn berikutnya harus kembali normal.
6. **CLI:** ulangi tugas tool/completion/interrupt secara terpisah dan catat event coverage/trust/config. Jangan menganggap Terminal.app sebagai host jika CLI sebenarnya di terminal lain. Catat unsupported routing sebagai batas M1.
7. Tutup Nudge saat kedua workflow host berjalan, lalu ulangi ketika Nudge tidak dibuka. Codex tetap menerima prompt, menjalankan tool dan selesai tanpa stall/error Nudge. Buka Nudge kembali; event berikutnya memulihkan status tanpa completion replay atau pemulihan transcript palsu.
8. Pada konfigurasi uji, reinstall beberapa kali dan uninstall. Pastikan owned duplicates menjadi satu, foreign hooks tetap utuh, no-op tidak rewrite, config malformed bytes tetap sama dan backup tidak terhapus. Periksa helper path masih bekerja setelah app relaunch/move yang representatif.
9. Hover/expand/collapse live pada notch dan layar fallback; periksa focus, clipping, Reduce Motion serta sleep/wake ketika working dan setelah Stop. Ini native/manual regression, bukan klaim dari unit tests.
10. Catat event-to-visible latency dan aktivitas idle pada Mac. Target M1 terasa langsung; jangan mengklaim angka p95/CPU terukur dari source review. Jika hook tidak datang, gunakan diagnostics untuk membedakan transport/config/trust/reload; rekam gap yang belum dapat dipastikan.

Isi matriks hasil berikut di `Nudge-M1-Verification.md`, dengan fixture/provenance yang aman dan actual/pending/unsupported/failed per event:

| Workflow | Versi | Config efektif | Trust/reload | Event coverage | UI/failure result |
|---|---|---|---|---|---|
| Desktop new local | Pending | Pending | Pending | Pending | Pending |
| Desktop resumed local | Pending | Pending | Pending | Pending | Pending |
| Desktop interrupt | Pending | Pending | Pending | Pending | Pending |
| CLI new/resumed/interrupt | Pending | Pending | Pending | Pending | Pending |
| Nudge unavailable, kedua host | Pending | Pending | Pending | Pending | Pending |
| Reinstall/uninstall pada config uji | N/A | Temporary | N/A | N/A | Pending |

## 14. Kriteria selesai dan handoff

- [x] Scope dibatasi M1. M0 QA pending dicatat sebagai explicit user-directed sequencing override.
- [x] Build Debug berjalan dan dua Xcode test bundles benar-benar berjalan; hasil akhir dicatat di Verification.
- [x] Envelope strict validation, socket owner-only/lifecycle checks, dan bridge failure behavior mempunyai tests.
- [x] Installer temp-config idempotent, parse-before-write, foreign-preserving, backup/atomic replacement, dan safe uninstall mempunyai tests.
- [x] Live empty/default UI, Demo isolation, focused snapshot, terminal Stop dedupe, dan interrupt mapping telah dihubungkan pada source.
- [x] Codex hooks bersifat observe-only; app meminta intent/preview untuk config mutation dan tidak mengubah trust/permission decisions.
- [x] Release build lulus; M0 standalone reducer/geometry/layout checks lulus secara static/hermetic (manual visual QA tetap pending).
- [ ] Desktop new/resumed langsung dari GUI dibuktikan developer; CLI dibuktikan terpisah dengan versi/config/trust/event coverage.
- [ ] Developer menyelesaikan native UI/M0 regression dan manual M1 workflow; tidak ada synthetic evidence yang dihitung sebagai pengganti.
- [x] Tidak ada commit dibuat karena pengguna belum meminta commit.

Handoff sementara berisi source/build/tests dan batas manual di `Nudge-M1-Verification.md`; versi kandidat dan synthetic-only contract berada di `Nudge-M1-Codex-Contract.md`. Implementasi source M1 tersedia, tetapi acceptance/phase M1 **masih pending** sampai developer memverifikasi kedua host dan QA visual sesuai daftar manual. **Tidak ada pekerjaan M2 dimulai.**

## ATURAN PENGERJAAN — blok wajib dari AGENTS.md

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
