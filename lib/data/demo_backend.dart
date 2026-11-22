import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/pricing.dart';
import 'backend.dart';
import 'models.dart';

/// Server simulasi di dalam aplikasi (mode demo / tes). Meniru kontrak API:
/// idempotensi per UUID, delta pull dengan kursor dan tombstone, tanda stok
/// negatif, verifikasi total (BR-11), dan webhook QRIS bertanda tangan (BR-10).
///
/// Dipakai bila `API_BASE_URL` tidak diisi. Bukan pengganti backend sungguhan.
class DemoBackend implements SyncApi, AuthApi, PaymentGateway {
  DemoBackend({DateTime Function()? now, this.autoPayAfter = const Duration(seconds: 8)})
      : _now = now ?? DateTime.now {
    _seed();
  }

  final DateTime Function() _now;

  /// QRIS demo otomatis lunas setelah jeda ini (null = hanya lewat webhook).
  final Duration? autoPayAfter;
  static const webhookSecret = 'demo-webhook-secret';

  // ---- kendali simulasi (tes) ----
  bool online = true;
  int _failNext = 0;
  bool _failPermanent = false;
  void failNext(int n, {bool permanent = false}) {
    _failNext = n;
    _failPermanent = permanent;
  }

  int pushCalls = 0;

  // ---- data server ----
  int _version = 0;
  final Map<String, (int, ProductCategory)> _cats = {};
  final Map<String, (int, Product)> _prods = {};
  final Map<String, int> _tombstoneVersion = {};
  final Map<String, int> serverStock = {};
  final Map<String, int> _stockVersion = {};
  final Map<String, (int, int)> _priceVersion = {}; // productId -> (versi, harga)
  final Map<String, Map<String, dynamic>> orders = {};
  final Map<String, Set<String>> orderFlags = {};
  final Map<String, Map<String, dynamic>> refunds = {};
  final Map<String, Map<String, dynamic>> shifts = {};
  final Map<String, Map<String, dynamic>> _charges = {};
  final Set<String> _webhookEvents = {};
  int taxBps = 0;
  int _loginFails = 0;

  void _seed() {
    for (final c in const [('c1', 'Kopi'), ('c2', 'Non-kopi'), ('c3', 'Makanan')]) {
      _cats[c.$1] = (++_version, ProductCategory(id: c.$1, name: c.$2));
    }
    void prod(String id, String sku, String name, String cat, int price, int stock,
        {int min = 5}) {
      _prods[id] = (
        ++_version,
        Product(
            id: id,
            sku: sku,
            name: name,
            category: '',
            categoryId: cat,
            price: price,
            barcode: '89900000000${id.substring(1).padLeft(2, '0')}',
            minStock: min)
      );
      serverStock[id] = stock;
      _stockVersion[id] = ++_version;
    }

    prod('p1', 'KOP-001', 'Kopi susu gula aren', 'c1', 18000, 42);
    prod('p2', 'KOP-002', 'Americano', 'c1', 15000, 38);
    prod('p3', 'KOP-003', 'Cappuccino', 'c1', 22000, 5);
    prod('p4', 'NON-001', 'Matcha latte', 'c2', 24000, 3);
    prod('p5', 'NON-002', 'Es teh lemon', 'c2', 12000, 25);
    prod('p6', 'MKN-001', 'Croissant butter', 'c3', 20000, 12);
    prod('p7', 'MKN-002', 'Roti bakar cokelat', 'c3', 16000, 9);
  }

  // ---- ubah katalog di sisi server (dipakai tes) ----
  void setPrice(String id, int price) {
    final (_, p) = _prods[id]!;
    _prods[id] = (++_version, p.copyWith(price: price));
    _priceVersion[id] = (_version, price);
  }

  void deleteProduct(String id) {
    _prods.remove(id);
    _tombstoneVersion[id] = ++_version;
  }

  void setServerStock(String id, int balance) {
    serverStock[id] = balance;
    _stockVersion[id] = ++_version;
  }

  void _gate() {
    if (!online) throw const SyncException('Tidak ada koneksi', permanent: false);
    if (_failNext > 0) {
      _failNext--;
      throw SyncException(_failPermanent ? 'Data tidak valid' : 'Server error',
          permanent: _failPermanent, status: _failPermanent ? 422 : 503);
    }
  }

