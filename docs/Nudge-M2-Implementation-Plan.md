# Nudge — Implementation Plan M2: Codex Edge-Case Hardening

Tanggal: **2 Oktober 2026**. Status: **implementasi source dan fixture M2 selesai; verifikasi live/manual developer masih pending**. Plan ini ditulis sebelum pelaksanaan; hasil aktual dan batasnya tercatat di [M2 verification handoff](Nudge-M2-Verification.md).

Sumber kebenaran: [project brief](Nudge-Project-Brief.md), bagian 6, 45, dan milestone M2; [AGENTS.md](../AGENTS.md). Baseline implementasi dan acceptance M1 dicatat dalam [M1 verification](Nudge-M1-Verification.md) dan [M1 contract](Nudge-M1-Codex-Contract.md).

Pengguna kemudian secara eksplisit menginstruksikan pelaksanaan M2 sebelum M1 live verification selesai. Urutan itu dicatat sebagai override; M1 belum dianggap lulus. Implementasi tidak memulai live turn, memasang hooks, atau mengubah konfigurasi Codex nyata.

## 1. Hasil yang dituju dan batas fase

Workflow M2: **developer melanjutkan local thread Desktop → event pertama dapat berupa tool tanpa SessionStart → Nudge materialisasikan konteks dan memperbaiki metadata → tool panjang tetap aktif meskipun tenang → completion muncul sekali meskipun ada duplicate/suggestion Stop → sleep/wake memulihkan satu current presentation tanpa replay**. Jalankan workflow setara secara terpisah di CLI. Reinstall/uninstall pada config uji juga mempertahankan foreign hooks dan bytes malformed config.

Deliverable: deterministic lifecycle hardening, dedupe yang tidak menelan enrichment/progress valid, pending reconciliation pada domain, kebijakan inactivity, sleep/wake reconciliation, installer/resolver hardening, fixtures berprovenance, serta handoff manual M2.

Scope M2 mencakup:

- Duplicate hook cleanup, duplicate events, dan completion dedupe.
- Suggestion-style Stop, dengan batas kontrak host yang eksplisit.
- Resume tanpa SessionStart, termasuk turn baru setelah terminal turn lama.
- Metadata enrichment tanpa mengulang state transition.
- Long-running tools, concurrent tools, dan quiet thinking/waiting.
- Pending cleanup berdasarkan bukti progress/resolution yang relevan.
- Sleep/wake, stale timers, motion cancellation, dan completion consumption.
- Malformed/unsupported config preservation dan reversible mutation.
- Custom CODEX_HOME serta target configuration Desktop/CLI yang berbeda.

UI question/permission mirror dan onboarding attention tetap M3. M2 menambahkan state pending minimal yang dapat diuji melalui canonical fixtures; tidak memasang PermissionRequest, mengimplementasikan live question mirror, atau membuat tombol keputusan. Precise navigation M4, permission actions M5, distribution M6, sounds, app-server, transcript fallback, dan dependency baru tidak masuk scope.

## 2. Baseline dan prasyarat

Pemeriksaan source pada tanggal plan menemukan:

| Area | Yang sudah tersedia | Celah M2 |
|---|---|---|
| Project | Nudge, NudgeBridge, dua Xcode test bundles, shared Nudge scheme | Gunakan project/scheme yang ada; tambahkan membership hanya untuk file baru |
| Adapter/wire | Enam event M1, sanitasi, envelope v1 strict, input 1 MiB/frame 64 KiB | Stop classification belum membuktikan suggestion-only; metadata hanya project basename |
| Session reducer | Placeholder dari event pertama, active tool map, ledger 32 completed turns | Turn berbeda pada tool ditolak jika session sudah memiliki turn; ordering memakai numeric turn IDs |
| Monitor | Actor, semantic key cache 512 entry | Key tidak memuat project/tool payload, tanpa TTL; duplicate event dapat menelan enrichment |
| Completion presentation | Key session+turn, transient timers | Hanya satu consumed completion key; perpindahan fokus A → B → A dapat replay completion A |
| Sleep/wake | Observers, cancel presentation timers, hide/show panel | snapshotChanged masih dapat menghasilkan celebration saat sleeping; wake tidak mengambil ulang focused snapshot monitor |
| Motion | Nudgie original dan Reduce Motion | Task pengembalian hop tidak dikelola untuk cancellation/sleep |
| Installer | Exact command ownership, private backup saat install, atomic replace, malformed JSON refusal | Backup belum dibuat saat uninstall; matcher/foreign-field/race cases perlu fixtures lebih lengkap |
| Config target | Explicit folder per host, environment CODEX_HOME candidate | Invalid override diam-diam fallback; environment Nudge belum membuktikan config efektif host |
| Pending | Waiting phases tersedia untuk demo/focus | Session domain belum memiliki pending identity atau resolution rules |
| Tests | M1 mencatat 28 tests passed serta Release build passed | Hasil historis; tidak dijalankan ulang untuk sesi plan dan bukan bukti live host |

