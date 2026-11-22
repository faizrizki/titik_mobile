import 'package:flutter_test/flutter_test.dart';
import 'package:titik_mobile/core/format.dart';
import 'package:titik_mobile/core/pricing.dart';

void main() {
  group('computeTotals (BR-01, BR-11)', () {
    test('urutan: diskon item -> diskon transaksi -> pajak atas subtotal setelah diskon', () {
      // 2 x 18.000 (diskon item 10%) + 1 x 15.000
      final t = computeTotals(
        const [PriceLine(18000, 2, Discount.percent(10)), PriceLine(15000, 1)],
        txnDiscount: const Discount.amount(5000),
        taxBps: 1100, // 11%
      );
      expect(t.subtotal, 51000);
      expect(t.itemDiscount, 3600);
      // diskon transaksi dihitung atas 51.000 - 3.600 = 47.400
      expect(t.txnDiscount, 5000);
      expect(t.taxBase, 42400);
      expect(t.tax, 4664); // 42.400 x 11% = 4.664
      expect(t.total, 47064);
    });

    test('diskon transaksi persen dihitung setelah diskon item', () {
      final t = computeTotals(
        const [PriceLine(10000, 1, Discount.amount(2000))],
        txnDiscount: const Discount.percent(50),
      );
      expect(t.taxBase, 4000); // (10.000-2.000) x 50%
      expect(t.total, 4000);
    });

    test('pembulatan half-up ke rupiah, tanpa desimal', () {
      // 1.001 x 10% = 100,1 -> 100 ; 1.005 x 10% = 100,5 -> 101
      expect(const Discount.percent(10).of(1001), 100);
      expect(const Discount.percent(10).of(1005), 101);
      final t = computeTotals(const [PriceLine(333, 1)], taxBps: 1100); // 36,63
      expect(t.tax, 37);
      expect(t.total, 370);
    });

    test('diskon tidak melebihi nilai dan tidak negatif', () {
      expect(const Discount.amount(99999).of(5000), 5000);
      expect(const Discount.amount(-5).of(5000), 0);
      expect(const Discount.percent(150).of(5000), 5000);
      final t = computeTotals(const [PriceLine(1000, 1, Discount.amount(5000))],
          txnDiscount: const Discount.amount(5000), taxBps: 1100);
      expect(t.total, 0);
    });

    test('tanpa pajak dan tanpa diskon: total = subtotal', () {
      final t = computeTotals(const [PriceLine(18000, 2), PriceLine(15000, 1)]);
      expect(t.total, 51000);
      expect(t.tax, 0);
    });
  });

  group('refundAmount', () {
    final lines = const [PriceLine(18000, 2), PriceLine(15000, 1)];
    final totals = computeTotals(lines,
        txnDiscount: const Discount.amount(1000), taxBps: 1100);

    test('retur semua item = total persis', () {
      expect(refundAmount(lines: lines, returnQty: {0: 2, 1: 1}, orderTotal: totals.total),
          totals.total);
    });

    test('retur sebagian memuat porsi diskon dan pajak', () {
      final a = refundAmount(lines: lines, returnQty: {1: 1}, orderTotal: totals.total);
      // porsi 15.000 dari 51.000 x total
      expect(a, roundDiv(totals.total * 15000, 51000));
    });

    test('retur bertahap tidak pernah melebihi total (tanpa selisih pembulatan)', () {
      final first = refundAmount(lines: lines, returnQty: {0: 1}, orderTotal: totals.total);
      final second = refundAmount(
          lines: lines,
          returnQty: {0: 2, 1: 1},
          orderTotal: totals.total,
          alreadyRefunded: first);
      expect(first + second, totals.total);
    });
  });

  test('selisih kas (BR-09)', () {
    expect(
        cashDifference(openingCash: 200000, cashSales: 100000, cashRefunds: 20000, physicalCash: 270000),
        -10000);
    expect(
        cashDifference(openingCash: 200000, cashSales: 0, cashRefunds: 0, physicalCash: 200000),
        0);
  });

  test('format rupiah dan persen', () {
    expect(rupiah(1250000), 'Rp1.250.000');
    expect(rupiah(-5000), '−Rp5.000');
    expect(pctLabel(1100), '11');
    expect(pctLabel(250), '2,5');
  });
}
