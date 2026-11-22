import '../core/pricing.dart';

enum PayMethod { cash, qris }

enum TxnStatus { paid, voided, returned }

enum SyncState { pending, synced, failed }

PayMethod _method(String? s) => s == 'qris' ? PayMethod.qris : PayMethod.cash;

DateTime _dt(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

class ProductCategory {
  const ProductCategory({required this.id, required this.name});
  final String id;
  final String name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory ProductCategory.fromJson(Map<String, dynamic> j) =>
      ProductCategory(id: j['id'] as String, name: j['name'] as String);
}

class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    required this.price,
    this.categoryId = '',
    this.barcode,
    this.imageUrl,
    this.minStock = 5,
  });
  final String id;
  final String sku;
  final String name;

  /// Nama kategori (hasil resolusi dari [categoryId]).
  final String category;
  final String categoryId;
  final int price; // rupiah bulat
  final String? barcode;
  final String? imageUrl;
  final int minStock;

  Product copyWith({String? category, int? price}) => Product(
        id: id,
        sku: sku,
        name: name,
        category: category ?? this.category,
        categoryId: categoryId,
        price: price ?? this.price,
        barcode: barcode,
        imageUrl: imageUrl,
        minStock: minStock,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'name': name,
        'category': category,
        'categoryId': categoryId,
        'price': price,
        'barcode': barcode,
        'imageUrl': imageUrl,
        'minStock': minStock,
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        sku: (j['sku'] as String?) ?? '',
        name: j['name'] as String,
        category: (j['category'] as String?) ?? '',
        categoryId: (j['categoryId'] as String?) ?? '',
        price: (j['price'] as num).toInt(),
        barcode: j['barcode'] as String?,
        imageUrl: j['imageUrl'] as String?,
        minStock: (j['minStock'] as num?)?.toInt() ?? 5,
      );
}

/// Baris transaksi. Menyimpan snapshot nama dan harga saat transaksi (BR-04).
class TxnLine {
  TxnLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    this.discount = const Discount.none(),
    this.sku = '',
  });
  final String productId;
  final String name;
  final String sku;
  final int unitPrice;
  final int qty;
  final Discount discount;

  PriceLine get priced => PriceLine(unitPrice, qty, discount);
  int get gross => unitPrice * qty;
  int get total => priced.net; // setelah diskon item

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'sku': sku,
        'unitPrice': unitPrice,
        'qty': qty,
        'discount': discount.toJson(),
      };

  factory TxnLine.fromJson(Map<String, dynamic> j) => TxnLine(
        productId: j['productId'] as String,
        name: j['name'] as String,
        sku: (j['sku'] as String?) ?? '',
        unitPrice: (j['unitPrice'] as num).toInt(),
        qty: (j['qty'] as num).toInt(),
        discount: Discount.fromJson((j['discount'] as Map?)?.cast<String, dynamic>()),
      );
}

class Txn {
  Txn({
    required this.uuid,
    required this.id,
    required this.time,
    required this.method,
    required this.lines,
    required this.totals,
    required this.paid,
    this.txnDiscount = const Discount.none(),
    this.taxBps = 0,
    this.status = TxnStatus.paid,
    this.syncState = SyncState.pending,
    this.syncError,
    this.refunded = 0,
    this.shiftId = '',
    this.cashierName = '',
    this.branchId = '',
    this.note = '',
    this.paymentRef,
    this.needsReview = false,
    this.needsReconcile = false,
    Map<String, int>? returnedQty,
  }) : returnedQty = returnedQty ?? {};

  final String uuid; // identitas global, dibuat klien (BR-05)
  final String id; // nomor tampil, mis. TRX-0187
  final DateTime time;
  final PayMethod method;
  final List<TxnLine> lines;
  final Totals totals;
  final int paid; // uang diterima
  final Discount txnDiscount;
  final int taxBps;
  TxnStatus status;
  SyncState syncState;
  String? syncError;
  int refunded;
  final String shiftId;
  final String cashierName;
  final String branchId;
  final String note;
  final String? paymentRef;

  /// Ditandai server: stok negatif, perlu ditinjau manajer (BR-06).
  bool needsReview;

  /// QRIS dicatat saat offline; menunggu pertemuan dengan webhook.
  final bool needsReconcile;
  final Map<String, int> returnedQty; // productId -> qty sudah dikembalikan

