# Nudge — Implementation Plan: Arsitektur App dan Fondasi M0

Tanggal: 1 Oktober 2026. Status: **implementasi M0 berjalan; lihat catatan build dan QA di `Nudge-M0-Verification.md`**.

Sumber kebenaran: [project brief](Nudge-Project-Brief.md) dan [AGENTS.md](../AGENTS.md). Fase aktif yang direncanakan: **M0 — Notch Playground**. Dokumen ini mencakup arsitektur awal dan urutan pekerjaan dalam satu fase; bukan izin melanjutkan M1.

Update implementasi 1 Oktober 2026: app shell, menu bar, notch panel/fallback, presentation reducer, dan simulator phase sudah ditambahkan. Test target dan hasil visual developer masih pending; status rinci ada di [catatan verifikasi M0](Nudge-M0-Verification.md). M1 belum dimulai.

## 1. Hasil yang ingin dicapai

Satu aplikasi native macOS bernama Nudge yang dapat dijalankan dari Xcode, hidup di menu bar, dan menampilkan satu konteks simulasi melalui notch overlay atau compact island pada layar tanpa notch. Developer dapat mengganti phase, mencoba hover/click/keyboard, serta menilai Nudgie dan motion sebelum menghubungkan aktivitas Codex nyata.

Workflow M0: **launch → pilih simulated phase → lihat status/pose → hover untuk peek → klik untuk expanded → simulated attention tetap terlihat → simulated progress membersihkan attention → completion sekali → kembali tenang**.

Scope tambahan sesuai instruksi pengguna: redesign lima keadaan dari screenshot (monitor, approval, question, minimized, confirmation). Gunakan native system type 11–14 pt untuk teks readable, SF Mono untuk file/path/diff/kode, hitam solid, satu focused-session row, metadata tenang, code preview monospace, dan action rows sederhana. Buang nested cards, gradient panel, uppercase playground labels, dan quota/multi-provider rows. Instruksi lanjutan pengguna mempertahankan ukuran/layout minimized saat ini (wing di sisi kamera); perubahan dimensi hanya untuk expanded/attention/confirmation. Klarifikasi UX terbaru: minimized tidak mengganggu menu bar; expanded boleh menutup item menu bar karena fokus pengguna berada pada Nudge. Approval/jawaban dan diff tetap fixture M0 berlabel Demo; receipt adalah feedback keputusan simulasi, bukan completion turn. Klik monitor membuka aplikasi host melalui navigator terisolasi; activation tidak menjamin routing tab/thread dan tidak menyelesaikan M1/M4. Kontrak live approval/question/deep link, hook/config, dan IPC tidak berubah.

File tambahan yang diperlukan untuk scope ini: `Nudge/Debug/PlaygroundScenario.swift` (fixture UI), `Nudge/UI/NotchComponents.swift` (tokens dan native button states), `Nudge/Integration/Codex/Navigation/CodexNavigator.swift` (app activation yang diminta), `NudgeCoreTests/PresentationChecks.swift` (timer/feedback invariants), `PRODUCT.md`, `.impeccable/surfaces/` (konteks/kontrak Impeccable), serta `DESIGN.md` dan `.impeccable/design.json` (kaidah visual yang benar-benar dibangun). `.gitignore` mengecualikan render/review cache Impeccable. Update source membership Xcode, AppState, model/reducer, geometry, panel controller, root view, menu simulator, dan verification record. AppDelegate menutup event-driven mouse monitors saat terminate; tidak ada polling hover. Fixture tests tidak meluncurkan Codex/Terminal; verifikasi manual menguji lima state, tombol, keyboard, camera exclusion, menu clicks, focus, motion, dan fallback. Tidak membaca transcript/config pengguna atau membuat approval nyata.

M0 selesai setelah build dan automated checks yang relevan lolos **serta developer memverifikasi visual/window behavior secara manual**. Build atau fixture yang lolos belum cukup untuk menyebut M0 selesai.

