# Nudge — Implementation Plan M3: Attention UX

Tanggal: **3 Oktober 2026**. Status: **plan disetujui pengguna; implementasi sumber M3 selesai; host/manual acceptance masih pending**.

Sumber kebenaran: [project brief](Nudge-Project-Brief.md), bagian 6.7–6.9, skenario question/permission, dan milestone M3; [AGENTS.md](../AGENTS.md). Baseline: [M2 verification](Nudge-M2-Verification.md), [kontrak Codex](Nudge-M1-Codex-Contract.md), dan source repository saat plan dibuat. Identitas visual mengikuti `PRODUCT.md`, `DESIGN.md`, dan surface brief notch yang sudah ada.

## 1. Outcome, scope, dan gate fase

Workflow yang diselesaikan M3: **local thread Codex membutuhkan jawaban/izin → Nudge menunjukkan alasan attention dari event yang tervalidasi → pengguna kembali ke Codex → menjawab atau memutuskan langsung di Codex → progress/resolution yang relevan membersihkan pending → Nudge kembali menampilkan aktivitas**. Workflow Desktop new/resumed dan CLI diverifikasi terpisah.

Deliverable M3:

- Live mirror `request_user_input` dan permission pada jalur host yang tersedia dan terbukti.
- Pending identity, bounded preview, dedupe, dan reconciliation yang tidak menghapus request belum terjawab.
- Attention persisten, satu konteks utama, akses ke semua sesi aktif di expanded, dan Nudgie attention yang tenang.
- Tombol `Answer in Codex`/`Open Codex` untuk aktivasi Desktop; arahan yang jujur ketika sesi berasal dari CLI atau origin belum diketahui.
- Fixtures, meaningful tests, catatan kontrak M3, dan handoff manual developer.

Precise thread routing tetap acceptance M4. Source saat ini sudah memiliki eksperimen deep link; M3 tidak memperluasnya atau menjadikan penerimaan URL oleh OS sebagai bukti navigasi berhasil. Attention M3 memakai aktivasi Desktop yang sudah tersedia pada `CodexNavigator.open(.desktop)`. Allow Once/Deny, programmatic answers, persistent allow, bypass, sounds, transcript fallback, app-server baru, distribusi, dan dependency baru berada di luar scope.

**Gate urutan:** M2 source/hermetic tests tercatat selesai, tetapi acceptance live/manual M1 dan M2 masih pending. Pengguna kemudian secara eksplisit memerintahkan implementasi M3; pekerjaan mengikuti override scope tersebut tanpa mengubah status host M1/M2 menjadi passed. M3 berhenti pada handoff ini sampai verifikasi manual developer dicatat dan pengguna memberi instruksi fase berikutnya.

## 2. Baseline aktual dan gap M3

| Boundary | Sudah ada | Perubahan yang diperlukan |
|---|---|---|
| Hook adapter/installer | Enam event M1; handler wildcard, backup, atomic mutation | Tambah permission hanya setelah kontrak dikunci; kenali question melalui jalur yang terbukti |
| Wire | V2; receiver menerima V1/V2; strict keys, finite tool summaries, frame 64 KiB | Payload interaction yang bounded dan tervalidasi; compatibility baru |
| Domain | `PendingInteraction` berisi id/kind/optional toolCallID; event pending/resolved; placeholder session | Metadata presentasi dan correlation evidence; pending live belum diproduksi adapter |
| Reducer | Pending bertahan; matching tool finish, explicit resolution, terminal lifecycle membersihkan | Pencegahan late request/replay; permission tanpa tool ID; multiple pending jika host mengizinkan |
| Monitor/ingress | Actor dan ordered ingress; semantic dedupe; focused + active snapshots | Canonicalize interaction; snapshot membawa pending yang aman; dedupe tidak menelan enrichment |
| Focus | Attention mendahului working/selection; expanded mengurutkan attention dulu | Satukan keputusan AppState/focus agar selected attention dapat diperiksa tanpa kalah oleh snapshot berikutnya |
| Presentation | Waiting selalu attention; collapse/timer tidak menghapus waiting; sleep/wake | Receipt navigasi tanpa semantic resolution; per-request motion consumption |
| UI | Question/permission yang kaya masih Demo; live selalu `liveMonitor` | Live attention card dan CTA; tetap bisa melihat semua sesi aktif |
| Navigation | Basic Desktop activation dan eksperimen `openSession` | Attention memakai aktivasi, error terlihat, pending tetap tersimpan |

