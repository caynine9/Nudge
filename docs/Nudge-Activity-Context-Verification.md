# Activity Context — Verification dan Handoff

Tanggal implementasi: **3 Oktober 2026**

Scope ini menampilkan daftar semua sesi aktif yang telah terdeteksi saat Nudge expanded, menjaga expanded monitor maksimal 10 pt lebih tinggi dari baseline, menampilkan tool summary terverifikasi, memperjelas project/session identity, dan menghapus badge Live. Perilaku urutan: pending attention dahulu, lalu turn yang paling baru dimulai atau dilanjutkan. Tool update tidak mengubah posisi row.

## Batas data yang tersedia

Hook event yang didokumentasikan menyediakan identity sesi, project cwd, nama tool, dan tool input pada event tertentu. Nudge menampilkan project basename serta short session ID; kontrak yang ditinjau tidak menyediakan chat title. Task commentary seperti “Adding monitor edge-case tests…” juga tidak disediakan oleh hook yang dipakai. Karena itu, adapter merangkum beberapa invokasi shell sederhana menjadi label tetap yang bounded dan memakai “Running command” untuk command yang ambigu. Teks command, prompt, output, transcript, dan assistant message tidak diteruskan ke wire. Ketika tidak ada tool aktif, `Thinking…` tetap state yang benar-benar teramati.

## Compatibility dan recovery

Wire v2 membawa allowlist ringkasan tetap. App baru menerima wire v1 lama sebagai fallback generik; app lama menolak frame v2 dan helper kembali tanpa menghambat Codex. Jalankan aksi **Install or refresh Codex hooks** dari Nudge untuk memperbarui helper lokal sebelum memakai app baru bersama hook yang sudah terdaftar. Hook config tidak perlu ditulis ulang bila entry Nudge sudah benar. Jika versi app dan helper tidak cocok, pasang ulang helper yang sepasang melalui aksi yang sama; config malformed tetap dipertahankan. Tidak ada konfigurasi Codex nyata yang diubah selama implementasi ini.

## Validasi otomatis

| Pemeriksaan | Hasil |
|---|---|
| `xcodebuild -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test` | Lulus; 51 test, 0 gagal. Build Debug termasuk di dalam action ini. |
| Swift 6 notch geometry checks | Lulus; expanded dengan sesi overflow bertambah tepat 10 pt. |
| Swift 6 static layout checks | Lulus; state notch dan fallback dengan 2 serta 8 sesi tetap di dalam batas shell/canvas. |
| `git diff --check` | Lulus. |
| Codex Desktop/CLI live event coverage | Belum diuji; fixture dan build tidak membuktikan dukungan host. |
| Native visual/input/accessibility QA | Menunggu developer di macOS. |

Geometry/layout checks adalah fixture render hermetic, bukan pengganti uji scroll, interaksi panel, notch fisik, atau host nyata. Tidak ada hook/config pengguna yang dipasang, dihapus, atau diubah.

## Verifikasi manual oleh developer

1. Buka Nudge di layar dengan notch dan layar tanpa notch/external display. Pastikan badge Live hilang, row menampilkan project + short session ID + phase, dan Demo tetap ditandai Demo. Uji hover, expand/collapse, Spaces/full screen, menu-bar behavior, dan Reduce Motion.
2. Dengan fixture atau dua sesi nyata yang tersedia, buka expanded view dan pastikan setiap sesi aktif tampil sekali; dua sesi dalam project sama tetap mudah dibedakan. Pastikan attention berada paling atas, turn terbaru setelahnya, dan tool update tidak membuat row meloncat.
3. Pastikan daftar hanya menaikkan tinggi expanded baseline 10 pt. Scroll sampai sesi terakhir dengan scrollbar, lalu kirim update atau masukkan sesi baru saat sedang membaca bagian bawah. Row/posisi yang sedang dibaca harus tetap terjaga dan scroll tidak menutup panel.
4. Jalankan new serta resumed local thread langsung di Codex Desktop. Catat versi, effective config, trust/reload, dan event coverage. Cocokkan session ID/project dan tool summary; thinking tanpa tool harus tetap tampil sebagai Thinking. Ulangi terpisah di Codex CLI.
5. Jalankan sedikitnya dua thread secara bersamaan, termasuk lintas project. Uji working, tool selesai, question/permission yang tersedia, completion, failure/interruption, dan selection; pastikan status/row yang tepat berubah. Jangan menganggap judul atau task commentary tampil sampai host benar-benar menyediakan sumber yang tervalidasi.
6. Di sandbox config, gunakan aksi refresh helper dan verifikasi entry hook tetap idempotent serta foreign hooks/backup terjaga. Uji mismatch versi hanya dengan fixture/sandbox; pastikan Codex tetap dapat bekerja saat Nudge tidak tersedia.
7. Uji keyboard, VoiceOver, window focus, sleep/wake, dan Reduce Motion sambil expanded list terbuka. Perubahan list/wake tidak boleh replay completion atau menghilangkan pending attention.

Catat versi dan hasil Desktop/CLI secara terpisah. Acceptance live M1 tetap pending sampai workflow Desktop new/resumed dan CLI masing-masing dibuktikan developer.