Follow-up motion sesuai laporan pengguna: focal moment adalah shell yang tumbuh dari notch dengan anchor tetap. AppKit tetap satu pemilik ukuran window, memakai deceleration tanpa overshoot; SwiftUI mempertahankan lebar akhir konten dan crossfade singkat agar teks tidak reflow selama resize. Exit lebih cepat daripada expand. Morph radius tidak boleh meloncat saat mode berubah. Tidak menambah loop idle/dependency; Reduce Motion meniadakan resize/crossfade. File yang disentuh: `NotchPanelController.swift`, `NotchRootView.swift`, `NotchComponents.swift`, `NotchGeometry.swift` (shared preferred size), geometry fixtures, surface/design records dan verification record. Tidak menyentuh hooks/config/wire. Build/fixtures memeriksa endpoint geometry; developer memeriksa rapid reversal, hover/pin/attention/receipt, sleep/wake dan perubahan Reduce Motion di tengah transisi. Frame-rate/smoothness tidak dibuktikan oleh static renders.

## 2. Kondisi awal dan scope

Repository saat plan dibuat hanya memiliki `AGENTS.md` dan `docs/Nudge-Project-Brief.md`. Working tree bersih. Toolchain yang diperiksa: Xcode 27.0 (27A266a), Swift 6.4, active developer directory `/Applications/Xcode.app/Contents/Developer`. Belum ada Xcode project, sehingga build/test aplikasi belum dapat dijalankan. Availability API tetap mengikuti deployment target macOS 15, bukan versi SDK terpasang.

**Dikerjakan di M0:** accessory shell, menu bar, satu NSPanel, screen geometry, empat presentation mode, semantic state untuk simulasi, original Nudgie, motion tokens, hover hysteresis, Reduce Motion, basic sleep/wake untuk presentation, dan playground controls.

**Ditunda:** NudgeBridge, IPC/socket, wire schema, hook/config installer, live SessionReducer, Codex navigation, transcript parsing, onboarding integrasi, launch at login, sound, updater, signing/notarization untuk distribusi. Jangan membuat target, folder kosong, atau protocol placeholder untuk subsystem tersebut.

Sleep/wake M0 hanya mengurus panel, motion, dan timer simulasi. Rekonsiliasi lifecycle session nyata tetap menjadi pekerjaan fase integrasi/hardening.

## 3. Keputusan arsitektur awal

| Area | Keputusan M0 | Alasan/boundary |
|---|---|---|
| Platform | macOS 15+, Swift 6 language mode | Baseline brief; gunakan API yang tersedia pada deployment target |
| Project | Satu `Nudge.xcodeproj` | Mudah dibuka, build, dan diverifikasi developer |
| Target | `Nudge` dan `NudgeCoreTests` | Helper/integration tests ditambahkan ketika subsystem nyata tersedia di M1 |
| App shell | SwiftUI `App` + AppKit `AppDelegate` | Composition SwiftUI; window/lifecycle dimiliki AppKit |
| App identity | `LSUIElement = YES`, accessory activation policy | Menu-bar companion; tidak membuka primary window saat launch |
| UI state | `@MainActor @Observable AppState` | Satu owner untuk current snapshot dan presentation; view hanya membaca/mengirim intent |
| Model | Value types semantic, tanpa SwiftUI/AppKit | UI tidak bergantung pada hook payload atau nama event provider |
| Reducer | Pure `PresentationReducer` | Hover, perhatian, transient completion, dan collapse tidak dicampur dengan lifecycle domain |
| Window | Satu retained `NSPanel` + `NSHostingView` | Mengontrol anchor, frame, input, Spaces, dan display changes |
| Mascot | Original SwiftUI Shape/Canvas | Tajam di ukuran kecil, tanpa dependency/asset raster pipeline |
| Motion | Semantic effects + centralized tokens | Cancelable, satu completion flourish, menghormati aksesibilitas |
| Persistence | Tidak diperlukan untuk simulasi M0 | Debug state reset saat launch; tidak membaca project/transcript/config pengguna |
| Dependencies | Apple frameworks saja | Tidak perlu DI framework, state library, project generator, atau backend |

`NudgeCoreTests` dibuat sebagai **unhosted macOS unit test bundle**. Hanya file production pure model/reducer/geometry yang dibutuhkan diberi membership pada app dan test target. Ini menguji kode production yang sama tanpa meluncurkan accessory app atau membangun module/package tambahan. Pastikan membership tidak memasukkan file UI/bootstrap; jangan membuat salinan implementation untuk tests.

