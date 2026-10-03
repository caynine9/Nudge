# Nudge — Implementation Plan M4: Precise Navigation

Tanggal: **3 Oktober 2026**. Status: **M4 source implemented; Debug and build-for-testing passed; test execution and host/manual acceptance pending**.

Sumber kebenaran: [project brief](Nudge-Project-Brief.md), bagian 6.16, 37, dan milestone M4; [AGENTS.md](../AGENTS.md). Baseline implementasi dan batas acceptance: [M3 verification](Nudge-M3-Verification.md), [M3 Codex contract](Nudge-M3-Codex-Contract.md), serta source repository saat plan dibuat.

## 1. Outcome, scope, dan gate fase

Workflow M4: **pengguna berada di aplikasi lain → memilih attention atau sesi Nudge → Nudge mencoba membuka local thread yang relevan di Codex Desktop bila precise navigation diaktifkan dan identitas tersedia → kegagalan beralih ke aktivasi Desktop dengan recovery yang jelas → pengguna melanjutkan di Codex → hanya progress/lifecycle Codex yang valid mengubah pending interaction**.

Deliverable:

- Satu boundary `CodexNavigator` untuk attention, klik sesi aktif, dan aktivasi Desktop.
- Eksperimen deep link existing local thread yang ditargetkan ke aplikasi melalui bundle ID.
- Preference `Use precise Codex thread navigation`, dengan jalur aktivasi yang tetap berfungsi ketika Off.
- Fallback untuk ID tidak tersedia/tidak valid, route failure, missing/archived thread sesuai kemampuan host, dan aplikasi belum berjalan.
- Hasil navigasi yang membedakan delivery/activation dari bukti thread benar-benar tampil; diagnostics bounded dan aman.
- Hermetic tests, catatan kontrak navigasi, dan handoff manual developer.

Tidak termasuk Allow Once/Deny, jawaban programmatic, terminal tab routing, membuka atau membuat thread baru sebagai recovery, conversation browser, remote/cloud routing, app-server baru, transcript parsing, redesign notch, dependency baru, dan distribusi. M5/M6 tidak dimulai dalam sesi M4.

**Gate urutan:** M3 source/build/hermetic suite tercatat selesai, tetapi manual/live acceptance M1–M3 masih pending. Pengguna secara eksplisit menginstruksikan implementasi M4 setelah review plan; instruksi itu mengizinkan M4 berlanjut sebelum gate manual sebelumnya dicatat. Override ini tidak mengubah status penerimaan M1–M3. Precise navigation tetap Off sampai pengguna/developer mengaktifkan eksperimen, dan acceptance tetap menunggu bukti Desktop serta CLI terpisah.

## 2. Baseline aktual dan gap

| Boundary | Kondisi repository | Perubahan M4 |
|---|---|---|
| Navigator | Struct `CodexNavigator`, basic Desktop activation, `openSession(String)` | Boundary injectable untuk native workspace dan satu request/outcome yang jelas; implemented in existing navigator |
| Deep link | `CodexThreadDeepLink.url(sessionID:)`, percent encoding dan limit 256 bytes | Identitas thread eksplisit pada request, reserved-route validation, targeted delivery |
| Routing | `NSWorkspace.shared.open(url)` mengandalkan default scheme handler | Resolve aplikasi melalui bundle ID, kirim URL langsung ke aplikasi tersebut |
| Attention | `openAttentionInCodex()` selalu `open(.desktop)` | Gunakan konteks session/turn/interaction yang ditangkap saat klik |
| Session list | `openLiveSession` mencoba route dari session ID; collapse ketika OS menerima | Gunakan policy/toggle sama; outcome tidak mengklaim exact thread terbuka |
| Preference | Belum ada toggle precise navigation | Nudge-only setting/menu toggle, default Off; wired for opt-in experiment |
| Identity | Snapshot hanya memiliki `sessionID`/`turnID`; host origin tidak ada di wire V3 | Tidak menganggap pilihan host instalasi sebagai origin; validasi mapping session→thread |
| Metadata | Optional reader `thread/read` sudah mencari title berdasarkan session ID | Title lookup bukan bukti routing; tidak menjadi prerequisite navigasi |
| Tests | URL valid/encoding/invalid dasar di `CodexEventIngressTests` | Tambah branch fallback, targeting, deadline, stale results, dan pending invariants |

