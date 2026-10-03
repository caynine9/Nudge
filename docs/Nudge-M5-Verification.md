# Nudge M5 — Implementasi dan Handoff Verifikasi

Tanggal: **3 Oktober 2026**. Status: **implementasi source dan hermetic suite selesai; build/test lulus; penerimaan live Desktop/CLI dan pemeriksaan UI native masih pending developer**.

Implementation plan: [Nudge-M5-Implementation-Plan.md](Nudge-M5-Implementation-Plan.md). Batas kontrak host: [Nudge-M5-Codex-Contract.md](Nudge-M5-Codex-Contract.md).

## Yang diimplementasikan

- Bridge helper memiliki mode action khusus `PermissionRequest`. Mode tersebut menunggu paling lama 10 detik untuk satu response dan hanya menulis JSON Allow Once/Deny resmi jika menerima response dengan schema dan invocation ID yang cocok. Semua jalur unavailable, timeout, malformed, atau disconnect kembali tanpa keputusan agar Codex memakai approval native.
- Jalur monitoring event tetap terpisah. Permission mirror membawa ID invocation yang sama supaya attention card live dapat dikaitkan dengan channel response tanpa mengubah wire event V1–V3.
- Socket response terpisah memakai frame maksimal 4 KiB, owner/current-user check, mode `0600`, peer UID check, dan cleanup socket stale berdasarkan type, owner, dan inode. Listener menerima paling banyak delapan koneksi bersamaan.
- `PermissionBroker` menegakkan satu keputusan per request, maksimum delapan channel, FIFO per sesi, batas waktu, verifikasi context sebelum response, pembatalan saat opt-out/sleep/quit, serta rekonsiliasi progress tool yang cocok. Status sent tidak menyatakan host berhasil menerapkan keputusan.
- Hanya `Bash` dengan ringkasan operasi yang aman dan bounded yang mendapat tombol live. Command mentah tidak ditampilkan atau dikirim ke response socket. Pertanyaan tetap memakai jalur Answer in Codex.
- Installer mengubah hanya handler `PermissionRequest` milik Nudge saat mode dipilih. Bentuk command lama dan baru dikenali secara exact; duplicate canonical group milik Nudge dideduplikasi. Foreign hooks dipertahankan.
- Preference permission actions default Off. Pengguna perlu memilih host/config, meninjau dan mempercayai hooks di Codex, lalu menjalankan verifikasi sandbox untuk Desktop dan CLI masing-masing sebelum mengandalkan tombol.
- UI attention menampilkan status request dan Allow Once/Deny saat channel aktif. Open Codex mencabut channel terlebih dahulu. Demo preview tetap terpisah. Presentation reducer, geometri notch, hover 100/320 ms, expanded behavior, grouping, scroll cap, navigator, dan metadata reader tidak diubah oleh scope M5 ini.

## Pemeriksaan otomatis

Perintah yang dijalankan:

```bash
xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/nudge-m5-implementation-derived \
  -resultBundlePath /tmp/nudge-m5-implementation-tests-final5.xcresult test
xcrun xcresulttool get test-results summary \
  --path /tmp/nudge-m5-implementation-tests-final5.xcresult --format json
git diff --check
plutil -lint Nudge.xcodeproj/project.pbxproj
```

Hasil final suite: **88 passed, 0 failed, 0 skipped**. Suite mencakup build app/helper, test target, validasi protocol dan redaction, roundtrip socket, one-shot broker, expiry/native fallback, queue per-session, stale context dan matching-tool reconcile, installer migration/duplicate handling, serta helper subprocess dengan server socket sintetis. Tiga percobaan sebelum hasil final menangkap dua isu fixture (helper test hanya menerima override socket dalam `/tmp`) dan satu nama lokal yang menutupi helper request; fixture diperbaiki lalu suite penuh dijalankan ulang. Tidak ada kegagalan yang disembunyikan dari hasil final.

`git diff --check` dan `plutil -lint` lulus. Warning Xcode yang terlihat adalah pemilihan destination arm64 saat dua arsitektur cocok, warning binary helper bertanda tangan tidak di-strip, dan diagnostic lifecycle XCTest dari Xcode; tidak ada warning tersebut yang menggagalkan suite.

Semua endpoint, socket, dan payload automated tests sintetis. Tidak ada config Codex, trust record, policy, backup pengguna, atau keputusan permission nyata yang diubah/dijalankan.

Identitas response bersifat per helper invocation karena host tidak menjamin request ID. Duplicate handler canonical Nudge dideduplikasi installer, tetapi provider retry/duplicate callback tidak digabungkan. Requests overlap diantrikan per sesi dan tetap harus diuji manual; satu klik hanya menulis ke koneksi invocation yang identitasnya sedang tampil. Bila korelasi progress ambigu, pending attention dipertahankan secara konservatif. Batas ini membuat dukungan live tetap eksperimental sampai Gate host lulus.