Local Debug build memakai signing lokal yang tersedia dan tidak membutuhkan Developer ID release credentials. Bundle identifier ditetapkan sekali saat scaffold dan dicatat; signing team personal tidak di-hard-code untuk semua developer. Hardened runtime/release entitlements bukan bukti distribution readiness pada M0.

## 4. Data flow dan ownership

```text
Playground controls [DEBUG]
    → PlaygroundController
    → semantic ActivitySnapshot
    → AppState (@MainActor)
    → PresentationReducer(state, input) → new state + effects
    → PresentationEffectRunner → scheduled input / motion trigger
    → NotchPresentation + content + MascotPose
    → NotchPanelController / SwiftUI views

Pointer / click / keyboard ────────────────→ presentation input
Sleep / wake / Reduce Motion changes ─────→ presentation input/policy
Screen configuration → ScreenGeometryProvider → NotchGeometry → panel/layout
```

Boundary yang disiapkan untuk M1, **hanya sebagai arah desain**:

```text
verified Desktop + CLI hooks → NudgeBridge → validated envelope/socket
    → canonical events → SessionReducer → focused semantic snapshot
    → AppState → presentation pipeline M0
```

M1 mengganti sumber snapshot simulasi dengan hasil reducer session. Domain event tidak memanggil `setFrame`, menjalankan animasi, atau menentukan ukuran panel. UI tidak membaca config, raw provider payload, socket, atau transcript. State presentation tidak menjadi sumber kebenaran phase session.

Tanggung jawab utama:

- `AppDelegate`: memiliki lifetime panel, screen/lifecycle observers, dan effect runner; cleanup saat termination.
- `AppState`: menyimpan satu snapshot dan state presentation; menerapkan hasil reducer pada main actor. Tidak menjalankan filesystem/IPC work.
- `PlaygroundController`: menghasilkan data synthetic dengan session/turn ID stabil. Pemilihan state yang sama tidak membuat completion baru; aksi **New simulated turn** membuat turn baru secara eksplisit.
- `PresentationReducer`: memutuskan mode, prioritas content, dan semantic effects. Tidak membaca clock global, `NSScreen`, atau accessibility API langsung.
- `PresentationEffectRunner`: menjalankan effect dengan delay/timer yang dapat dibatalkan; mengirim input kembali dengan token generation. Tidak menentukan ulang aturan UX.
- `ScreenGeometryProvider`: membaca AppKit screen data pada main actor dan mengubahnya menjadi value snapshot. `NotchGeometry` menghitung frame dan content-safe regions secara pure.
- `NotchPanelController`: satu-satunya owner window frame/level/hit testing; views hanya mengatur content layout.
- `MotionPolicy`: menerjemahkan system accessibility/sleep/visibility menjadi motion yang diizinkan; Canvas hanya menggambar pose.

Tidak ada kebutuhan background service di M0: reducer kecil dan screen/UI access berada di main actor. Saat M1 ditambahkan, decode/normalization, IPC, dan file operations harus berada di luar main actor sebelum hasil diterapkan ke `AppState`.

## 5. Model dan aturan presentation

Implementasikan model secukupnya untuk workflow M0:

- `SessionID` / `TurnID`: stable value identity untuk fixture dan transition.
- `SessionPhase`: `discovered`, `idle`, `thinking`, `toolUse`, `waitingPermission`, `waitingInput`, `completed`, `failed`, `interrupted`, `ended`.
- `ActivitySnapshot`: identity, project label, phase, optional bounded tool/interaction/completion/failure summary. Tidak menyimpan prompt, transcript, raw shell command/output, atau wire payload.
- `ToolActivity`: summary dan semantic category secukupnya untuk pose (read, edit, shell, test, web, git, other).
- `NotchPresentation`: `collapsed`, `peek`, `expanded`, `attention`.
- `PresentationState`: mode, pointer/explicit expansion state, current identity, transient deadline/token, dan consumed completion identity.
- `PresentationInput` / `PresentationEffect`: snapshot changed, pointer entered/exited, explicit expand/collapse, timer fired, sleep/wake, serta policy changed.

Associated summaries tetap lightweight; `Codable`, host metadata, full `CodexSession`, `PendingInteraction` queue, dan raw hook schema ditentukan di M1 sesuai kontrak terverifikasi. Jangan mengunci format serialization dari kebutuhan playground.

