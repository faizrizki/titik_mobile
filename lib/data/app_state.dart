import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/pricing.dart';
import 'backend.dart';
import 'local_store.dart';
import 'models.dart';
import 'sync_service.dart';

/// Pengajuan void/retur ditolak karena aturan bisnis.
class BusinessRuleException implements Exception {
  const BusinessRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ringkasan angka satu shift.
class ShiftSummary {
  const ShiftSummary({
    required this.cashSales,
    required this.qrisSales,
    required this.cashRefunds,
    required this.refundsTotal,
    required this.txnCount,
    required this.expectedCash,
  });
  final int cashSales, qrisSales, cashRefunds, refundsTotal, txnCount, expectedCash;
  int get salesTotal => cashSales + qrisSales - refundsTotal;
}

/// State aplikasi di atas database lokal (SQLite) dengan outbox.
///
/// Semua layar membaca dari memori yang di-hidrasi dari database lokal;
/// jaringan hanya dipakai [SyncService]. Setiap perubahan ditulis ke database
/// dalam SATU transaksi (data + outbox + mutasi stok) sebelum memori berubah.
class AppState extends ChangeNotifier {
  AppState({LocalStore? store, TokenStore? tokens, DateTime Function()? now})
      : store = store ?? MemoryStore(),
        tokens = tokens ?? MemoryTokenStore(),
        now = now ?? DateTime.now;

  /// Instans global yang dipakai layar. Diganti saat bootstrap (lihat main.dart).
  static AppState I = AppState();

  final LocalStore store;
  final TokenStore tokens;
  final DateTime Function() now;
  static const _uuid = Uuid();

  AuthApi? auth;
  PaymentGateway? gateway;
  SyncService? sync;

  // ---------- data (hidrasi dari database lokal) ----------
  Session? session;
  final Map<String, Product> _products = {};
  final Map<String, ProductCategory> _categories = {};
  final Map<String, int> _serverStock = {};
  final Map<String, int> stock = {}; // = saldo server + mutasi belum terkirim
  final List<StockMovement> movements = [];
  final List<Txn> txns = []; // terbaru di depan
  final List<Refund> refunds = [];
  final List<Shift> shifts = [];
  final List<AuditEntry> audit = [];
  final List<OutboxItem> _outbox = [];
  final Map<String, String> cursors = {};
  int _orderSeq = 0;
  int _outboxSeq = 0;
  DateTime? lastSyncAt;
  bool loaded = false;

  // ---------- keranjang ----------
  final Map<String, int> cart = {}; // productId -> qty
  final Map<String, Discount> lineDiscounts = {};
  Discount txnDiscount = const Discount.none();
  String cartNote = '';

  /// Memberi tahu pendengar dari luar (mis. SyncService).
  void touch() => notifyListeners();

  /// True bila memakai server simulasi (API_BASE_URL kosong).
  static bool demoMode = false;

  // ---------- init ----------
  Future<void> init() async {
    await store.open();
    for (final j in await store.readAll(T.categories)) {
      final c = ProductCategory.fromJson(j);
      _categories[c.id] = c;
    }
    for (final j in await store.readAll(T.products)) {
      final p = Product.fromJson(j);
      _products[p.id] = p;
    }
    for (final j in await store.readAll(T.stock)) {
      _serverStock[j['productId'] as String] = (j['balance'] as num).toInt();
    }
    movements.addAll((await store.readAll(T.movements)).map(StockMovement.fromJson));
    txns.addAll((await store.readAll(T.orders)).map(Txn.fromJson));
    txns.sort((a, b) => b.time.compareTo(a.time));
    refunds.addAll((await store.readAll(T.refunds)).map(Refund.fromJson));
    shifts.addAll((await store.readAll(T.shifts)).map(Shift.fromJson));
    audit.addAll((await store.readAll(T.audit)).map(AuditEntry.fromJson));
    _outbox
      ..addAll((await store.readAll(T.outbox)).map(OutboxItem.fromJson))
      ..sort((a, b) => a.seq.compareTo(b.seq));
    for (final m in await store.readAll(T.meta)) {
      final id = m['id'] as String;
      if (id == 'session') {
        session = Session.fromJson((m['profile'] as Map).cast<String, dynamic>());
      } else if (id == 'seq') {
        _orderSeq = (m['order'] as num).toInt();
        _outboxSeq = (m['outbox'] as num).toInt();
      } else if (id == 'lastSync') {
        lastSyncAt = DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt());
      } else if (id.startsWith('cursor:')) {
        cursors[id.substring(7)] = m['value'] as String;
      }
    }
    // Sesi hanya valid bila token masih ada di penyimpanan aman.
    if (session != null && await tokens.read() == null) session = null;
    _recomputeStock();
    loaded = true;
    notifyListeners();
  }