  bool get synced => syncState == SyncState.synced;
  int get subtotal => totals.subtotal;
  int get itemDiscount => totals.itemDiscount;
  int get discount => totals.discountTotal;
  int get tax => totals.tax;
  int get total => totals.total;
  int get change => method == PayMethod.cash ? paid - total : 0;
  int get itemCount => lines.fold(0, (s, l) => s + l.qty);
  int get returnableValue => total - refunded;

  int remainingQty(TxnLine l) => l.qty - (returnedQty[l.productId] ?? 0);

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'id': id,
        'time': time.millisecondsSinceEpoch,
        'method': method.name,
        'lines': lines.map((l) => l.toJson()).toList(),
        'totals': {
          'subtotal': totals.subtotal,
          'itemDiscount': totals.itemDiscount,
          'txnDiscount': totals.txnDiscount,
          'taxBase': totals.taxBase,
          'tax': totals.tax,
          'total': totals.total,
        },
        'paid': paid,
        'txnDiscount': txnDiscount.toJson(),
        'taxBps': taxBps,
        'status': status.name,
        'syncState': syncState.name,
        'syncError': syncError,
        'refunded': refunded,
        'shiftId': shiftId,
        'cashierName': cashierName,
        'branchId': branchId,
        'note': note,
        'paymentRef': paymentRef,
        'needsReview': needsReview,
        'needsReconcile': needsReconcile,
        'returnedQty': returnedQty,
      };

  factory Txn.fromJson(Map<String, dynamic> j) {
    final t = j['totals'] as Map<String, dynamic>;
    return Txn(
      uuid: j['uuid'] as String,
      id: j['id'] as String,
      time: _dt(j['time']),
      method: _method(j['method'] as String?),
      lines: (j['lines'] as List)
          .map((e) => TxnLine.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      totals: Totals(
        subtotal: (t['subtotal'] as num).toInt(),
        itemDiscount: (t['itemDiscount'] as num).toInt(),
        txnDiscount: (t['txnDiscount'] as num).toInt(),
        taxBase: (t['taxBase'] as num).toInt(),
        tax: (t['tax'] as num).toInt(),
        total: (t['total'] as num).toInt(),
      ),
      paid: (j['paid'] as num).toInt(),
      txnDiscount: Discount.fromJson((j['txnDiscount'] as Map?)?.cast<String, dynamic>()),
      taxBps: (j['taxBps'] as num?)?.toInt() ?? 0,
      status: TxnStatus.values.byName(j['status'] as String),
      syncState: SyncState.values.byName(j['syncState'] as String),
      syncError: j['syncError'] as String?,
      refunded: (j['refunded'] as num?)?.toInt() ?? 0,
      shiftId: (j['shiftId'] as String?) ?? '',
      cashierName: (j['cashierName'] as String?) ?? '',
      branchId: (j['branchId'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      paymentRef: j['paymentRef'] as String?,
      needsReview: (j['needsReview'] as bool?) ?? false,
      needsReconcile: (j['needsReconcile'] as bool?) ?? false,
      returnedQty: ((j['returnedQty'] as Map?) ?? {})
          .map((k, v) => MapEntry(k as String, (v as num).toInt())),
    );
  }

  /// Muatan yang dikirim ke server (POST /sync/push, type=order).
  Map<String, dynamic> toApiJson() => {
        'uuid': uuid,
        'number': id,
        'createdAt': time.toUtc().toIso8601String(),
        'method': method.name,
        'shiftId': shiftId,
        'branchId': branchId,
        'cashierName': cashierName,
        'note': note,
        'items': lines
            .map((l) => {
                  'productId': l.productId,
                  'name': l.name, // snapshot (BR-04)
                  'unitPrice': l.unitPrice,
                  'qty': l.qty,
                  'discount': l.discount.toJson(),
                })
            .toList(),
        'txnDiscount': txnDiscount.toJson(),
        'taxBps': taxBps,
        'subtotal': totals.subtotal,
        'discountTotal': totals.discountTotal,
        'tax': totals.tax,
        'total': totals.total,
        'paid': paid,
        'paymentRef': paymentRef,
        'needsReconcile': needsReconcile,
      };
}

/// Pengajuan void/retur yang menunggu PIN manajer.
class ReturnRequest {
  ReturnRequest(
      {required this.txnId,
      required this.fullVoid,
      required this.items,
      required this.reason,
      required this.amount});
  final String txnId; // nomor tampil transaksi
  final bool fullVoid;
  final Map<String, int> items; // productId -> qty dikembalikan
  final String reason;
  final int amount;
}

/// Catatan void/retur (BR-07). Transaksi asli tidak dihapus.
class Refund {
  Refund({
    required this.uuid,
    required this.orderUuid,
    required this.fullVoid,
    required this.items,
    required this.reason,
    required this.amount,
    required this.method,
    required this.approvedById,
    required this.approvedByName,
    required this.requestedBy,
    required this.time,
    required this.shiftId,
  });
  final String uuid;
  final String orderUuid;
  final bool fullVoid;
  final Map<String, int> items;
  final String reason;
  final int amount;
  final PayMethod method;
  final String approvedById;
  final String approvedByName;
  final String requestedBy;
  final DateTime time;
  final String shiftId;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'orderUuid': orderUuid,
        'fullVoid': fullVoid,
        'items': items,
        'reason': reason,
        'amount': amount,
        'method': method.name,
        'approvedById': approvedById,
        'approvedByName': approvedByName,
        'requestedBy': requestedBy,
        'time': time.millisecondsSinceEpoch,
        'shiftId': shiftId,
      };

  factory Refund.fromJson(Map<String, dynamic> j) => Refund(
        uuid: j['uuid'] as String,
        orderUuid: j['orderUuid'] as String,
        fullVoid: j['fullVoid'] as bool,
        items: (j['items'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        reason: j['reason'] as String,
        amount: (j['amount'] as num).toInt(),
        method: _method(j['method'] as String?),
        approvedById: j['approvedById'] as String,
        approvedByName: j['approvedByName'] as String,
        requestedBy: j['requestedBy'] as String,
        time: _dt(j['time']),
        shiftId: (j['shiftId'] as String?) ?? '',
      );
}

class Shift {
  Shift({
    required this.uuid,
    required this.cashierId,
    required this.cashierName,
    required this.branchId,
    required this.openedAt,
    required this.openingCash,
    this.closedAt,
    this.closingCash,
    this.expectedCash,
    this.difference,
    this.note = '',
    this.salesTotal = 0,
    this.cashSales = 0,
    this.qrisSales = 0,
    this.cashRefunds = 0,
    this.txnCount = 0,
  });
  final String uuid;
  final String cashierId;
  final String cashierName;
  final String branchId;
  final DateTime openedAt;
  final int openingCash;
  DateTime? closedAt;
  int? closingCash;
  int? expectedCash;
  int? difference;
  String note;
  int salesTotal, cashSales, qrisSales, cashRefunds, txnCount;

  bool get isOpen => closedAt == null;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'branchId': branchId,
        'openedAt': openedAt.millisecondsSinceEpoch,
        'openingCash': openingCash,
        'closedAt': closedAt?.millisecondsSinceEpoch,
        'closingCash': closingCash,
        'expectedCash': expectedCash,
        'difference': difference,
        'note': note,
        'salesTotal': salesTotal,
        'cashSales': cashSales,
        'qrisSales': qrisSales,
        'cashRefunds': cashRefunds,
        'txnCount': txnCount,
      };

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        uuid: j['uuid'] as String,
        cashierId: (j['cashierId'] as String?) ?? '',
        cashierName: (j['cashierName'] as String?) ?? '',
        branchId: (j['branchId'] as String?) ?? '',
        openedAt: _dt(j['openedAt']),
        openingCash: (j['openingCash'] as num).toInt(),
        closedAt: j['closedAt'] == null ? null : _dt(j['closedAt']),
        closingCash: (j['closingCash'] as num?)?.toInt(),
        expectedCash: (j['expectedCash'] as num?)?.toInt(),
        difference: (j['difference'] as num?)?.toInt(),
        note: (j['note'] as String?) ?? '',
        salesTotal: (j['salesTotal'] as num?)?.toInt() ?? 0,
        cashSales: (j['cashSales'] as num?)?.toInt() ?? 0,
        qrisSales: (j['qrisSales'] as num?)?.toInt() ?? 0,
        cashRefunds: (j['cashRefunds'] as num?)?.toInt() ?? 0,
        txnCount: (j['txnCount'] as num?)?.toInt() ?? 0,
      );
}

/// Jenis mutasi stok (BR-03). Saldo stok adalah hasil turunan dari mutasi.
enum MovementType { sale, returned, adjustment, transferIn, transferOut, opening }

class StockMovement {
  StockMovement({
    required this.uuid,
    required this.productId,
    required this.type,
    required this.delta,
    required this.refId,
    required this.time,
    this.synced = false,
  });
  final String uuid;
  final String productId;
  final MovementType type;
  final int delta; // bertanda: penjualan negatif, retur positif
  final String refId; // uuid order/refund
  final DateTime time;
  bool synced;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'productId': productId,
        'type': type.name,
        'delta': delta,
        'refId': refId,
        'time': time.millisecondsSinceEpoch,
        'synced': synced,
      };

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        uuid: j['uuid'] as String,
        productId: j['productId'] as String,
        type: MovementType.values.byName(j['type'] as String),
        delta: (j['delta'] as num).toInt(),
        refId: (j['refId'] as String?) ?? '',
        time: _dt(j['time']),
        synced: (j['synced'] as bool?) ?? false,
      );
}

