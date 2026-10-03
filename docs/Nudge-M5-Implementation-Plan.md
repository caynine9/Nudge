# Nudge — Implementation Plan M5: Permission Actions

Tanggal: **3 Oktober 2026**. Status terkini: **source M5 dan hermetic suite sudah diimplementasikan; 88 tests lulus; live acceptance Desktop/CLI dan verifikasi manual masih pending**. Rincian hasil ada di [Nudge-M5-Verification.md](Nudge-M5-Verification.md) dan status kontrak host di [Nudge-M5-Codex-Contract.md](Nudge-M5-Codex-Contract.md).

Baseline terbaru: **`d854a35` — hover langsung expanded, tanpa peek/pin**, diaudit pada bagian 15. Bagian 3 dan 14 adalah riwayat snapshot sebelumnya; aturan UI aktif di bagian 7 mengikuti baseline terbaru ini.

Sumber kebenaran: [project brief](Nudge-Project-Brief.md), bagian 6.7–6.10 dan milestone M5; [AGENTS.md](../AGENTS.md). Baca juga [M3 contract](Nudge-M3-Codex-Contract.md), [M3 verification](Nudge-M3-Verification.md), [M4 contract](Nudge-M4-Codex-Contract.md), dan [M4 verification](Nudge-M4-Verification.md).

Dokumen ini dibuat setelah audit dan plan, lalu implementasi M5 dilanjutkan atas instruksi eksplisit pengguna. M5 tetap optional; pekerjaan ini tidak memulai M6 dan tidak mengubah status acceptance fase sebelumnya. Bagian 14–15 menyimpan audit historis sebelum source M5; bagian 16 mencatat hasil implementasi terkini.

## 1. Aturan pengerjaan

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

## 2. Outcome dan batas M5

Workflow yang dituju: **Codex local meminta permission → Nudge menampilkan satu request yang identitas dan scope-nya jelas → pengguna memilih Allow Once atau Deny → helper mengembalikan tepat satu keputusan untuk invocation tersebut → lifecycle Codex merekonsiliasi attention**. Jika jalur keputusan tidak tersedia, expired, ambiguous, atau belum terverifikasi, pengguna melanjutkan melalui Codex.

Deliverable M5, setelah gate kontrak lulus:

- Allow Once/Deny untuk jenis permission dan host yang sudah dibuktikan mendukungnya.
- Response channel lokal dengan request identity, bounded queue, deadline, dan one-shot decision.
- Handoff ke native Codex saat pengguna memilih Open Codex atau tidak mengambil keputusan dalam window yang tersedia.
- Reconciliation terhadap native resolution, cancellation, turn change, disconnect, quit, dan sleep/wake.
- Opt-in Nudge yang default Off, installer reversible, hermetic tests, dan catatan kontrak/verification M5.

Tidak termasuk persistent allow, exec-policy amendments, bypass, automatic approval, programmatic question answering, remote/cloud requests, terminal routing, transcript recovery, app-server control plane, redesign notch, dependency baru, atau pekerjaan M6. `request_user_input` tetap memakai mirror + Answer in Codex.

## 3. Audit baseline yang harus dipertahankan

Audit dilakukan pada **HEAD `03d6d4e`**, setelah commit M4 `cc7c783`, attention `0df1254`, project grouping `2c79e28`, dan live usage `98d4e3e`. Repository sudah memiliki aplikasi dan empat target; keterangan tahap dokumentasi di bagian Status Repository AGENTS.md adalah snapshot lama, bukan kondisi aktual.

| Area | Kondisi aktual | Implikasi M5 |
|---|---|---|
| Project | `Nudge`, `NudgeBridge`, `NudgeCoreTests`, `NudgeIntegrationTests`; shared scheme Nudge; macOS 15+, Swift 6, accessory app | Pertahankan scaffold, target, signing, dan scheme; tidak membuat project baru |
| Event spine | Adapter → wire V3 → Unix socket → ordered ingress → monitor actor → reducer → AppState | Gunakan pipeline ini; jangan mengganti monitoring dengan permission channel |
| Bridge | Input bounded 1 MiB; total deadline 250 ms; exit success; non-Stop tanpa stdout | Belum bisa menerima keputusan dari UI; jalur biasa wajib tetap cepat |
| Socket | `/tmp/nudge-<uid>.sock`, owner `0600`, peer UID check, bounded frames; 16 koneksi; receive deadline 500 ms | Saat ini satu arah, lalu close; jangan menahan koneksi event untuk menunggu klik |
| Attention | `PendingInteraction`, queue per sesi sampai 16, resolved tombstones, matching progress, conservative ambiguity | Perlu identitas actionable terpisah dari ID mirror; pertahankan question queue dan focus policy |
| Permission identity | SHA-256 kind/session/turn/tool ID, fallback tool name; tool ID optional | Dua request sama-name dapat coalesce; hash ini bukan response token atau host request ID |
| Resolution | Domain punya `.interactionResolved`; raw hook wire tidak menyediakan event explicit resolution | Perlu ingress internal yang tervalidasi; jangan menghapus pending hanya karena tombol diklik |
| UI live | Permission hanya mirror + Open Codex Desktop; question preview bounded | Tambahkan tindakan secara lokal pada attention card; generic mirror tidak cukup untuk consent |
| UI demo | Allow once/Deny memanggil `resolvePreview`, dijaga `isDemoMode` | Pertahankan simulasi; jangan sambungkan tombol demo ke transport live |
| Navigation M4 | Navigator injectable, opt-in precise route default Off, activation fallback, deadline dan stale-context checks | Gunakan navigator yang sama; keputusan tidak tergantung deep link |
| Expanded UI | Project grouping, thread title fallback, scrolling; panel 160/170 pt di bawah camera band, ruang konten 122/132 pt setelah insets; viewport fix pada HEAD | Pertahankan layout, ukuran, scroll, dan pilihan sesi yang sudah ada |
| Optional metadata | `CodexThreadMetadataReader` membaca title dan usage secara bounded | Pertahankan fitur yang sudah ada; reader ini bukan approval connection |
| Installer | Tujuh event, `timeout: 1`; backup, lock, compare-and-replace, foreign preservation, malformed rejection, custom root | Ubah hanya owned PermissionRequest handler yang diperlukan |
| Evidence | M1–M4 live/manual acceptance masih pending pada dokumen handoff | Build/tests tidak menutup gate host; jangan menyatakan M5 ready hanya dari fixtures |

**Perubahan lokal yang sudah ada:** `Nudge.xcodeproj/project.pbxproj` menambahkan `B90000000000000000000001` (`CodexNavigatorTests.swift`) ke children group. File reference dan test source membership sudah tersedia. Pertahankan hunk ini; jangan reset/regenerate project atau memasukkannya ke commit M5 sebagai perubahan baru. SHA-256 saat audit: `e899365d9200b732cb7a944afd68fb8a850606d9465d726e0e2df11d7335ef24`.