  Op get _seqOp => Op.put(T.meta, 'seq', {'id': 'seq', 'order': _orderSeq, 'outbox': _outboxSeq});

  // ---------- akun ----------
  String get cashierName => session?.name ?? '';
  String get businessName => session?.businessName ?? 'titik';
  String get branch => session?.branchName ?? '';
  String get role => session?.role ?? 'cashier';
  bool get loggedIn => session != null;
  int get taxBps => session?.taxBps ?? 0;

  /// Masuk ke server (butuh internet hanya di sini). Data usaha lain dihapus
  /// bila akun berasal dari tenant berbeda.
  Future<void> login(String email, String password) async {
    final api = auth;
    if (api == null) throw StateError('Layanan auth belum dikonfigurasi');
    final (sess, tok) = await api.login(email, password);
    if (session != null && session!.tenantId != sess.tenantId) {
      if (_outbox.isNotEmpty) {
        throw const BusinessRuleException(
            'Masih ada data belum terkirim dari usaha lain di perangkat ini.');
      }
      await _wipeLocal();
    }
    await tokens.write(tok);
    await store.apply([Op.put(T.meta, 'session', {'id': 'session', 'profile': sess.toJson()})]);
    session = sess;
    notifyListeners();
  }

  Future<void> logout() async {
    if (_outbox.isNotEmpty) {
      throw BusinessRuleException('${_outbox.length} data belum terkirim. Sinkronkan dulu.');
    }
    final t = await tokens.read();
    if (t != null) unawaited(auth?.logout(t.refresh) ?? Future.value());
    await tokens.clear();
    await store.apply([const Op.del(T.meta, 'session')]);
    session = null;
    cart.clear();
    lineDiscounts.clear();
    notifyListeners();
  }

  Future<void> _wipeLocal() async {
    await store.wipe();
    _products.clear();
    _categories.clear();
    _serverStock.clear();
    stock.clear();
    movements.clear();
    txns.clear();
    refunds.clear();
    shifts.clear();
    audit.clear();
    _outbox.clear();
    cursors.clear();
    _orderSeq = 0;
    _outboxSeq = 0;
    lastSyncAt = null;
  }

  // ---------- katalog ----------
  List<Product> get products {
    final l = _products.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return l;
  }

  List<ProductCategory> get categories {
    final l = _categories.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return l;
  }

  Product product(String id) => _products[id]!;
  Product? maybeProduct(String id) => _products[id];

  /// Cocokkan SKU atau barcode (tanpa internet).
  Product? bySku(String code) {
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return null;
    for (final p in _products.values) {
      if (p.sku.toLowerCase() == c || (p.barcode ?? '').toLowerCase() == c) return p;
    }
    return null;
  }

