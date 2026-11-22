import 'package:flutter_test/flutter_test.dart';
import 'package:titik_mobile/data/app_state.dart';
import 'package:titik_mobile/data/backend.dart';
import 'package:titik_mobile/data/demo_backend.dart';
import 'package:titik_mobile/data/local_store.dart';
import 'package:titik_mobile/data/models.dart';
import 'package:titik_mobile/data/sync_service.dart';

import 'helpers.dart';

/// Server yang menerima push tetapi "aplikasi mati" sebelum kasir mencatat hasilnya.
class _CrashAfterPush implements SyncApi {
  _CrashAfterPush(this.inner, this.crashOnCall);
  final DemoBackend inner;
  final int crashOnCall;
  int calls = 0;
  @override
  Future<PushResult> push(OutboxItem item) async {
    final r = await inner.push(item);
    if (++calls == crashOnCall) throw StateError('aplikasi ditutup paksa');
    return r;
  }

  @override
  Future<ChangePage> changes(String kind, String? cursor, {int limit = 200}) =>
      inner.changes(kind, cursor, limit: limit);
}

void main() {
  group('offline dan outbox (US-06)', () {
    test('transaksi offline tersimpan lokal dengan UUID dan masuk outbox', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final t = await r.sell('p1', qty: 2);

      expect(t.uuid, isNotEmpty);
      expect(t.syncState, SyncState.pending);
      expect(r.state.pendingSync, 1);
      final ob = r.state.outbox.where((o) => o.type == 'order').single;
      expect(ob.id, t.uuid);
      expect(r.server.orders, isEmpty); // belum ada yang terkirim
      expect(r.state.stock['p1'], 40); // stok lokal berkurang: 42 - 2
    });

    test('tidak ada fitur inti yang terkunci: bisa jualan saat offline berkali-kali', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      for (var i = 0; i < 5; i++) {
        await r.sell('p2');
      }
      expect(r.state.txns.length, 5);
      expect(r.state.pendingSync, 5);
    });
  });

  group('push idempoten (US-07, BR-05, BR-06)', () {
    test('500 transaksi offline tersinkron seluruhnya tanpa duplikat', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final uuids = <String>[];
      for (var i = 0; i < 500; i++) {
        uuids.add((await r.sell(i.isEven ? 'p1' : 'p2')).uuid);
      }
      expect(r.state.pendingSync, 500);

      r.probe.set(true);
      await r.sync.syncNow();

      expect(r.server.orders.length, 500);
      expect(r.server.orders.keys.toSet(), uuids.toSet());
      expect(r.server.orders.keys.toList(), uuids, reason: 'urutan kirim = urutan dibuat');
      expect(r.state.outbox, isEmpty);
      expect(r.state.txns.every((t) => t.synced), isTrue);
      expect(r.server.pushCalls, 501); // 500 order + 1 shift, tanpa kiriman ganda
      // 250 x p1 dari stok 42 -> negatif: transaksi tetap sah, ditandai (BR-06)
      expect(r.server.serverStock['p1'], 42 - 250);
      expect(r.state.txns.where((t) => t.needsReview), isNotEmpty);
      expect(r.state.stock['p1'], 42 - 250);
    });

    test('pengiriman ulang UUID yang sama tidak mengubah stok dua kali', () async {
      final r = await Rig.create();
      await r.openShift();
      final t = await r.sell('p1', qty: 3);
      await r.sync.syncNow();
      expect(r.server.serverStock['p1'], 39);

      final dupe = OutboxItem(
          seq: 999,
          id: t.uuid,
          type: 'order',
          payload: t.toApiJson(),
          createdAt: 0);
      final res = await r.server.push(dupe);
      expect(res.duplicate, isTrue);
      expect(r.server.serverStock['p1'], 39);
      expect(r.server.orders.length, 1);
    });

    test('checkout dengan UUID yang sama dua kali (ketuk ganda) hanya membuat satu transaksi',
        () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      const id = 'order-uuid-1';
      r.state.add('p1');
      final a = await r.state.checkout(PayMethod.cash, 18000, uuid: id);
      r.state.add('p1');
      final b = await r.state.checkout(PayMethod.cash, 18000, uuid: id);
      expect(identical(a, b), isTrue);
      expect(r.state.txns.length, 1);
      expect(r.state.outbox.where((o) => o.type == 'order').length, 1);
    });

    test('penulisan order, mutasi stok, dan outbox atomik: gagal tulis tidak meninggalkan sisa',
        () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      r.state.add('p1', 2);
      r.store.failAfterOps = 2; // gagal di tengah transaksi database
      await expectLater(r.state.checkout(PayMethod.cash, 36000), throwsStateError);
      r.store.failAfterOps = null;

      expect(r.state.txns, isEmpty);
      expect(r.state.outbox.where((o) => o.type == 'order'), isEmpty);
      expect(r.state.stock['p1'], 42);
      await r.restart();
      expect(r.state.txns, isEmpty);
      expect((await r.store.readAll(T.orders)), isEmpty);
      expect((await r.store.readAll(T.movements)), isEmpty);
    });

    test('data tetap utuh setelah aplikasi dibuka ulang', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final t = await r.sell('p3');
      await r.restart();

      expect(r.state.loggedIn, isTrue);
      expect(r.state.txns.single.uuid, t.uuid);
      expect(r.state.outbox.where((o) => o.type == 'order').single.id, t.uuid);
      expect(r.state.stock['p3'], 4);
      expect(r.state.shiftOpen, isTrue);
      expect(r.state.products.length, 7);
    });

    test('server menolak total yang tidak cocok dengan perhitungan (BR-11): kegagalan permanen',
        () async {
      final r = await Rig.create();
      await r.openShift();
      final t = await r.sell('p1');
      final bad = t.toApiJson()..['total'] = 1;
      await expectLater(
          r.server.push(OutboxItem(seq: 1, id: 'x', type: 'order', payload: {...bad, 'uuid': 'x'}, createdAt: 0)),
          throwsA(isA<SyncException>().having((e) => e.permanent, 'permanent', isTrue)));
    });
  });

  group('kegagalan dan backoff', () {
    test('kegagalan sementara: exponential backoff, urutan terjaga, pulih otomatis', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final a = await r.sell('p1');
      final b = await r.sell('p2');
      final c = await r.sell('p5');
      r.probe.set(true);

      r.server.failNext(1); // 5xx pada item pertama (shift)
      await r.sync.syncNow();
      final head = r.state.pendingOutbox.first;
      expect(head.type, 'shift');
      expect(head.attempts, 1);
      expect(head.nextAttemptAt, r.clock.now().millisecondsSinceEpoch + 2000);
      expect(r.server.orders, isEmpty, reason: 'item di belakang tidak boleh menyalip');
      final callsAfterFirst = r.server.pushCalls;

      await r.sync.syncNow(); // masih dalam jeda backoff
      expect(r.server.pushCalls, callsAfterFirst);

      r.clock.advance(const Duration(seconds: 2));
      r.server.failNext(1); // gagal lagi -> jeda 4 detik
      await r.sync.syncNow();
      expect(r.state.pendingOutbox.first.attempts, 2);
      expect(r.state.pendingOutbox.first.nextAttemptAt,
          r.clock.now().millisecondsSinceEpoch + 4000);

      r.clock.advance(const Duration(seconds: 4));
      await r.sync.syncNow();
      expect(r.state.outbox, isEmpty);
      expect(r.server.orders.keys.toList(), [a.uuid, b.uuid, c.uuid]);
    });

    test('rumus backoff: 2,4,8,... detik, dibatasi 5 menit', () async {
      final r = await Rig.create();
      expect(r.sync.backoff(0), const Duration(seconds: 2));
      expect(r.sync.backoff(1), const Duration(seconds: 4));
      expect(r.sync.backoff(3), const Duration(seconds: 16));
      expect(r.sync.backoff(30), const Duration(minutes: 5));
    });

    test('kegagalan permanen ditandai dan ditampilkan; item lain tetap terkirim; bisa diulangi',
        () async {
      final r = await Rig.create();
      await r.openShift();
      await r.sync.syncNow(); // shift terkirim
      r.probe.set(false);
      final a = await r.sell('p1');
      final b = await r.sell('p2');
      r.probe.set(true);

      r.server.failNext(1, permanent: true);
      await r.sync.syncNow();

      expect(r.state.txn(a.id).syncState, SyncState.failed);
      expect(r.state.txn(a.id).syncError, isNotNull);
      expect(r.state.failedSync, 1);
      expect(r.state.lastSyncFailed, isTrue);
      expect(r.state.txn(b.id).synced, isTrue, reason: 'item berikutnya tetap lanjut');
      expect(r.server.orders.containsKey(a.uuid), isFalse);

      // Tombol "Ulangi" mengembalikan item ke antrean.
      await r.sync.syncNow(force: true);
      expect(r.state.txn(a.id).synced, isTrue);
      expect(r.state.failedSync, 0);
      expect(r.server.orders.containsKey(a.uuid), isTrue);
    });

    test('menutup paksa aplikasi saat sinkron tidak menghilangkan atau menggandakan transaksi',
        () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      final uuids = [for (var i = 0; i < 5; i++) (await r.sell('p1')).uuid];
      r.probe.set(true);

      // Server menerima item ke-3 tetapi aplikasi mati sebelum mencatat hasilnya.
      final crash = SyncService(
          state: r.state,
          api: _CrashAfterPush(r.server, 3),
          probe: r.probe,
          periodic: const Duration(days: 1));
      await expectLater(crash.syncNow(), throwsStateError);

      await r.restart(); // buka ulang dari database yang sama
      expect(r.state.txns.length, 5, reason: 'tidak ada transaksi hilang');
      await r.sync.syncNow();

      expect(r.server.orders.keys.toList(), uuids);
      expect(r.server.serverStock['p1'], 42 - 5, reason: 'stok dikurangi tepat sekali');
      expect(r.state.outbox, isEmpty);
      expect(r.state.txns.every((t) => t.synced), isTrue);
    });
  });

  group('konflik (spesifikasi sinkronisasi)', () {
    test('dua perangkat offline menjual produk yang sama: keduanya diterima, stok konsisten, selisih ditandai',
        () async {
      final server = DemoBackend(autoPayAfter: null);
      final a = await Rig.create(server: server);
      final b = await Rig.create(server: server);
      a.probe.set(false);
      b.probe.set(false);
      await a.openShift();
      await b.openShift();
      // p4 (Matcha latte) stok server 3; masing-masing perangkat menjual 2.
      final ta = await a.sell('p4', qty: 2);
      final tb = await b.sell('p4', qty: 2);

      a.probe.set(true);
      await a.sync.syncNow();
      b.probe.set(true);
      await b.sync.syncNow();
      await a.sync.syncNow(); // A menarik stok akhir

      expect(server.orders.length, 2, reason: 'keduanya diterima');
      expect(server.serverStock['p4'], -1);
      expect(a.state.txn(ta.id).needsReview, isFalse);
      expect(b.state.txn(tb.id).needsReview, isTrue, reason: 'yang membuat stok negatif ditandai');
      expect(a.state.stock['p4'], -1);
      expect(b.state.stock['p4'], -1);
    });

    test('stok lokal = saldo server + mutasi yang belum terkirim', () async {
      final r = await Rig.create();
      await r.openShift();
      r.probe.set(false);
      await r.sell('p1', qty: 2);
      expect(r.state.stock['p1'], 40);
      r.server.setServerStock('p1', 100); // perangkat lain menambah stok

      r.probe.set(true);
      await r.sync.syncNow();
      expect(r.server.serverStock['p1'], 98);
      expect(r.state.stock['p1'], 98);
    });

    test('QRIS yang dicatat saat offline ditandai untuk rekonsiliasi', () async {
      final r = await Rig.create(online: false);
      await r.openShift();
      r.state.add('p1');
      final t = await r.state.checkout(PayMethod.qris, 0, reconcile: true);
      expect(t.needsReconcile, isTrue);
      expect(t.toApiJson()['needsReconcile'], isTrue);
    });
  });

  group('pull delta (US-04, BR-12)', () {
    test('unduhan awal memakai kursor kosong dengan pagination', () async {
      final server = DemoBackend(autoPayAfter: null);
      final state = AppState(store: MemoryStore())..auth = server;
      await state.init();
      final sync = SyncService(
          state: state,
          api: server,
          probe: ManualConnectivity(),
          pageSize: 2,
          periodic: const Duration(days: 1));
      state.sync = sync;
      await state.login('sari@kopisudut.id', 'rahasia123');
      await sync.syncNow();

      expect(state.products.length, 7);
      expect(state.categories.map((c) => c.name), ['Kopi', 'Makanan', 'Non-kopi']);
      expect(state.product('p1').category, 'Kopi');
      expect(state.stock['p1'], 42);
      expect(state.cursors.keys, containsAll([SyncKind.category, SyncKind.product, SyncKind.stock]));
    });

    test('perubahan harga turun lewat pull; riwayat transaksi memakai snapshot (BR-04)', () async {
      final r = await Rig.create();
      await r.openShift();
      final t = await r.sell('p5');
      expect(t.lines.single.unitPrice, 12000);

      r.server.setPrice('p5', 15000);
      await r.sync.syncNow();

      expect(r.state.product('p5').price, 15000);
      expect(r.state.txn(t.id).lines.single.unitPrice, 12000);
      expect(r.state.txn(t.id).total, 12000);
    });

    test('produk dihapus dikirim sebagai tombstone dan hilang dari katalog lokal', () async {
      final r = await Rig.create();
      await r.openShift();
      final t = await r.sell('p6');
      r.state.add('p6'); // ada di keranjang saat dihapus
      r.server.deleteProduct('p6');
      await r.sync.syncNow();

      expect(r.state.maybeProduct('p6'), isNull);
      expect(r.state.cart.containsKey('p6'), isFalse);
      expect(r.state.txn(t.id).lines.single.name, 'Croissant butter'); // riwayat utuh
    });

    test('kursor tersimpan: setelah buka ulang hanya perubahan baru yang diunduh', () async {
      final r = await Rig.create();
      await r.restart();
      final cursor = r.state.cursors[SyncKind.product];
      expect(cursor, isNotNull);
      final page = await r.server.changes(SyncKind.product, cursor);
      expect(page.items, isEmpty);

      r.server.setPrice('p1', 19000);
      await r.sync.syncNow();
      expect(r.state.product('p1').price, 19000);
    });

    test('katalog dapat dicari dan difilter tanpa internet', () async {
      final r = await Rig.create(online: false);
      expect(r.state.search('kopi').map((p) => p.id), containsAll(['p1']));
      expect(r.state.search('', category: 'Makanan').length, 2);
      expect(r.state.search('MKN-002').single.name, 'Roti bakar cokelat');
      expect(r.state.bySku('89900000000' '03')?.id, 'p3'); // barcode
      expect(r.state.search('tidak ada'), isEmpty);
    });
  });

  group('auth dan sesi', () {
    test('login salah ditolak; sesi dan token tersimpan; keluar butuh antrean kosong', () async {
      final server = DemoBackend(autoPayAfter: null);
      final state = AppState(store: MemoryStore())..auth = server;
      await state.init();
      await expectLater(state.login('sari@kopisudut.id', 'salah'),
          throwsA(isA<SyncException>().having((e) => e.status, 'status', 401)));
      expect(state.loggedIn, isFalse);

      await state.login('sari@kopisudut.id', 'rahasia123');
      expect(state.loggedIn, isTrue);
      expect((await state.tokens.read())?.refresh, 'demo-refresh');

      await state.openShift(100000); // menaruh item di outbox
      await expectLater(state.logout(), throwsA(isA<BusinessRuleException>()));
    });

    test('login dibatasi setelah terlalu banyak percobaan salah', () async {
      final server = DemoBackend();
      for (var i = 0; i < 5; i++) {
        await expectLater(server.login('sari@kopisudut.id', 'x'), throwsA(isA<SyncException>()));
      }
      await expectLater(server.login('sari@kopisudut.id', 'rahasia123'),
          throwsA(isA<SyncException>().having((e) => e.status, 'status', 429)));
    });
  });
}