**Perubahan lain yang terlihat pada pengecekan akhir sesi:** `Nudge/UI/NotchRootView.swift`, `DESIGN.md`, dan `.impeccable/surfaces/nudge-ui-notchrootview-swift.md` berubah di workspace selama audit. Diff tersebut dibaca dan dipertahankan: fixed content height setelah camera band/insets, clipping, peek spacing 6 pt, project/count/navigation header yang digabung, dan project-group top spacing 4/10 pt. Ini bukan perubahan yang dibuat sesi plan M5. Implementasi nanti harus mulai dari source terbaru, mempertahankan hunk-hunk ini dan memeriksa fit action rows di dalam content height tersebut. Jangan mengembalikan file ke snapshot HEAD atau menimpa dengan versi saat plan pertama dibaca. Hasil 73 tests berasal dari run audit; tidak dianggap bukti verifikasi edit paralel yang baru terlihat setelah run itu.

**Temuan installer dari source review:** branch `canonicalOwnedGroup` mempertahankan setiap group canonical tanpa memeriksa `foundCanonicalOwned`. Dua standalone canonical groups milik Nudge bisa tetap dua. Test existing menggandakan handler di mixed group, sehingga belum menguji kasus ini. M5 wajib menambah fixture dua canonical groups dan memperbaiki dedupe secara sempit di installer sebelum memasang response hook; duplicate decision handlers adalah risiko langsung fase ini.

Temuan lain yang menjadi gate: host origin tidak ada di wire V3; `integrationHost` adalah pilihan instalasi, bukan bukti host pengirim. Korelasi singleton tool pada reducer cukup untuk mirror konservatif, tetapi tidak boleh menjadi authority untuk mengirim allow/deny.

### Pemeriksaan yang benar-benar dijalankan

| Pemeriksaan | Hasil audit |
|---|---|
| `git status`, history, diff project, source/tests/contracts | Dibaca; source dan perubahan lokal dipertahankan |
| `xcodebuild -version` | Xcode 27.0, build 27A266a |
| `xcodebuild -list -project Nudge.xcodeproj` | Empat target dan scheme Nudge/NudgeBridge terdeteksi |
| `xcodebuild ... test` dengan DerivedData terisolasi | Berhasil; build app/helper/test targets dan **73 tests passed, 0 failed, 0 skipped** |
| Build warning | Dua warning copy signed helper: binary tidak di-strip; tidak ada test failure |
| `git diff --check` | Lulus pada baseline |
| Real permission, hooks/trust/config, physical notch | Tidak dijalankan/diubah; pending developer |

Perintah audit:

```bash
xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/nudge-m5-plan-audit-derived \
  -resultBundlePath /tmp/nudge-m5-plan-audit-tests.xcresult test
xcrun xcresulttool get test-results summary \
  --path /tmp/nudge-m5-plan-audit-tests.xcresult --format json
```

Log berada di `/tmp/nudge-m5-plan-audit-tests.log`; result bundle bersifat sementara. Standalone layout checks dan pemeriksaan visual/manual tidak dijalankan sebagai bagian audit ini. Hasil di atas memverifikasi baseline, bukan implementasi M5.

## 4. Kontrak resmi, versi, dan gate feasibility

Official OpenAI documentation ditinjau pada 3 Oktober 2026:

- `PermissionRequest` mengembalikan `hookSpecificOutput.hookEventName = "PermissionRequest"` dan `decision.behavior = "allow" | "deny"`; tanpa keputusan, native approval flow berlaku. Deny dari matching hook lain mengalahkan allow. `updatedInput`, `updatedPermissions`, dan `interrupt` tidak didukung di output ini. [Hooks — PermissionRequest](https://learn.chatgpt.com/docs/hooks#permissionrequest).
- Input PermissionRequest mendokumentasikan session/turn/tool name/input, tanpa request ID atau `tool_use_id` yang dijamin. Decision harus melalui hook sinkron; background hooks tidak bisa approve. Timeout handler memakai detik dan definition baru perlu trust review. [Official Hooks](https://learn.chatgpt.com/docs/hooks).
- App-server memiliki approval requests dan resolution notifications pada connection client-nya. Dokumentasi ini tidak membuktikan response connection ke existing Desktop/CLI threads melalui reader milik Nudge. [App Server — Approvals](https://learn.chatgpt.com/docs/app-server#approvals).

Ringkasan tersebut menetapkan bentuk protocol, **belum** membuktikan semantics Allow Once pada setiap jenis permission/versi. Tidak menggunakan `acceptForSession`, grants session/turn, atau perubahan policy sebagai pengganti one-shot approval.

Versi lokal dibaca tanpa menjalankan turn:

| Host/runtime candidate | Versi yang terdeteksi | Bukti yang belum ada |
|---|---|---|
| Desktop bundle `com.openai.codex`, di `/Applications/ChatGPT.app` | 26.930.31428, build 12913 | Permission hook dan response pada local new/resumed thread |
| CLI bundled pada Desktop tersebut | `codex-cli 0.160.0` | Bukti runtime ini benar-benar menjalankan hook Desktop yang diuji |
| CLI dari PATH `/Users/tantowi/.local/bin/codex` | `codex-cli 0.154.0` | Permission response, timeout, dan reconciliation CLI |

Nama/path bundle tidak boleh di-hard-code; navigator tetap resolve bundle ID. Effective config, trust, reload behavior, approval policy, dan runtime pemilik hook belum diverifikasi. Jangan menyamakan kedua CLI binaries atau menganggap keduanya mengikuti dokumentasi terbaru.

### Gate A — wajib sebelum live action implementation/enabling

Developer memverifikasi di sandbox; AI dapat menyiapkan fixture dan membaca sumber/schema resmi tanpa mengubah config nyata:

1. Desktop local new **dan** resumed threads, dimulai langsung dari app, menghasilkan PermissionRequest; CLI diuji terpisah. Catat versi/build, executable runtime, effective config/custom home, dan trust.
2. Output allow berlaku tepat pada request/scope yang ditampilkan; deny benar-benar menolak, bukan interpreted sebagai allow atau action baru. Mulai dari jenis shell permission yang terbukti one-shot; perlu bukti tambahan untuk file/network/MCP.
3. Buktikan hook ordering, duplicate handler behavior, cancellation, deny dari foreign hook, neutral/no-output, helper crash/timeout, dan kapan native prompt tersedia.
4. Buktikan identitas yang menghubungkan invocation aktif ke request yang ditampilkan. Jika host tidak punya request ID, connection + invocation nonce boleh menargetkan satu callback, tetapi **tidak** membuktikan bahwa callback lain duplicate request yang sama.
5. Buktikan external resolution dan sinyal valid untuk menginvalidasi response channel. Jika identity/liveness atau race dengan native resolution tidak bisa dijamin, request tetap mirror-only.
6. Verifikasi runtime provenance per invocation sejauh host mendukungnya. Pilihan host di menu/config, claimed host field, PID saja, dan adanya metadata title bukan bukti compatibility. Bila origin tidak bisa dibedakan, jangan aktifkan actions sampai seluruh runtime yang bisa memakai handler tersebut lolos kontrak; selain itu fallback native.

Hasil disimpan dalam `Nudge-M5-Codex-Contract.md` sebagai matrix **host/version/config/trust/type/new-resumed/output/scope/ordering/cancellation/fallback/result** dengan sanitized fixtures dan provenance. Unknown tidak dianggap pass. Jika salah satu host belum mendukung, catat partial/unsupported; jangan menyebut M5 kedua host selesai.

### Trade-off yang tidak boleh disembunyikan

Jalur hook sinkron menahan operasi dan dapat menunda native prompt sampai helper keluar. Mirror M3 yang sudah keluar dalam 250 ms tidak dapat diberi keputusan retroaktif. Menambah tombol tanpa helper yang masih hidup akan menghasilkan UI palsu.

Usulan batas awal untuk diuji pada Gate A: setup/handshake maksimum **250 ms**, response window maksimum **10 detik total sejak helper mulai**, outer timeout PermissionRequest **12 detik**. Ini batas rancangan, bukan angka compatibility yang sudah terbukti. Jika app tidak siap, feature Off, root/runtime unsupported, atau handshake gagal, helper tetap keluar dalam budget jalur biasa. Jangan memakai default timeout panjang.

Jika pengguna memilih Open Codex/Return to Codex saat channel hidup, lepaskan hook dengan **no decision terlebih dahulu**, lalu gunakan navigator M4 atau guidance CLI. Pending attention tetap ada sampai resolution/progress yang valid. Deadline tetap berjalan saat request antre atau focus berpindah; tidak di-reset ketika di-hover.

Developer harus menilai apakah delay pendek ini dapat diterima. Jika native prompt harus muncul bersamaan tanpa delay, kontrak hook ini belum cukup: hentikan jalur actions dan catat kebutuhan response transport resmi yang mendukung host tersebut. Jangan membuat app-server pengganti atau memperpanjang blocking untuk menyiasati gate.

## 5. Arsitektur perubahan yang additive

Bagian 5–8 mendefinisikan invariant dan intended architecture. Source saat ini adalah experimental slice M5; kontrak/runtime evidence, host ID guarantees, serta batas perilaku yang belum dibuktikan tetap dijelaskan di [Nudge-M5-Codex-Contract.md](Nudge-M5-Codex-Contract.md) dan [Nudge-M5-Verification.md](Nudge-M5-Verification.md). Jangan membaca requirement desain sebagai bukti bahwa seluruh jaminan host telah tercapai.

Pertahankan event wire V1/V2/V3 dan socket utama. Tambahkan **permission protocol V1 yang terpisah**, lewat candidate endpoint `/tmp/nudge-<uid>-p.sock`. Endpoint baru dipilih agar request yang menunggu klik tidak mengambil 16 slots atau menghambat ordered ingress event utama. Gunakan kembali low-level framing/socket helpers; codec baru tidak melonggarkan decoder V3 yang strict.

```text
Event biasa / permission mirror-only
  → NudgeBridge (250 ms) → existing event socket/wire V3
  → CodexEventIngress → CodexEventMonitor → SessionReducer → AppState

PermissionRequest dengan opt-in + kontrak terverifikasi
  → NudgeBridge, satu invocation + nonce acak
  → bounded PermissionSocketTransport / protocol V1
  → PermissionBroker actor, register + live channel
  → validated canonical event melalui existing ordered ingress
  → SessionReducer / AppState → existing live attention card

Klik Allow Once / Deny
  → captured request context → PermissionBroker (claim sekali)
  → connection yang sama → helper memvalidasi response
  → helper membentuk stdout resmi untuk invocation tersebut → Codex

Expired / unavailable / Open Codex / cancelled
  → revoke action channel → helper keluar tanpa decision
  → native Codex + reconciliation event yang terverifikasi
```

Tanggung jawab:

- **Bridge:** boundary raw input/output Codex; parsing bounded, nonce per invocation, output allow/deny hanya setelah response valid untuk channel tersebut. Raw tool input tidak diteruskan sebagai command yang dijalankan Nudge.
- **Permission protocol/transport:** strict field/version/type/size validation, peer/path checks, handshake, framed reply, EOF/disconnect, deadline dan cancellation; tidak menyimpan UI state.
- **PermissionBroker actor:** live channel registry, one-shot claim, deadline, ambiguity/overflow, delivery status dan invalidation; file/socket I/O di luar main actor. Transport handles dan tokens tidak menjadi bagian SwiftUI/Core.
- **Core:** metadata pending request, actionable availability, deterministic lifecycle/reconciliation. Core tetap tidak mengenal stdout Codex atau AppKit.
- **Ordered ingress/monitor:** jalur canonical internal untuk permission registration/status/resolution setelah validation; hook events dan response lifecycle tidak saling mendahului secara tidak terkontrol.
- **AppState/UI:** tampilkan state, capture session/turn/request generation saat klik, invoke service, buang hasil stale. AppKit tetap mengatur activation/keyboard sesuai panel saat ini.

Tidak perlu response abstraction generik multi-provider. Buat boundary injectable pada transport/clock untuk failure tests yang nyata.

## 6. Identity, queue, dan reconciliation

1. Pisahkan **mirror interaction ID** existing dari **invocation/action ID**. Gunakan random nonce per helper invocation, scope session + turn + optional authoritative host/tool ID + broker generation + live connection. PID/start time hanya metadata pendukung, bukan request identity.
2. Same connection/frame retry dengan nonce yang sama idempotent. Nonce reuse pada connection lain atau context berbeda ditolak. Jangan cache/replay allow untuk duplicate hooks atau invocation baru.
3. Bila dua invocation punya authoritative host request ID yang sama, dedupe sesuai kontrak yang dibuktikan. Tanpa ID itu, overlapping requests dengan mirror identity sama dianggap ambiguous: disable actions dan return native, bukan menyalurkan satu allow ke semua callbacks. Repeated request setelah keputusan sebelumnya wajib meminta klik baru.
4. Untuk request actionable yang diterima broker, gunakan invocation identity pada canonical pending state. Jangan sekaligus mengirim mirror PermissionRequest V3 yang sama sehingga muncul dua cards. Jika handshake ditolak sebelum register, jalur V3 menjadi fallback; jika register sudah diterima, broker mengubah availability pada pending yang sama saat handoff/expiry.
5. Pertahankan limit 16 pending interactions per sesi. Usulan response channels aktif maksimum 8 global, dengan FIFO per sesi dan absolute deadline per invocation. Overflow mengembalikan callback baru ke native dan memberi bounded attention indicator; tidak menghasilkan permission decision atau phantom request.
6. State channel: `available → submitting → submitted`, atau `returnedToCodex / expired / unavailable / cancelled`. `submitted` berarti response terkirim/ditulis, **bukan** host telah menerapkan keputusan. Setelah EOF tanpa receipt, hasil unknown; jangan auto-retry allow. Jika register sudah dikirim tetapi acknowledgment hilang, tutup neutral dan invalidasi registrasi melalui EOF/deadline; jangan mengirim fallback mirror kedua yang membuat dua cards. Fallback V3 dipakai ketika belum ada registration yang mungkin diterima; ketidakpastian delivery dicatat sebagai best-effort monitoring.
7. Klik ganda diklaim sekali; action response hanya mengandung enum allow-once/deny/return-to-Codex. Late callback, expired token, beda turn, resolved tombstone, unknown ID, generation lama, atau channel yang sudah ditutup tidak bisa menulis decision.
8. Revoke availability terlebih dahulu pada verified external resolution, terminal lifecycle, turn replacement, sleep, quit, helper disconnect, opt-out, atau config/runtime compatibility berubah. Sleep/wake tidak membuka kembali decision channel lama atau mengulang klik. Gunakan clock deadline yang memperhitungkan waktu sleep; uptime yang berhenti saat sleep tidak boleh memperpanjang kesempatan mengirim reply lama ketika wake.
9. Expiry channel **tidak** menghapus permission dari session. Pending berpindah mirror-only sampai matching progress/lifecycle yang valid; Open Codex bukan resolution. Deny tidak dipresentasikan sebagai successful completion.
10. Reuse `.interactionResolved` hanya jika bukti scope request tepat tersedia. Matching tool heuristic M3 tidak boleh dipakai untuk mengizinkan action. Sinyal yang tidak bisa dipetakan mempertahankan pending secara konservatif dan mengarahkan ke Codex.

Cancellation dan click harus diproses oleh satu broker, dengan revalidation sebelum menulis response. Ini memberi ordering lokal, bukan atomicity global terhadap host; Gate A harus membuktikan bahwa host tidak menerapkan reply usang. Jika host tidak menyediakan guarantees yang diperlukan, batasi jalur tersebut menjadi mirror-only.

## 7. UI dan privacy

Gunakan `liveAttention` yang ada. Tampilkan Allow Once/Deny hanya ketika request permission memiliki channel aktif, kontrak didukung, identity unambiguous, dan konteks operasi cukup jelas untuk consent. Tool name/project label saja tidak cukup untuk approve; jika scope tidak dapat ditampilkan aman, tetap Open Codex.

Tambahkan descriptor terstruktur yang di-whitelist dan bounded untuk **jenis operasi yang diverifikasi**, dengan konteks minimal dan redaction sebelum IPC. Jangan menampilkan command/diff sintetis dari demo sebagai detail live. Bila redaction/truncation menyembunyikan informasi yang memengaruhi keputusan, jangan tampilkan Allow Once. Raw payload, full command/output, prompt, question options, transcript, paths dan secrets tidak dipersist/log. Preview sensitif yang dibutuhkan hanya boleh ditambah dengan scope/aksi eksplisit yang sesuai privacy brief.

Saat submitting, disable kedua tombol untuk request tersebut dan beri feedback singkat. Setelah submitted, gunakan copy yang tidak mengklaim host success; setelah expired/delegated, arahkan ke Codex. Open Codex tetap tersedia untuk recovery; untuk CLI, berikan guidance kembali ke terminal tanpa mengklaim routing terminal.

Pertahankan Nudgie, single attention pulse, Reduce Motion, satu focused context ketika collapsed, grouped sessions, usage, navigation preference, dan expanded cap **160/170 pt di bawah camera band**. Hover langsung membuka expanded setelah **100 ms**; cursor keluar menutupnya setelah **320 ms**. Tidak ada peek atau persistent pin. Gunakan model terbaru `isExpanded`, timer `.hover`, serta input `.expand`/`.toggleExpanded`; jangan mengembalikan API/state lama. Pending attention tetap menjadi card sampai resolution valid; menutup daftar sesi mengembalikan attention card dan tidak menjawab request.

Angka 160/170 pt bukan tinggi viewport daftar: setelah top/bottom insets 16/22 pt, ruang konten expanded adalah **122/132 pt**, lalu header/usage mengurangi ruang scroll yang tersisa. Untuk attention permission, budget konten normal adalah **186 pt** (224 − 38); question **154 pt** (192 − 38). M5 harus menjaga descriptor, action rows, error dan recovery tetap terlihat dalam budget ini. Jangan memperbesar island untuk seluruh queue. Demo tetap memiliki guard dan label simulasi. Jangan memindahkan `resolvePreview` ke live path atau memakai global hotkey yang bisa menyetujui request lain; keyboard/VoiceOver harus terikat pada card dan konteks aktif. Lifetime response channel tidak boleh bergantung pada hover/collapse daftar; revocation tetap mengikuti aturan broker di bagian 6.

## 8. Compatibility, installer, backup, dan recovery

**Default:** mode permission actions Off. Mode mirror memakai tujuh handler yang ada, timeout 1 detik dan bridge budget 250 ms. Opt-in hanya boleh mengubah owned PermissionRequest handler setelah Gate A; proposed command menambahkan flag exact `--permission-actions` dan timeout 12 detik. Enam handler lainnya tetap seperti baseline.

Installer perlu mengenali **dua exact owned command forms**: legacy mirror dan mode action baru, bukan sekadar basename/prefix bebas. Normalize duplicate canonical/mixed owned entries menjadi satu expected handler; preserve foreign handler, matcher, metadata dan unknown custom command. Perubahan helper path tidak otomatis mengklaim ownership handler lama yang belum bisa dibuktikan.

Upgrade/opt-out/uninstall tetap memakai lock, parse-before-write, backup bytes original, owner/file-type checks, compare-and-replace, atomic write dan skip write jika unchanged. Malformed/duplicate-key JSON tetap byte-for-byte. Backup failure berarti batal mutation. Jangan mengubah `config.toml`, approval policy, trust records, atau rule files. Effective root untuk Desktop/CLI/custom home diverifikasi; root bersama tidak boleh menerima dua mode handler yang conflicting.

Definition yang berubah perlu review/trust ulang; UI tidak boleh mengklaim trust otomatis. Opt-in global pada Nudge tidak otomatis membuktikan capability setiap host/root. Jika tidak bisa memisahkan runtime unsupported pada shared root, gunakan mirror untuk root tersebut sampai seluruh runtime terverifikasi.

| Pair / failure | Perilaku yang diwajibkan |
|---|---|
| App baru + helper lama | Existing V1–V3 monitoring/mirror; tidak ada tindakan |
| Helper baru + app lama/off | Response endpoint/handshake unavailable; neutral exit cepat, best-effort V3 mirror |
| Protocol/version mismatch | Reject sebelum state mutation; tidak mengirim decision |
| Helper lama + action-mode config | Harus terbukti neutral dalam timeout; jika tidak, rollback config ke mirror bersama helper |
| App/helper crash atau hung app | EOF atau absolute helper deadline; kembali native tanpa allow |
| User opt-out | Revoke live channels, refresh hanya owned PermissionRequest handler ke mirror; no replay |
| Uninstall | Revoke channels; hapus hanya exact owned forms; foreign config/backup dipertahankan |

Backup config untuk rollback diperiksa terhadap perubahan foreign sejak backup dibuat; jangan restore whole file otomatis di atas perubahan pengguna. Recovery normal adalah installer merge ke mirror mode. File/backup pengguna tidak dihapus oleh automated tests.

Response socket juga `0600`, owner current user, peer UID validation, bounded codec, safe stale cleanup berdasarkan type/owner/inode. Token hanya di memory dan tidak ditulis ke logs/preferences. UID check dan nonce tidak memberi isolasi dari seluruh proses jahat yang sudah berjalan sebagai user yang sama; jangan menyatakan keamanan melampaui boundary lokal tersebut.

## 9. File yang disentuh

**Implementasi aktual M5:**

| File / kelompok | Perubahan terbatas |
|---|---|
| `NudgeBridge/main.swift`, `BridgeProcessor.swift`, `CodexHookAdapter.swift` | Action mode opt-in, bounded response wait, official output, invocation UUID, dan sanitized permission mirror |
| `Nudge/IPC/PermissionWire.swift` **baru**, `PermissionSocketTransport.swift` **baru** | Protocol V1 strict dan response socket terpisah dari event socket V1–V3 |
| `Nudge/Services/PermissionBroker.swift` **baru** | Actor one-shot claim, queue per sesi, deadline, context guard, lifecycle cancellation/reconciliation |
| `Nudge/Services/CodexEventIngress.swift`, `Nudge/App/NudgeAppDelegate.swift` | Broker lifecycle preprocessor, listener setup, sleep/quit cancellation dan context/status wiring |
| `Nudge/App/AppState.swift` | Preference default Off, status/request map, context validation, navigation handoff dan installer wiring |
| `Nudge/UI/NotchRootView.swift`, `Nudge/UI/PlaygroundMenuView.swift` | Action/recovery feedback dalam attention card dan opt-in pada menu existing; demo actions tetap terpisah |
| `Nudge/Integration/Codex/Hooks/CodexHookInstaller.swift` | Exact legacy/action ownership, PermissionRequest timeout selektif, canonical-owned duplicate dedupe |
| `NudgeIntegrationTests/PermissionActionTests.swift` **baru** | Codec, redaction, broker one-shot/queue/expiry/context/reconcile dan official output |
| `NudgeIntegrationTests/BridgeFailureTests.swift`, `HookInstallerTests.swift` | Hermetic helper subprocess dan migration/dedupe installer fixtures |
| `Nudge.xcodeproj/project.pbxproj` | Target/file membership M5. Hunk existing pengguna untuk group `CodexNavigatorTests.swift` tetap dipertahankan |
| `docs/Nudge-M5-Codex-Contract.md`, `docs/Nudge-M5-Verification.md` **baru** | Batas dokumentasi resmi, host gate, hasil suite dan langkah manual |

Tidak mengubah reducer domain/presentation, `CodexNavigator.swift`, `CodexThreadMetadataReader.swift`, grouping, mascot, geometry atau aset. Hover langsung expanded, timer 100/320 ms, clipping/insets, scroll cap, focus/navigation behavior, dan M1–M4 session semantics tetap pada implementation yang sudah established; attention UI hanya menambah status/action row bounded. Automated regression suite lulus, sementara native layout/runtime tetap perlu diperiksa developer.

## 10. Urutan implementasi dalam satu fase M5

1. **Freeze baseline.** Catat git status/diff dan checksum perubahan lokal, jalankan baseline suite; jangan reset/stash destructive atau regenerate scaffold.
2. **Gate A dan contract record.** Bentuk output resmi dan limitation identitas ditinjau dan dicatat. Runtime sandbox evidence kedua host belum tersedia; karena itu code tetap experimental/Off default, dan runtime acceptance/ship gate masih terbuka di contract record.
3. **Protocol dan broker hermetic.** Bangun strict response codec, channel registry, nonce/generation, exactly-once claim, bounded queue, neutral fallback dan cancellation dengan fake clocks/transport.
4. **Bridge dan installer.** Tambahkan response path opt-in, output encoder finite, stdout purity, selective handler migration dan narrow duplicate-group fix. Automated testing hanya temporary config/socket.
5. **Canonical lifecycle.** Integrasikan registration/status/resolution ke ordered ingress dan reducer; action expiry tidak meng-expire pending attention; pertahankan M1–M4 invariants.
6. **UI existing.** Wire tindakan pada live permission yang eligible, context guard dan feedback; keep demo isolated, fallback navigator M4 dan seluruh viewport work.
7. **Regression, handoff dan commit.** Jalankan relevant suite/build/diff; isi verification, serahkan numbered manual steps, dan commit hanya perubahan M5 bila diminta dengan Conventional Commits Inggris, misalnya `feat(permission): add one-shot Codex permission actions`. Jangan lanjut M6.

Langkah-langkah ini merekam urutan dalam satu fase M5. Implementasi source dilanjutkan atas instruksi eksplisit pengguna, dengan host runtime gate tetap pending. Ketiadaan bukti host bukan alasan mengganti scope menjadi CLI-only atau demo buttons-only.

## 11. Meaningful automated tests

Daftar berikut adalah target coverage dalam plan. Cakupan yang benar-benar sudah dijalankan dan batas test yang tersisa tercatat di [Nudge-M5-Verification.md](Nudge-M5-Verification.md); jangan menyamakan target yang belum ditulis dengan test yang telah lulus.

- **Protocol:** unknown/duplicate fields, invalid enum/version, missing scope, mismatch nonce/generation, wrong peer, oversized/truncated frame, EOF dan deadline. Rejected frames tidak membuat phantom session/request.
- **One-shot/race:** double click, allow-versus-deny race, cancellation sebelum reply, context/turn change, opt-out, late receipt dan helper restart; paling banyak satu output decision per invocation, tidak pernah ada automatic retry/replay allow.
- **Queue/identity:** same nonce retry, nonce pada connection berbeda, authoritative-ID dedupe, no-ID same-name ambiguity, sequential same-name requests wajib consent baru, per-session ordering dan overflow dengan native fallback.
- **Process boundary:** jalankan helper sungguhan terhadap fake response server; assert stdout tepat official allow/deny ketika diotorisasi test response. Unavailable/hung/crashed/malformed/expired paths exit neutral bounded; non-permission hooks tetap 250 ms. Secret sentinel tidak masuk wire/stdout/log.
- **Ordering/reconciliation:** register diterima hanya sekali; no double mirror card; submitted bukan host success; neutral handoff/expiry mempertahankan pending; matching progress/resolution clears only its request; unrelated tools tidak membersihkan ambiguous attention; denial/interruption bukan completion.
- **Failure isolation:** penuhi permission queue lalu kirim tool/completion pada event socket; event flow tetap responsif. Sleep/quit menghentikan channels tanpa replay; shutdown tidak menunggu human deadline lewat `flushEvents`.
- **Installer:** duplicate canonical groups, mixed groups, old/new mode dedupe, reinstall no-write, mirror→action→mirror/uninstall, malformed unchanged, backup/atomic conflict, custom/shared roots, foreign deny preserved dan old-helper recovery.
- **Regression:** seluruh **77 baseline cases pada `d854a35`** tetap lolos, termasuk empat tests hover-expanded baru; navigation targeting/fallback, pending context, project grouping, ordinary wire V1–V3 dan completion dedupe tetap. Tambahkan coverage untuk attention datang setelah pointer exit serta sleep/wake attention list pada bagian 15.

Gunakan socket/path sementara dengan random names dan defaults store terisolasi; fake native host untuk automated tests. Test interaksi Codex nyata dan visual panel menjadi tanggung jawab developer. Build-for-testing bukan test execution. Tambahkan target membership tests; existing standalone visual checks tidak otomatis tercakup dalam XCTest.

## 12. Verifikasi manual oleh developer

Semua langkah berikut **pending**. Gunakan sandbox project dan config recoverable; instalasi/perubahan config nyata serta real decisions hanya oleh developer atau setelah instruksi eksplisit yang mengizinkannya.

1. Catat macOS, Desktop version/build/bundle/runtime, CLI version/path, effective config/custom home, approval policy, trust/reload, permission types dan M1–M4 acceptance yang masih pending.
2. Dalam Desktop local **new** thread yang dimulai langsung di app, trigger harmless permission dengan kontrak one-shot terverifikasi. Cocokkan session/turn/request dan operasi yang ditampilkan; pilih Allow Once dan buktikan hanya scope itu diterapkan. Ulangi pada **resumed** thread tanpa terminal launch atau Nudge app-server.
3. Uji Deny di Desktop sandbox. Buktikan operasi ditolak, card tidak menyatakan success, dan lifecycle/attention dapat melanjutkan sesuai hasil host. Ulangi Allow Once/Deny pada CLI secara terpisah.
4. Biarkan response window habis lalu jawab di native host. Konfirmasi native prompt tersedia setelah neutral handoff, actionable buttons mati, pending tidak hilang karena waktu saja, dan matching progress membersihkan card. Catat actual maximum delay.
5. Pilih Open Codex ketika channel aktif. Konfirmasi hook dilepas tanpa keputusan terlebih dahulu, navigator M4 masih berfungsi, dan pending tetap sampai native resolution. Untuk CLI, kembali ke terminal; Desktop activation tidak boleh diklaim sebagai keputusan/routing CLI.
6. Uji external resolution/cancel, turn interruption dan turn baru; klik card lama, callback lambat, dan klik ganda. Tidak ada response salah request, duplicate output atau auto-retry.
7. Trigger duplicate dan overlapping same-name requests di sandbox. Buktikan safe queue/ambiguity fallback; satu klik tidak menyetujui invocation lain dan request berikutnya membutuhkan klik baru. Uji foreign deny hook tanpa mengubah foreign policy.
8. Tutup/crash Nudge sebelum request dan ketika channel pending; uji helper unavailable serta app hung. Codex kembali native dalam budget tanpa allow. Reopen tidak menghidupkan kembali keputusan lama.
9. Sleep/wake saat pending/submitting, pindah sesi/window/Space dan demo mode. Channel lama invalid; event monitoring, attention, completion single-play dan navigation tetap benar.
10. Pada config sementara, uji upgrade, opt-in/out, re-trust, duplicate canonical groups, custom/shared root, malformed JSON, foreign hooks, rollback dan uninstall. Config yang tidak berubah tidak ditulis ulang; backups/foreign data tetap.
11. Uji physical notch dan fallback, hover langsung expanded 100 ms/leave 320 ms tanpa pin, expanded 160/170 pt + scroll, project grouping/title/usage, keyboard/VoiceOver, Reduce Motion serta long/redacted descriptor. Generic/unsafe context tidak menawarkan Allow Once; demo tidak mengirim permission. Uji attention datang setelah pointer exit lalu resolved di luar panel, serta sleep/wake ketika attention list terbuka; panel tidak boleh tertinggal expanded tanpa pointer/timer, dan pending card tidak dianggap resolved oleh collapse.
12. Periksa bounded diagnostics/privacy dan idle CPU saat feature Off/on tanpa request. Catat hasil sebagai **host/version/scenario/identity/scope/output/latency/native fallback/resolution/result**; jangan memasukkan command/prompt/secrets penuh ke fixture atau logs.

## 13. Checklist akhir M5

- [ ] Gate A lulus dengan evidence Desktop new/resumed dan CLI yang dicatat terpisah; unsupported types/hosts ditandai jelas.
- [ ] Allow Once/Deny benar-benar diterapkan sesuai scope/contract; tidak ada persistent grants/bypass atau question answering.
- [ ] Offline/crash/hung/timeout/overflow kembali native bounded, tanpa silent allow.
- [ ] Exactly-once per invocation, duplicate/ambiguity safe, external resolution dan stale context teruji.
- [ ] Ordinary event spine, questions, navigation, project grouping, usage dan viewport existing tetap berfungsi.
- [ ] Installer preserving/idempotent; malformed untouched; backup/recovery/opt-out/uninstall teruji pada temporary roots.
- [ ] Privacy defaults tetap; socket owner/peer/schema checks; heavy I/O di luar main actor.
- [ ] Build dan relevant tests benar-benar dijalankan; result dan limitation tercatat di verification M5.
- [ ] Developer menjalankan numbered manual verification; pending tetap ditulis pending.
- [ ] Hunk pengguna di project dipertahankan; commit M5 terpisah bila diminta; M6 tidak dimulai.

**Kriteria selesai:** workflow permission nyata berhasil pada host/type yang kontraknya terbukti, dengan offline behavior, queue dan external resolution yang aman. Source implementation + synthetic tests tanpa host evidence hanya berstatus implemented/pending acceptance; M5 optional tidak menghambat handoff MVP mirror + jump atau M6 yang diminta secara terpisah.

## 14. Audit ulang working tree sebelum implementasi M5

Tanggal: **3 Oktober 2026**, setelah pengguna meminta pengecekan ulang atas perubahan codebase. Audit ini membaca source/diff dan menjalankan automated checks; tidak mengimplementasikan M5 atau memperbaiki source.

### Git status dan scope perubahan

HEAD tetap **`03d6d4e`**; tidak ada commit baru atau staged changes. Empat tracked files modified dan satu file untracked ditemukan. Daftar file sama dengan pengecekan akhir sesi pembuatan plan. Namun saat audit ulang berlangsung, tiga file UI/design berubah lagi: penghapusan global active-session count dan computed property-nya. Perubahan ini dibaca dan dipertahankan, bukan dikembalikan ke snapshot audit awal. Checksum project tetap sama.

| Status | File | Perubahan terhadap HEAD / keputusan audit |
|---|---|---|
| Modified | `Nudge/UI/NotchRootView.swift` | Fixed content height + clipping, peek stack 6 pt, header project/navigation gabungan, single focused row, group spacing 4/10 pt; latest diff menghapus global active-session count dari shared live-monitor header dan menghapus `activeSessionsLabel`. Pertahankan seluruh perubahan ini saat M5 |
| Modified | `DESIGN.md` | Mencatat aturan layout/insets/peek dan count dihilangkan pada peek; source menghilangkan global header count juga pada expanded. Perbedaan cakupan wording ini dicatat, dokumen milik pekerjaan lain dipertahankan |
| Modified | `.impeccable/surfaces/nudge-ui-notchrootview-swift.md` | Tambahan PEEK FIT terbaru menyebut peek tanpa global active-session count; dipertahankan |
| Modified | `Nudge.xcodeproj/project.pbxproj` | Menambahkan existing navigator test file ke group; bukan perubahan build membership atau dependency. Checksum tetap sama dengan audit pertama |
| Untracked | `docs/Nudge-M5-Implementation-Plan.md` | Dokumen plan sesi ini, diperbarui dengan hasil audit ulang; belum di-commit |

Diff tracked terbaru: **4 files, 26 insertions, 20 deletions**. Bridge, event wire V3, hook installer, session reducer, navigator dan metadata reader tidak berubah terhadap baseline audit sebelumnya. Tidak ada source baru untuk permission actions. Global visual session count hilang dari shared live monitor, tetapi accessible scroll label dan conditional per-project counts tetap tersedia; data sesi/focus/queue tidak dihapus.

### Pemeriksaan source dan static UI

- **Accessibility:** labels/hints attention, session list dan recovery tetap tersedia; Reduce Motion dan guard demo/live dipertahankan. Keyboard/focus/VoiceOver nyata tetap pending developer.
- **Performance:** diff hanya composition/layout; tidak menambah IPC, file operations, polling atau animation loop. CPU/frame-rate belum diprofilkan.
- **Appearance:** opaque black, native typography, palette dan original mascot tidak diubah. Source sejalan dengan tambahan design records.
- **Native behavior:** camera band dan NSPanel/windowing tidak berubah. Render hanya memeriksa endpoint statis; physical notch, focus, Spaces dan motion bukan hasil audit otomatis ini.
- **Adaptivity/layout:** batas tinggi baru berlaku juga pada attention, sehingga fit action/recovery harus diperiksa. Render statis pada notch/fallback yang diperiksa menunjukkan primary CTA, retry action dan guidance CLI tetap terlihat pada fixture question dua baris + navigation failure dan permission + failure. Peek working/title/tool juga tetap terlihat dengan title truncation yang diharapkan. Ini bukan jaminan untuk seluruh payload atau geometri layar.

Tidak ada regresi baru yang terbukti pada scope diff dan fixtures yang diperiksa. Temuan dedupe installer pada bagian 3 tetap berlaku dan belum diperbaiki; gate response channel/identity/host evidence M5 juga tetap berlaku. Skor UI runtime tidak diberikan dari source/render; audit memakai kontrak native macOS repository, bukan preset iOS/Android/web dari tooling.

### Verifikasi audit ulang

| Check | Hasil |
|---|---|
| Debug build melalui `xcodebuild test` pada snapshot awal audit ulang | Lulus |
| XCTest suite snapshot awal | **73 passed, 0 failed, 0 skipped** |
| Existing `NudgeCoreTests/NotchLayoutChecks.swift`, compiled/run Swift 6 | Lulus: full-canvas shell containment pada notch/fallback dan multi-session fixtures |
| Temporary static render harness | 12 endpoint renders dibuat; enam peek/attention recovery renders inspeksi visual. Semua memakai synthetic metadata, injected fake navigator, isolated defaults dan Reduce Motion; tidak meluncurkan Codex atau memutus permission nyata |
| `git diff --check` | Lulus |
| Tracked-file fingerprints selama audit | Mendeteksi edit UI/design tambahan; project tetap sama, seluruh external edits dipertahankan |
| Live Desktop/CLI, mouse/keyboard/VoiceOver, physical panel, performance | Pending developer; tidak disimpulkan dari build/render |

Perintah test ulang menggunakan DerivedData yang sama, result baru `/tmp/nudge-m5-reaudit-tests.xcresult`, dan log `/tmp/nudge-m5-reaudit-tests.log`. Harness/binary/render sementara berada di `/tmp/nudge-m5-reaudit-render`; source repository tidak dimodifikasi untuk checks tersebut. Existing layout check memeriksa opaque bounds, bukan keterjangkauan kontrol; karena itu render attention/recovery juga diperiksa terpisah. Test run dan static renders pertama memakai snapshot sebelum penghapusan global count yang muncul di tengah audit. Hasil tersebut tidak diklaim sebagai verifikasi snapshot paling akhir; confirmation build/tests setelah perubahan tambahan dicatat terpisah di bawah.

**Confirmation setelah edit tambahan:** Debug build melalui `xcodebuild test` kembali lulus, **73 passed, 0 failed, 0 skipped**. Result `/tmp/nudge-m5-reaudit-latest-tests.xcresult`, log `/tmp/nudge-m5-reaudit-latest-tests.log`. Fingerprints keempat tracked files tetap sama sepanjang confirmation run sampai pengecekan akhir. Snapshot source terbaru yang diuji: `NotchRootView.swift` SHA-256 `f403caff433d778fcd1720f3422816eafbfa8405025a3ee3040703ef4defc52c`; project checksum tetap seperti bagian 3. Static renders tidak diulang setelah penghapusan count; perubahan ini dibaca dari diff, bukan diklaim mendapat inspeksi visual runtime baru.

**Dampak terhadap plan:** arsitektur M5 tetap additive. Bagian 7 diperjelas agar 160/170 pt tidak dianggap sebagai tinggi konten/scroll viewport: preserve insets/clipping yang baru, gunakan budget konten aktual, dan periksa fit descriptor/action/error/recovery saat implementasi nanti. Sesi audit ulang hanya memperbarui dokumen ini. Tidak ada commit, config/trust mutation, source fix atau pekerjaan M6.

## 15. Audit perubahan hover langsung expanded

Tanggal: **3 Oktober 2026**. Baseline **`d854a35` (`feat(ui): expand session list directly on hover`)**, dibanding `03d6d4e`. Commit mencakup **14 files, 150 insertions, 98 deletions**, termasuk source, tests, AGENTS.md dan project brief. Working tree sekarang hanya `project.pbxproj` modified (hunk group navigator test yang sama) dan dokumen plan ini untracked; perubahan UI/design audit sebelumnya sudah masuk commit baru.

### Kontrak terbaru yang dipertahankan

- Presentation sekarang `collapsed`, `expanded`, `attention`, `confirmation`; `.peek` dihapus. `peekVisible`/`pinnedOpen` menjadi `isExpanded`; timer `.peek` menjadi `.hover`.
- Hover 100 ms membuka expanded berisi grouped session list pada lebar 480 pt; leave 320 ms menutup. Klik compact membuka surface yang sama tanpa pin permanen; Escape memakai collapse.
- Generation guards menolak hover/close timer lama saat pointer cepat keluar/masuk; empat tests baru menguji hover, rapid reentry, click tanpa pin dan leave attention list tanpa menghapus request.
- Attention tetap prioritas; tombol list membuka seluruh sesi dan collapse kembali ke card pending. Completion/failure transients serta sleep timer invalidation tetap terpisah dari session state.
- Geometry tetap 160/170 pt di bawah camera band; clipping/insets, scroll, usage, title/grouping dan navigation existing dipertahankan. Tidak ada perubahan bridge, hook/wire protocol atau permission decisions pada commit ini.

Source/tests produksi tidak lagi memakai `.peek`, `peekVisible`, `pinnedOpen`, `togglePinned` atau `peekGeneration`. Referensi peek dalam bagian audit historis dokumen ini tetap sebagai riwayat, bukan instruksi implementasi aktif.

### Temuan yang berhasil direproduksi

**[P2] Expansion bisa tertinggal setelah attention resolved di luar panel.** Lokasi: `Nudge/Core/PresentationReducer.swift:68–73`. Urutan reducer: thinking → pointer masuk → hover timer membuka expanded → pointer keluar menjadwalkan collapse → PermissionRequest datang sebelum timer close → attention menginvalidasi/cancel collapse, tetapi `isExpanded` tetap true → progress mengubah phase ke thinking saat `pointerInside == false`. Hasil aktual adalah `.expanded` tanpa replacement collapse effect. Outside pointer update berikutnya juga tidak menghasilkan effect karena pointer sudah false. Dampak: monitor tetap terbuka sampai pengguna masuk/keluar lagi atau Escape, bertentangan dengan kontrak tanpa persistent pin. Rekomendasi: ketika attention berakhir, rekonsiliasi expansion terhadap pointer/current presentation dan jadwalkan close atau collapse jika di luar; pertahankan completion/failure transients yang sah. Tambahkan test exact ordering di atas. Ini celah state yang masih ada pada baseline, bukan klaim bahwa commit baru memperkenalkan seluruh akar masalahnya.

**[P2] Attention session list tetap expanded setelah sleep/wake.** Lokasi: `Nudge/Core/PresentationReducer.swift:168–189`, dengan prioritas mode di `Nudge/Core/NudgeModels.swift:236`. Urutan: pending permission → toggle list ketika pointer inside → sleep → wake dengan cursor tetap di luar panel. Sleep menghapus `isExpanded` dan pointer serta timers, tetapi mempertahankan `showsSessionList == true`. Wake menghasilkan `.expanded` tanpa hover/close timer. Dampak: daftar sesi menutup card request yang belum dijawab dan tetap terbuka di luar kontrak hover. Rekomendasi: reset list presentation pada sleep/wake atau rekonsiliasi ke attention card saat pointer di luar; snapshot/pending permission tetap utuh. Tambahkan test sleep/wake dengan list pending, bukan hanya completion/no-replay. Temuan ini juga tidak membuktikan host/runtime behavior baru; yang terbukti adalah reducer sequence.

Kedua skenario dijalankan melalui harness reducer sementara `/tmp/nudge-hover-state-audit.swift` dan binary `/tmp/nudge-hover-state-audit`, compiled Swift 6 dengan production models/events/reducer. Harness tidak mengubah source, mengirim hook, membuka Codex atau melakukan permission decision nyata. Output menunjukkan `isExpanded true / pointerInside false / replacement close timer false` pada skenario pertama, serta `showsSessionList true / pointerInside false / mode expanded` setelah wake pada skenario kedua.

### Verifikasi dan batas audit

| Check | Hasil |
|---|---|
| Debug app/helper/test build melalui `xcodebuild test` | Lulus |
| XCTest suite | **77 passed, 0 failed, 0 skipped** |
| Additional reducer probes di luar existing suite | Mereproduksi dua temuan P2 di atas; existing suite belum menutup skenario itu |
| Existing standalone PresentationChecks, NotchGeometryChecks dan NotchLayoutChecks (Swift 6) | Semua lulus; geometry/layout checks memeriksa endpoint/canvas, bukan state race atau interaksi fisik |
| Scan obsolete state symbols pada source/tests | Tidak ditemukan |
| `git diff --check` | Lulus |
| Fingerprints seluruh tracked files selama audit | Tidak berubah; source dan hunk project pengguna dipertahankan |
| Native hover/focus/Spaces/scroll/motion, sleep/wake nyata dan host integration | Pending developer |

Result bundle `/tmp/nudge-m5-hover-audit-tests.xcresult`, log `/tmp/nudge-m5-hover-audit-tests.log`. Tests yang lulus tidak membatalkan reproduksi tambahan; keduanya menguji urutan yang belum tercakup.

**Dampak terhadap M5:** bagian UI, file scope, regression tests dan manual verification di plan ini diperbarui agar mengikuti hover-expanded baru. Tidak mengembalikan peek/pin, tidak mengubah session/permission semantics ketika list collapse, dan tidak memperbaiki source selama audit. Prioritaskan dua temuan presentation sebelum menilai polish M5; perbaikan sempit dan tests dapat dikerjakan dalam scope yang diminta berikutnya. Gate kontrak permission Desktop/CLI dan response identity tetap berlaku.

## 16. Hasil implementasi M5

Source implementation dikerjakan setelah pengguna secara eksplisit meminta M5 dilanjutkan. Response path baru terpisah dari event socket, feature default Off, dan installer hanya mengubah handler exact milik Nudge saat mode dipilih. Existing hook/config nyata tidak dipasang atau diubah selama sesi. Tidak ada commit.

Scope actual mengikuti file list bagian 9. Tidak ada perubahan pada `SessionReducer`, `PresentationReducer`, navigator, metadata reader, geometry, mascot, project grouping, atau established hover behavior. Hunk existing pengguna di `Nudge.xcodeproj/project.pbxproj` untuk `CodexNavigatorTests.swift` tetap dipertahankan di samping membership M5.

Bukti automated terkini serta detail hasil build, suite, static checks dan manual handoff berada di [Nudge-M5-Verification.md](Nudge-M5-Verification.md). Live Codex Desktop local new/resumed, CLI new/resumed, trust/effective config, approval semantics, native notch, accessibility, dan failure/recovery runtime **belum diverifikasi**. Source dan synthetic tests saja tidak menyelesaikan Gate A maupun penerimaan M5.

Identity saat ini adalah UUID per helper invocation, bukan host request ID; provider duplicate/retry callback tidak di-coalesce. Action decisions dikirim kembali hanya pada response socket invocation yang sama, dan channel per sesi dibatasi/diantrekan. `tool_use_id` optional pada hook input; korelasi progress yang ambigu tetap konservatif. Detail limitation ini tercatat di [Nudge-M5-Codex-Contract.md](Nudge-M5-Codex-Contract.md). Jangan mengaktifkan atau mengandalkan mode action untuk host/runtime sampai verifikasi manual membuktikan request identity, hook ordering, Allow Once/Deny, timeout, native fallback, dan external resolution.