  /// Pencarian dan filter kategori dari database lokal.
  List<Product> search(String query, {String? category}) {
    final q = query.trim().toLowerCase();
    return products.where((p) {
      if (category != null && category != 'Semua' && p.category != category) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.barcode ?? '').contains(q);
    }).toList();
  }

  void _recomputeStock() {
    stock.clear();
    for (final id in {..._serverStock.keys, ..._products.keys}) {
      stock[id] = _serverStock[id] ?? 0;
    }
    for (final m in movements) {
      if (!m.synced) stock[m.productId] = (stock[m.productId] ?? 0) + m.delta;
    }
  }

  // ---------- keranjang ----------
  int qtyOf(String id) => cart[id] ?? 0;
  int get cartCount => cart.values.fold(0, (a, b) => a + b);

  Totals get totals => computeTotals(
        [
          for (final e in cart.entries)
            PriceLine(product(e.key).price, e.value, lineDiscounts[e.key] ?? const Discount.none())
        ],
        txnDiscount: txnDiscount,
        taxBps: taxBps,
      );
  int get subtotal => totals.subtotal;
  int get discount => totals.discountTotal;
  int get tax => totals.tax;
  int get total => totals.total;

  /// Penjualan tidak pernah diblokir oleh stok lokal (BR-06); stok negatif
  /// ditandai saat sinkron.
  void add(String id, [int n = 1]) {
    final next = qtyOf(id) + n;
    if (next <= 0) {
      cart.remove(id);
      lineDiscounts.remove(id);
    } else {
      cart[id] = next;
    }
    notifyListeners();
  }

  void setLineDiscount(String id, Discount d) {
    if (d.isNone) {
      lineDiscounts.remove(id);
    } else {
      lineDiscounts[id] = d;
    }
    notifyListeners();
  }

  void setTxnDiscount(Discount d) {
    txnDiscount = d;
    notifyListeners();
  }

  void setNote(String n) {
    cartNote = n.trim();
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    lineDiscounts.clear();
    txnDiscount = const Discount.none();
    cartNote = '';
    notifyListeners();
  }

  String newUuid() => _uuid.v4();

  // ---------- shift (BR-08, BR-09) ----------
  Shift? get currentShift {
    final uid = session?.userId;
    for (final s in shifts) {
      if (s.isOpen && s.cashierId == uid) return s;
    }
    return null;
  }

  /// Shift terakhir (aktif, atau yang baru ditutup) untuk tampilan ringkasan.
  Shift? get activeShift {
    final c = currentShift;
    if (c != null) return c;
    Shift? last;
    for (final s in shifts) {
      if (s.closedAt != null && s.cashierId == session?.userId) {
        if (last == null || s.closedAt!.isAfter(last.closedAt!)) last = s;
      }
    }
    return last;
  }

  bool get shiftOpen => currentShift != null;
  int get openingCash => activeShift?.openingCash ?? 0;
  DateTime get shiftStart => activeShift?.openedAt ?? now();
  int get physicalCash => activeShift?.closingCash ?? 0;

  Future<Shift> openShift(int cash) async {
    final sess = session;
    if (sess == null) throw StateError('Belum masuk');
    if (currentShift != null) {
      throw const BusinessRuleException('Anda masih punya shift yang terbuka.'); // BR-08
    }
    if (cash < 0) throw ArgumentError('Kas awal tidak valid');
    final sh = Shift(
      uuid: _uuid.v4(),
      cashierId: sess.userId,
      cashierName: sess.name,
      branchId: sess.branchId,
      openedAt: now(),
      openingCash: cash,
    );
    final ob = _newOutbox('shift', sh.uuid, sh.toJson());
    await store.apply([
      Op.put(T.shifts, sh.uuid, sh.toJson()),
      Op.put(T.outbox, ob.seq.toString(), ob.toJson()),
      _seqOp,
    ]);
    shifts.add(sh);
    _outbox.add(ob);
    notifyListeners();
    sync?.kick();
    return sh;
  }

  ShiftSummary summaryOf(Shift sh) {
    var cash = 0, qris = 0, count = 0;
    for (final t in txns) {
      if (t.shiftId != sh.uuid) continue;
      if (t.method == PayMethod.cash) {
        cash += t.total;
      } else {
        qris += t.total;
      }
      if (t.status != TxnStatus.voided) count++;
    }
    var cashRef = 0, refTotal = 0;
    for (final r in refunds) {
      if (r.shiftId != sh.uuid) continue;
      refTotal += r.amount;
      if (r.method == PayMethod.cash) cashRef += r.amount;
    }
    return ShiftSummary(
      cashSales: cash,
      qrisSales: qris,
      cashRefunds: cashRef,
      refundsTotal: refTotal,
      txnCount: count,
      expectedCash: sh.openingCash + cash - cashRef,
    );
  }

  ShiftSummary? get summary => activeShift == null ? null : summaryOf(activeShift!);
  int get salesTotal => summary?.salesTotal ?? 0;
  int get cashSales => summary?.cashSales ?? 0;
  int get cashRefunds => summary?.cashRefunds ?? 0;
  int get qrisSales => summary?.qrisSales ?? 0;
  int get txnCount => summary?.txnCount ?? 0;
  int get expectedCash => summary?.expectedCash ?? 0;

  /// Transaksi pada shift aktif/terakhir.
  List<Txn> get shiftTxns {
    final sh = activeShift;
    return sh == null ? [] : txns.where((t) => t.shiftId == sh.uuid).toList();
  }

  /// Menutup shift. Selisih = kas fisik - (kas awal + tunai - retur tunai), selalu disimpan.
  Future<Shift> closeShift(int physical, {String note = ''}) async {
    final sh = currentShift;
    if (sh == null) throw const BusinessRuleException('Tidak ada shift terbuka.');
    final sm = summaryOf(sh);
    final closed = Shift.fromJson(sh.toJson())
      ..closedAt = now()
      ..closingCash = physical
      ..expectedCash = sm.expectedCash
      ..difference = cashDifference(
          openingCash: sh.openingCash,
          cashSales: sm.cashSales,
          cashRefunds: sm.cashRefunds,
          physicalCash: physical)
      ..note = note.trim()
      ..salesTotal = sm.salesTotal
      ..cashSales = sm.cashSales
      ..qrisSales = sm.qrisSales
      ..cashRefunds = sm.cashRefunds
      ..txnCount = sm.txnCount;
    final ob = _newOutbox('shift', closed.uuid, closed.toJson());
    await store.apply([
      Op.put(T.shifts, closed.uuid, closed.toJson()),
      Op.put(T.outbox, ob.seq.toString(), ob.toJson()),
      _seqOp,
    ]);
    shifts[shifts.indexWhere((s) => s.uuid == sh.uuid)] = closed;
    _outbox.add(ob);
    notifyListeners();
    sync?.kick();
    return closed;
  }

  // ---------- checkout ----------
  OutboxItem _newOutbox(String type, String id, Map<String, dynamic> payload) => OutboxItem(
        seq: ++_outboxSeq,
        id: id,
        type: type,
        payload: payload,
        createdAt: now().millisecondsSinceEpoch,
      );

  Txn? txnByUuid(String uuid) {
    for (final t in txns) {
      if (t.uuid == uuid) return t;
    }
    return null;
  }

  /// Menyimpan transaksi: order, mutasi stok, dan outbox ditulis dalam satu
  /// transaksi database (US-05, US-06). [uuid] opsional agar retry tidak
  /// membuat transaksi ganda (BR-05).
  Future<Txn> checkout(
    PayMethod method,
    int received, {
    String? uuid,
    String? paymentRef,
    bool reconcile = false,
  }) async {
    final sess = session;
    if (sess == null) throw StateError('Belum masuk');
    final id = uuid ?? _uuid.v4();
    final dup = txnByUuid(id);
    if (dup != null) return dup;
    final shift = currentShift;
    if (shift == null) throw const BusinessRuleException('Buka shift sebelum berjualan.');
    if (cart.isEmpty) throw const BusinessRuleException('Keranjang kosong.');
    final t = totals;
    if (method == PayMethod.cash && received < t.total) {
      throw const BusinessRuleException('Uang diterima kurang dari total.');
    }

    final lines = [
      for (final e in cart.entries)
        TxnLine(
          productId: e.key,
          name: product(e.key).name, // snapshot (BR-04)
          sku: product(e.key).sku,
          unitPrice: product(e.key).price,
          qty: e.value,
          discount: lineDiscounts[e.key] ?? const Discount.none(),
        )
    ];
    final txn = Txn(
      uuid: id,
      id: 'TRX-${(_orderSeq + 1).toString().padLeft(4, '0')}',
      time: now(),
      method: method,
      lines: lines,
      totals: t,
      paid: method == PayMethod.cash ? received : t.total,
      txnDiscount: txnDiscount,
      taxBps: taxBps,
      shiftId: shift.uuid,
      cashierName: sess.name,
      branchId: sess.branchId,
      note: cartNote,
      paymentRef: paymentRef,
      needsReconcile: reconcile,
    );
    final mv = [
      for (final l in lines)
        StockMovement(
          uuid: _uuid.v4(),
          productId: l.productId,
          type: MovementType.sale,
          delta: -l.qty,
          refId: id,
          time: txn.time,
        )
    ];
    _orderSeq++;
    final ob = _newOutbox('order', id, txn.toApiJson());
    try {
      await store.apply([
        Op.put(T.orders, id, txn.toJson()),
        for (final m in mv) Op.put(T.movements, m.uuid, m.toJson()),
        Op.put(T.outbox, ob.seq.toString(), ob.toJson()),
        _seqOp,
      ]);
    } catch (_) {
      _orderSeq--;
      _outboxSeq--;
      rethrow;
    }
    txns.insert(0, txn);
    movements.addAll(mv);
    for (final m in mv) {
      stock[m.productId] = (stock[m.productId] ?? 0) + m.delta;
    }
    _outbox.add(ob);
    clearCart();
    sync?.kick();
    return txn;
  }

  Txn txn(String id) => txns.firstWhere((t) => t.id == id || t.uuid == id);

  // ---------- void / retur (BR-07, BR-13) ----------
  DateTime? _pinLockedUntil;
  int _pinFails = 0;

  Duration? get pinLockRemaining {
    final u = _pinLockedUntil;
    if (u == null || !u.isAfter(now())) return null;
    return u.difference(now());
  }

  /// Verifikasi PIN manajer secara lokal (berfungsi offline). Terkunci 60 detik
  /// setelah 5 kesalahan berturut-turut.
  Approver? verifyManagerPin(String pin) {
    if (pinLockRemaining != null) return null;
    for (final a in session?.approvers ?? const <Approver>[]) {
      if (hashPin(a.salt, pin) == a.pinHash) {
        _pinFails = 0;
        return a;
      }
    }
    if (++_pinFails >= 5) {
      _pinFails = 0;
      _pinLockedUntil = now().add(const Duration(seconds: 60));
    }
    return null;
  }

  /// Nilai kembali yang dihitung dari aturan harga (tidak dipercayakan ke UI).
  int refundValue(Txn t, Map<String, int> items) {
    final cum = <int, int>{};
    for (var i = 0; i < t.lines.length; i++) {
      final l = t.lines[i];
      cum[i] = (t.returnedQty[l.productId] ?? 0) + (items[l.productId] ?? 0);
    }
    return refundAmount(
      lines: t.lines.map((l) => l.priced).toList(),
      returnQty: cum,
      orderTotal: t.total,
      alreadyRefunded: t.refunded,
    );
  }

  Future<Refund> applyReturn(ReturnRequest r, Approver approver) async {
    final sess = session;
    if (sess == null) throw StateError('Belum masuk');
    if (!sess.approvers.any((a) => a.id == approver.id)) {
      throw const BusinessRuleException('Persetujuan bukan dari manajer terdaftar.');
    }
    if (r.reason.trim().isEmpty) throw const BusinessRuleException('Alasan wajib diisi.');
    final orig = txn(r.txnId);
    if (orig.status == TxnStatus.voided) {
      throw const BusinessRuleException('Transaksi sudah di-void.');
    }
    if (r.fullVoid && orig.refunded > 0) {
      throw const BusinessRuleException('Transaksi sudah punya retur; gunakan retur sebagian.');
    }
    final items = r.fullVoid
        ? {for (final l in orig.lines) l.productId: orig.remainingQty(l)}
        : {...r.items}..removeWhere((_, v) => v <= 0);
    if (items.isEmpty) throw const BusinessRuleException('Tidak ada item yang dikembalikan.');
    for (final e in items.entries) {
      final line = orig.lines.where((l) => l.productId == e.key);
      if (line.isEmpty || e.value > orig.remainingQty(line.first)) {
        throw const BusinessRuleException('Jumlah retur melebihi jumlah yang dibeli.');
      }
    }
    final amount = r.fullVoid ? orig.returnableValue : refundValue(orig, items);
    if (amount <= 0 || amount > orig.returnableValue) {
      throw const BusinessRuleException('Nilai retur tidak valid.');
    }

    final clone = Txn.fromJson(orig.toJson());
    final before = {'status': orig.status.name, 'refunded': orig.refunded};
    items.forEach((pid, q) => clone.returnedQty[pid] = (clone.returnedQty[pid] ?? 0) + q);
    clone.refunded += amount;
    clone.status = r.fullVoid ? TxnStatus.voided : TxnStatus.returned;

    final refund = Refund(
      uuid: _uuid.v4(),
      orderUuid: orig.uuid,
      fullVoid: r.fullVoid,
      items: items,
      reason: r.reason.trim(),
      amount: amount,
      method: orig.method,
      approvedById: approver.id,
      approvedByName: approver.name,
      requestedBy: sess.name,
      time: now(),
      shiftId: currentShift?.uuid ?? '',
    );
    final mv = [
      for (final e in items.entries)
        StockMovement(
          uuid: _uuid.v4(),
          productId: e.key,
          type: MovementType.returned,
          delta: e.value,
          refId: refund.uuid,
          time: refund.time,
        )
    ];
    final entry = AuditEntry(
      uuid: _uuid.v4(),
      actor: '${sess.name} (disetujui ${approver.name})',
      action: r.fullVoid ? 'order.void' : 'order.return',
      entityId: orig.uuid,
      time: refund.time,
      before: before,
      after: {'status': clone.status.name, 'refunded': clone.refunded},
      detail: refund.reason,
    );
    final ob = _newOutbox('refund', refund.uuid, {
      ...refund.toJson(),
      'audit': entry.toJson(),
    });
    await store.apply([
      Op.put(T.orders, orig.uuid, clone.toJson()),
      Op.put(T.refunds, refund.uuid, refund.toJson()),
      for (final m in mv) Op.put(T.movements, m.uuid, m.toJson()),
      Op.put(T.audit, entry.uuid, entry.toJson()),
      Op.put(T.outbox, ob.seq.toString(), ob.toJson()),
      _seqOp,
    ]);
    orig
      ..status = clone.status
      ..refunded = clone.refunded
      ..returnedQty.addAll(clone.returnedQty);
    refunds.add(refund);
    movements.addAll(mv);
    for (final m in mv) {
      stock[m.productId] = (stock[m.productId] ?? 0) + m.delta;
    }
    audit.add(entry);
    _outbox.add(ob);
    notifyListeners();
    sync?.kick();
    return refund;
  }

  // ---------- outbox & sinkronisasi ----------
  bool get online => sync?.online ?? false;
  List<OutboxItem> get outbox => List.unmodifiable(_outbox);
  List<OutboxItem> get pendingOutbox =>
      _outbox.where((o) => o.status == OutboxStatus.pending).toList();
  List<OutboxItem> get failedOutbox =>
      _outbox.where((o) => o.status == OutboxStatus.failed).toList();

  int get pendingSync => txns.where((t) => t.syncState == SyncState.pending).length;
  int get failedSync => failedOutbox.length;
  int get syncedCount => txns.where((t) => t.synced).length;
  bool get lastSyncFailed => failedSync > 0;

  Txn? _txnOfOutbox(OutboxItem o) => o.type == 'order' ? txnByUuid(o.id) : null;

  Future<void> outboxSucceeded(OutboxItem item, PushResult res) async {
    final ops = <Op>[Op.del(T.outbox, item.seq.toString())];
    final t = _txnOfOutbox(item);
    Txn? updated;
    if (t != null) {
      updated = Txn.fromJson(t.toJson())
        ..syncState = SyncState.synced
        ..syncError = null
        ..needsReview = res.flags.contains('negative_stock');
      ops.add(Op.put(T.orders, t.uuid, updated.toJson()));
    }
    // Mutasi item ini kini sudah diterapkan server.
    final ref = item.type == 'order' ? item.id : item.type == 'refund' ? item.id : null;
    final done = ref == null ? <StockMovement>[] : movements.where((m) => m.refId == ref && !m.synced).toList();
    for (final m in done) {
      final nm = StockMovement.fromJson(m.toJson())..synced = true;
      ops.add(Op.put(T.movements, nm.uuid, nm.toJson()));
    }
    await store.apply(ops);
    _outbox.removeWhere((o) => o.seq == item.seq);
    if (t != null && updated != null) {
      t
        ..syncState = SyncState.synced
        ..syncError = null
        ..needsReview = updated.needsReview;
    }
    for (final m in done) {
      m.synced = true;
      _serverStock[m.productId] = (_serverStock[m.productId] ?? 0) + m.delta;
    }
    _recomputeStock();
    notifyListeners();
  }

  /// Kegagalan sementara: jadwalkan ulang dengan backoff.
  Future<void> outboxRetry(OutboxItem item, String error, int nextAttemptAt) async {
    item
      ..attempts += 1
      ..nextAttemptAt = nextAttemptAt
      ..error = error;
    await store.apply([Op.put(T.outbox, item.seq.toString(), item.toJson())]);
    notifyListeners();
  }

  /// Kegagalan permanen: tandai dan tampilkan ke pengguna.
  Future<void> outboxFailed(OutboxItem item, String error) async {
    item
      ..status = OutboxStatus.failed
      ..error = error;
    final ops = <Op>[Op.put(T.outbox, item.seq.toString(), item.toJson())];
    final t = _txnOfOutbox(item);
    if (t != null) {
      t
        ..syncState = SyncState.failed
        ..syncError = error;
      ops.add(Op.put(T.orders, t.uuid, t.toJson()));
    }
    await store.apply(ops);
    notifyListeners();
  }

  /// "Ulangi": item gagal permanen dikembalikan ke antrean.
  Future<void> retryFailed() async {
    final ops = <Op>[];
    for (final o in _outbox.where((o) => o.status == OutboxStatus.failed)) {
      o
        ..status = OutboxStatus.pending
        ..attempts = 0
        ..nextAttemptAt = 0
        ..error = null;
      ops.add(Op.put(T.outbox, o.seq.toString(), o.toJson()));
      final t = _txnOfOutbox(o);
      if (t != null) {
        t
          ..syncState = SyncState.pending
          ..syncError = null;
        ops.add(Op.put(T.orders, t.uuid, t.toJson()));
      }
    }
    if (ops.isNotEmpty) await store.apply(ops);
    notifyListeners();
  }

  Future<void> markSynced() async {
    lastSyncAt = now();
    await store.apply([
      Op.put(T.meta, 'lastSync', {'id': 'lastSync', 'at': lastSyncAt!.millisecondsSinceEpoch})
    ]);
    notifyListeners();
  }

  /// Menerapkan satu halaman perubahan dari server beserta kursor barunya,
  /// atomik. Produk yang dihapus (tombstone) hilang dari katalog lokal
  /// tetapi transaksi lama tetap utuh (snapshot).
  Future<void> applyChanges(String kind, ChangePage page) async {
    final ops = <Op>[];
    switch (kind) {
      case SyncKind.category:
        for (final j in page.items) {
          final c = ProductCategory.fromJson(j);
          _categories[c.id] = c;
          ops.add(Op.put(T.categories, c.id, c.toJson()));
        }
        for (final id in page.deletedIds) {
          _categories.remove(id);
          ops.add(Op.del(T.categories, id));
        }
        // Nama kategori pada produk ikut diperbarui.
        for (final p in _products.values.toList()) {
          final name = _categories[p.categoryId]?.name;
          if (name != null && name != p.category) {
            _products[p.id] = p.copyWith(category: name);
            ops.add(Op.put(T.products, p.id, _products[p.id]!.toJson()));
          }
        }
      case SyncKind.product:
        for (final j in page.items) {
          var p = Product.fromJson(j);
          final name = _categories[p.categoryId]?.name;
          if (name != null) p = p.copyWith(category: name);
          _products[p.id] = p;
          ops.add(Op.put(T.products, p.id, p.toJson()));
        }
        for (final id in page.deletedIds) {
          _products.remove(id);
          cart.remove(id);
          lineDiscounts.remove(id);
          ops.add(Op.del(T.products, id));
        }
      case SyncKind.price:
        for (final j in page.items) {
          final id = j['productId'] as String;
          final p = _products[id];
          if (p == null) continue;
          _products[id] = p.copyWith(price: (j['price'] as num).toInt());
          ops.add(Op.put(T.products, id, _products[id]!.toJson()));
        }
      case SyncKind.stock:
        for (final j in page.items) {
          final id = j['productId'] as String;
          final bal = (j['balance'] as num).toInt();
          _serverStock[id] = bal;
          ops.add(Op.put(T.stock, id, {'productId': id, 'balance': bal}));
        }
    }
    if (page.nextCursor != null) {
      ops.add(Op.put(T.meta, 'cursor:$kind', {'id': 'cursor:$kind', 'value': page.nextCursor}));
    }
    await store.apply(ops);
    if (page.nextCursor != null) cursors[kind] = page.nextCursor!;
    _recomputeStock();
    notifyListeners();
  }

  /// Tes: memuat ulang dari database yang sama (simulasi aplikasi ditutup paksa).
  @visibleForTesting
  Future<AppState> reopen() async {
    final s = AppState(store: store, tokens: tokens, now: now);
    await s.init();
    return s;
  }
}