class AuditEntry {
  AuditEntry({
    required this.uuid,
    required this.actor,
    required this.action,
    required this.entityId,
    required this.time,
    this.before,
    this.after,
    this.detail = '',
  });
  final String uuid;
  final String actor;
  final String action; // mis. order.void, order.return
  final String entityId;
  final DateTime time;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final String detail;

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'actor': actor,
        'action': action,
        'entityId': entityId,
        'time': time.millisecondsSinceEpoch,
        'before': before,
        'after': after,
        'detail': detail,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        uuid: j['uuid'] as String,
        actor: j['actor'] as String,
        action: j['action'] as String,
        entityId: j['entityId'] as String,
        time: _dt(j['time']),
        before: (j['before'] as Map?)?.cast<String, dynamic>(),
        after: (j['after'] as Map?)?.cast<String, dynamic>(),
        detail: (j['detail'] as String?) ?? '',
      );
}

enum OutboxStatus { pending, failed }

/// Satu item antrean kirim. Urutan ditentukan [seq].
class OutboxItem {
  OutboxItem({
    required this.seq,
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt = 0,
    this.status = OutboxStatus.pending,
    this.error,
  });
  final int seq;
  final String id; // UUID entitas (kunci idempotensi)
  final String type; // order | refund | shift
  final Map<String, dynamic> payload;
  final int createdAt;
  int attempts;
  int nextAttemptAt; // epoch ms
  OutboxStatus status;
  String? error;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'id': id,
        'type': type,
        'payload': payload,
        'createdAt': createdAt,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt,
        'status': status.name,
        'error': error,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        seq: (j['seq'] as num).toInt(),
        id: j['id'] as String,
        type: j['type'] as String,
        payload: (j['payload'] as Map).cast<String, dynamic>(),
        createdAt: (j['createdAt'] as num).toInt(),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        nextAttemptAt: (j['nextAttemptAt'] as num?)?.toInt() ?? 0,
        status: OutboxStatus.values.byName((j['status'] as String?) ?? 'pending'),
        error: j['error'] as String?,
      );
}