M1 acceptance masih **pending**: Desktop new/resumed, CLI, trust/config, Nudge-unavailable, dan native QA belum ditandai lulus developer. Instruksi eksplisit untuk mulai M2 mengubah urutan kerja, tetapi tidak mengubah status bukti host menjadi passed. M2 source dapat ditinjau; verifikasi manual tetap menjadi gate sebelum acceptance dan sebelum M3.

## 3. Kontrak yang diverifikasi dan yang masih perlu bukti

Rujukan resmi ditinjau pada 2 Oktober 2026:

- Stop membawa turn_id, stop_hook_active, dan optional last_assistant_message. Flag tersebut menunjukkan turn pernah dilanjutkan oleh Stop; bukan penanda suggestion-only dan bukan bukti final/nonfinal saat ini. Neutral output Stop tetap JSON `{}`. [Hooks](https://learn.chatgpt.com/docs/hooks).
- Hook sources dapat bertumpuk, termasuk hooks.json dan inline hooks pada config.toml. Ini membatasi deduplication installer ke file yang dikelolanya. [Advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced).
- CODEX_HOME didokumentasikan untuk CLI dan beberapa host/runtime lain; daftar itu belum membuktikan root efektif Desktop yang dibuka melalui GUI. Custom root harus sudah ada. [Environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables).

Panduan Hooks yang diperiksa tidak memberikan discriminator suggestion-only. Karena itu, penelitian Code Island dalam brief adalah edge-case requirement, bukan kontrak wire yang boleh langsung diasumsikan. Tidak menyalin code/artwork proyek tersebut.

Sebelum mengubah adapter live, lengkapi catatan kontrak dengan:

| Host/workflow | Kandidat dari M1, bukan pemeriksaan versi baru | Bukti yang harus dicatat developer |
|---|---|---|
| Desktop new/resumed local | 26.928.31416, build 12553 | Versi saat test, config efektif, trust/reload, event pertama resume, stable IDs |
| Desktop extra Stop/continuation | Kandidat Desktop yang sama | Bentuk Stop, turn identity, chronology, apakah terminal setelah continuation terobservasi |
| CLI new/resumed | codex 0.154.0 | Versi saat test, root shell/CODEX_HOME, trust/reload, coverage tool/Stop/interrupt |
| CLI custom home | Versi saat test | Dua root terpisah; install ke root yang dipilih; default home tidak tersentuh |
| Desktop custom root | Pending capability | Jalur yang didukung host; jika tidak tersedia, catat unsupported beserta batasnya |

Fixtures host hanya berasal dari capture developer yang sudah disanitasi. Fixture buatan diberi label synthetic, termasuk suggestion/pending fixtures; tidak dihitung sebagai event coverage Desktop/CLI. Catat source URL, tanggal, host/version, scenario, expected transition, dan alasan field yang dibuang. Jangan menyimpan prompt, transcript, output command, secrets, atau path personal asli.

Jika discriminator suggestion tidak dapat dibuktikan, same-turn extra Stop tetap ditahan oleh completion ledger. Suggestion-only sebagai event pertama atau dengan identitas berbeda **belum dapat dijamin**: catat limitation, jangan membuat regex assistant prose, menebak ID, atau menyebut coverage tersebut passed. Validasi ulang asumsi M1 yang membuang semua Stop dengan stop_hook_active=true; keputusan adapter baru harus mengikuti bukti terminal/continuation, bukan nama flag.

## 4. Tanggung jawab dan alur data

```text
Desktop / CLI command hooks
  → NudgeBridge / CodexHookAdapter: validasi + sanitasi + provider classification
  → envelope v1 / owner-only socket: strict decode, bounded delivery
  → serial ingress → CodexEventMonitor actor
       ├─ metadata merge + short-lived duplicate filter
       ├─ SessionReducer: turn/tools/pending/lifecycle invariants
       └─ FocusPolicy: satu konteks prioritas
  → ordered snapshot/transition update
  → AppState @MainActor → PresentationReducer
  → current NSPanel presentation + cancellable Nudgie motion

Sleep/wake → suspend effects → monitor current snapshot → restore presentation
Installer/resolver → selected temporary/explicit config target, terpisah dari event stream
```

Core menerima canonical events dan identifier; tidak mengimpor format provider, SwiftUI, atau AppKit. Adapter memutus klasifikasi provider sebelum raw payload dibuang. Monitor menyimpan state/cache bounded di memori dan memberikan snapshot serta identity transisi terminal; view tidak menentukan apakah sebuah turn baru selesai.

Parsing, IPC, config reads/writes, fixture sanitization, dan reconciliation berada di luar main actor. Main actor hanya menerapkan update UI, workspace lifecycle, panel, serta efek ringan. Task terpisah per socket callback saat ini tidak menjamin urutan aplikasi snapshot; gunakan satu jalur ingest serial dan revision lokal agar hasil lama tidak menimpa hasil baru. Urutan ingest bukan bukti urutan semantik event lintas helper.

## 5. Desain hardening domain dan completion

### 5.1 Dedupe dan metadata enrichment

Pisahkan **transport duplicate** dari **semantic lifecycle idempotency**:

1. Validasi envelope sebelum membuat state/cache entry.
2. Merge metadata aman yang lebih lengkap; absent/empty/default label tidak menurunkan metadata yang sudah valid. Jangan memperbarui lastActivityAt hanya karena enrichment/duplicate.
3. Duplicate fingerprint memakai session, turn, event, tool ID, dan nilai payload canonical yang diizinkan. Gunakan structured key agar delimiter dalam ID tidak menyebabkan collision. Timestamp penerimaan helper tidak menjadi identitas duplicate.
4. TTL awal duplicate cache: **2 detik monotonic**, maksimum **512 entries**; clock dapat diinjeksi. Pertahankan lifecycle idempotency meski TTL habis/cache penuh. Tidak ada polling permanen; prune saat ingress/reconciliation.
5. Metadata baru pada duplicate tetap diterapkan, tetapi tidak membuka kembali tool yang selesai, mengubah focus recency palsu, atau menghasilkan completion effect.

Jangan memakai hash raw prompt/tool output. Bounded cache tidak menggantikan reducer ledger. Boundary test harus melewati TTL, cache eviction, dan repeated tool IDs untuk membuktikan keduanya berbeda.

### 5.2 Turn identity, resume, dan tool order

Turn ID adalah opaque string; jangan memakai UInt64 comparison atau urutan alfabet sebagai chronology. observed_at_ms saat ini dibuat bridge saat invocation, bukan timestamp asli host, sehingga delayed delivery tidak otomatis berarti new work.

Aturan:

- Trusted canonical event sebelum SessionStart dapat membuat placeholder. Missing identity tetap ditolak decoder dan tidak membuat phantom session.
- SessionStart terlambat hanya enrich metadata; tidak mengubah working/waiting/terminal phase menjadi idle.
- UserPromptSubmit untuk turn baru membuka turn generation dan membersihkan activeTools/pending milik turn lama; duplicate prompt turn yang sama tidak mereset progress.
- Jika turn saat ini sudah terminal, PreToolUse dari turn berbeda yang belum dikenal dapat memulai resumed turn tanpa SessionStart/UserPromptSubmit. Saat session belum punya turn, tool menetapkan identity turn.
- Event dari turn yang sudah tercatat retired/terminal tidak mengambil alih current turn. Tools terminal memiliki tombstone sehingga delayed duplicate PreToolUse tidak membuka tool kembali setelah PostToolUse.
- Jika session masih aktif/waiting dan tool dari turn berbeda muncul tanpa anchor yang membuktikan pergantian, jangan mengakhiri current turn berdasarkan waktu saja. Catat ambiguity secara aman dan dokumentasikan batas kontrak; accepted UserPromptSubmit menjadi anchor pergantian.
- PostToolUse yang datang sebelum PreToolUse pada placeholder dapat materialisasikan turn dan mencatat tool selesai. Late matching PreToolUse tidak membuat stuck toolUse. Terminal event valid dapat materialisasikan unknown session/turn dengan satu terminal transition.
- Concurrent tools berakhir per tool ID; selesai satu tool tidak membersihkan tools lain. Late Stop/Interrupt dari retired turn tidak mengubah current turn.

Ledger turn/tool bounded mengikuti lifecycle: jangan membuang current turn, active tools, pending, atau identitas completion yang masih bisa dipresentasikan. Retired-turn retention dan eviction harus tertulis dalam tests. Replay setelah restart proses atau setelah metadata lama dihapus bukan jaminan exactly-once lintas instalasi; tidak menambah transcript database/persistent event ledger.

### 5.3 Stop dan completion effects

Tiga hal harus terpisah: raw Stop diterima, canonical turn terminal, dan completion effect ditampilkan.

- Adapter mempertahankan neutral response untuk Codex walaupun event dropped/unsupported. Suggestion/continuation classification hanya menggunakan kontrak/fixture terverifikasi.
- Reducer menghasilkan didCompleteTurn hanya pada terminal transition pertama untuk session+turn. Same-turn suggestion/duplicate Stop sesudahnya tidak memperbarui terminal recency atau membersihkan turn baru.
- SubagentStop tidak dipetakan ke main-turn completion. Event tersebut tetap di luar daftar enam hooks M1; payload yang tidak cocok ditolak, tanpa phantom session.
- Bawa terminal transition identity ke presentation. Snapshot completed akibat focus switch/enrichment/wake bukan trigger celebration.
- Ganti satu consumed key dengan consumption policy per session+turn, bounded bersama retained sessions. Uji A completed → B completed → A focused: tidak ada flourish/card/timer baru untuk A.
- Completion hanya memicu satu transient card dan satu mascot pulse saat eligible di konteks fokus. Completion background tidak diantre menjadi parade saat focus/wake; status terminal tetap dapat diketahui dari current snapshot.
- Failed/interrupted tidak pernah menjalankan success effect. Tidak menambahkan sound pada M2; jika sound ditambahkan di fase lain, harus memakai identitas transisi yang sama.

Jaminan utama: **satu semantic completion dan maksimal satu presentation effect per retained session+turn**, tanpa replay dari duplicate hooks, metadata, focus changes, atau sleep/wake.

## 6. Pending reconciliation dan inactivity

M2 menambahkan pending domain minimal: kind question/permission, stable request ID, session/turn, optional associated tool ID, dan creation/lifecycle identity. Tidak menyimpan question text, choices, command, atau permission decision. Canonical input untuk seed pending digunakan pada tests; production permission/question hook capture dan UI detail dimulai M3.

Resolution harus membuktikan keterkaitan:

| Input setelah pending | Hasil |
|---|---|
| Matching PostToolUse pada tool/turn terkait | Clear pending tersebut; phase kembali mengikuti remaining tools |
| Explicit canonical resolution yang cocok | Clear hanya request yang cocok |
| Verified progress yang membuktikan tool terkait lanjut | Clear sesuai identity dan host contract, bukan sembarang event |
| New-turn anchor, Stop/Interrupt/lifecycle termination valid | Invalidasi pending milik turn yang berakhir; jangan clear pending turn lain |
| Unrelated concurrent tool, duplicate/late old-turn event, SessionStart metadata | Pending tetap |
| Open Codex, hover/collapse, quiet interval, sleep/wake | Pending tetap |

Waiting status harus menang atas stale tool label dalam snapshot. Canonical lifecycle termination dapat diuji sebagai domain input tanpa memasang SessionEnd hook baru. Provider event untuk termination/permission tidak ditambahkan tanpa scope dan contract record tersendiri.

Inactivity bukan terminal proof. Thinking, toolUse, waitingPermission, dan waitingInput tetap hidup tanpa batas timeout aktivitas. Untuk session idle/terminal yang tidak dipilih dan tidak memiliki pending/tools, retensi memori awal **30 menit** dapat dipruning saat event baru/wake; tidak menambah timer per session. Completion grace tetap concern FocusPolicy/presentation dan tidak menandai session ended.

Tidak menambah PID fallback di M2 karena hook semantics yang tersedia lebih kuat dan PID ancestry belum diverifikasi. Fixture PID reuse dicatat **not applicable: fallback absent**, bukan passed. Jika kemudian dibutuhkan, wajib PID+process start time dan test reuse sebelum digunakan; PID alive/dead saja tidak mengakhiri session.

## 7. Sleep/wake dan motion

Sleep:

1. Set sleeping flag sebelum menjalankan update UI berikutnya; batalkan peek/collapse/transient/feedback tasks dan increment generations.
2. Batalkan mascot hop task serta reset pose offset tanpa animasi. Pause motion ketika sleeping; Reduce Motion tetap dihormati.
3. Ingress dapat memperbarui domain/latest snapshot, tetapi tidak menghasilkan celebration, transient timers, sound, atau transition queue. Tandai terminal identity saat sleep sebagai consumed/suppressed untuk presentation.

Wake:

1. Ambil focused snapshot terbaru dari monitor melalui jalur serial yang sama; revision guard mencegah hasil reconciliation lama menimpa event baru.
2. Terapkan satu restoration input pada presentation; rebuild geometry/panel memakai current display dan visibility preference.
3. Jangan memutar ulang completed/failed transient, stale hover, atau timer generation lama. Pending tetap attention sampai valid resolution; working tetap working meski quiet.
4. Timer baru hanya untuk interaction baru setelah wake. Repeated sleep/wake idempotent, termasuk saat Demo aktif; domain live dan demo tetap terisolasi.

Unit tests menyimulasikan snapshot completed saat sleeping, delayed timers, repeated wake, focus switch, dan Reduce Motion cancellation. Native timing/window behavior tetap diperiksa developer di Mac.

## 8. Installer, configuration, compatibility, dan recovery

### Compatibility strategy

Default M2 **mempertahankan wire schema v1, enam registered event names, helper command, socket path/mode, dan neutral hook output M1**. Hardening domain/presentation dilakukan di app; pending fixtures tidak mengubah wire. Jangan menambah fields ke v1 karena decoder lama menolak unknown keys.

Jika bukti host memerlukan metadata wire baru untuk menyelesaikan M2, tulis addendum sebelum implementasi: versi baru, field whitelist, reader menerima v1+versi baru, fixtures kedua versi, serta rollout app reader sebelum helper writer. Decoder v1 lama akan drop frame baru; Codex tetap lanjut. Rollback pasangan app/helper, jangan mengklaim mixed versions kompatibel. Jangan menaruh raw provider payload pada schema baru.

Hook-definition perubahan dapat memerlukan review/trust ulang; tampilkan status itu tanpa mengubah trust. M2 tidak mengubah config.toml. Unknown inline/project/managed config layers dilaporkan sebagai compatibility boundary dan tidak diedit dengan string replacement.

### Installer mutation

- Parse-before-write; malformed JSON, duplicate keys, wrong root/handler shapes, symlink/nonregular path, dan unsupported structures tidak dianggap empty config.
- Canonicalization hanya untuk exact Nudge ownership. Per event dalam selected hooks.json: 0 → 1, 1 → 1, N → 1. Jangan menghapus helper lain yang sekadar memiliki kata Nudge pada command.
- Pastikan canonical owned handler berada dalam group yang menerima event coverage yang dituju. Retaining handler pertama dalam restrictive matcher dapat membuat coverage hilang; pisahkan owned handler dari mixed group bila aman, preserve foreign handler/group metadata. Jika ownership/extra fields membuat rewrite ambigu, abort dengan repair guidance.
- Preserve foreign commands, matchers, order relatif, timeout, unknown events, root metadata, dan group fields. Foreign **semantic values** harus sama setelah write; byte-for-byte wajib untuk no-op, failure, malformed, dan backup original. JSON formatting boleh berubah hanya saat mutation valid.
- No-op install/uninstall tidak membuat backup atau rewrite; assert bytes/inode unchanged. Lock/temp artifacts mengikuti kebutuhan operasi dan tidak merusak file asli.
- Backup exact original sebelum **setiap mutation yang berubah, termasuk uninstall**. Backup failure membatalkan replacement. Backup privat 0600; direktori owner-only; jangan menghapus backup otomatis.
- Atomic replacement pada direktori yang sama, preserve original mode, verify file type/owner, compare original sebelum write. Concurrent installer memakai lock; file berubah oleh editor menghasilkan conflict jika terdeteksi. Jangan mengklaim lock mengikat editor eksternal atau check+rename sebagai atomic compare-and-swap.
- Tambahkan injectable mutation boundary untuk conflict/backup/write failure tests yang deterministik. Jika file berubah, jangan overwrite lewat retry otomatis. Catat keterbatasan race eksternal yang belum bisa dijamin.

### Configuration resolver

Explicit folder per host memiliki prioritas atas candidate environment, lalu default candidate. Absolute nonempty CODEX_HOME yang invalid/tidak ada tidak boleh diam-diam menjadi ~/.codex atau membuat root yang salah. Kembalikan error actionable; path relatif tidak diselesaikan terhadap working directory Nudge.

Nudge environment tidak selalu sama dengan shell CLI atau Desktop GUI. Tampilkan source/confidence serta selected target, tanpa mengatakan effective config sudah terverifikasi hanya karena folder dipilih. Desktop dan CLI boleh memakai root berbeda atau sama; shared root tidak dipasang dua kali. Ganti pilihan host tidak memindahkan/menghapus hooks root lama secara otomatis.

### Backup dan recovery

Jika config malformed: original bytes tetap; tampilkan target dan instruksi developer memperbaiki file lalu retry. Jika permission/backup/write conflict: tidak ada destructive fallback atau reset config. Jika instalasi gagal setelah helper tersedia, Codex tetap mandiri; status tidak boleh menyebut hooks installed.

Recovery dari backup adalah aksi developer: tinjau snapshot dan current config, restore hanya bila tidak membuang perubahan baru/foreign entries. Default pemulihan integrasi adalah safe uninstall/reinstall pada root yang dipilih; jangan auto-restore seluruh backup. Uninstall menghapus hanya owned handlers, tidak menghapus root, config lain, helper/data Codex, atau backups pengguna.

## 9. Failure behavior, privacy, dan trade-offs

| Risiko/failure | Perilaku yang diharapkan |
|---|---|
| Nudge tertutup/crash, socket unavailable/stalled | Bridge tetap deadline bounded 250 ms target M1, exit neutral; Codex melanjutkan sesuai native host behavior |
| Malformed/unknown/oversized envelope atau invalid peer | Drop sebelum mutation; bounded diagnostic code, tanpa phantom session |
| Missing events atau metadata | Placeholder/batas confidence; tidak menebak completion, trust failure, title, atau host |
| Delayed events/opaque turn ambiguity | Lindungi active/terminal identity; diagnostic ambiguity; tidak mengandalkan urutan angka/wall clock |
| Cache/retention eviction | Tidak menghapus current active/waiting/pending; jaminan replay dibatasi retained lifecycle |
| Suggestion-only tanpa indikator host | Same-turn dedupe tetap aman; broader detection pending/unsupported dicatat |
| Malformed config atau race | Preserve original bila abort; recovery guidance; foreign config tidak direset |
| Custom home berbeda per host | Target eksplisit dan evidence terpisah; tidak mengikuti environment Nudge secara buta |

Tidak ada account/cloud/telemetry atau persistent raw event/transcript cache. Diagnostics memakai OSLog dengan reason codes dan identifier yang direduksi, tanpa prompt/tool input/output/assistant text/path personal. Captures disanitasi sebelum menjadi repo fixtures. Backup config adalah exception recovery yang sudah dibutuhkan installer, disimpan privat dan tidak masuk logging/export.

Trade-off: domain pending ditambahkan lebih dahulu supaya M3 memakai invariants teruji; live mirror tetap belum tersedia. Exactly-once effects dibatasi proses/retained lifecycle; tidak menambah persistence hanya untuk replay historis. Tidak ada app-server atau transcript fallback untuk menutupi host coverage yang gagal. Pilihan ini menjaga M2 fokus pada reliability jalur M1.

## 10. File yang disentuh saat implementasi M2

| File/area | Alasan |
|---|---|
| Nudge/Core/Events/NudgeEvent.swift | Canonical identity, metadata update, pending/progress/termination domain inputs |
| Nudge/Core/Reducer/SessionReducer.swift | Opaque turn policy, tool tombstones, lifecycle/pending reconciliation |
| Nudge/Core/NudgeModels.swift | Snapshot/transition identity, consumed effects, sleep restoration state |
| Nudge/Core/Reducer/FocusPolicy.swift | Quiet/waiting stability dan retention/focus interaction |
| Nudge/Services/CodexEventMonitor.swift | TTL duplicate cache, metadata merge, retained ledger, current snapshot API |
| Nudge/Services/CodexEventIngress.swift, Nudge/IPC/UnixSocketTransport.swift | Ordered actor ingress and bounded socket-delivery barrier before wake snapshot |
| Nudge/Core/PresentationReducer.swift | Transition-driven effects, focus/wake/sleep replay protection |
| Nudge/App/AppState.swift | Ordered UI update, safe restore/effect scheduling, resolver errors |
| Nudge/App/NudgeAppDelegate.swift | Serial event delivery dan monitor wake reconciliation |
| Nudge/UI/Nudgie.swift, Nudge/UI/NotchRootView.swift | Sleep-aware cancellable hop dan penerusan motion eligibility saja |
| Nudge/Integration/Codex/Hooks/CodexHookAdapter.swift | Stop assumptions dan safe metadata classification sesuai evidence |
| Nudge/Integration/Codex/Hooks/CodexHookInstaller.swift | Canonical ownership/matcher handling, backup uninstall, deterministic failure seam |
| Nudge/Integration/Codex/Hooks/CodexConfigurationResolver.swift | Invalid-root errors dan independent target provenance |
| NudgeCoreTests/SessionReducerTests.swift, FocusPolicyTests.swift, PresentationReducerTests.swift | Domain/focus/presentation regressions dan fake clock |
| NudgeIntegrationTests/CodexEventIngressTests.swift, SocketTransportTests.swift | Ordered ingress and socket-delivery barrier before wake reconciliation |
| NudgeIntegrationTests/HookInstallerTests.swift, WireAdapterTests.swift | Config preservation, Stop/privacy, monitor duplicate/enrichment, dan failure regression |
| NudgeIntegrationTests/Fixtures/Codex/edge-cases/ (baru) | Sanitized sequence fixtures dan provenance README |
| Nudge.xcodeproj/project.pbxproj | Membership source/tests/resources baru pada target yang benar |
| docs/Nudge-M1-Codex-Contract.md | Koreksi kontrak/assumption M1 dengan tanggal/evidence; pertahankan provenance historis |
| docs/Nudge-M2-Implementation-Plan.md, docs/Nudge-M2-Verification.md | Rencana, hasil, batas coverage, developer handoff |

Schema wire v1 tidak berubah. `Nudge/App/NudgeAppDelegate.swift` menjalankan socket drain/barrier di task background dan menerapkan snapshot di main actor. `Nudge/UI/NotchRootView.swift` dan `Nudge/UI/Nudgie.swift` hanya meneruskan sleep eligibility dan membatalkan hop tertunda. Tidak ada perubahan pada NotchPanelController atau kontrak wire.

## 11. Urutan implementasi satu fase

1. **Baseline dan kontrak.** Review M1/manual status; catat gate/override, actual host candidates, serta batas suggestion/Stop/custom home. Buat fixtures dan provenance lebih dahulu; tentukan apakah schema v1 cukup.
2. **Domain identity dan reducer.** Tutup resume/new-turn/tool-order celah, metadata merge, pending cleanup, quiet retention. Tests opaque IDs/retired turns/pending relevance membuktikan transisi.
3. **Monitor dan completion delivery.** TTL fingerprint, semantic ledgers, serial ingress/revision, serta terminal identity ke presentation. Uji duplicates melewati TTL/cache eviction dan focus A/B/A.
4. **Sleep/wake serta motion.** Suppress effects saat sleep, reconcile current snapshot, cancel mascot task. Uji delayed timer/snapshot race dan repeat wake.
5. **Installer/resolver.** Temp configs saja: canonical handler coverage, uninstall backup, failure preservation, invalid custom roots, shared/separate target. UI existing menampilkan error/recovery tanpa screen baru.
6. **Build/tests dan handoff.** Jalankan relevant suites, catat executed count/failures, siapkan verification matrix; developer memeriksa host/native UX. Perbaiki hanya M2, kemudian berhenti. Tidak mulai M3.

## 12. Automated tests dan bukti yang diperlukan

Semua tests hermetic memakai temporary config/socket, in-memory sequences, clock injection, dan subprocess helper test. Tidak menggunakan config/socket produksi atau menjalankan permission decisions nyata.

| Boundary | Skenario bermakna | Expected |
|---|---|---|
| Stop | Real Stop → duplicate → suggestion-style same-turn, timestamp berbeda, TTL lewat | Satu semantic completion; satu eligible card/pulse; terminal time tetap |
| Stop contract | stop_hook_active=true, continuation dan later terminal sesuai evidence | Tidak menyamakan flag dengan suggestions; unsupported case ditandai |
| Main/subagent | SubagentStop/mismatched expected event | Tidak menyelesaikan main turn atau membuat phantom session |
| Resume | First PreToolUse/PostToolUse/Stop tanpa SessionStart; terminal old → unseen new tool turn | Placeholder valid, correct phase, new resumed turn diterima sesuai anchor policy |
| Metadata | Late SessionStart/new label pada duplicate tool, missing/invalid cwd sesudah valid | Enrichment tanpa regression, reset tool, fake recency, atau pulse |
| Ordering | UUID/non-numeric turn IDs, old prompt/Stop terlambat, Post sebelum Pre, concurrent tools | Opaque identity; retired events tidak takeover; finished tool tidak reopen |
| Cache | TTL boundary, 512-entry overflow, canonical key delimiter collisions | Valid progress/enrichment tetap masuk; semantic dedupe bertahan |
| Quiet | Fake clock +10 menit dan +24 jam saat thinking/toolUse/waiting | State/focus masih aktif; no inactivity termination |
| Pending | Matching resolution vs unrelated tool/turn, open/collapse/metadata/quiet, new-turn terminal | Hanya valid relevant progress/termination yang clear |
| Focus/effects | A complete → B complete → A selected, metadata update, background completion | Tidak replay card/pulse; satu context tetap prioritas |
| Sleep | Completion diterima sleeping, timer lama sesudah wake, repeated sleep/wake, Demo isolation | Zero sleeping/replayed pulse, no stale transient/timer, latest snapshot |
| Delivery | Rapid revisions, wake reconciliation beradu dengan new event | Snapshot lama tidak menimpa latest state |
| Installer | 0/1/N owned entries, mixed/restrictive matcher, foreign near-match/unknown fields | Satu canonical handler; foreign values/order utuh; ambiguous shape abort |
| Backup | Install/uninstall mutation, backup unavailable, no-op reinstall/uninstall | Exact private backup sebelum mutation; backup fail abort; no-op no rewrite |
| Config failure | Truncated/duplicate-key/root-array JSON, permission, symlink, editor conflict/write failure | Original bytes tetap pada abort; no empty-config fallback |
| Resolver | Explicit > environment > default, invalid/relative/missing root, host roots berbeda/sama | Target/error benar; tidak membaca/mengubah config nyata |
| Wire/privacy | Unknown/version/size rejection, fixture secret sentinels | No state mutation; sentinel tidak muncul di wire/diagnostics |
| Bridge | Unavailable/stalled temporary socket, invalid input | Neutral output dan bounded failure seperti M1 |

PID-reuse fixture conditional, hanya jika process fallback benar-benar ditambahkan. Runtime latency/CPU, native accessibility/Spaces/notch/motion, config trust, dan real host coverage tidak dibuktikan oleh unit fixtures.

Perintah eksekusi saat implementasi tersedia:

```bash
xcodebuild -list -project Nudge.xcodeproj
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Release -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test
git diff --check
```

Shared TestAction harus menjalankan kedua test bundles; zero executed tests bukan passed. Ulangi M0 static checks yang relevan jika shared presentation/model berubah. Jika toolchain/scheme tidak tersedia atau gagal, catat batasnya tanpa mengklaim build/manual passed.

## 13. Verifikasi manual oleh developer

Semua item mulai **pending**. Developer memakai sandbox project serta konfigurasi uji yang dapat dipulihkan. AI tidak memasang integrasi ke config nyata, mengirim live prompt, atau menggantikan verifikasi native tanpa instruksi eksplisit.

1. Catat versi/build Desktop, CLI, macOS, launch method, config efektif per host, trust/reload, dan status M1. Pastikan Desktop pengujian dimulai langsung dari GUI tanpa terminal/app-server Nudge.
2. **Desktop new/resumed:** mulai turn baru dan lanjutkan local thread existing. Cocokkan first event, project enrichment, thinking/tool/completed/interrupted. Uji resume yang event awalnya bukan SessionStart, termasuk setelah previous turn sudah selesai.
3. **CLI terpisah:** ulangi new/resumed/tool/completion/interrupt; catat perbedaan IDs/event coverage. Hasil Desktop tidak dianggap bukti CLI atau sebaliknya.
4. Jalankan tool panjang pada kedua host sampai quiet interval melewati 10 menit; Nudge tetap working. Selesaikan tool lalu pastikan status lanjut/terminal normal. Catat bila host tidak menyediakan event yang dibutuhkan.
5. Jalankan synthetic duplicate/suggestion demo melalui temporary event harness. Pastikan satu completion card/pulse; lakukan focus A → B → A tanpa replay. Jika extra Stop alami dapat direproduksi di host, simpan sanitized fixture dengan provenance; synthetic bukan live proof.
6. Sleep/wake saat working, setelah completion, dan ketika completion diterima sekitar sleep. Pastikan satu current presentation, tanpa celebration replay, hover flicker, timer ganda, atau mascot hop tertunda. Ulangi Reduce Motion.
7. Seed pending canonical pada harness: unrelated progress/open/collapse/quiet tidak clear; matching progress/terminal clear. Live question/permission resolution tetap verifikasi M3 dan tidak disebut sudah supported oleh M2.
8. Pada temp config, install/reinstall dengan duplicate owned handlers dan foreign hooks; uninstall lalu periksa exact backup, foreign semantic values, no-op bytes, malformed original bytes, dan safe failure/recovery. Uji restrictive matcher dan foreign command yang mirip Nudge.
9. Uji CLI memakai custom CODEX_HOME yang sudah ada serta folder Nudge pilihan host; pastikan root default tetap utuh. Uji Desktop custom configuration melalui jalur yang didukung host. Catat unsupported bila host tidak menyediakannya; jangan memaksa GUI membaca shell environment.
10. Tutup Nudge saat kedua host bekerja dan ulangi ketika Nudge tidak dibuka. Codex harus lanjut normal; setelah Nudge dibuka event baru mengembalikan status tanpa replay completion lama. Keputusan permission tetap di Codex.
11. Periksa regresi physical notch/fallback display, hover, Spaces/full-screen, menu-bar auto-hide, keyboard/VoiceOver, dan idle motion. Catat hasil aktual beserta limitations; source review/build tidak menggantikan native QA.

Isi docs/Nudge-M2-Verification.md saat implementasi dengan actual/pending/unsupported/failed:

| Workflow | Versi/config/trust | Event/fixture provenance | Hasil |
|---|---|---|---|
| Desktop new/resumed/interrupt | Pending | Pending live | Pending |
| CLI new/resumed/interrupt | Pending | Pending live | Pending |
| Long tool + quiet, Desktop | Pending | Pending live | Pending |
| Long tool + quiet, CLI | Pending | Pending live | Pending |
| Duplicate/suggestion Stop | Pending | Synthetic dan host evidence dipisahkan | Pending |
| Sleep/wake/focus/Reduce Motion | Pending | Native/manual | Pending |
| Pending cleanup domain | N/A | Canonical synthetic; live UX M3 | Pending |
| Reinstall/uninstall/corrupt config | Temp target | Config test/manual | Pending |
| Custom home CLI / Desktop | Pending per host | Pending / unsupported jika terbukti | Pending |
| Nudge unavailable | Pending per host | Pending live | Pending |

## 14. Kriteria selesai dan handoff

- [ ] Scope hanya M2; gate/override M1 tercatat dan evidence historis tidak diubah menjadi passed.
- [ ] Known edge-case fixtures mencakup duplicates/suggestions, resume, enrichment, long/quiet tools, pending relevance, sleep/wake, malformed config, dan custom root.
- [ ] Completion tepat sekali untuk retained lifecycle; metadata/focus/TTL/wake tidak mengulang card/pulse. Failed/interrupted berbeda dari success.
- [ ] Thinking/toolUse/waiting tidak expire karena quiet interval; valid pending progress membersihkan stale state tanpa false resolution.
- [ ] Installer idempotent, foreign-preserving, private backup untuk install/uninstall mutation, no-op skip write, serta error preservation teruji.
- [ ] Config efektif dan event coverage Desktop/CLI tercatat terpisah; GUI new/resumed tidak membutuhkan terminal/app-server Nudge.
- [ ] Suggestion discriminator/Stop continuation dan custom Desktop configuration limitations dijelaskan; unsupported cases tidak diklaim lulus.
- [ ] Debug/Release build dan relevant tests dijalankan dengan executed counts, atau batas toolchain dijelaskan; git diff --check bersih.
- [ ] Developer menyelesaikan numbered manual verification; native/live item yang pending tetap tercatat pending.
- [ ] Tidak ada mutation config/data nyata oleh AI, transcript/secrets persistence, heavy main-actor work, atau dependency/backend/provider tambahan.
- [ ] Commit terpisah M2 hanya bila diminta pengguna, berbahasa Inggris dan Conventional Commits; contoh `fix(core): harden Codex session lifecycle`.

Handoff berisi perubahan source, automated results, host/version/config/trust matrix, sanitized fixture provenance, recovery instructions, dan manual results/limitations. Source-complete dengan live/manual pending belum berarti fase accepted. Setelah M2 diserahkan, berhenti dan tunggu instruksi sebelum M3.

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