Perubahan UI, geometry, aset, dan Xcode project yang belum di-commit sudah ada saat plan dibuat. Implementasi M4 harus mempertahankannya dan hanya mengubah hunk yang diperlukan untuk navigasi/test membership. Jangan memasukkan perubahan pengguna ke commit fase M4.

## 3. Kontrak resmi dan bukti host yang dibutuhkan

Ditinjau **3 Oktober 2026**:

- Referensi Commands resmi mencantumkan `codex://threads/<thread-id>` untuk local chat dengan technical thread ID. Referensi juga memiliki route `threads/new`; M4 hanya memakai existing-thread route. [Official Commands — Deep links](https://learn.chatgpt.com/docs/reference/commands#deep-links).
- Referensi Hooks menyebut `session_id` sebagai current Codex session ID. Informasi itu belum cukup untuk membuktikan bahwa setiap hook ID bisa digunakan sebagai technical thread ID pada semua host/config. [Official Hooks — Common input fields](https://learn.chatgpt.com/docs/hooks#common-input-fields).
- Sumber resmi yang ditinjau tidak menetapkan acknowledgment bahwa target thread tampil, routing ke window/Space tertentu, ataupun recovery archived/missing thread untuk versi terpasang. Bagian brief mengenai edge case diperlakukan sebagai research snapshot.

Sebelum mengunci perilaku precise navigation, buat `docs/Nudge-M4-Codex-Contract.md` dan isi matrix berikut dengan bukti terpisah. Nilai versi historis di M1 tidak disalin sebagai versi aktual.

| Jalur | Bukti yang dicatat developer | Keputusan |
|---|---|---|
| Desktop new local thread | Versi/build, bundle ID aktual, sanitized hook session ID dibanding technical thread ID, route yang benar-benar tampil | Mapping session ID boleh digunakan hanya untuk kontrak yang terbukti |
| Desktop resumed local thread | Identitas tetap konsisten; route membuka thread yang sama | Tidak bergantung pada `SessionStart` baru |
| CLI new/resumed local thread | Versi, effective root/custom `CODEX_HOME`, trust, apakah Desktop mengenal thread tersebut | Route CLI di Desktop hanya bila visibility/mapping terbukti; tidak menjanjikan terminal continuation |
| Desktop closed / multiple windows | Launch melalui aplikasi terpilih, foreground behavior, window/Space yang tampil | Routing exact window tidak dijanjikan tanpa kontrak |
| Archived/missing ID | OS delivery result dan UI hasil terpisah; apakah ada rejection resmi | Error yang teramati → fallback; accepted-but-unverified → app activation/recovery, tanpa klaim exact success |
| Scheme handler berbeda / app berbeda | Bundle ID yang dipakai dan targeted URL delivery | Tidak mengandalkan default scheme handler |

**Identity decision:** request navigasi memisahkan local `sessionID` untuk korelasi Nudge dari optional candidate `threadID` untuk route. Tidak perlu menambah wire field bila mapping hook ID→thread ID dibuktikan untuk host yang ditargetkan. Pembentukan candidate dilakukan di adapter navigasi, bukan view. Bila mapping belum tersedia, gunakan activation-only; jangan mencari thread berdasarkan project label, title, waktu, atau transcript filename.

Origin event V3 tetap unknown. Precise toggle adalah opt-in eksperimen membuka local thread ID di Desktop, bukan classifier Desktop/CLI. Eligibility candidate harus mengikuti bukti mapping dan batas config yang tercatat; jika root/origin yang diperlukan tidak dapat diketahui, tetap activation-only. Tidak menganggap semua events berasal dari root yang dipilih di menu. Apabila dukungan penuh ternyata membutuhkan host/root/thread metadata baru, dokumentasikan proposal compatibility sebelum memperluas schema; perubahan wire tidak menjadi default scope M4.

Untuk verified CLI origin, CTA menjelaskan bahwa request dijawab di sesi CLI asal. Membuka salinan thread di Desktop bukan bukti bahwa permission/question CLI bisa diputuskan dari sana. Untuk origin unknown, tetap gunakan label `Open Codex Desktop`/`Answer in Codex Desktop` existing dengan arahan CLI yang jujur saat diperlukan.

## 4. Data flow dan boundary

```text
Validated activity snapshot + navigation preference
  → AppState captures session / turn / interaction context at click
  → CodexNavigator request: optional thread candidate + activation-only policy
  → injectable workspace boundary
      → resolve Desktop application by verified bundle ID
      → targeted URL delivery OR app activation/launch
      → bounded outcome + finite diagnostics
  → AppState applies current navigation feedback only
  → existing PresentationReducer / SwiftUI

Codex hook progress → existing event spine → SessionReducer
                  → pending reconciliation, independent of navigation
```

`Core` tetap bebas AppKit, raw provider, dan URL syntax. Main actor menangani AppKit operations dan UI feedback. Tidak ada parsing transcript, blocking file reads, process waits, config mutation, atau enrichment RPC dalam click path. Async native callbacks tidak memblokir main actor.

Gunakan protocol kecil pada boundary workspace agar tests dapat mengontrol installed/running app, targeted open, activation, failure, dan callback terlambat tanpa meluncurkan Codex. `CodexNavigator` dapat tetap menjadi implementasi konkret; tidak perlu membuat service framework atau protocol untuk setiap model.

Request/outcome minimum:

- Request: local session correlation, optional candidate thread ID, dan policy precise/activation-only. Turn/request identity tetap dimiliki caller untuk mencegah stale feedback.
- Outcome: `threadRouteDispatched` atau `desktopActivated(reason)`; error akhir hanya jika Desktop tidak dapat dibuka/diaktifkan. `threadRouteDispatched` berarti delivery native berhasil, bukan `threadOpened`.
- Reason finite: precise disabled, identity unavailable/invalid, route rejected, route deadline, atau activation-only recovery. Jangan membuat alasan `archived`/`missing` tanpa signal resmi.
- Jika route berhasil dikirim tetapi aktivasi yang diperlukan gagal, return failure/degraded outcome yang jujur; jangan menyembunyikan kegagalan foreground di balik route success.

## 5. Policy navigasi dan expected failure cases

1. Tangkap target dari snapshot saat klik. Attention memakai session card yang ditampilkan; row memakai ID row. Snapshot berikutnya tidak boleh mengganti tujuan operasi yang sedang berlangsung.
2. Baca policy/toggle saat request dibuat. Default preference Off; upgrade dari source eksperimen tanpa preference juga Off. Off memanggil activation-only dan sama sekali tidak membentuk/mengirim deep link.
3. Resolve installed/running application melalui bundle ID yang diverifikasi. Baseline repository memakai `com.openai.codex`; verifikasi terhadap versi host sebelum dianggap kontrak tetap. Bila tidak ditemukan, tampilkan error aplikasi unavailable. Jangan membuka aplikasi bernama mirip atau scheme handler lain secara diam-diam.
4. Bila candidate ID valid dan eligible, bentuk existing-thread URL di navigator. Gunakan native targeted URL API (`NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`) dengan aplikasi hasil bundle resolution dan `configuration.activates = true`, atau ekuivalen Apple yang diverifikasi pada deployment target. Tidak perlu shell `open`.
5. Bila route ditolak/error/deadline, coba aktivasi/launch Desktop **sekali**. Bila ID missing/invalid atau precise Off, langsung ke jalur ini. Error invalid ID tidak menghentikan fallback.
6. Bila URL delivery diterima, pastikan operasi menargetkan app dengan activation enabled. Receipt hanya menyatakan route dikirim. Jika ada signal native bahwa app belum aktif, lakukan satu activation recovery; tidak mengulang URL atau bermain dengan semua windows.
7. Tanpa official acknowledgment target, missing/archived thread yang diterima OS tidak dapat dideteksi secara pasti. User tetap mendapat Desktop foreground melalui targeted open/activation; sediakan aksi `Open Codex Desktop` yang melewati route dan arahan memilih thread manual. Jangan melakukan polling screenshot/accessibility, probing database, automatic unarchive, atau membuat thread pengganti.
8. Jika fallback juga gagal, tampilkan pesan finite: aplikasi unavailable, gagal membuka, atau operasi melewati deadline. Retry hanya dari aksi pengguna. Hindari raw NSError yang mungkin membawa path/URL.

**Validation ID:** gunakan batas identifier existing 256 UTF-8 bytes, tolak kosong/control characters, reserved `new`, serta dot segments `.`/`..`. Pertahankan opaque IDs dengan percent encoding satu path segment; jangan mensyaratkan UUID tanpa kontrak. Uji `/`, `?`, `#`, `%`, whitespace, dan Unicode agar tidak mengubah host/path/query/fragment atau membuka route lain. Encoded path separators tetap memerlukan bukti bahwa host memperlakukannya sebagai ID; input ambigu yang belum didukung beralih ke activation-only. Jangan menerima URL penuh dari payload.

**Deadline dan concurrency:** tetapkan budget provisional 5 detik total per klik: maksimal 2 detik route dan sisa budget untuk fallback; activation-only maksimal 5 detik. Timer menggunakan waktu monotonic dan dapat diinjeksikan. Budget membatasi berapa lama UI berstatus Opening; native launch mungkin tetap selesai setelah timeout. Implementasi race tidak boleh memakai structured task group yang menunggu callback non-cancellable hingga selesai. Gunakan request token dan single-completion gate sehingga callback terlambat tidak mengubah feedback, memainkan motion, collapse panel baru, atau mengirim fallback kedua. Tidak mengklaim timer dapat membatalkan launch yang sudah diserahkan ke OS.

Satu request in-flight cukup sesuai `isOpeningHost` existing. Klik berulang tidak meluncurkan beberapa app atau antrean route. Sleep/app shutdown membatalkan feedback request dan melepaskan state Opening tanpa replay saat wake; side effect OS yang terlanjur dikirim tetap mungkin selesai.

**Nudge unavailable:** navigation bukan bagian hook response. Nudge tertutup/crash/socket unavailable tidak mengubah native coding, approval, atau question flow. Tidak menambah hold, decision output, atau syarat Nudge agar Codex melanjutkan.

## 6. Integrasi UX dan state

- Satukan `openAttentionInCodex`, `openLiveSession`, dan live focused-context action melalui navigator/policy yang sama. `openFocusedHost()` Demo tetap mempertahankan perilaku preview; jangan memakai ID simulasi untuk precise route.
- Attention CTA mencoba candidate hanya ketika eligible dan precise On. Berhasil delivery/activation tidak memanggil `interactionResolved`, tidak mengubah phase, dan tidak memainkan success/celebration.
- Untuk attention, pertahankan perilaku M3: card tetap attention sampai relevant host progress. Tidak perlu menambah presentation dismissal state di M4.
- Untuk row sesi non-attention, collapse boleh dilakukan setelah delivery/activation berhasil hanya bila konteks target masih relevan dan tidak ada attention baru. Fallback reason tetap dapat ditemukan ketika panel dibuka lagi. Kegagalan akhir mempertahankan panel agar pesan/retry dapat dibaca.
- Feedback terikat request context; jika session/turn/interaction yang ditampilkan berubah sebelum callback, jangan menempelkan error lama ke card baru. Operation gate tetap dilepas tepat sekali.
- Teks route receipt tidak menyatakan `Thread opened`. Gunakan copy ringkas seperti `Codex opened. Select the chat if it is not shown.` ketika target belum dapat dikonfirmasi; tampilkan detail recovery saat pengguna kembali ke Nudge tanpa memperbesar panel.
- Tambah toggle di menu existing, bukan settings window baru. Aksi recovery activation-only tersedia pada navigasi yang unverified/degraded/failed. Mengubah toggle tidak memodifikasi hook trust maupun config Codex.
- Preserve expanded cap dan scroll existing, attention ordering, satu focused context, original Nudgie, nonactivating panel, Reduce Motion, VoiceOver, dan keyboard access. Hover tidak melakukan navigasi; activation hanya dari klik/aksi eksplisit.

## 7. Compatibility, privacy, backup, dan recovery

Default scope M4 **tidak mengubah hooks, wire V3, installer, bridge, atau config Codex**. Receiver V1/V2/V3 existing tetap dipakai. Tidak perlu backup config karena tidak ada mutation config dalam fase ini.

Perubahan persistence hanya Boolean preference Nudge `usePreciseCodexThreadNavigation`. Tidak ada migrasi destructive; key absent berarti Off. Recovery: matikan toggle untuk kembali ke activation-only, atau gunakan aksi activation-only tanpa mengubah preference. Preference tests memakai isolated UserDefaults suite/injected store, bukan preferences pengguna.

Jika discovery membutuhkan field wire baru, berhenti pada proposal perubahan scope yang menjelaskan producer/consumer compatibility, optional field validation, old helper/new app behavior, matching helper upgrade, installer backup/atomic replacement bila handler berubah, dan rollback. Jangan menyelipkan schema upgrade ke implementasi navigasi.

Diagnostics melalui `OSLog` berisi finite route/fallback/error reason dan elapsed duration yang dibatasi. Jangan log thread/session/turn ID mentah, URL, project path, config path, title, preview, prompt, command, atau raw NSError. Tidak menyimpan navigation history atau transcript. Tests memakai sentinel untuk memastikan tidak ada sensitive data pada diagnostic message. Runtime tidak memerlukan cloud backend, account baru, telemetry, atau dependency tambahan.

Tidak memakai title cache sebagai routing authority. Optional metadata lookup boleh tetap berjalan lewat boundary existing tetapi hasil unavailable/timeout tidak menunda tombol navigasi dan tidak menjadi bukti thread tampil.

## 8. Urutan implementasi dalam satu fase M4

1. **Contract gate:** catat sumber resmi, verified bundle ID, mapping IDs dan root constraints, outcome semantics, serta matrix host pending. Developer menyediakan bukti live; AI tidak meluncurkan thread/config testing nyata tanpa instruksi.
2. **Navigation boundary:** extend navigator dan URL validation; tambahkan injectable workspace/deadline, targeted delivery, activation fallback, dan finite diagnostics. Tulis meaningful hermetic tests bersama boundary.
3. **Preference dan wiring:** satu preference Nudge, dependency injection pada AppState, captured click context, request tokens, dan common action untuk attention/session row.
4. **Recovery UX:** toggle/menu, status Opening, finite issue text, activation-only retry; preserve pending dan geometry/UI pengguna.
5. **Automated verification:** build dan relevant/full hermetic suite melalui scheme existing; check diff dan privacy invariants. Test tidak memakai workspace asli atau app launch nyata.
6. **Handoff:** tulis M4 verification dengan hasil aktual, pending host matrix, limitations, dan langkah manual bernomor. Setelah developer memverifikasi M4, berhenti; jangan lanjut M5/M6 tanpa instruksi.

## 9. File yang disentuh saat implementasi

| File | Perubahan yang diizinkan |
|---|---|
| `Nudge/Integration/Codex/Navigation/CodexNavigator.swift` | Request/outcome, URL validation, policy, targeted delivery/fallback, injectable boundary/deadline, diagnostics |
| `Nudge/App/AppState.swift` | Common action, captured context, preference, injected navigator, current-only feedback, request lifecycle |
| `Nudge/UI/PlaygroundMenuView.swift` | Precise toggle dan activation-only recovery/menu action |
| `Nudge/UI/NotchRootView.swift` | CTA/recovery feedback minimal; preserve hunk UI/mascot pengguna |
| `NudgeIntegrationTests/CodexNavigatorTests.swift` (baru) | Fake workspace/deadline, isolated preference, URL policy, and captured context |
| `NudgeIntegrationTests/CodexEventIngressTests.swift` | Pindahkan URL-only tests ke navigator tests tanpa mengubah ingress tests |
| `Nudge.xcodeproj/project.pbxproj` | Source/test membership yang diperlukan saja; preserve perubahan existing |
| `docs/Nudge-M4-Codex-Contract.md` (baru) | Research, identity/bundle contracts, evidence matrix, limitations |
| `docs/Nudge-M4-Verification.md` (baru) | Hasil automated aktual dan handoff manual |
| `docs/Nudge-M4-Implementation-Plan.md` | Status plan/hasil keputusan kontrak setelah implementasi |

Target integration tests saat ini hostless. Jangan mengubahnya menjadi hosted app tests atau compile seluruh AppState/UI demi menguji navigation policy. Jika context guard perlu diuji secara hermetic, ekstrak helper kecil `Nudge/Integration/Codex/Navigation/CodexNavigationContext.swift` yang benar-benar dipakai AppState, dan tambahkan membership; tidak membuat salinan logic khusus test. Native feedback/focus/collapse tetap diverifikasi developer. Perubahan `PresentationReducer`/`SessionReducer` tidak direncanakan karena navigation tidak memutasi semantic session.

File di luar daftar tidak di-refactor tanpa alasan tertulis dan kebutuhan fase yang konkret. Saat ini hanya dokumen plan ini yang dibuat; tabel merupakan allowlist implementasi mendatang.

## 10. Meaningful automated tests dan commands

Tests harus memverifikasi perilaku pada boundary, bukan hanya menyamai implementation:

1. Precise Off/default absent: nol URL delivery, satu activation; hasil tetap berguna tanpa metadata reader/socket.
2. Valid/eligible ID: URL mengandung satu encoded ID; delivery menargetkan aplikasi hasil bundle lookup, bukan default scheme handler. No fallback berulang setelah callback sukses.
3. Missing/invalid/reserved ID: tidak ada deep link atau new-thread launch; satu activation fallback.
4. Native rejection/error: satu targeted attempt lalu satu activation; outcome menyebut degradation. App unavailable/fallback failure menghasilkan finite error yang dapat ditampilkan.
5. Native callback tidak datang: deadline melepaskan Opening, menjalankan fallback sesuai budget, tanpa hang; callback terlambat tidak mengubah outcome atau menggandakan aksi.
6. Rapid clicks, sleep/cancellation, turn/session/interaction berubah: tujuan tetap dari click awal; stale receipt/error tidak diterapkan ke konteks baru dan gate dilepas sekali.
7. Navigation success/failure/Off tidak menghapus pending question/permission, tidak menyelesaikan turn, dan tidak memicu completion. Kombinasikan context tests dengan reducer fixtures existing tanpa menjalankan app live.
8. Missing/archived simulasi tanpa host acknowledgment tetap menghasilkan delivery-unverified, bukan exact success atau alasan archived yang dibuat-buat. Known rejection mengaktifkan fallback.
9. Preference persist/read memakai isolated suite; raw ID/path/error sentinels tidak muncul di diagnostic strings.

Perintah saat implementasi, memakai shared scheme `Nudge` yang sudah mencantumkan kedua test targets:

```bash
xcodebuild -list -project Nudge.xcodeproj
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test
git diff --check
```

Build/tests belum dijalankan ulang dalam sesi pembuatan plan karena source aplikasi tidak diubah. Hasil M3 bersifat historis, bukan hasil M4. Catat limitation bila toolchain/test membership tidak tersedia; successful URL fixture tidak membuktikan Desktop navigation.

## 11. Verifikasi manual oleh developer

Gunakan sandbox project dan workflow yang dapat dipulihkan. Desktop/CLI dan new/resumed dicatat terpisah; jangan menjalankan keputusan permission lewat Nudge.

1. Catat macOS, Desktop versi/build/bundle ID, CLI versi, effective config roots/custom `CODEX_HOME`, trust status, serta status manual M1–M3. Cocokkan mapping hook session ID terhadap technical thread ID tanpa menyimpan konten percakapan.
2. Mulai local thread langsung dari Desktop, pindah ke aplikasi lain, aktifkan precise navigation, lalu klik row Nudge. Pastikan thread yang dimaksud tampil; catat targeted delivery terpisah dari hasil visual.
3. Resume thread Desktop dan ulangi tanpa terminal launch/app-server Nudge. Verifikasi destination tidak bergantung pada `SessionStart` baru atau title lookup.
4. Pada Desktop, picu question/permission yang didukung host, lalu klik attention CTA. Pastikan thread/konteks relevan terbuka, pending tetap setelah klik, dan hanya native jawaban/keputusan serta relevant progress yang membersihkan card.
5. Matikan precise navigation. Klik attention dan row sesi; pastikan Desktop aktif/launch, monitoring tetap berjalan, pending tidak clear, dan Nudge tidak mencoba exact route.
6. Tutup Desktop lalu uji click dari aplikasi lain. Pastikan launch ke app yang benar. Uji multiple windows, Spaces, full-screen, dan displays; catat window/Space routing yang tidak dijamin, serta tidak ada focus steal akibat hover.
7. Gunakan ID yang hilang atau thread sandbox archived melalui tindakan developer. Jika host menolak, pastikan activation fallback; jika OS menerima tetapi thread tidak tampil, pastikan Desktop terbuka dan recovery activation-only/manual selection tersedia. Jangan auto-unarchive atau membuat thread baru.
8. Uji unavailable app/native open failure pada environment uji yang aman. Error harus terlihat, Opening tidak stuck, dan retry tidak menggandakan launches. Gunakan fake workspace untuk failure yang tidak praktis direproduksi secara manual.
9. Jalankan CLI new/resumed secara terpisah, termasuk custom config root. Catat apakah thread tersedia di Desktop. Nudge tidak menjanjikan terminal/tab routing atau bahwa membuka Desktop menyelesaikan request CLI. Jalur tanpa verified mapping memakai activation-only.
10. Klik lalu cepat berpindah selection/session; buat attention baru saat operasi in-flight, dan uji sleep/wake. Jangan ada error/receipt lama pada card baru, completion replay, atau callback yang collapse attention baru.
11. Uji toggle setelah relaunch Nudge, keyboard/VoiceOver, narrow fallback/physical notch, Reduce Motion, scroll cap existing, dan recovery copy. Navigasi tidak memperbesar panel atau mengganti artwork/motion existing.
12. Tutup/crash Nudge ketika Codex bekerja atau waiting. Codex tetap usable tanpa auto-allow. Inspect diagnostics untuk kebocoran ID/URL/path/preview, dan pastikan M4 tidak mengubah hooks/config Codex.

Format bukti: **host/version / new atau resumed / config+trust / precise On atau Off / identity mapping / native delivery outcome / observed thread+window / pending behavior / result atau limitation**. Status `pending`, `passed`, `failed`, atau `unsupported` selalu disertai evidence; fixture/OS acceptance tidak mengubah hasil visual menjadi passed.

## 12. Kriteria selesai dan handoff

- [ ] Attention dan row sesi memakai navigator/policy yang sama dan captured target yang benar.
- [ ] Local thread valid benar-benar tampil pada Desktop untuk kontrak/version yang diverifikasi; new dan resumed dibuktikan developer.
- [ ] Precise Off, missing/invalid ID, route rejection, dan timeout memiliki activation fallback atau visible final error bila app unavailable.
- [ ] Accepted-but-unverified missing/archived route tidak diklaim sukses exact; Desktop activation dan recovery tetap tersedia.
- [ ] Desktop/CLI evidence terpisah; origin/root uncertainty dan unsupported CLI visibility dicatat tanpa mengurangi acceptance Desktop.
- [ ] Navigation tidak resolve pending, mengubah turn phase, atau replay motion; stale callback aman.
- [ ] Hooks/wire/config tetap kompatibel; privacy dan Nudge-unavailable invariants dipertahankan.
- [ ] Debug build, relevant/full hermetic suite, dan diff checks benar-benar dijalankan; limitations dicatat.
- [ ] Developer menyelesaikan langkah manual sesuai kriteria, atau bagian pending tetap ditandai dan M4 belum disebut accepted.
- [ ] Handoff memuat files changed, hasil test, host matrix, limitations, serta recovery toggle/activation-only.
- [ ] Bila commit diminta pengguna: commit fase terpisah, misalnya `feat(navigation): add precise Codex routing with activation fallback`; perubahan pengguna yang tidak terkait dikecualikan.

Berhenti setelah handoff M4. Build/hermetic tests dapat menyelesaikan source verification; acceptance navigasi live/visual tetap membutuhkan developer. M5 optional bukan kelanjutan otomatis.

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