| Trigger | Perilaku yang harus terlihat |
|---|---|
| Thinking/tool changed | Status dan pose berubah; tetap collapsed jika pengguna tidak membuka panel |
| Pointer enter | Peek setelah delay awal ~100 ms; tidak mengaktifkan aplikasi |
| Pointer exit | Collapse setelah ~300 ms; re-entry membatalkan effect lama |
| Klik/keyboard expand | Expanded dengan pin eksplisit sampai close/Escape; hover exit tidak menutup pin |
| Waiting permission/input | Attention menetap sampai snapshot progress/terminal yang relevan; tool summary lama tidak menutupi request |
| Klik pada simulated attention | Tidak dianggap resolved; playground menyediakan progress berikutnya |
| Completed turn baru | Expanded transient ~3.2 s dan satu flourish; repeated snapshot tidak memutar ulang |
| Failed | Content/pose failure; expanded transient awal ~5 s; tidak memakai celebration |
| Interrupted | Status dan pose berbeda dari success; tidak memakai celebration |
| Discovered/idle/ended | Content tenang; tidak ada completion effect; kosong/no-context dipahami secara eksplisit |
| Sleep | Cancel timers/transitions; pause decoration; simpan semantic state |
| Wake | Recompute satu current presentation; transient yang lewat tidak diputar ulang, pending attention tetap attention |

Delay adalah starting tokens yang dituning manual. Timer input membawa identity/generation agar callback lama tidak menutup turn atau attention baru. User-pinned expansion tidak ditutup oleh completion timer. Prioritas attention di atas hover/pin; ketika attention resolved, reducer menghitung ulang presentation dari current state.

Clock/scheduler memiliki satu boundary yang dapat diinjeksikan untuk tests. Production memakai monotonic duration untuk delays; test memakai fake time tanpa `sleep`. Wake membatalkan generation lama dan mengevaluasi deadline/current state sekali.

M0 menguji **presentation dedupe** pada snapshot yang sama. Dedupe raw hooks, suggestion-only Stop, dan subagent completion belum diimplementasikan dan bukan klaim coverage M0.

## 6. Window, geometry, dan interaksi native

1. Buat `NSPanel` borderless/nonactivating, clear background, `isOpaque = false`, dan window level yang cukup untuk overlay. Mulai evaluasi pada `.statusBar`; jangan mengangkatnya ke level yang menutupi system alerts. Gunakan `canJoinAllSpaces`/`fullScreenAuxiliary` sebagai konfigurasi awal yang wajib dibuktikan manual, bukan jaminan routing semua Spaces.
2. Gunakan `NSScreen.frame`, `safeAreaInsets`, dan auxiliary top areas ketika valid. Jangan menempatkan panel memakai `visibleFrame` saja: area menu bar/notch memiliki aturan berbeda dari work area biasa.
3. Pilih built-in display jika tersedia; fallback ke display utama yang tersedia. Tetap pada display tersebut saat hover. Re-evaluate pada display disconnect/reconfiguration; jangan membuat panel kedua atau mengejar pointer terus-menerus. Playground boleh memiliki display override untuk QA, tanpa preferences produk lengkap.
4. Hitung physical housing exclusion dari gap auxiliary areas jika tersedia. Jika metadata geometry tidak konsisten, pilih compact island di bawah safe top boundary dan tetap menyediakan status/menu bar. Jangan menebak notch width yang menimpa content.
5. Physical camera housing adalah area yang tidak dapat dirender. Shell boleh tampak menyatu dengan notch, tetapi label, controls, dan Nudgie harus berada di shoulder regions yang aman atau di bawah housing. Collapsed width 250–300 pt dalam brief adalah starting value; lebar nyata harus mencakup housing, minimum content widths, dan safe insets.
6. Semua perhitungan memakai point/global screen coordinates, termasuk layar dengan origin negatif. Clamp ukuran pada screen yang dipilih dan perhitungkan backing scale untuk alignment. Card height mengikuti content dengan batas screen-safe; teks panjang memakai line limits/truncation.
7. Anchor **top-center tetap** saat height/width berubah. Panel controller memiliki satu transition progress untuk frame/shape/layout. Jangan menjalankan dua resize animation independen (AppKit dan SwiftUI) yang menimbulkan clipping atau text snap. Prototype morph diuji sebelum menambah card detail.
8. Window bounds mengikuti visible shell plus area shadow yang kecil. Transparent padding tidak boleh menjadi invisible hit area besar yang memblokir menu bar/aplikasi lain. Hover tracking harus mengikuti current geometry sepanjang transition; cancellation mencegah enter/exit loop akibat resize.
9. Hover/automatic status tidak membuat panel key atau mengaktifkan Nudge. Untuk input keyboard, gunakan explicit user interaction; panel hanya menerima key sesuai kebutuhan, tidak menjadi main window. Menu bar selalu menyediakan jalur membuka playground/expanded tanpa hover.
10. No-context state tetap tenang; menu bar menyediakan Show/Hide overlay, Playground, dan Quit. Hiding overlay menghentikan decorative motion; app termination membersihkan observers dan scheduled tasks.