  // ===== AuthApi =====
  @override
  Future<(Session, AuthTokens)> login(String email, String password) async {
    if (!online) throw const SyncException('Tidak ada koneksi');
    if (_loginFails >= 5) {
      throw const SyncException('Terlalu banyak percobaan. Coba lagi nanti.',
          permanent: false, status: 429);
    }
    if (email.trim().toLowerCase() != 'sari@kopisudut.id' || password != 'rahasia123') {
      _loginFails++;
      throw const SyncException('Email atau kata sandi salah.', permanent: true, status: 401);
    }
    _loginFails = 0;
    const salt = 'demo-salt';
    return (
      Session(
        userId: 'u-sari',
        name: 'Sari Lestari',
        role: 'cashier',
        tenantId: 't-kopi-sudut',
        businessName: 'Kopi Sudut',
        branchId: 'b-dipatiukur',
        branchName: 'Sudut Dipatiukur',
        taxBps: taxBps,
        approvers: [
          Approver(id: 'u-dimas', name: 'Dimas Prakoso', salt: salt, pinHash: hashPin(salt, '1234')),
        ],
      ),
      const AuthTokens('demo-access', 'demo-refresh')
    );
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    if (!online) throw const SyncException('Tidak ada koneksi');
    if (refreshToken != 'demo-refresh') {
      throw const SyncException('Sesi berakhir', permanent: true, status: 401, authExpired: true);
    }
    return const AuthTokens('demo-access', 'demo-refresh');
  }

  @override
  Future<void> logout(String refreshToken) async {}

  // ===== SyncApi =====
  @override
  Future<PushResult> push(OutboxItem item) async {
    pushCalls++;
    _gate();
    switch (item.type) {
      case 'shift':
        shifts[item.id] = item.payload;
        return const PushResult();
      case 'order':
        return _pushOrder(item);
      case 'refund':
        return _pushRefund(item);
      default:
        throw SyncException('Jenis tidak dikenal: ${item.type}', permanent: true, status: 400);
    }
  }

  PushResult _pushOrder(OutboxItem item) {
    final o = item.payload;
    final uuid = o['uuid'] as String;
    if (orders.containsKey(uuid)) return const PushResult(duplicate: true); // BR-05
    final items = (o['items'] as List?) ?? const [];
    if (items.isEmpty) {
      throw const SyncException('Pesanan tanpa item', permanent: true, status: 422);
    }
    // Hitung ulang dengan aturan yang sama (BR-11); harga & nama dari snapshot klien.
    final lines = [
      for (final i in items.cast<Map>())
        PriceLine((i['unitPrice'] as num).toInt(), (i['qty'] as num).toInt(),
            Discount.fromJson((i['discount'] as Map?)?.cast<String, dynamic>()))
    ];
    final t = computeTotals(lines,
        txnDiscount: Discount.fromJson((o['txnDiscount'] as Map?)?.cast<String, dynamic>()),
        taxBps: (o['taxBps'] as num?)?.toInt() ?? 0);
    if (t.total != (o['total'] as num).toInt()) {
      throw const SyncException('Total tidak cocok dengan perhitungan server',
          permanent: true, status: 422);
    }
    final flags = <String>{};
    for (final i in items.cast<Map>()) {
      final pid = i['productId'] as String;
      final bal = (serverStock[pid] ?? 0) - (i['qty'] as num).toInt();
      serverStock[pid] = bal;
      _stockVersion[pid] = ++_version;
      if (bal < 0) flags.add('negative_stock'); // BR-06: tetap diterima
    }
    orders[uuid] = o;
    if (flags.isNotEmpty) orderFlags[uuid] = flags;
    return PushResult(flags: flags.toList());
  }

  PushResult _pushRefund(OutboxItem item) {
    final r = item.payload;
    final uuid = r['uuid'] as String;
    if (refunds.containsKey(uuid)) return const PushResult(duplicate: true);
    if (!orders.containsKey(r['orderUuid'])) {
      throw const SyncException('Pesanan asal tidak ditemukan', permanent: true, status: 404);
    }
    if ((r['reason'] as String? ?? '').trim().isEmpty || (r['approvedById'] as String? ?? '').isEmpty) {
      throw const SyncException('Alasan dan persetujuan manajer wajib (BR-07)',
          permanent: true, status: 422);
    }
    for (final e in (r['items'] as Map).entries) {
      serverStock[e.key as String] = (serverStock[e.key] ?? 0) + (e.value as num).toInt();
      _stockVersion[e.key as String] = ++_version;
    }
    refunds[uuid] = r;
    return const PushResult();
  }