Envelope hanya membawa `source: codex`; pilihan host pada menu instalasi bukan bukti origin event. Jangan menambahkan label Desktop/CLI berdasarkan konfigurasi yang mungkin dipakai bersama. Test result historis M2 bukan hasil pengujian M3.

## 3. Contract discovery sebelum adapter live

Ringkasan sumber resmi yang ditinjau **3 Oktober 2026**: `PreToolUse`/`PostToolUse` mencakup local function tools, tetapi specialized paths dapat opt out; guide tidak menyebut `request_user_input` secara eksplisit. `PreToolUse`/`PostToolUse` mendokumentasikan `tool_use_id`; tabel `PermissionRequest` mendokumentasikan turn/tool/input tanpa menjamin ID tersebut. Permission tanpa keputusan hook memakai native approval flow; non-managed hooks perlu trust atas definisi saat ini. Ini bukan bukti coverage installed Desktop/CLI. [Official Hooks guide](https://learn.chatgpt.com/docs/hooks).

**Gate kontrak M3:** sebelum mengunci schema dan correlation rules, buat `docs/Nudge-M3-Codex-Contract.md` dengan versi, supported fields, event ordering, neutral response, resolution signals, dan provenance fixture. Periksa panduan resmi kembali saat implementasi dimulai. Pengambilan event live dilakukan developer; AI hanya menggunakan fixtures/temp config tanpa izin live yang eksplisit.

| Jalur | Yang harus dibuktikan per host | Keputusan implementasi |
|---|---|---|
| Question | Nama tool tepat, shape argumen pertanyaan, Pre/Post coverage, tool/turn IDs, hasil setelah menjawab/cancel | Recognizer exact-match sesuai kontrak; jangan menganggap semua nama mengandung `input` adalah question |
| Permission | PermissionRequest coverage, turn identity, request/tool ID jika ada, ordering terhadap Pre/Post | Jangan mewajibkan undocumented `tool_use_id` atau mengarang ID tool |
| Resolution | Jawaban, approval, denial, cancel, interrupt; apakah ada progress yang mengidentifikasi request | Correlation rule harus ditopang fixture, bukan hanya waktu atau nama tool |
| Origin | Apakah payload/launch context memberi host yang dapat dipercaya | Jika tidak, origin unknown; menu installer bukan classifier host |
| Config/trust | Effective root, shared root/custom CODEX_HOME, reload dan trust setelah perubahan | Gunakan resolver/installer existing; tidak mengubah feature/trust flags otomatis |

Kandidat historis pada catatan M1: Desktop `26.928.31416` build `12553`, CLI `0.154.0`. Itu bukan versi yang diperiksa ulang dalam sesi plan ini; developer mencatat versi aktual saat verifikasi.

Jika hooks tidak mengirim question atau tidak memiliki resolution evidence yang memadai, investigasi jalur lokal yang didukung dan catat limitation. App-server terpisah, assistant prose, quiet interval, atau synthetic question bukan pengganti bukti Desktop. Jangan menyebut M3 selesai ketika workflow yang seharusnya tersedia masih gagal. Coverage yang benar-benar unsupported dicatat per versi dengan alasan; jangan diam-diam menurunkan scope ke CLI-only.

## 4. Data flow dan tanggung jawab

```text
Desktop / CLI hook (kontrak terverifikasi)
  → NudgeBridge: bounded read → CodexHookAdapter: whitelist + sanitasi
  → wire interaction / tool progress → owner-only socket
  → CodexEventIngress → CodexEventMonitor: canonical event
  → SessionReducer: pending identity, resolution, lifecycle
  → ActivitySnapshot: bounded attention presentation
  → AppState @MainActor → PresentationReducer → SwiftUI / NSPanel / Nudgie

Attention CTA → AppState navigation action → CodexNavigator → Desktop activation
             → navigation result saja; tidak mengirim semantic resolution
```

Parsing, sanitasi, encoding, IPC, installer, dan reduction tetap di helper/actor/background boundary. Main actor hanya menerapkan snapshot, efek presentasi, dan AppKit navigation. View tidak memahami raw Codex JSON, tidak mengubah config, dan tidak memberi jawaban/keputusan.

### Model dan validation yang direncanakan

- Extend `PendingInteraction` dengan preview opsional dan correlation metadata minimum; gunakan model Codable wire tersendiri bila diperlukan agar Core tetap bebas raw provider fields.
- Identitas question menggunakan session + turn + verified tool/request ID. Identitas ini ikut semantic dedupe; perubahan preview tidak membuat request baru atau mengulang attention motion.
- Permission menggunakan request ID resmi jika tersedia. Bila tidak, simpan local observation identity dan correlation confidence secara eksplisit. Local digest/timestamp bukan bukti identitas request eksternal. Jangan menggabungkan request identik atau memasangkan ke tool concurrent secara diam-diam.
- Snapshot membawa pending kind, identity, bounded display text, dan kemampuan navigasi yang benar-benar diketahui. Waiting tetap mengalahkan stale tool label.
- Default tampilan tetap berguna tanpa preview: `Codex has a question` atau `Codex needs permission`. Preview berasal hanya dari field question yang diverifikasi; gunakan pertanyaan pertama dan jumlah pertanyaan tambahan, maksimal 240 karakter. Permission memakai finite activity summary existing; raw command/diff/approval reason tidak diperlukan.
- Question text hanya berada dalam memori, tanpa opsi jawaban yang bisa diklik, full prompt, transcript, tool output, atau received URL. Terapkan plain text, strip control characters, conservative secret/path filtering, dan fallback generic bila konten tidak aman. Redaction heuristik tidak menjamin semua secret dikenali; gunakan preview generic ketika ragu. Log tidak pernah memuat preview.
- Tetap batasi input 1 MiB, frame 64 KiB, IDs 256 bytes. Limit preview diperiksa ulang receiver; reject field/type/enum/cross-event combination yang tidak sah sebelum materialisasi session. Duplicate object keys ditolak.

**Concurrent requests:** verifikasi apakah host dapat memiliki lebih dari satu pending pada satu turn. Bila ya, gunakan ordered pending collection kecil di session, dengan satu computed focused interaction untuk UI. Batas rencana 16 per session; overflow mempertahankan indikator attention dan diagnostics tanpa membuang pending sebagai resolved. Recovery overflow memerlukan resolution/reconciliation yang terbukti atau termination, bukan timeout. Jangan mempertahankan satu slot yang menimpa request sebelumnya. Jika kontrak menjamin serial requests, pertahankan model tunggal dan simpan evidence jaminannya; jangan membangun queue spekulatif.

## 5. Reconciliation dan dedupe

Reuse reducer M2; jangan mengganti turn identity/tombstone atau completion policy tanpa kebutuhan M3. Semua resolution berlaku hanya pada session/turn/request yang relevan.

| Input/aksi | Efek semantic pending |
|---|---|
| Question baru dengan identity valid | Materialisasikan placeholder jika perlu; pending → waitingInput |
| Permission baru dengan identity valid | Pending → waitingPermission; tidak menghasilkan approval |
| Duplicate request/enrichment | Satu pending; enrich metadata aman; tanpa replay motion atau reset urutan |
| PostToolUse cocok dengan question | Clear hanya pending yang terkait, termasuk kasus Post tiba sebelum delayed Pre |
| Permission resolution/progress yang terbukti | Clear request terkait; progress dari tool lain/concurrent tidak cukup |
| Resolution dari turn lama/request lain | Ignore; pending aktif tetap utuh |
| New valid turn atau terminal lifecycle yang relevan | Invalidate pending turn lama; interrupted tetap interrupted |
| Open Codex, app menjadi foreground, collapse, Escape | Tidak clear pending |
| Quiet interval, timer, sleep/wake, metadata SessionStart | Tidak clear pending |

Simpan bounded resolved-interaction tombstones per turn, seperti ledger tool M2, agar callback terlambat tidak membangkitkan question kembali setelah selesai. Jangan hanya mengandalkan dedupe TTL dua detik. Nilai provisional: maksimum 512 resolved identities per retained turn/session state, diselaraskan dengan batas tool existing tanpa menyimpan preview dalam ledger.

**Permission correlation adalah gate, bukan tebakan:** matching tool ID yang resmi adalah jalur terbaik. Progress dengan hanya turn ID atau tool name belum otomatis membuktikan keputusan request tertentu ketika concurrency mungkin terjadi. Rule singleton/order hanya dipakai jika kontrak host dan chronology fixtures membuktikannya. Jika tidak ada bukti, pending bertahan dan limitation ditampilkan sampai valid resolution/termination. Denial/cancel yang tidak memproduksi Post harus memiliki jalur rekonsiliasi yang terbukti; jangan mengarang event `PermissionResolved` yang tidak dikirim host.

Socket loss/app restart tidak memulihkan state secara ajaib. Request yang tidak terobservasi tidak boleh direkonstruksi dari transcript. Reopening Nudge memproses event berikutnya tanpa replay; gap event yang menyebabkan pending tidak terrekonsiliasi dicatat sebagai keterbatasan, dengan recovery melalui lifecycle valid. Tidak menandai pending resolved hanya karena listener restart.

## 6. UX attention dan native behavior

Mode Operate: pengguna sedang di aplikasi lain dan perlu mengetahui alasan Codex menunggu serta tempat melanjutkannya. Preserve opaque black, native type, original Nudgie, camera exclusion, anchor, dan motion existing.

1. **Request muncul:** buka attention untuk satu focused context; tampilkan project/session label, question/permission title + symbol, preview aman atau generic fallback, dan CTA. Hindari fake diff dan Demo content pada live card.
2. **Masih pending:** pointer keluar tidak menghapus/collapse attention otomatis. Tidak ada timeout attention atau pulse loop. Nudgie melakukan satu cue kecil untuk identity baru lalu diam dalam pose attention; Reduce Motion memakai pose statis. Sleep mematikan cue; wake membangun current view tanpa replay.
3. **Desktop CTA:** `Answer in Codex` untuk question, `Open Codex` untuk permission. Panggil basic Desktop activation; tampilkan launch failure dengan retry, dan pertahankan pending. Untuk M3, setelah aktivasi berhasil card tetap attention, sehingga tidak perlu state dismissal baru. Tidak menampilkan success receipt/celebration setelah klik CTA.
4. **CLI/origin unknown:** apabila CLI origin terbukti, beri instruksi `Continue in your Codex CLI session`; activation Desktop menjadi secondary convenience dengan label yang jelas. Bila unknown, `Open Codex` membuka Desktop disertai arahan singkat bahwa sesi CLI dilanjutkan di terminal. Jangan menjanjikan terminal/tab routing atau bahwa Desktop akan menjawab request CLI.
5. **Banyak sesi:** collapsed/peek tetap satu konteks. Expanded mempertahankan semua active rows, attention dahulu lalu urutan turn existing. Konten yang panjang memakai scroll. Viewport expanded tetap 160 pt + 10 pt untuk multiple sessions (170 pt, ditambah camera band pada notch); jangan menambah 10 pt lagi. Attention memakai batas geometry attention existing; sediakan akses eksplisit ke daftar semua sesi tanpa mematikan pending. Jika perlu, presentation-only aksi membuka session list meskipun ada attention, sementara collapsed tetap mengindikasikan pending. Selecting pending row menampilkan card request tersebut; selection tidak mengubah state semantic.
6. **Resolved di Codex:** snapshot progress menghapus card terkait dan menampilkan working/current tool atau terminal status. Pending lain tetap visible; completion tetap hanya dari completion event, bukan dari jawaban/approval.

Focus default tetap attention-first, lalu pilihan pengguna, lalu working sesuai brief. Dalam kelompok attention, pilihan pengguna harus bertahan sampai request resolved; jangan ada dua aturan yang saling bertentangan di FocusPolicy dan AppState. Tool update/background session tidak mencuri focused question atau scroll anchor. Tanpa pilihan, gunakan ordering attention existing dengan tie-break stable session ID.

Keyboard/VoiceOver: CTA berupa native Button, focus ring terlihat, label memuat project dan jenis attention. Hover tidak mengaktifkan app. Enter/Space bekerja hanya ketika kontrol memiliki keyboard focus; tidak ada global shortcut yang menjawab/approve. Escape hanya aksi presentasi, tetap mempertahankan pending; implementasinya mengikuti pilihan sticky card di atas. Status dipahami melalui teks/simbol, bukan warna saja. Pertanyaan panjang/truncated tetap punya action jelas dan tidak melewati shoulders atau menutupi tombol.

## 7. Compatibility, backup, dan recovery sebelum mutation

### Wire upgrade

Rencana **V3** untuk interaction payload. Receiver baru tetap menerima V1/V2 dengan validation lama dan tanpa phantom attention. Event interaction hanya valid di V3. Daftar versi supported dibuat eksplisit `[1, 2, 3]`; menaikkan `currentVersion` saja tidak cukup karena validator saat ini menguji current/legacy.

Helper baru mengirim V3; app lama menolak frame tanpa memblokir Codex. App baru menerima helper lama tetapi live attention belum tersedia. Install action existing mengganti helper owner-checked sebelum memperbarui hooks; dokumentasikan pasangan app/helper. Recovery: install ulang versi yang cocok, atau pulihkan helper matching versi lama dan hanya entries milik Nudge dari backup; jangan overwrite keseluruhan hooks.json jika foreign config berubah sesudah backup.

### Hook upgrade

Setelah kontrak dikunci, tambah `PermissionRequest` ke managed events. Question memakai Pre/Post existing jika coverage terbukti; jangan memasang handler tambahan identik. Karena installer mengiterasi `CodexHookEvent.allCases`, pisahkan daftar managed events dari wire cases bila V3 memerlukan internal event yang bukan hook Codex.

Sebelum write: resolve effective target → parse/validate original → compose preserving foreign handlers → private exact-byte backup → recheck concurrent changes → atomic replace. No-op tidak menulis. Malformed/unsupported/symlink/permission denied/backup failure tidak menyentuh original. Uninstall mengenali ownership lama dan baru, menghapus hanya handler Nudge; perubahan handler dapat memerlukan trust ulang. Jangan mengubah trust database, config.toml, approval policy, atau flags Codex. Temporary config saja untuk automated testing.

### Bridge response dan failure

Tetap deadline total 250 ms untuk stdin + normalisasi + send, bukan timeout baru setiap tahap. Permission mirror selesai tanpa decision payload dan tanpa menunggu pengguna; exact neutral stdout diverifikasi dalam contract gate. Tidak ada `allow`, `deny`, answer, additional model context, atau altered input. Nudge unavailable, malformed event, socket timeout, dan helper mismatch tetap mengembalikan kontrol ke Codex secara cepat sesuai kontrak. Owner-only socket mode/peer validation dan transport existing tidak di-refactor.

## 8. Urutan implementasi dalam satu fase M3

1. **Contract + fixture gate:** lengkapi host/identity/resolution matrix; fixtures synthetic ditandai jelas. Pisahkan blockers coverage dari kemampuan yang sudah terbukti. Putuskan correlation, preview fields, dan concurrency sebelum mengunci V3.
2. **Wire + adapter + helper:** implementasi V3 dan legacy acceptance; normalize question/permission; neutral output/failure tests. Uji payload adversarial sebelum menghubungkan UI.
3. **Domain + monitor:** expose pending presentation metadata, resolve matching evidence, late-event tombstones, focus/selection consistency; reuse ordered ingress.
4. **Live UI + navigation:** live card terpisah dari Demo, CTA activation, error/retry, all-session access, per-identity mascot cue, bounded geometry dan accessibility.
5. **Installer compatibility:** temp-config upgrade/reinstall/uninstall; backup, foreign entries, ownership, no-op, custom roots, re-trust guidance.
6. **Verification + handoff:** jalankan checks relevan, tulis hasil aktual dan manual matrix. Berhenti pada M3; acceptance menunggu developer, tidak melanjutkan M4/M5.

## 9. File yang disentuh saat implementasi

Daftar ini merupakan batas implementasi. Perubahan tambahan pada test `NudgeCoreTests/SessionReducerTests.swift` hanya memperbarui assertion lama agar memeriksa identitas pending tanpa mengabaikan timestamp baru.

| File/area | Alasan |
|---|---|
| `Nudge/Core/Events/NudgeEvent.swift` | Pending preview/identity dan semantic dedupe |
| `Nudge/Core/Reducer/SessionReducer.swift` | Matching resolution, tombstones, conditional concurrent pending |
| `Nudge/Core/NudgeModels.swift` | Safe attention snapshot dan presentation input bila session list perlu override |
| `Nudge/Core/Reducer/FocusPolicy.swift` | Deterministic focused attention dan selection |
| `Nudge/Core/PresentationReducer.swift` | Sticky semantic attention, session-list access, cue consumption/sleep |
| `Nudge/IPC/WireEnvelope.swift` | Strict V3, explicit V1/V2 compatibility, interaction validation |
| `Nudge/Integration/Codex/Hooks/CodexHookAdapter.swift` | Provider recognizer, sanitasi dan field whitelist |
| `Nudge/Integration/Codex/Hooks/CodexHookInstaller.swift` | Managed PermissionRequest/ownership/upgrade compatibility |
| `NudgeBridge/main.swift`, `Nudge/Integration/Codex/Hooks/BridgeProcessor.swift` | Neutral output/deadline integration hanya jika diperlukan |
| `Nudge/Services/CodexEventMonitor.swift` | Interaction canonicalizer dan focused/active snapshots |
| `Nudge/App/AppState.swift` | Live CTA, navigation status, single focus policy |
| `Nudge/UI/NotchRootView.swift`, `Nudge/UI/NotchComponents.swift` | Live attention card, session list access, bounded content |
| `Nudge/UI/Nudgie.swift` | Cue identity dan Reduce Motion/sleep behavior bila pose existing belum cukup |
| `Nudge/UI/NotchGeometry.swift`, `Nudge/UI/NotchPanelController.swift` | Hanya jika live layout/keyboard access memerlukan wiring; preserve existing bounds/anchor |
| `Nudge/Integration/Codex/Navigation/CodexNavigator.swift` | Hanya injection seam untuk activation tests jika diperlukan; deep link tetap scope existing |
| `NudgeCoreTests/SessionReducerTests.swift`, `FocusPolicyTests.swift`, `PresentationReducerTests.swift`, `WireValidationTests.swift` | State/correlation/compatibility invariants |
| `NudgeCoreTests/NotchLayoutChecks.swift`, `PresentationChecks.swift` | Sesuaikan expectation nyata yang berubah, bukan snapshot tests yang menyalin implementation |
| `NudgeIntegrationTests/WireAdapterTests.swift`, `CodexEventIngressTests.swift`, `HookInstallerTests.swift`, `BridgeFailureTests.swift` | End-to-end hermetic boundary/failure coverage |
| `NudgeIntegrationTests/Fixtures/Codex/attention/` + README baru | Sanitized scenario/provenance; synthetic/live dibedakan |
| `NudgeIntegrationTests/CodexNavigationTests.swift` baru bila seam diperlukan | Activation success/failure tanpa meluncurkan app nyata |
| `docs/Nudge-M3-Codex-Contract.md`, `docs/Nudge-M3-Verification.md` baru | Contract evidence dan developer handoff |
| `Nudge.xcodeproj/project.pbxproj` | Target membership source/fixtures/tests baru saja |
| `PRODUCT.md`, `DESIGN.md`, `.impeccable/surfaces/nudge-ui-notchrootview-swift.md` | Perbarui hanya perilaku live M3 yang benar-benar diimplementasikan |

Perubahan di luar daftar memerlukan alasan tertulis. Tidak ada rename folder besar, parser config baru, atau transport rewrite.

## 10. Meaningful automated verification

1. **Adapter/privacy:** exact question recognizer, multiple/malformed questions, missing preview fallback, permission tanpa tool ID, unknown tool tidak menjadi question; raw prompt/command/output/path/secret sentinels tidak masuk envelope/log. Whitelisted question excerpt satu-satunya text preview yang dibolehkan.
2. **Wire:** V1/V2 unchanged acceptance; valid V3 question/permission; unknown version/keys, duplicate keys, wrong kind/event, missing identity, invalid enum/control characters, oversize payload; malformed input tidak menciptakan session.
3. **Reducer:** request sebelum SessionStart, matching resolution, wrong session/turn/request, duplicate setelah TTL, resolved → delayed pending, duplicate metadata enrichment, interrupt/new turn, independent sessions; concurrent tool progress tidak membersihkan request lain. Conditional queue test jika host mendukung multiple pending.
4. **Permission chronology:** approval dan denial/cancel paths dari contract fixtures; request tanpa ID tidak dipasangkan melalui tebakan. Evidence yang ambigu tetap pending dan diagnostic; limitation tidak disamarkan oleh test synthetic success.
5. **Presentation/focus:** attention menang atas stale tool, selected pending tidak dicuri working/attention update lain, all-session list masih bisa diakses, CTA success/failure/Escape/timer tidak resolve, stale timer tidak menghapus request baru, motion sekali per identity, sleep/wake tanpa replay.
6. **Installer:** enam handler lama → tambahan permission tepat sekali, duplicates/foreign/matcher preservation, no-op, uninstall ownership lama/baru, malformed bytes unchanged, backup/atomic/concurrent-edit failures, separate/custom roots; semua dengan temporary config.
7. **Bridge/ingress:** unavailable/stalled socket, app crash/disconnect, partial/malformed stdin, version mismatch; bounded completion dan neutral permission stdout/exit. End-to-end fixture request → wire → monitor → matching progress → cleared snapshot tanpa host/config nyata.
8. **Navigation:** fake activation success/failure/retry; no semantic clear, no deep link dependency pada attention action; origin unknown/CLI labels tidak mengklaim exact routing.

Gunakan shared scheme existing:

```bash
xcodebuild -list -project Nudge.xcodeproj
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test
git diff --check
```

Jalankan tests targeted selama perubahan; satu full relevant test action sebelum handoff. Pada implementasi ini Debug build dan full test suite dijalankan dan berhasil; `git diff --check` juga bersih. Source/static checks bukan bukti native runtime QA, yang tetap menjadi tanggung jawab developer.

## 11. Verifikasi manual oleh developer

Seluruh langkah berikut **pending**; AI tidak menjalankannya tanpa instruksi eksplisit. Gunakan sandbox project dan recoverable configuration; developer mengendalikan trust, prompts, dan keputusan nyata.

1. Catat macOS, Desktop/CLI versi/build, effective config root masing-masing, custom CODEX_HOME, trust/reload, dan status acceptance M2. Setelah install M3, review definisi hook yang berubah melalui mekanisme host yang tersedia; jangan menganggap hilangnya event selalu masalah trust.
2. Mulai local thread langsung di Desktop dan picu question pada mode host yang mendukungnya. Cocokkan question/IDs, project, safe preview, attention dan Nudgie; ulangi pada resumed thread tanpa terminal launch atau Nudge app-server.
3. Dari aplikasi lain, klik `Answer in Codex`; pastikan Desktop aktif. Jangan jawab dulu: pending harus tetap terlihat. Jawab langsung di Codex; catat event yang membersihkannya dan pastikan Nudge menunjukkan progress terbaru.
4. Picu native permission pada Desktop dalam sandbox; klik `Open Codex`, kemudian uji approval serta denial/cancel melalui Codex secara terpisah. Catat jalur resolution masing-masing; Nudge tidak memberi keputusan dan tidak tersangkut setelah progress valid.
5. Ulangi question/permission/answer/approval/denial/cancel pada CLI secara independen. Catat event differences dan batas routing. CTA/instruksi tidak boleh menyatakan membuka Desktop menyelesaikan request CLI.
6. Biarkan request belum dijawab selama quiet interval dan saat tool/session lain aktif. Hover keluar, collapse/Escape, memilih session lain, serta aktivasi Desktop tidak menghapusnya. Uji dua attention sessions dan semua active rows dalam list yang bisa di-scroll tanpa melebihi cap expanded.
7. Sleep/wake saat question dan permission pending, serta setelah resolution. Pastikan pending benar, current snapshot tunggal, tidak replay cue/celebration atau timer lama. Ulangi dengan Reduce Motion, VoiceOver, keyboard focus, dan Increase Contrast.
8. Uji pertanyaan panjang, multi-question, preview kosong/ditolak, non-notch display, physical notch, rapid hover, Spaces/full-screen, dan menu auto-hide. CTA tetap terlihat/terjangkau, camera band tetap kosong, dan hover tidak mencuri focus.
9. Uji Codex Desktop tidak berjalan/tidak tersedia serta activation failure. Error/retry terlihat; pending tidak ditandai answered. Exact thread routing tetap dicatat terpisah sebagai eksperimen M4.
10. Tutup/crash Nudge ketika question/permission muncul dan jawab di Codex; pastikan host tetap memakai native flow tanpa auto-allow. Buka Nudge lagi, lanjutkan/new turn; status pulih dari event yang tersedia, tanpa klaim pemulihan request yang hilang atau replay lama.
11. Pada config sementara, upgrade/reinstall/uninstall M3 dengan foreign hooks dan malformed file. Pastikan backup/private bytes, owner-only socket, matching app/helper version, no-op, foreign preservation, serta custom root recovery sesuai plan.

Catat hasil pada `docs/Nudge-M3-Verification.md` dengan kolom **host + versi / scenario / effective config + trust / observed request + resolution signal / provenance / hasil atau limitation**. Status allowed: pending, passed, failed, unsupported dengan evidence; fixtures tidak mengubah status live menjadi passed.

## 12. Kriteria selesai dan handoff

- Question/permission yang tersedia pada Desktop new/resumed dan CLI terdeteksi melalui jalur terbukti, dengan evidence terpisah.
- User melanjutkan di Codex; Desktop CTA mengaktifkan app dan failure dapat dipahami. Tidak ada decisions/answers dari Nudge.
- Pending tetap aktif sampai matching resolution/progress atau lifecycle invalidation valid; denial/cancel tidak menyebabkan stale card permanen pada jalur yang didukung.
- Duplicate/late callbacks, unrelated progress, focus switching, quiet interval, dan sleep/wake tidak menyebabkan lost attention/replay.
- Live UI preserve visual identity, bounds, all-active-session access, accessibility, motion hemat, dan privacy defaults.
- Wire upgrade, installer backup/recovery, foreign config, malformed preservation, dan Nudge-unavailable invariants lolos checks relevan.
- Contract/fixture provenance, automated results, limitations, dan numbered manual handoff lengkap. M3 acceptance tetap pending sampai developer mencatat manual evidence.
- Commit terpisah sesuai instruksi pengguna, menggunakan English Conventional Commits; jangan commit perubahan pengguna yang tidak terkait. Contoh scope implementasi: `feat(attention): mirror Codex questions and permissions`.

Risiko utama: question hooks tidak tersedia pada specialized path, permission tidak punya stable request identity, missed resolution saat IPC terputus, host origin ambigu, dan preview sensitif. Mitigasi mengikuti gate kontrak, strict validation, conservative correlation/generic preview, honest diagnostics, serta native Codex recovery. Tidak menutup risiko dengan auto-approval, transcript scraping, TTL resolution, atau klaim dukungan sintetis.

## ATURAN PENGERJAAN — blok wajib

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