Referensi API Apple: [safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets), [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel). Availability auxiliary areas macOS 12+ juga diperiksa pada `NSScreen.h` SDK lokal. Perilaku fisik/full-screen tetap memerlukan QA pada mesin developer.

## 7. Nudgie, motion, dan aksesibilitas

Gambar karakter dari nol: rounded cursor creature, dua mata, detail cursor kecil, terbaca pada ~22–28 pt. Jangan mengambil source/artwork dari Code Island atau reference mascot.

Pose minimum: idle, thinking, tool use, attention, done, failure, interrupted. Permission dan question dapat memakai expression/badge berbeda dengan anatomy yang sama. Hindari membuat asset atau animation per tool name.

Centralize expand/collapse, hover delays, attention tap, completion flourish, dan failure motion. Completion <700 ms, sekali per identity. Idle statis sebagai default; sparse blink boleh ditambahkan dengan cancellable scheduling. Tidak ada perpetual `TimelineView`, display-link, polling, atau high-frequency timer untuk idle. Working motion berjalan hanya saat visible/relevant dan cadence-nya tenang.

Hormati perubahan Reduce Motion saat app berjalan: hentikan hop/shake/bounce, gunakan short fade atau state change, tetap pertahankan status/attention. Bridge kebijakan untuk AppKit frame transition juga harus memakai preferensi yang sama dengan SwiftUI [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).

Status memiliki teks dan glyph, bukan warna saja. Mascot decorative diabaikan VoiceOver. Expanded/attention controls memiliki label, focus order, dan akses keyboard; Escape menutup expansion yang boleh ditutup. Pending interaction tetap tersedia dan tidak dihapus oleh dismissal UI. Increase Contrast diuji. Playground hanya di Debug dengan identitas simulasi yang jelas; tidak ada tombol Open Codex yang terlihat bekerja padahal belum terintegrasi.

## 8. Urutan pekerjaan dalam M0

Urutan di bawah adalah work packages **dalam fase yang sama**, bukan fase tambahan.

| Urutan | Pekerjaan | Hasil yang dapat diperiksa sebelum lanjut |
|---|---|---|
| 1 | Scaffold Xcode, app identity, shared scheme, menu bar, panel statis | Build macOS 15 target; launch menampilkan accessory shell; Show/Hide/Quit bekerja |
| 2 | Screen snapshots, pure geometry, top-center anchor, fallback | Geometry tests lolos; panel dapat diperiksa pada physical notch/non-notch |
| 3 | Semantic snapshot, presentation reducer, cancelable effects, basic debug picker | Semua phase/mode bisa ditampilkan tanpa live source; precedence dan timers teruji |
| 4 | Shell morph, safe content layout, hover/click/keyboard | Repeated expand/collapse tidak flicker, clipping, atau focus steal dalam QA developer |
| 5 | Original Nudgie, pose mapping, motion tokens, Reduce Motion | Working/attention/done/failure/interrupted terlihat berbeda; flourish sekali |
| 6 | Sleep/wake, display changes, long labels, cleanup, QA scenarios | Tidak replay/timer ganda; fallback/recovery berjalan; build dan tests terakhir lolos |
| 7 | Handoff M0 dan catatan verifikasi | Developer menjalankan checklist bernomor; M1 tetap menunggu instruksi |

Build/check dijalankan setelah perubahan substantif pada project/state/window. Jangan membangun screen settings/onboarding kosong untuk memberi kesan lengkap. Jika motion/geometry tidak layak, perbaiki workflow M0 sebelum menambah subsystem lain.

