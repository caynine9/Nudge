# Nudge M5 — Codex Permission Contract

Tanggal: **3 Oktober 2026**. Status: **bentuk respons hook ditinjau dari dokumentasi resmi; dukungan runtime dan semantics host masih menunggu verifikasi manual Desktop dan CLI**.

Dokumen ini mencatat batas kontrak M5 untuk implementasi saat ini. Ini bukan bukti bahwa Codex Desktop atau CLI pada versi lokal telah menjalankan atau menerapkan keputusan dari Nudge.

## Kontrak hook yang didokumentasikan

Dokumentasi resmi `PermissionRequest` menetapkan hook sinkron yang dapat menjawab dengan `allow` atau `deny`. Bila hook kembali tanpa keputusan, flow approval native Codex tetap menangani permintaan. Output yang digunakan Nudge:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "allow" }
  }
}
```

Untuk deny, helper mengirim `behavior: "deny"` dan pesan statis `Denied in Nudge.`. Tidak ada field grant persisten, perubahan policy, atau jawaban untuk `request_user_input`.

Input hook yang didokumentasikan membawa `session_id`, `turn_id`, `tool_name`, serta `tool_input`. Dokumentasi tidak menjamin request ID atau `tool_use_id`; `tool_input.description` opsional. Karena itu helper membuat UUID baru untuk satu invocation, mengikat satu response socket ke invocation tersebut, dan hanya meneruskan ringkasan deskripsi yang lolos redaction ketat. Payload command tidak masuk ke wire protocol, log, atau preferences. Saat ini tombol hanya dapat aktif untuk `Bash` dengan deskripsi aman yang tersedia; input lain kembali ke Codex native.

`allow` adalah jawaban untuk invocation hook itu menurut bentuk kontrak yang didokumentasikan. Penerapan scope sekali saja pada setiap host/jenis permission, urutan beberapa hook, dan efek hook `deny` dari handler lain tetap harus dibuktikan di runtime. Dokumentasi menyebut deny dari hook lain dapat mengalahkan allow Nudge. Karena itu status “sent to Codex” berarti response ditulis ke helper, bukan bukti host menerima atau menjalankan operasi.

UUID yang dibuat helper mengikat satu proses hook dengan satu response socket; itu bukan provider request ID. Setiap callback terpisah mendapat UUID baru dan broker tidak melakukan coalescing terhadap provider retry/duplicate callback. Installer mencegah duplicate canonical handler milik Nudge, tetapi tidak membuktikan bahwa host tidak akan mengulangi invocation atau bahwa handler foreign tidak akan mengubah hasil. Broker membatasi channel dan mengantrekannya per sesi; tanpa host ID, pengujian duplicate/overlap harus memastikan UI tidak mengarahkan satu klik ke callback lain.

## Runtime yang harus diverifikasi

| Host | Local new thread dari aplikasi/CLI | Resumed thread | Response Allow Once/Deny | Hasil |
|---|---|---|---|---|
| Codex Desktop | Belum diverifikasi | Belum diverifikasi | Belum diverifikasi | Gate manual pending |
| Codex CLI | Belum diverifikasi | Belum diverifikasi | Belum diverifikasi | Gate manual pending |

Versi candidate yang tercatat dalam audit awal plan: Desktop `26.930.31428` build `12913`, bundled CLI `0.160.0`, dan CLI PATH `0.154.0`. Nilai ini adalah snapshot audit, bukan verifikasi terhadap sesi uji M5. Catat versi, binary/path, effective config/custom `CODEX_HOME`, trust, dan policy pada setiap pengujian baru. Jangan menganggap bundled CLI dan CLI PATH sebagai runtime yang sama.

M5 tetap **eksperimental dan Off secara default** sampai setiap host yang dipakai lulus verifikasi. Keberhasilan synthetic fixture membuktikan bentuk serialization dan failure handling Nudge saja. App-server approvals milik koneksi app-server Nudge tidak membuktikan kontrol atas thread Desktop yang telah berjalan.

## Sumber resmi

- [Codex Hooks — PermissionRequest](https://learn.chatgpt.com/docs/hooks#permissionrequest)
- [Codex Hooks — konfigurasi, timeout, trust, dan lifecycle](https://learn.chatgpt.com/docs/hooks)
- [Codex App Server — approvals](https://learn.chatgpt.com/docs/app-server#approvals)
