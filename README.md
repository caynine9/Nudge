# Nudge

Companion kecil di menu bar dan notch Mac buat menemani kamu saat Codex bekerja. Jadi, waktu pindah ke aplikasi lain, kamu tetap bisa lihat progresnya dan tahu kapan perlu kembali ke Codex.

Nudge menampilkan project, status kerja, ringkasan tool, dan perhatian saat ada pertanyaan, izin, atau pekerjaan selesai. Hover untuk melihat sesi yang terdeteksi; geser cursor keluar untuk menutupnya. Ada mascot original bernama **Nudgie**, dan Mac tanpa notch tetap bisa pakai tampilan compact di bagian atas layar.

**Masih dalam pengembangan.** Integrasi ditujukan untuk Codex Desktop dan CLI, tetapi verifikasi live keduanya masih pending. Navigasi thread dan permission actions masih experimental.

## Install

Butuh **macOS 15 atau lebih baru** dan Codex Desktop atau CLI untuk memantau aktivitas.

1. Buka [Releases](https://github.com/caynine9/Nudge/releases) dan unduh `Nudge-<version>-macOS.dmg` jika build tersedia.
2. Buka DMG, lalu drag **Nudge.app** ke **Applications**.
3. Jalankan Nudge dari Applications. Ikonnya muncul di menu bar; Nudge tidak tampil di Dock.

Build personal saat ini belum memakai Developer ID signing/notarization, jadi macOS bisa meminta konfirmasi tambahan. Detailnya ada di [panduan distribusi](docs/Distribution.md).

## Hubungkan ke Codex

1. Dari menu bar Nudge, buka **Codex hooks** dan pilih **Host configuration**: Desktop atau CLI.
2. Periksa lokasi konfigurasi. Kalau memakai folder khusus atau `CODEX_HOME`, gunakan **Choose configuration folder…**. Desktop dan CLI bisa memakai lokasi berbeda.
3. Klik **Install or refresh hooks**, lalu konfirmasi. Hooks adalah penghubung lokal yang memberi tahu Nudge saat aktivitas Codex berubah.
4. Review dan trust hooks Nudge di Codex sesuai petunjuk host. Matikan **Demo playground** jika aktif, lalu mulai atau lanjutkan thread lokal.

Installer membuat backup sebelum mengubah file yang sudah ada dan mempertahankan hooks lain. Untuk melepas integrasi, pilih **Remove Nudge hooks from selected config** sebelum menghapus aplikasinya.

## Build dari source

Butuh Xcode lengkap dengan toolchain Swift 6. Dari folder repo:

```bash
./scripts/package-dmg.sh
```

Hasilnya ada di `dist/Nudge-<version>-macOS.dmg`. Untuk development, buka `Nudge.xcodeproj`, pilih scheme **Nudge**, lalu Run. UI memakai SwiftUI dan AppKit; aktivitas masuk lewat helper native `NudgeBridge` dan Unix socket lokal.

Nudge tidak memerlukan akun sendiri, tidak menambahkan telemetry, dan tidak menyimpan transcript penuh secara default. Codex tetap bisa bekerja saat Nudge ditutup.