## 9. File yang disentuh saat implementasi M0

Daftar berikut adalah batas awal; file hanya dibuat ketika dipakai. Jika perlu file di luar daftar, catat alasan tertulis sebelum mengubahnya. Source documents tidak di-refactor sebagai bagian scaffold.

```text
.gitignore
Nudge.xcodeproj/project.pbxproj
Nudge.xcodeproj/xcshareddata/xcschemes/Nudge.xcscheme
Nudge/App/NudgeApp.swift
Nudge/App/AppDelegate.swift
Nudge/App/AppState.swift
Nudge/Core/Models/ActivitySnapshot.swift
Nudge/Core/Models/SessionPhase.swift
Nudge/Core/Models/ToolActivity.swift
Nudge/Core/Models/NotchPresentation.swift
Nudge/Core/Reducer/PresentationReducer.swift
Nudge/Core/Reducer/PresentationEffect.swift
Nudge/UI/Notch/NotchPanelController.swift
Nudge/UI/Notch/ScreenGeometryProvider.swift
Nudge/UI/Notch/NotchGeometry.swift
Nudge/UI/Notch/NotchRootView.swift
Nudge/UI/Notch/NotchShell.swift
Nudge/UI/Components/ActivityLabel.swift
Nudge/UI/Components/StatusGlyph.swift
Nudge/UI/Components/StatusCardView.swift
Nudge/UI/Mascot/NudgeMascot.swift
Nudge/UI/Mascot/MascotPose.swift
Nudge/UI/Motion/MotionTokens.swift
Nudge/UI/Motion/MotionPolicy.swift
Nudge/Services/PresentationEffectRunner.swift
Nudge/Services/SleepWakeObserver.swift
Nudge/Debug/PlaygroundController.swift
Nudge/Debug/PlaygroundView.swift
Nudge/Support/Info.plist
Nudge/Support/Assets.xcassets/Contents.json
Nudge/Support/Assets.xcassets/AppIcon.appiconset/*
NudgeCoreTests/PresentationReducerTests.swift
NudgeCoreTests/NotchGeometryTests.swift
NudgeCoreTests/Support/TestScheduler.swift
docs/Nudge-M0-Verification.md
```

ID/state/input dapat ditempatkan bersama file model/reducer terkait agar tidak membuat satu file per trivial type. Icon M0 dibuat original sederhana; final distribution icon bukan syarat playground. `Info.plist` memakai satu strategi konfigurasi yang konsisten, bukan generated dan manual plist yang saling menimpa.

Penyesuaian M0 dari review ukuran: `NotchGeometry`, `NotchRootView`, dan `NotchPanelController` yang sudah ada tetap di folder `Nudge/UI/`. Compact memakai camera exclusion dengan dua wing kecil; nama project/detail pindah ke hover. Instruksi lanjutan pengguna menghapus neck/undakan pada expanded: satu bidang full-width yang melebar/memanjang dari anchor notch yang sama; pengguna secara eksplisit menolak pemindahan ke bawah menu bar. Minimized tetap seperti semula, content expanded tetap mengecualikan kamera. Tambahan `NudgeCoreTests/NotchGeometryChecks.swift` adalah executable fixture checks untuk geometry dan shape tanpa membuka app, karena shared unit-test target belum tersedia. Checks ini dikompilasi bersama source produksi; bukan pengganti QA fisik atau test target lengkap. Tidak ada perubahan hook/config/IPC/dependency.

Dokumen plan ini sendiri adalah satu-satunya file yang ditambahkan saat perencanaan. `docs/Nudge-M0-Verification.md` baru dibuat saat implementasi untuk mencatat evidence dan pending QA.

## 10. Automated validation yang bermakna

Gunakan Swift Testing untuk pure reducer/geometry tests. Uji invariants, bukan bentuk body view atau token animation yang akan dituning.

