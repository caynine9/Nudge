# Threaded Active Sessions — Verification dan Handoff

Tanggal: 3 Oktober 2026.

Expanded monitor sekarang mengelompokkan sesi aktif di bawah label project. Judul chat dibaca melalui `thread/read` app-server lokal hanya untuk session ID yang sudah masuk lewat hooks; request memakai `includeTurns: false`, memvalidasi `thread.id`, dan menampilkan `thread.name` yang dibatasi. Jika binary, home, respons, atau judul tidak tersedia, row kembali ke short ID. Status semantic dan ringkasan tool berbagi kolom kanan. Collapsed/peek tetap satu konteks; cap expanded tetap +10 pt dan scroll. Tidak ada perubahan hook, config, helper, atau wire.

## Validasi otomatis dan batasnya

| Pemeriksaan | Hasil |
|---|---|
| `xcodebuild -quiet -project Nudge.xcodeproj -scheme Nudge -configuration Debug -destination 'platform=macOS' test` | Lulus: 64 tes, 0 gagal. |
| Metadata fake app-server | Lulus: ID harus cocok, judul dibatasi, request tidak memuat turns, proses tidak responsif kembali dalam deadline. |
| Probe read-only pada satu thread lokal | Binary Desktop yang dibundel (Codex CLI 0.160.0) dan implementasi Swift mengembalikan judul untuk ID yang cocok, tanpa menampilkan teks judul pada output tes. CLI terpasang 0.154.0 juga mengembalikan judul pada probe terpisah. Ini bukti kontrak metadata untuk satu thread, bukan acceptance workflow Desktop/CLI penuh. |
| Grouping tests | Lulus: satu sesi sekali, urutan kelompok berdasarkan anggota prioritas tertinggi, urutan anggota tetap, fallback project tak dikenal. |
| Static notch layout checks | Lulus pada notch dan fallback, termasuk 2 sesi satu project serta 8 sesi lintas project; shell tetap di ukuran yang ditargetkan. Capture hosted memperlihatkan project heading, judul sesi, dan status/aktivitas sejajar di kanan. Capture ini tidak menguji runtime NSPanel atau scroll fisik. |
| Impeccable layout detector | `[]` pada `NotchRootView.swift`. Launcher tidak mengenali nilai platform `macos` dan memperlakukannya sebagai web; aturan native dari project brief dan source tetap dipakai. |
| `git diff --check` | Lulus. |

Title lookup memakai proses lokal yang dibatasi 2,5 detik dan respons 128 KiB, dengan cache singkat. Judul hanya ada dalam memori Nudge, tidak masuk wire/log/persistence. `thread/read` tidak memulai, melanjutkan, atau subscribe thread. Ketidakcocokan project folder yang kebetulan punya basename sama tetap mungkin karena wire saat ini hanya mengirim project label. Perubahan judul saat sesi sedang tenang baru terbaca pada event berikutnya. Desktop new/resumed dan CLI masih perlu diverifikasi terpisah oleh developer.

## Verifikasi manual oleh developer

1. Jalankan build terbaru di Mac bernotch dan layar tanpa notch. Pastikan header project (misalnya **Nudge**) berada di atas row chat; row menampilkan judul bila tersedia, atau ID pendek bila belum. Judul panjang tetap terbaca/terpotong wajar tanpa mendorong status keluar panel.
2. Jalankan dua sesi aktif dalam project sama dan satu sesi dari project lain. Pastikan setiap sesi tampil sekali di bawah project yang tepat, status serta aktivitas tool rata kanan, urutan stabil saat tool event masuk, dan scroll mencapai row terakhir dalam cap expanded +10 pt.
3. Dari Codex Desktop, buat local chat baru lalu resume chat lain. Bandingkan judul, project, dan ID yang dipilih dengan Codex. Catat versi, effective `CODEX_HOME`, trust hooks, serta apakah title tersedia sebelum/sesudah turn. Ulangi workflow setara di CLI dan catat hasilnya terpisah.
4. Klik masing-masing row untuk memastikan chat yang tepat terbuka. Deep link yang diterima OS saja belum membuktikan tujuan benar; uji juga fallback ketika judul metadata tidak tersedia.
5. Uji hover/expanded, keyboard/VoiceOver, Reduce Motion, sleep/wake, Spaces/full-screen, dan window focus. Perubahan judul tidak boleh memicu celebration, menghapus attention, atau membuat list melompat ketika sedang di-scroll.

Sumber kontrak: [Codex Hooks](https://learn.chatgpt.com/docs/hooks), [Codex app-server](https://learn.chatgpt.com/docs/app-server), dan [Codex deep links](https://learn.chatgpt.com/docs/reference/commands). Manual visual dan live-host acceptance tetap di tangan developer sesuai AGENTS.md.