/// Manajer yang boleh menyetujui void/retur. PIN tidak disimpan polos.
class Approver {
  const Approver(
      {required this.id, required this.name, required this.salt, required this.pinHash});
  final String id;
  final String name;
  final String salt;
  final String pinHash;
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'salt': salt, 'pinHash': pinHash};
  factory Approver.fromJson(Map<String, dynamic> j) => Approver(
      id: j['id'] as String,
      name: j['name'] as String,
      salt: j['salt'] as String,
      pinHash: j['pinHash'] as String);
}

/// Profil sesi (non-rahasia). Token disimpan terpisah di penyimpanan aman.
class Session {
  const Session({
    required this.userId,
    required this.name,
    required this.role,
    required this.tenantId,
    required this.businessName,
    required this.branchId,
    required this.branchName,
    this.taxBps = 0,
    this.approvers = const [],
  });
  final String userId;
  final String name;
  final String role; // owner | manager | cashier
  final String tenantId;
  final String businessName;
  final String branchId;
  final String branchName;
  final int taxBps;
  final List<Approver> approvers;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'role': role,
        'tenantId': tenantId,
        'businessName': businessName,
        'branchId': branchId,
        'branchName': branchName,
        'taxBps': taxBps,
        'approvers': approvers.map((a) => a.toJson()).toList(),
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        userId: j['userId'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        tenantId: j['tenantId'] as String,
        businessName: j['businessName'] as String,
        branchId: j['branchId'] as String,
        branchName: j['branchName'] as String,
        taxBps: (j['taxBps'] as num?)?.toInt() ?? 0,
        approvers: ((j['approvers'] as List?) ?? [])
            .map((e) => Approver.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class AuthTokens {
  const AuthTokens(this.access, this.refresh);
  final String access;
  final String refresh;
}