| Boundary | Skenario wajib |
|---|---|
| Presentation precedence | Waiting mengalahkan stale tool label; hover exit/timer tidak menutup pending attention |
| Hover scheduling | Enter lalu exit cepat tidak peek; re-entry membatalkan collapse; obsolete token tidak mengubah state baru |
| Explicit expansion | Pin tidak ditutup hover exit/completion timer; Escape mengikuti aturan attention/dismissal |
| Completion identity | Repeated completed snapshot menghasilkan satu flourish; new turn boleh flourish baru; failed/interrupted tidak celebrate |
| Sleep/wake | Old timer tidak berlaku; expired transient tidak diputar ulang; waiting tetap attention |
| Motion policy | Reduce Motion/sleep/hidden menekan decorative effect tanpa menghilangkan semantic state |
| Geometry | Notch, no-notch, incomplete auxiliary metadata, small screen, negative origin, mixed scale, display removal snapshots |
| Safe layout | Frame tetap top-centered dan dalam selected screen; content regions tidak masuk physical housing; long content dibatasi |

Fake clock memajukan waktu secara deterministik. Bila diperlukan effect runner test, injeksikan scheduler dan cek cancellation/callback generation tanpa menunggu real time. Reducer/geometry unit tests tidak membuktikan focus behavior, visual smoothness, energy usage, atau physical notch alignment.

Perintah setelah project tersedia:

```bash
xcodebuild -list -project Nudge.xcodeproj
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test
git diff --check
```

Shared `Nudge` scheme memasukkan `NudgeCoreTests` pada Test action. Build Release juga diperiksa sekali untuk memastikan playground Debug tidak menjadi jalur wajib/terbuka pada release. Deployment target dan Swift 6 mode diperiksa di resolved build settings; lint source saja tidak cukup.

## 11. Failure cases, risiko, dan recovery

| Risiko/failure | Penanganan M0 |
|---|---|
| Screen metadata berubah/tidak lengkap | Cancel transition lama, recompute geometry, pilih compact island aman; menu bar tetap bisa dipakai |
| Display terlepas saat expanded | Re-select display, clamp/re-anchor satu panel; tidak menyimpan reference NSScreen yang sudah usang |
| Full-screen/Spaces/menu-bar auto-hide berbeda | Catat machine/OS dan observasi; tune public AppKit configuration setelah QA, tanpa private API |
| Window/shell resize tidak sinkron | Satu owner transition; perbaiki prototype dan content insets sebelum menambah motion |
| Rapid hover/phase changes | Cancelable effects + generation tokens + stable view identity |
| Sleep atau Reduce Motion di tengah flourish | Hentikan motion, tandai effect consumed, rebuild current state tanpa replay |
| Teks simulasi terlalu panjang | Bounded synthetic summaries, line limits, content-adaptive card dengan maksimum ukuran |
| Debug control dianggap integrasi nyata | Debug-only playground dan explicit simulation identity; belum ada aksi navigation/approval |
| Swift 6 isolation/build issue | Betulkan actor boundaries; jangan mematikan concurrency checks global sebagai jalan pintas |
| App crash/closed | Tidak ada ketergantungan Codex atau config mutation; Codex tetap berjalan mandiri |

M0 tidak mengubah hook/config/wire schema, sehingga tidak memerlukan backup konfigurasi Codex atau migrasi data. Tidak membaca `CODEX_HOME`, memasang socket, meminta Accessibility permission, atau menyimpan transcript. Recovery M0 cukup launch ulang/reset simulated state. Log jika diperlukan hanya kategori phase/transition, tanpa paths/teks pengguna.

Trade-off yang diterima: satu app target dengan pure files, satu simulated context, satu display policy, satu generic status card dengan variasi content. Package extraction, multi-session focus reducer, diagnostic store, dan source protocols ditambahkan hanya saat ada boundary nyata yang memerlukannya. Optional app-server enrichment dan transcript fallback tetap di luar fondasi ini.

## 12. Kontrak Desktop/CLI sebelum M1

M0 tidak menggunakan atau mengklaim kompatibilitas hook/deep link. Nama event dalam brief tetap research snapshot. Tidak ada live verification Codex pada pekerjaan M0.

Sebelum implementasi M1, buat plan terpisah dan validasi sumber resmi terkini. Catat **secara terpisah** untuk Desktop dan CLI: host version, effective config location/custom `CODEX_HOME`, trust behavior, observed event names/payload/turn identity, tool progress, completion/interruption, dan bridge-unavailable behavior. Desktop harus mencakup new/resumed local thread yang dimulai langsung di app tanpa terminal launch.

