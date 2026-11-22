/// Perhitungan harga. Semua nominal integer rupiah (BR-01), tanpa double.
///
/// Urutan tetap (BR-11), harus identik dengan server:
///   1. diskon per item
///   2. diskon transaksi (atas subtotal setelah diskon item)
///   3. pajak atas subtotal setelah semua diskon
/// Pembulatan: half-up ke rupiah terdekat.
library;

/// Diskon berupa nominal rupiah atau persen (0-100).
class Discount {
  const Discount.none()
      : percent = false,
        value = 0;
  const Discount.amount(this.value) : percent = false;
  const Discount.percent(this.value) : percent = true;

  final bool percent;
  final int value;

  bool get isNone => value <= 0;

  /// Nilai diskon terhadap [base], tidak pernah melebihi [base] dan tidak negatif.
  int of(int base) {
    if (value <= 0 || base <= 0) return 0;
    final v = percent ? roundDiv(base * value.clamp(0, 100), 100) : value;
    return v > base ? base : v;
  }

  Map<String, dynamic> toJson() => {'type': percent ? 'percent' : 'amount', 'value': value};

  factory Discount.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Discount.none();
    final v = (j['value'] as num?)?.toInt() ?? 0;
    return j['type'] == 'percent' ? Discount.percent(v) : Discount.amount(v);
  }

  @override
  bool operator ==(Object other) =>
      other is Discount && other.percent == percent && other.value == value;
  @override
  int get hashCode => Object.hash(percent, value);
}

/// Pembagian bilangan bulat dengan pembulatan half-up (untuk n >= 0).
int roundDiv(int n, int d) => (n * 2 + d) ~/ (d * 2);

class PriceLine {
  const PriceLine(this.unitPrice, this.qty, [this.discount = const Discount.none()]);
  final int unitPrice;
  final int qty;
  final Discount discount;

  int get gross => unitPrice * qty;
  int get discountAmount => discount.of(gross);
  int get net => gross - discountAmount;
}

class Totals {
  const Totals({
    required this.subtotal,
    required this.itemDiscount,
    required this.txnDiscount,
    required this.taxBase,
    required this.tax,
    required this.total,
  });

  /// Jumlah harga kotor semua item.
  final int subtotal;
  final int itemDiscount;
  final int txnDiscount;

  /// Subtotal setelah semua diskon, dasar pengenaan pajak.
  final int taxBase;
  final int tax;
  final int total;

  int get discountTotal => itemDiscount + txnDiscount;
}

/// [taxBps]: tarif pajak dalam basis poin (1100 = 11%; 1 bps = 0,01%).
Totals computeTotals(
  List<PriceLine> lines, {
  Discount txnDiscount = const Discount.none(),
  int taxBps = 0,
}) {
  final subtotal = lines.fold(0, (s, l) => s + l.gross);
  final itemDiscount = lines.fold(0, (s, l) => s + l.discountAmount);
  final afterItem = subtotal - itemDiscount;
  final txnDisc = txnDiscount.of(afterItem);
  final base = afterItem - txnDisc;
  final tax = taxBps <= 0 ? 0 : roundDiv(base * taxBps, 10000);
  return Totals(
    subtotal: subtotal,
    itemDiscount: itemDiscount,
    txnDiscount: txnDisc,
    taxBase: base,
    tax: tax,
    total: base + tax,
  );
}

/// Nilai kembali untuk retur: porsi item yang dikembalikan dari total pesanan
/// (termasuk bagian diskon transaksi dan pajaknya).
///
/// [returnQty] adalah jumlah KUMULATIF yang dikembalikan per indeks baris
/// (termasuk retur sebelumnya); [alreadyRefunded] nilai yang sudah dikembalikan.
/// Hasilnya adalah nilai tambahan untuk retur ini. Mengembalikan semua item
/// menghasilkan sisa total persis (tanpa selisih pembulatan), sehingga jumlah
/// kumulatif tidak pernah melebihi [orderTotal].
int refundAmount({
  required List<PriceLine> lines,
  required Map<int, int> returnQty,
  required int orderTotal,
  int alreadyRefunded = 0,
}) {
  final netAll = lines.fold(0, (s, l) => s + l.net);
  if (netAll <= 0) return 0;
  var returnedNet = 0;
  var returnedAll = true;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final q = (returnQty[i] ?? 0).clamp(0, l.qty);
    returnedNet += q == l.qty ? l.net : roundDiv(l.net * q, l.qty);
    if (q != l.qty) returnedAll = false;
  }
  final cumulative = returnedAll ? orderTotal : roundDiv(orderTotal * returnedNet, netAll);
  final amount = cumulative - alreadyRefunded;
  return amount < 0 ? 0 : amount;
}

/// Selisih kas (BR-09): kas fisik - (kas awal + penjualan tunai - retur tunai).
int cashDifference({
  required int openingCash,
  required int cashSales,
  required int cashRefunds,
  required int physicalCash,
}) =>
    physicalCash - (openingCash + cashSales - cashRefunds);
