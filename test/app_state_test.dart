import 'package:flutter_test/flutter_test.dart';
import 'package:titik_mobile/core/pricing.dart';
import 'package:titik_mobile/data/app_state.dart';
import 'package:titik_mobile/data/demo_backend.dart';
import 'package:titik_mobile/data/models.dart';

import 'helpers.dart';

void main() {
  group('transaksi tunai (US-05)', () {
    test('total, diskon, pajak, dan kembalian dihitung benar (BR-11) dan cocok dengan server', () async {
      final server = DemoBackend(autoPayAfter: null)..taxBps = 1100;
      final r = await Rig.create(server: server);
      await r.openShift();
      r.state
        ..add('p1', 2) // 2 x 18.000
        ..add('p2') // 1 x 15.000
        ..setLineDiscount('p1', const Discount.percent(10))
        ..setTxnDiscount(const Discount.amount(5000));

      final totals = r.state.totals;
      expect(totals.subtotal, 51000);
      expect(totals.itemDiscount, 3600);
      expect(totals.txnDiscount, 5000);
      expect(totals.tax, 4664);
      expect(totals.total, 47064);

      final t = await r.state.checkout(PayMethod.cash, 50000);
      expect(t.total, 47064);
      expect(t.change, 2936);
      expect(r.state.cart, isEmpty);
      expect(r.state.txnDiscount.isNone, isTrue);

      await r.sync.syncNow(); // server menghitung ulang dan menerima (tidak ada galat permanen)
      expect(r.state.txn(t.id).synced, isTrue);
      expect(r.server.orders[t.uuid]!['total'], 47064);
    });

    test('snapshot nama dan harga tersimpan di order_items (BR-04)', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final t = await r.sell('p3');
      final item = (t.toApiJson()['items'] as List).single as Map;
      expect(item['name'], 'Cappuccino');
      expect(item['unitPrice'], 22000);
    });

    test('uang kurang ditolak; tanpa shift ditolak; keranjang kosong ditolak', () async {
      final r = await Rig.create(online: false);
      r.state.add('p1');
      await expectLater(r.state.checkout(PayMethod.cash, 18000),
          throwsA(isA<BusinessRuleException>()), reason: 'belum ada shift');
      await r.openShift();
      await expectLater(r.state.checkout(PayMethod.cash, 1000),
          throwsA(isA<BusinessRuleException>()), reason: 'uang kurang');
      r.state.clearCart();
      await expectLater(r.state.checkout(PayMethod.cash, 1000),
          throwsA(isA<BusinessRuleException>()), reason: 'keranjang kosong');
    });

    test('stok lokal habis tidak memblokir penjualan (BR-06)', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      await r.sell('p4', qty: 5); // stok lokal 3
      expect(r.state.stock['p4'], -2);
      expect(r.state.txns.length, 1);
    });
  });

  group('shift dan kas (US-09, BR-08, BR-09)', () {
    test('satu kasir hanya boleh punya satu shift terbuka', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      await expectLater(r.openShift(), throwsA(isA<BusinessRuleException>()));
      expect(r.state.shifts.length, 1);
    });

    test('selisih kas = fisik - (kas awal + tunai - retur tunai), selalu disimpan', () async {
      final r = await Rig.create(online: false);
      await r.openShift(200000);
      await r.sell('p1'); // tunai 18.000
      await r.sell('p3'); // tunai 22.000
      r.state.add('p1');
      await r.state.checkout(PayMethod.qris, 0); // QRIS 18.000 tidak masuk kas
      // retur tunai Rp18.000 atas transaksi pertama
      final first = r.state.txns.last;
      await r.state.applyReturn(
          ReturnRequest(txnId: first.id, fullVoid: true, items: {}, reason: 'Salah input', amount: 0),
          r.manager);

      final sm = r.state.summary!;
      expect(sm.cashSales, 40000);
      expect(sm.qrisSales, 18000);
      expect(sm.cashRefunds, 18000);
      expect(sm.expectedCash, 200000 + 40000 - 18000);

      final closed = await r.state.closeShift(220000, note: 'Kembalian kurang');
      expect(closed.expectedCash, 222000);
      expect(closed.difference, -2000);
      expect(closed.note, 'Kembalian kurang');
      expect(closed.isOpen, isFalse);
      expect(r.state.shiftOpen, isFalse);

      // tersimpan, masuk outbox, dan bertahan setelah buka ulang
      expect(r.state.outbox.where((o) => o.type == 'shift').length, 2); // buka + tutup
      await r.restart();
      expect(r.state.shifts.single.difference, -2000);
      await r.state.openShift(100000); // shift baru boleh setelah yang lama ditutup
    });

    test('transaksi tercatat pada shift yang benar', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final t = await r.sell('p1');
      expect(t.shiftId, r.state.currentShift!.uuid);
      expect(r.state.shiftTxns.single.uuid, t.uuid);
    });
  });

  group('void dan retur (US-10, BR-07, BR-13)', () {
    test('void: transaksi asli tidak dihapus, stok kembali lewat mutasi return, tercatat di audit log',
        () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final t = await r.sell('p1', qty: 2);
      expect(r.state.stock['p1'], 40);

      final refund = await r.state.applyReturn(
          ReturnRequest(txnId: t.id, fullVoid: true, items: {}, reason: 'Pelanggan batal', amount: 0),
          r.manager);

      final after = r.state.txn(t.id);
      expect(after.status, TxnStatus.voided);
      expect(after.refunded, 36000);
      expect(r.state.txns.length, 1, reason: 'transaksi asli tetap ada');
      expect(r.state.stock['p1'], 42);
      final mv = r.state.movements.where((m) => m.type == MovementType.returned).single;
      expect(mv.delta, 2);
      expect(mv.refId, refund.uuid);
      final log = r.state.audit.single;
      expect(log.action, 'order.void');
      expect(log.actor, contains('Dimas'));
      expect(log.before!['status'], 'paid');
      expect(log.after!['status'], 'voided');
      expect(r.state.outbox.where((o) => o.type == 'refund').length, 1);
    });

    test('wajib ada alasan dan persetujuan manajer terdaftar', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final t = await r.sell('p1');
      final req = ReturnRequest(txnId: t.id, fullVoid: true, items: {}, reason: ' ', amount: 0);
      await expectLater(r.state.applyReturn(req, r.manager), throwsA(isA<BusinessRuleException>()));
      const fake = Approver(id: 'orang-lain', name: 'Bukan manajer', salt: 's', pinHash: 'h');
      await expectLater(
          r.state.applyReturn(
              ReturnRequest(txnId: t.id, fullVoid: true, items: {}, reason: 'x', amount: 0), fake),
          throwsA(isA<BusinessRuleException>()));
      expect(r.state.txn(t.id).status, TxnStatus.paid);
    });

    test('retur sebagian bertahap: nilai proporsional, tidak boleh melebihi yang dibeli', () async {
      final server = DemoBackend(autoPayAfter: null)..taxBps = 1100;
      final r = await Rig.create(server: server, online: false);
      await r.openShift();
      r.state
        ..add('p1', 2)
        ..add('p2')
        ..setTxnDiscount(const Discount.amount(1000));
      final t = await r.state.checkout(PayMethod.cash, 100000);

      final a = await r.state.applyReturn(
          ReturnRequest(txnId: t.id, fullVoid: false, items: {'p1': 1}, reason: 'Rusak', amount: 0),
          r.manager);
      expect(r.state.txn(t.id).status, TxnStatus.returned);
      expect(a.amount, greaterThan(0));
      expect(r.state.stock['p1'], 41);

      await expectLater(
          r.state.applyReturn(
              ReturnRequest(txnId: t.id, fullVoid: false, items: {'p1': 2}, reason: 'Rusak', amount: 0),
              r.manager),
          throwsA(isA<BusinessRuleException>()),
          reason: 'sisa hanya 1 p1');

      final b = await r.state.applyReturn(
          ReturnRequest(txnId: t.id, fullVoid: false, items: {'p1': 1, 'p2': 1}, reason: 'Rusak', amount: 0),
          r.manager);
      expect(a.amount + b.amount, t.total, reason: 'total retur kumulatif = total transaksi');
      expect(r.state.txn(t.id).refunded, t.total);
    });

    test('void ganda ditolak', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final t = await r.sell('p1');
      final req = ReturnRequest(txnId: t.id, fullVoid: true, items: {}, reason: 'x', amount: 0);
      await r.state.applyReturn(req, r.manager);
      await expectLater(r.state.applyReturn(req, r.manager), throwsA(isA<BusinessRuleException>()));
    });

    test('retur offline terkirim ke server dan stok server kembali', () async {
      final r = await Rig.create();
      await r.openShift();
      final t = await r.sell('p1', qty: 2);
      await r.sync.syncNow();
      await r.state.applyReturn(
          ReturnRequest(txnId: t.id, fullVoid: true, items: {}, reason: 'Salah input', amount: 0),
          r.manager);
      await r.sync.syncNow();
      expect(r.server.refunds.length, 1);
      expect(r.server.serverStock['p1'], 42);
      expect(r.state.stock['p1'], 42);
      expect(r.state.outbox, isEmpty);
    });

    test('PIN manajer: salah ditolak, terkunci setelah 5 kali, terbuka lagi setelah 60 detik', () async {
      final r = await Rig.create(online: false);
      expect(r.state.verifyManagerPin('1234')?.name, 'Dimas Prakoso');
      for (var i = 0; i < 5; i++) {
        expect(r.state.verifyManagerPin('0000'), isNull);
      }
      expect(r.state.pinLockRemaining, isNotNull);
      expect(r.state.verifyManagerPin('1234'), isNull, reason: 'terkunci walau PIN benar');
      r.clock.advance(const Duration(seconds: 61));
      expect(r.state.pinLockRemaining, isNull);
      expect(r.state.verifyManagerPin('1234'), isNotNull);
    });

    test('PIN tidak disimpan polos', () async {
      final r = await Rig.create(online: false);
      final a = r.manager;
      expect(a.pinHash, isNot('1234'));
      expect(a.pinHash.length, greaterThan(20));
    });
  });
}