  @override
  Future<ChangePage> changes(String kind, String? cursor, {int limit = 200}) async {
    _gate();
    final since = int.tryParse(cursor ?? '') ?? 0;
    final rows = <(int, Map<String, dynamic>)>[];
    final dead = <(int, String)>[];
    switch (kind) {
      case SyncKind.category:
        for (final e in _cats.values) {
          if (e.$1 > since) rows.add((e.$1, e.$2.toJson()));
        }
      case SyncKind.product:
        for (final e in _prods.values) {
          if (e.$1 > since) rows.add((e.$1, e.$2.toJson()));
        }
        for (final e in _tombstoneVersion.entries) {
          if (e.value > since) dead.add((e.value, e.key));
        }
      case SyncKind.price:
        for (final e in _priceVersion.entries) {
          if (e.value.$1 > since) rows.add((e.value.$1, {'productId': e.key, 'price': e.value.$2}));
        }
      case SyncKind.stock:
        for (final e in _stockVersion.entries) {
          if (e.value > since) {
            rows.add((e.value, {'productId': e.key, 'balance': serverStock[e.key] ?? 0}));
          }
        }
      default:
        throw SyncException('Jenis tidak dikenal: $kind', permanent: true, status: 400);
    }
    final all = <(int, Object)>[...rows, ...dead]..sort((a, b) => a.$1.compareTo(b.$1));
    final page = all.take(limit).toList();
    final more = all.length > page.length;
    final items = <Map<String, dynamic>>[];
    final ids = <String>[];
    for (final e in page) {
      if (e.$2 is String) {
        ids.add(e.$2 as String);
      } else {
        items.add(e.$2 as Map<String, dynamic>);
      }
    }
    final next = page.isEmpty ? cursor : '${page.last.$1}';
    return ChangePage(items: items, deletedIds: ids, nextCursor: next, hasMore: more);
  }

  // ===== PaymentGateway =====
  @override
  Future<QrisCharge> createQris({required String orderUuid, required int amount}) async {
    if (!online) throw const SyncException('Tidak ada koneksi');
    final id = 'qr-${_charges.length + 1}-${Random().nextInt(1 << 20)}';
    final exp = _now().add(const Duration(minutes: 15));
    _charges[id] = {
      'orderUuid': orderUuid,
      'amount': amount,
      'expiresAt': exp,
      'paidAt': autoPayAfter == null ? null : _now().add(autoPayAfter!),
      'paid': false,
    };
    return QrisCharge(id: id, qrString: 'DEMO-QRIS|$id|$amount|$orderUuid', amount: amount, expiresAt: exp);
  }

  @override
  Future<QrisState> status(String chargeId) async {
    if (!online) throw const SyncException('Tidak ada koneksi');
    final c = _charges[chargeId];
    if (c == null) throw const SyncException('Tagihan tidak ditemukan', permanent: true, status: 404);
    final paidAt = c['paidAt'] as DateTime?;
    if (paidAt != null && !_now().isBefore(paidAt)) {
      // Dalam demo, "webhook" datang dari simulasi pembayaran.
      c['paid'] = true;
    }
    if (c['paid'] == true) return QrisState.paid;
    if (_now().isAfter(c['expiresAt'] as DateTime)) return QrisState.expired;
    return QrisState.pending;
  }

  /// Tanda tangan webhook yang sah untuk [body].
  static String sign(String body) =>
      Hmac(sha256, utf8.encode(webhookSecret)).convert(utf8.encode(body)).toString();

  /// Webhook gateway (BR-10): tanda tangan wajib valid, diproses sekali.
  /// Mengembalikan true bila diproses, false bila duplikat.
  bool handleWebhook(String body, String signature) {
    if (sign(body) != signature) {
      throw const SyncException('Tanda tangan webhook tidak valid', permanent: true, status: 401);
    }
    final j = jsonDecode(body) as Map<String, dynamic>;
    final eventId = j['eventId'] as String;
    if (!_webhookEvents.add(eventId)) return false;
    final c = _charges[j['chargeId']];
    if (c == null) {
      throw const SyncException('Tagihan tidak ditemukan', permanent: true, status: 404);
    }
    if (j['status'] == 'paid') c['paid'] = true;
    return true;
  }
}