Permission/question coverage dicatat menurut host dan menjadi dasar M3; precise links diverifikasi di M4. Jangan menyimpulkan app-server milik Nudge mengamati thread Desktop existing. Jika jalur hooks gagal memenuhi Desktop requirement, investigasi supported local path dan laporkan limitation sebelum menetapkan implementasi; CLI-only tidak memenuhi M1/MVP.

Plan M1 harus menjelaskan ownership hooks, backup sebelum mutation pertama, parse-before-write, preservation foreign entries, idempotency, atomic replacement, malformed-config refusal, uninstall/recovery, bounded bridge timeout, owner-only socket, dan wire compatibility. Tidak ada real config mutation atau developer-only live/manual testing tanpa instruksi eksplisit.

## 13. Verifikasi manual oleh developer — handoff M0

Catat OS, hardware/display, build revision, hasil, dan screenshot/rekaman jika ada issue. Semua item ini **pending** saat plan dibuat.

1. Launch dari Xcode. Pastikan menu bar tersedia, tidak ada Dock/primary window default, Show/Hide/Quit bekerja, dan playground dapat dibuka melalui menu.
2. Simulasikan discovered, idle, thinking, seluruh kategori tool, waiting permission, waiting input, completed, failed, interrupted, ended/no context. Cocokkan teks/glyph/pose; failure dan interrupted tidak terlihat sebagai success.
3. Hover cepat dan expand/collapse berulang. Uji re-entry saat exit delay, click pin, close/Escape, long labels, dan perpindahan phase saat panel bertransisi. Pastikan tidak flicker, text snap, mascot teleport, atau clipping.
4. Dari editor/aplikasi lain, hover dan picu simulated completion/attention. Pastikan aplikasi aktif/keyboard focus tidak berubah otomatis; keyboard access tersedia melalui aksi eksplisit.
5. Pada physical notch, periksa shoulder insets, camera exclusion, top anchor, Nudgie, dan sparkle. Pada layar non-notch/external, periksa compact island. Uji mixed scale, disconnect display, dan display override QA jika tersedia.
6. Uji Spaces, Mission Control, full-screen, dan menu-bar auto-hide. Pastikan hit area tidak memblokir area transparan/menu bar secara berlebihan; catat keterbatasan konfigurasi nyata.
7. Aktifkan Reduce Motion dan Increase Contrast saat app berjalan; uji VoiceOver dan keyboard controls. Status tetap dipahami tanpa warna, mascot tidak berisik bagi VoiceOver, dan hover bukan satu-satunya jalur aksi.
8. Pilih completion pada turn yang sama berulang lalu buat new simulated turn. Pastikan flourish satu kali per turn. Biarkan attention lama dan klik panel; hanya simulated progress/terminal transition yang membersihkan pending state.
9. Sleep/wake saat working, attention, dan setelah completion. Pastikan tidak replay, tidak ada collapse timer ganda, dan current presentation kembali benar.
10. Diamkan idle dan sembunyikan overlay; periksa Activity Monitor secara awal untuk motion/timer yang berjalan terus. Ini smoke check M0, bukan bukti profiling release atau klaim CPU 0%.

## 14. Checklist penutupan M0

- [ ] Scope hanya M0; tidak ada live integration/config mutation.
- [ ] Debug build, Release build, test scheme, deployment target, signing lokal, dan `LSUIElement` diverifikasi; hasil command dicatat.
- [ ] Meaningful presentation/geometry/motion-policy tests lolos; installer/IPC/live reducer belum berlaku di M0.
- [ ] Empat presentation mode dan seluruh semantic phase dapat disimulasikan.
- [ ] Original Nudgie, safe layout, cancelable hover/timers, one-shot completion, dan Reduce Motion tersedia.
- [ ] Developer menjalankan verifikasi manual bernomor; issue dan pending hardware coverage dicatat.
- [ ] Tidak ada klaim support Desktop/CLI berdasarkan simulasi.
- [ ] Diff hanya file M0; commit terpisah ketika pengguna meminta, dengan message Bahasa Inggris, misalnya `Build the Nudge notch playground`.
- [ ] Berhenti setelah handoff M0. M1 menunggu hasil QA dan instruksi berikutnya.

## 15. Aturan pengerjaan wajib

Blok berikut disalin apa adanya dari AGENTS.md dan berlaku untuk pelaksanaan plan ini.

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
