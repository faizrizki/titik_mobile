# Offline dan sinkronisasi (mobile)

Semua layar kasir membaca dari database lokal (SQLite). Jaringan hanya dipakai `SyncService`.

## Menjalankan

```
flutter run                                              # mode demo (server simulasi di dalam aplikasi)
flutter run --dart-define=API_BASE_URL=https://api.xxx   # backend sungguhan
flutter run --dart-define=SENTRY_DSN=https://...         # opsional, pelaporan error
```

Mode demo: `sari@kopisudut.id` / `rahasia123`, PIN manajer `1234`. QRIS demo otomatis lunas setelah 8 detik.

## Berkas

| Berkas | Isi |
|---|---|
| `lib/core/pricing.dart` | Perhitungan harga integer rupiah (BR-01, BR-11), nilai retur, selisih kas (BR-09) |
| `lib/data/local_store.dart` | Penyimpanan lokal; `apply()` menulis banyak baris dalam satu transaksi database |
| `lib/data/app_state.dart` | Checkout, shift, void/retur, outbox, penerapan hasil pull |
| `lib/data/sync_service.dart` | Worker push/pull, backoff, pemicu koneksi/resume/timer |
| `lib/data/backend.dart` | Antarmuka `SyncApi`, `AuthApi`, `PaymentGateway`, hash PIN, penyimpanan token |
| `lib/data/http_backend.dart` | Klien REST untuk backend Go |
| `lib/data/demo_backend.dart` | Server simulasi (idempotensi, delta pull, webhook bertanda tangan) |
| `lib/core/receipt.dart`, `printer_service.dart` | ESC/POS 58/80 mm, PDF cadangan, Bluetooth |

## Kontrak endpoint

| Endpoint | Keterangan |
|---|---|
| `POST /auth/login` | `{email,password}` -> `{accessToken, refreshToken, session}`; `session` = `Session.toJson()` termasuk `approvers[]` (id, name, salt, pinHash) dan `taxBps` |
| `POST /auth/refresh`, `/auth/logout` | `{refreshToken}` |
| `POST /sync/push` | `{type: order\|refund\|shift, id: <uuid>, payload}` -> `{duplicate, flags[]}`. **Idempoten per `id`**; UUID yang sudah ada mengembalikan sukses tanpa mengubah stok. `flags` berisi `negative_stock` bila stok server menjadi negatif (transaksi tetap diterima, BR-06) |
| `GET /sync/changes?kind=&since=&limit=` | `kind`: `category`, `product`, `price`, `stock`. -> `{items[], deleted[], cursor, hasMore}`. `since` kosong = unduhan awal. `deleted` = tombstone (BR-12). Item `stock`: `{productId, balance}` |
| `POST /payments/qris` | `{orderUuid, amount}` -> `{id, qr, amount, expiresAt}` |
| `GET /payments/{id}` | `{status: pending\|paid\|expired}`; `paid` hanya setelah webhook gateway terverifikasi (BR-10) |

Klasifikasi galat: 5xx, 408, 429, jaringan putus = **sementara** (diulang dengan backoff 2, 4, 8 ... detik, maks 5 menit, urutan outbox dijaga).
Selain itu 4xx = **permanen** (ditandai, tampil di layar Masalah sinkronisasi, bisa diulangi manual).

## Aturan perhitungan (harus identik di server)

1. Diskon per item (nominal atau persen, dibatasi nilai baris).
2. Diskon transaksi atas subtotal setelah diskon item.
3. Pajak atas subtotal setelah semua diskon: `round_half_up(base * taxBps / 10000)`.

Server wajib menghitung ulang dari `items[].unitPrice/qty/discount`, `txnDiscount`, `taxBps`, dan menolak (422) bila `total` berbeda.

## Stok lokal

`stok lokal = saldo server (hasil pull) + mutasi lokal yang belum terkirim`. Setelah sebuah order terkirim, mutasinya
dianggap sudah diterapkan server; pull berikutnya menimpa dengan saldo sebenarnya.

## Keterbatasan yang diketahui

- PIN manajer 4 digit diverifikasi lokal (agar void/retur jalan offline) dengan hash+salt 2000 putaran dan penguncian 60 detik
  setelah 5 kesalahan. Server sebaiknya memeriksa ulang `approvedById` saat menerima `refund`.
- Notifikasi stok menipis dan shift (FCM) belum ada: butuh proyek Firebase (`google-services.json`).
- Font memakai `google_fonts`; tanpa unduhan pertama, aplikasi memakai font bawaan. Untuk offline penuh, taruh font di `assets/`.
