# Nudge — Implementation Plan: Activity Detail dan Active Sessions

Tanggal plan: **2 Oktober 2026**. Implementasi: **3 Oktober 2026**. Status: **source + hermetic tests implemented; manual macOS and live host verification pending**.

Sumber kebenaran: [project brief](Nudge-Project-Brief.md), [AGENTS.md](../AGENTS.md), source working tree saat peninjauan, serta permintaan eksplisit pengguna. Dokumen ini menjadi follow-up terbatas terhadap event spine dan metadata enrichment M1/M2, dengan perubahan presentation yang secara eksplisit diminta pengguna. Ini bukan eksekusi seluruh milestone M2–M6.

## 1. Hasil yang dituju dan scope aktif

Pengguna berpindah dari Codex ke app lain → membuka Nudge → langsung tahu **project mana, chat mana, statusnya apa, dan aktivitas apa yang teramati**. Jika beberapa sesi sedang aktif, semuanya tampil sebagai baris di expanded window, termasuk dua chat dalam project yang sama. Tinggi maksimum viewport daftar hanya **10 pt lebih tinggi dari expanded monitor sekarang**; isi selebihnya diakses dengan scroll, tanpa menunggu ruang layar habis.

Permintaan terbaru pengguna mengizinkan **semua sesi aktif di expanded window**. Ini mengesampingkan batas single-context di AGENTS.md/brief untuk tampilan expanded dalam scope ini. Collapsed dan hover peek tetap memprioritaskan satu focused session. Tidak menambahkan conversation history, prompt editor, provider lain, atau fleet controls.

Deliverable satu scope implementasi ini:

- Deskripsi aktivitas lebih informatif, berdasarkan tool event yang terverifikasi; task commentary bebas tidak direka.
- Project dan identitas sesi terpisah; karena hook tidak memberi judul chat, row memakai short session ID sebagai fallback.
- Semua sesi aktif yang terdeteksi ditampilkan dalam expanded window.
- Tinggi panel mengikuti isi hingga maksimum expanded monitor saat ini + 10 pt, lalu scroll dengan scrollbar native.
- Badge **Live dihapus**; badge Demo tetap untuk konten simulasi.
- Tests boundary, catatan kontrak, dan handoff manual untuk Desktop serta CLI.

Dokumen ini menjadi plan sekaligus batas scope implementation. Live hook/config nyata tidak disentuh. Untuk hasil build/test dan handoff, lihat [verification record](Nudge-Activity-Context-Verification.md). Implementasi memakai helper/wire baseline saat ini dan menambahkan v2; bagian batas upgrade dicatat di bawah.

## 2. Diagnosis dari implementasi saat ini

| Area | Fakta source | Dampak |
| --- | --- | --- |
| State | `SessionPhase` sudah membedakan `thinking` dan `toolUse`; selesai tool terakhir kembali ke thinking | Working tidak seluruhnya dipetakan ke thinking. Thinking bisa valid ketika belum ada tool aktif, tetapi tidak menjelaskan konteks pekerjaan |
| Adapter | `CodexHookAdapter.activity(for:)` memakai tool name; `tool_input` dan assistant text dibuang | Bash selalu “Running command”, edit selalu “Editing files”; tujuan pekerjaan belum tersedia |
| Wire | Envelope v1 memvalidasi kombinasi category/summary/symbol terhadap beberapa literal tetap | Mengubah adapter saja menjadi verbose akan membuat validasi wire menolak summary baru |
| Metadata | `projectLabel` berasal dari basename `cwd`; `sessionID`/`turnID` tersedia, tanpa chat title atau host asal | “Nudge” pada screenshot adalah label folder project, bukan judul chat |
| Monitor | Actor menyimpan dictionary banyak sesi, tetapi `consume`/`currentSnapshot` hanya mengembalikan focused snapshot | UI tidak menerima daftar sesi lain |
| View | `liveMonitor` menampilkan project, phase, optional currentTool, dan badge Live | Identitas chat dan daftar aktif memang belum dirender; `activityLabel` tidak dipakai sebagai baris detail live |
| Geometry | Expanded height tetap 160 pt + camera band; hosting canvas dihitung dari ukuran mode tetap | Menambahkan daftar ke VStack saja berisiko clipping dan hit region yang salah |