## Gate yang masih pending

Dokumentasi resmi menetapkan bentuk output hook, tetapi belum membuktikan perilaku versi host lokal. Tabel bukti terbaru tetap:

| Host / skenario | Status |
|---|---|
| Desktop: local new thread dimulai langsung di app | Pending |
| Desktop: resumed thread tanpa terminal atau app-server Nudge | Pending |
| Desktop: Allow Once dan Deny diterapkan pada request yang cocok | Pending |
| CLI: new dan resumed thread | Pending, terpisah dari Desktop |
| CLI: Allow Once, Deny, timeout, native fallback | Pending |
| Hook trust/review, duplicate hooks, foreign deny dan effective config | Pending |
| Physical notch, keyboard, VoiceOver, Reduce Motion dan sleep/wake UI | Pending |

Jangan menyebut MVP/M5 host acceptance selesai sampai bukti ini dicatat. Jangan memasang ke config nyata atau membuat real permission decision sebagai bagian dari automated test.

## Verifikasi manual oleh developer

Jalankan satu per satu pada sandbox project/config recoverable; catat host, versi/build, binary/path, effective config/custom home, trust, scenario, session/turn, tool scope, output, latency, native fallback, resolution, dan hasil. Redact command, prompt, path, dan secrets dari catatan.

1. **Inventarisasi host.** Catat macOS, Codex Desktop version/build, bundled CLI version, CLI PATH version, binary yang benar-benar berjalan, effective config, custom `CODEX_HOME`, approval policy, hook trust/review, dan M1–M4 acceptance yang masih pending.
2. **Desktop new thread.** Mulai local thread langsung dari Codex Desktop. Trigger permission harmless yang kontraknya terverifikasi. Cocokkan card dengan thread/turn/operasi. Uji Allow Once dan buktikan hanya request itu diproses. Uji Deny dan pastikan operasi ditolak tanpa UI menyatakan sukses.
3. **Desktop resumed thread.** Resume thread dari aplikasi Desktop tanpa membuka terminal atau Nudge app-server; ulangi mirror, Allow Once, dan Deny. Catat jika event atau output hook berbeda dari new thread.
4. **CLI terpisah.** Jalankan skenario new/resumed dan Allow Once/Deny pada CLI yang path/version-nya dicatat. Jangan memakai keberhasilan Desktop atau fixture sintetis sebagai bukti CLI.
5. **Native recovery.** Biarkan deadline habis, pilih Open Codex, hilangkan listener, dan tutup Nudge ketika request menunggu. Pastikan tidak ada output decision dan approval native tetap dapat dipakai. Klik ganda, callback terlambat, dan turn lama tidak boleh mengambil keputusan baru.
6. **Queue dan hook ordering.** Uji request tumpang-tindih, request berulang dengan tool name sama, duplicate handler dan foreign deny. Buktikan satu klik hanya berlaku untuk satu invocation; catat bahwa deny hook lain dapat mengalahkan allow.
7. **Resolution dan lifecycle.** Selesaikan request langsung di host, lanjutkan progress tool, interupsi turn, mulai turn baru, lalu uji sleep/wake dan quit/reopen. Pastikan channel lama tidak hidup kembali, pending tidak hilang hanya karena waktu/app dibuka, dan completion tidak direplay.
8. **Installer recovery.** Hanya pada config uji: install/refresh action mode, trust/review hook, opt out ke mirror mode, uji duplicate Nudge groups, foreign hooks, malformed config, backup, dan uninstall. Pastikan foreign bytes/handlers serta backup dipertahankan dan malformed file tidak diubah.
9. **Native UI/accessibility.** Uji physical notch dan layar tanpa notch, card panjang/truncated, hover expanded/collapse, keyboard/VoiceOver, Reduce Motion, Spaces/full-screen, serta sleep/wake. Pastikan descriptor dan recovery terlihat tanpa memperbesar panel melewati cap atau menutupi pending request.
10. **Privacy/failure isolation.** Periksa bounded diagnostics dan pastikan command, prompt, file contents, token, atau secret tidak masuk UI/log/wire/preferences. Tutup Nudge saat Codex bekerja dan pastikan Codex tetap berjalan.

Perubahan M5 belum di-commit. Working tree juga berisi hunk `project.pbxproj` yang sudah ada dari pengguna untuk grouping `CodexNavigatorTests.swift`; hunk tersebut dipertahankan dan tidak boleh dihapus. Audit rincian status berada di plan.