Baseline ini mengacu pada working tree, bukan hanya HEAD. Dokumen M2 lama masih menyebut beberapa celah yang sudah berubah di source; jangan menganggap status historis dokumen sebagai bukti bahwa implementasi atau manual QA telah selesai.

## 3. Kontrak, sumber data, dan batas bukti

Dokumentasi resmi ditinjau pada tanggal plan:

- Hook membawa `session_id`, `cwd`, dan field tool-specific pada `PreToolUse`. Ini dapat menjadi dasar identitas dan ringkasan tool lokal. Dokumentasi tidak menjamin semua tool memiliki human-readable description. [Hooks](https://learn.chatgpt.com/docs/hooks).
- `transcript_path` bukan kontrak format transcript yang stabil. Plan ini tidak menjadikan transcript scraping sumber aktivitas wajib. [Hooks](https://learn.chatgpt.com/docs/hooks).
- App-server mendokumentasikan `thread.name` pada response metadata dan agent messages dengan phase commentary/final_answer. Ini adalah kandidat enrichment, **bukan bukti bahwa koneksi app-server milik Nudge dapat subscribe aktivitas thread Desktop yang sedang berjalan**. [App-server](https://learn.chatgpt.com/docs/app-server).

Sebelum mengubah adapter live, developer perlu mencatat versi Desktop/CLI saat pengujian, effective config, trust/reload, dan capture yang disanitasi untuk new/resumed thread, tool start/finish, concurrent sessions, dan field deskripsi. Kandidat historis di [M1 contract](Nudge-M1-Codex-Contract.md): Desktop `26.928.31416` build `12553`, CLI `0.154.0`; belum diperiksa ulang pada sesi plan ini.

Pisahkan dua jenis teks:

1. **Tool summary**: tindakan yang dapat dibuktikan dari tool event, misalnya “Running tests” atau “Editing SessionReducer.swift”.
2. **Task progress**: deskripsi seperti “Adding monitor edge-case tests…”, yang mungkin berasal dari commentary/status host. Jangan menghasilkan klaim ini hanya karena tool bernama Bash atau apply_patch.

Research gate dalam scope ini: identifikasi asal teks progress yang dimaksud pengguna pada host yang ditargetkan, lalu buktikan apakah ada jalur lokal yang didukung untuk membacanya dan mencocokkannya ke session/turn. Jika tidak ada, kirim hasil tool-summary dengan limitation eksplisit; **jangan menyebut exact Codex progress parity atau exact chat title telah selesai**. Jika jalurnya membutuhkan subsystem enrichment besar, tulis proposal terpisah sebelum memperluas implementasi. Tidak menjalankan/resume turn melalui app-server hanya untuk mengamati thread.

Hasil gate implementasi (3 Oktober): kontrak hook yang didokumentasikan menyediakan `tool_input` untuk tool tertentu, sehingga adapter memetakan sejumlah command sederhana ke ringkasan kategori tetap tanpa mengirim command. Event hook yang ditinjau tidak menyediakan task commentary atau chat title; integrasi metadata lokal lain tidak dibuktikan untuk thread Desktop aktif, jadi keduanya tetap deferred. Saat turn sedang thinking tanpa tool aktif, label `Thinking…` memang satu-satunya state yang didukung. UI menampilkan “Working” plus tool summary saat toolUse terdeteksi dan tetap memakai fallback ketika tidak ada sinyal lebih spesifik.

Judul chat dapat di-enrich melalui metadata read-only yang terbukti mengakses store/config host yang benar. Jika app-server metadata digunakan, minta summary tanpa turns dan hanya project sesi yang sudah teramati; jangan mengambil conversation history. Tidak membaca database internal Codex yang tidak terdokumentasi secara diam-diam. Host asal hanya ditampilkan jika ada provenance terverifikasi; pilihan host di menu Nudge bukan bukti asal event.

## 4. Model dan boundary

```text
Desktop / CLI hooks
  → NudgeBridge / CodexHookAdapter: validasi + bounded tool summary
  → versioned wire / owner-only Unix socket
  → CodexEventMonitor actor
       ├─ SessionReducer: phase, tool lifecycle, turn identity
       ├─ metadata merge: project, optional chat title, provenance
       ├─ list projection: seluruh sesi aktif terdeteksi
       └─ FocusPolicy: satu sesi untuk collapsed / peek
  → satu immutable monitor snapshot dengan revision
  → AppState @MainActor
  → PresentationReducer + list presentation
  → SwiftUI rows / NSPanel geometry

Optional verified local metadata/progress source
  → normalization + exact identity check → monitor actor
```

Tambahkan model minimal sesuai boundary yang diperlukan:

- Session context: stable `sessionID`, optional verified `threadID`, project label, optional `chatTitle`, optional source host, provenance dan metadata revision/time.
- Simpan urutan awal current turn (`turnStartedAt` dan tie-breaker deterministik) terpisah dari `lastActivityAt`. Prompt/turn start valid memberi urutan baru; resume tanpa start menggunakan progress pertama current turn sebagai waktu mulai teramati. Duplikat, enrichment dan tool berikutnya tidak mengubahnya. Ini bukan klaim waktu mulai asli bila Nudge baru mengamati sesi di tengah turn.
- Activity detail: bounded text, jenis `toolSummary` atau `taskProgress`, session/turn/tool identity yang relevan, observation time dan sumber. Phase tetap enum semantik; setiap deskripsi bukan phase baru.
- Monitor snapshot: `focusedSessionID`, focused activity snapshot, visible session snapshots, serta revision monotonik. Satu publikasi menghindari focus dan daftar berasal dari state berbeda.

Jangan menganggap hook session ID pasti sama dengan navigation thread ID tanpa verifikasi. Identitas internal selalu ID penuh; potongan ID hanya untuk label.

Metadata update tidak mengubah `lastActivityAt`, menciptakan turn, meresolve pending, atau memainkan completion. New turn membersihkan progress turn lama. Late enrichment hanya berlaku untuk session/turn yang cocok dan tidak boleh menghidupkan kembali terminal turn. Urutkan ingress dan tolak revision UI lama; detached Tasks per event pada delegate saat ini perlu ditinjau agar publikasi tidak terbalik.

Untuk concurrent tools, pilih aktivitas berdasarkan ordering start/progress yang teramati, bukan urutan alfabet `toolCallID`. Jika diperlukan, tampilkan “+N tools” kecil; jangan membuat tool IDs menjadi penentu aktivitas utama.

## 5. Deskripsi aktivitas yang akurat dan privat

Urutan informasi per sesi:

1. Attention/failure/interruption yang valid selalu punya prioritas.
2. Task progress terverifikasi untuk current turn dapat menjadi detail utama; current tool tetap bisa tampil sebagai baris pendukung.
3. Tanpa task progress, gunakan current tool summary yang spesifik dan aman.
4. Tanpa keduanya, gunakan phase fallback seperti “Thinking…” atau “Working”.

Progress message adalah update teramati, bukan bukti bahwa sebuah tool masih berjalan. Jika yang tersedia hanya commentary terakhir, beri konteks “Latest update”; setelah tool finish jangan mempertahankan “Running tests” sebagai current tool. Tidak ada timeout inactivity yang membuat thinking/long tool/pending menjadi selesai.

Normalisasi di bridge sebelum wire:

- Gunakan field deskripsi hanya pada tool/field yang kontraknya sudah diverifikasi. Tidak mem-forward arbitrary `description` dari seluruh MCP payload.
- Untuk shell, kenali invocation sederhana yang disetujui seperti runner tests/build/read/search. Hasilkan label tindakan; jangan tampilkan command mentah. Compound command yang ambigu fallback ke label generik.
- Untuk edit, jika target filename dapat diekstrak dengan parser bounded tanpa membawa patch content, tampilkan basename; ambiguous/multiple targets menjadi “Editing files” atau count aman.
- Jangan membaca file target atau menjalankan command dari payload untuk memperoleh label.
- Batasi detail awal ke 120 karakter; buang control characters, sanitasi URL credentials/token patterns, path personal, dan field sensitif. Free-form yang tidak dapat disanitasi dengan aman ditolak ke fallback. Batas karakter saja bukan jaminan privacy.
- Chat title juga user content: dibatasi dan tidak dicatat di diagnostics atau disimpan sebagai transcript. Jangan membuat judul dari prompt mentah secara default.

Update privacy fixtures agar summary yang diizinkan boleh lewat, tetapi prompt, command/output mentah, patch/file contents, full assistant message, transcript path, dan secret sentinels tetap tidak mencapai wire/log. Enrichment/progress hanya berada di memori, tanpa cache transcript atau persistence baru.

## 6. Expanded window dan identitas chat

Pertahankan opaque black, SF typography, original Nudgie, camera exclusion, dan anchor notch yang sama. Gunakan daftar baris langsung dengan separator tipis; tidak perlu nested cards.

Contoh struktur, seluruh isi berikut **contoh simulasi**:

```text
Codex · 2 active sessions

Nudge
Monitor edge-case tests        Working
Adding monitor edge-case tests…
Running tests

Invoice
Fix invoice rounding          Thinking…
Reviewing rounding behavior…
```

- **Project** dan **chat title** menjadi dua informasi berbeda. Judul asli jika tersedia; fallback jujur `Session a3f92c`. Buat short ID cukup panjang agar unik dalam daftar. Project belum diketahui menjadi `Unknown project`, tanpa mengklaim nama repository dari data yang belum ada.
- Satu row per stable session ID, bukan per project: dua chat Nudge tetap dua row. Jika basename project sama untuk directory berbeda, disambiguasi memakai metadata aman yang tersedia; jangan menampilkan absolute path personal.
- State + symbol terlihat di setiap row, activity detail maksimum dua baris, teks panjang ditruncate tanpa resize per karakter. Full bounded label dapat diakses VoiceOver/help.
- Header count mengacu ke sesi aktif yang **terdeteksi**, bukan seluruh chat yang dibuka Codex. Jangan memakai badge Live atau membuat klaim monitoring lengkap sebelum host coverage teruji.
- Aktif = thinking, toolUse, waitingPermission, waitingInput. Discovered/idle bukan sesi bekerja. Terminal focused session masih boleh menjadi transient row selama grace window; bukan history dan tidak dihitung active.
- Expanded menampilkan seluruh active set, tanpa top-N yang menyembunyikan sesi. Ketika cuma satu sesi, row memakai struktur sama. Tidak ada aktivitas: empty state yang jelas.
- Rekomendasi urutan expanded: **sesi yang membutuhkan jawaban/izin di atas**, lalu sesi aktif berdasarkan **current turn yang paling baru mulai atau dilanjutkan** (descending `turnStartedAt`). Di dalam kelompok attention, urutkan berdasarkan awal pending interaction, dengan tie-breaker stable session ID. Jangan memakai `lastActivityAt` sebagai sort key: sesi yang sering memanggil tool tidak boleh terus melompat ke atas.
- New/resumed turn yang valid boleh membawa sesi ke atas kelompok aktif; metadata update, tool progress biasa dan duplicate events tidak mengubah urutan. Memilih row hanya memberi penanda selected/focused, tanpa memindahkannya ke atas daftar. FocusPolicy collapsed/peek tetap terpisah dari sort order expanded.
- ID row stabil. Ketika pengguna sedang scroll, pertahankan row/offset yang sedang dibaca saat sesi baru masuk atau attention naik; jangan otomatis scroll ke atas. Sesi terbaru tetap berada di atas dalam data dan terlihat ketika pengguna kembali ke atas daftar. Akhir pending mengembalikan row ke posisi berdasarkan turn start, tanpa menghilangkan sesi aktif.
- Pemilihan row mengubah focused context untuk collapsed/peek. **Tidak mengklaim memilih row membuka exact Codex thread**; precise navigation M4 tetap terpisah. Tidak perlu menambah routing baru untuk menyelesaikan scope ini.
- Collapsed dan peek tetap kecil dan satu konteks. Expanded dan attention yang terbuka dapat memuat seluruh daftar aktif; pending tidak tersembunyi oleh row tool atau hilang saat memilih sesi lain. Ini tidak memasang live permission/question hooks baru.
- Hapus `NotchBadge(title: "Live")` pada monitor live. Demo tetap berlabel Demo pada setiap skenario simulasi.

## 7. Compact height cap dan native window behavior

Content height = camera band + padding/header + bounded row heights + separators. Pertahankan lebar incumbent sekitar 380 pt sebagai starting point. **Batas tinggi monitor/list: expanded height incumbent + 10 pt**, bukan tinggi layar. Pada source saat plan, expanded fallback = 160 pt sehingga cap = **170 pt**; pada layar notch cap = **notchHeight + 170 pt**. Interpretasikan permintaan “sekitar 10px” sebagai 10 logical points pada native macOS, agar konsisten pada Retina dan non-Retina. Nilai ini menjadi satu constant yang mudah dituning setelah developer QA.

Visible height = minimum(content height, monitor/list cap, ruang aman layar di bawah anchor). Batas layar hanya safety clamp untuk display sangat kecil. Header/count tetap di luar scroll viewport; daftar row menggunakan ScrollView dengan native vertical scroll indicator saat overflow. Semua row tetap ada di data dan dapat dijangkau, tanpa top-N. Dua atau lebih sesi boleh langsung membutuhkan scroll; jangan menaikkan cap untuk menampilkan semuanya sekaligus. Pending tetap punya row prioritas di atas; ukuran dedicated attention/confirmation yang sudah ada tidak diperkecil oleh cap monitor ini.

Tinjau geometry **dan hosting canvas** bersama agar canvas menampung cap monitor baru serta ukuran attention/confirmation yang sudah ada; panjang seluruh isi scroll tidak menjadi tinggi canvas. Transparent area di luar visible shell tidak boleh mengambil klik. Selaraskan clipping, visibleSizeChanged, panel tracking, screen refresh, dan hover hit region. Scroll di dalam panel tidak memicu collapse.

Shell tetap tumbuh dari notch anchor yang sama. Perubahan jumlah row boleh memakai transition terkontrol; perubahan teks aktivitas tidak menyebabkan height/motion loop. Preserve scroll/focus saat update dan session removal; jika selected session berakhir, pilih context berikut sesuai focus policy tanpa replay completion. Sleep membatalkan motion/timers; wake mengambil satu current list snapshot, tanpa replay row masuk/completion. Reduce Motion menggunakan update langsung.

## 8. Compatibility, backup, dan recovery sebelum implementasi

**Wire berubah** jika bounded summaries menggantikan literal whitelist atau metadata baru ditransport. Jangan menambahkan field ke v1 secara diam-diam: decoder lama menolak unknown keys.

- Definisikan envelope **v2** untuk payload baru dan pertahankan decoding v1 beserta validator legacy-nya pada app baru. Frame/identity limits, unknown-key rejection, ownership dan peer validation tetap berlaku.
- Helper lama → app baru: v1 tetap bekerja dengan fallback generik. Helper baru → app lama: tidak kompatibel untuk v2; fail-fast/no-op, diagnostic aman, Codex tetap bekerja. Jelaskan mismatch di integration status.
- App/helper baru dirilis berpasangan. Tinjau `BridgeHelperInstaller` agar update helper efektif dan reversible, bukan hanya file target aplikasi. Hook command tetap sama sehingga trust definition tidak perlu berubah jika kontrak host mengizinkannya; verifikasi bukan asumsi.
- Schema tidak dinegosiasikan melalui permission response. Deadline bridge dan neutral output event yang sudah ada tetap dipertahankan.
- Scope ini tidak membutuhkan hook event baru atau mutation `config.toml`/`hooks.json`. Jika ternyata field baru memerlukan perubahan handler, revisi plan lebih dahulu: exact Nudge ownership, private backup sebelum mutation, parse-before-write, preserve foreign hooks, atomic replacement, no-op jika identik, dan uninstall hanya Nudge entries.
- Recovery: rollback app/helper bersama; helper sebelumnya tetap bisa diterima sebagai v1 oleh app baru. Preserve backup/config bytes. Jangan menghapus config/backup atau mereset trust untuk mengatasi mismatch.

Tidak mengubah konfigurasi Codex nyata atau menjalankan live verification otomatis dalam sesi ini maupun implementasi tanpa instruksi eksplisit developer. Automated tests memakai fixtures, temporary config/socket, dan sandbox project.

## 9. Daftar file dalam scope implementasi

| Boundary | File |
| --- | --- |
| Domain/context/activity | `Nudge/Core/NudgeModels.swift`, `Nudge/Core/Events/NudgeEvent.swift`, `Nudge/Core/Reducer/SessionReducer.swift` |
| Focus/list projection | `Nudge/Core/Reducer/FocusPolicy.swift`, `Nudge/Services/CodexEventMonitor.swift` |
| Normalization/wire | `Nudge/Integration/Codex/Hooks/CodexHookAdapter.swift`, `Nudge/IPC/WireEnvelope.swift` |
| Delivery/helper update | `Nudge/App/NudgeAppDelegate.swift`, `Nudge/Services/BridgeHelperInstaller.swift` jika dibutuhkan paired upgrade |
| UI state/presentation | `Nudge/App/AppState.swift`, `Nudge/Core/PresentationReducer.swift` |
| Native panel/list | `Nudge/UI/NotchRootView.swift`, `Nudge/UI/NotchComponents.swift`, `Nudge/UI/NotchGeometry.swift`, `Nudge/UI/NotchPanelController.swift` |
| Demo | `Nudge/Debug/PlaygroundScenario.swift`, `Nudge/UI/PlaygroundMenuView.swift` untuk 1/2/banyak sesi simulasi |
| Tests | `NudgeCoreTests/{SessionReducerTests,FocusPolicyTests,PresentationReducerTests,WireValidationTests,NotchGeometryChecks,NotchLayoutChecks}.swift`, `NudgeIntegrationTests/{WireAdapterTests,BridgeFailureTests}.swift`, fixtures Codex yang relevan |
| Docs | Dokumen ini, `docs/Nudge-M1-Codex-Contract.md`, catatan verification baru `docs/Nudge-Activity-Context-Verification.md`, serta `PRODUCT.md`/`DESIGN.md` setelah behavior berubah |
| Project | `Nudge.xcodeproj/project.pbxproj` hanya jika file baru membutuhkan target membership |

Jika research gate lolos, normalizer/enricher kecil dapat ditempatkan di `Nudge/Integration/Codex/` dengan tests khusus dan provenance tertulis. Penambahan file di luar daftar harus memiliki alasan scope tertulis sebelum edit. Jangan refactor installer, mascot, navigation, atau subsystem lain sebagai sampingan.

## 10. Urutan pengerjaan dalam satu scope

1. Tinjau perubahan working tree dan hasil handoff M1/M2; catat bukti yang masih pending. Lengkapi field/source contract research untuk descriptions, title, identity, dan asal host.
2. Implementasikan normalization aman + compatibility v1/v2 dengan tests wire/privacy/failure. Tambahkan enrichment hanya pada jalur yang terbukti, tanpa ketergantungan lifecycle terhadap enrichment.
3. Tambahkan context/detail dan immutable multi-session projection. Pastikan list dan focus dipublikasikan secara berurutan dan completion tetap idempotent.
4. Implementasikan rows, title fallback, selection, hapus Live, serta dynamic geometry/canvas/scroll. Tambahkan skenario Demo yang jelas.
5. Jalankan build/tests dan static layout checks yang relevan; dokumentasikan limitations lalu serahkan verifikasi manual. Berhenti setelah scope ini, tanpa lanjut M3–M6.

## 11. Meaningful automated verification

- Adapter: description tersedia/absen/malformed, bounded filenames, test/build categorization, compound commands ambigu, MCP field yang tidak dikenal, truncation Unicode/control characters, secret/path sentinels tidak bocor.
- Wire: valid v1/v2 round-trip, versi/field/type/category/symbol salah, oversize, unknown keys, missing identity; helper unavailable/deadline/no-op tidak berubah.
- Reducer: tool start/finish, concurrent tools, late metadata tanpa SessionStart, title enrichment/rename, mismatch turn/session, new turn clears old detail, quiet long-running work/pending tetap aktif.
- Monitor/list: 0/1/2/banyak sesi, dua chat project sama, short-ID collision, attention priority, newest turn first, resume tanpa start, duplicate start tidak menaikkan posisi, tool/enrichment/selection tidak mengubah sort order, semua aktif ikut projection, terminal grace, revision lama ditolak, background completion tidak replay saat selection/wake.
- Presentation/geometry: count dan title update tanpa celebration/peek timer baru; multiline bounds, monitor/list cap tepat incumbent + 10 pt (170 pt fallback / notchHeight + 170 pt notch), tambahan sesi tidak melewati cap, scrollbar saat overflow, dedicated attention size tetap benar, non-notch Dock/visible frame, negative display origin, scroll viewport berada dalam canvas, transparent region tidak menjadi hit target.
- Static render untuk 1/2/banyak sesi, long/missing titles, long detail, mixed phases, screen pendek, notch/fallback. Static render bukan bukti runtime mouse/focus/Spaces.

Jalankan saat implementasi:

```bash
xcodebuild -list -project Nudge.xcodeproj
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test
git diff --check
```

Pada sesi planning ini build/tests aplikasi tidak dijalankan; hasil lama tidak dihitung sebagai validasi perubahan yang direncanakan.

## 12. Kriteria selesai dan verifikasi manual oleh developer

Scope selesai ketika project + chat identity jelas, activity detail mencerminkan data teramati, semua sesi aktif terdeteksi dapat dijangkau dalam expanded window dengan monitor/list cap incumbent + 10 pt dan scroll, urutan attention lalu newest turn tidak melompat pada tool update, Live hilang, dan lifecycle/privacy/geometry tetap benar. Exact title/progress parity hanya dicatat lulus jika sumbernya dibuktikan; fallback harus diberi limitation, bukan dilaporkan sebagai exact mirror.

Verifikasi manual oleh developer:

1. Catat versi, effective configuration, trust/reload dan event coverage Desktop/CLI secara terpisah. Buat new local thread langsung dari Desktop, lalu resume thread tanpa terminal launch; cocokkan project/chat identity dan tool/progress detail dengan Codex.
2. Uji read, edit, test/build, unknown tool dan thinking tanpa tool. Pastikan detail informatif bila data tersedia, fallback jujur bila tidak, dan tool selesai tidak terus diklaim sedang berjalan. Cocokkan contoh verbose progress hanya jika source gate sudah lolos.
3. Jalankan dua chat sekaligus dalam project sama dan chat lain di project berbeda. Expanded harus menampilkan setiap sesi satu kali, identitas berbeda, dan update pada row yang benar. Mulai/resume turn berikutnya: sesi tersebut naik di kelompok aktif; tool calls biasa tidak mengubah urutan. Attention tetap di atas. Pilih row: focused context collapsed/peek berubah tanpa memindahkan row.
4. Jalankan workflow setara di CLI; jika Desktop dan CLI aktif bersamaan, keduanya muncul. Jangan mengklaim host label benar sebelum provenance dicocokkan. Session yang belum pernah teramati Nudge tidak dianggap sudah terdeteksi.
5. Bandingkan expanded monitor baru dengan baseline: maksimum hanya 10 pt lebih tinggi (170 pt fallback / notchHeight + 170 pt notch), termasuk ketika banyak sesi. Scroll sampai row terakhir dengan scrollbar native; uji update selama scroll, sesi selesai/baru masuk, long titles, display kecil, notch dan external/no-notch, Dock/menu auto-hide. Pastikan row/offset yang sedang dibaca terjaga, tidak clipping, auto-scroll ke atas, collapse saat scroll, atau kehilangan focus.
6. Uji perhatian yang sudah tersedia, completion, failure/interruption, pindah selection, sleep/wake, Reduce Motion, keyboard dan VoiceOver. Pending tetap terlihat; metadata update/wake tidak memainkan celebration ulang.
7. Tutup Nudge saat kedua host bekerja dan uji mismatch/rollback helper pada sandbox. Codex tetap berlanjut, tanpa auto-approval atau changed output. Pastikan badge Live hilang dan semua preview simulasi tetap berlabel Demo.

Commit, jika diminta, terpisah untuk scope ini dengan Conventional Commits berbahasa Inggris, misalnya `feat(ui): show active session context and activity details`. Jangan memasukkan perubahan pengguna yang tidak terkait.

## ATURAN PENGERJAAN

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
