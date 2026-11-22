import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:titik_mobile/data/app_state.dart';
import 'package:titik_mobile/data/backend.dart';
import 'package:titik_mobile/data/demo_backend.dart';
import 'package:titik_mobile/data/local_store.dart';
import 'package:titik_mobile/data/models.dart';

/// Menguji implementasi SQLite sungguhan (bukan MemoryStore).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('SqliteStore: tulis, baca, hapus, dan rollback bila satu operasi gagal', () async {
    final s = SqliteStore(path: inMemoryDatabasePath);
    await s.open();
    await s.apply([
      const Op.put(T.meta, 'a', {'id': 'a', 'v': 1}),
      const Op.put(T.meta, 'b', {'id': 'b', 'v': 2}),
    ]);
    expect((await s.readAll(T.meta)).length, 2);

    // Operasi kedua menunjuk tabel yang tidak ada -> seluruh transaksi harus batal.
    await expectLater(
        s.apply([
          const Op.put(T.meta, 'c', {'id': 'c'}),
          const Op.put('tabel_tak_ada', 'x', {'id': 'x'}),
        ]),
        throwsA(anything));
    final ids = (await s.readAll(T.meta)).map((e) => e['id']).toSet();
    expect(ids, {'a', 'b'}, reason: 'c tidak boleh tertinggal');

    await s.apply([const Op.del(T.meta, 'a')]);
    expect((await s.readAll(T.meta)).single['id'], 'b');
    await s.wipe();
    expect(await s.readAll(T.meta), isEmpty);
    await s.close();
  });

  test('transaksi kasir bertahan di file SQLite setelah aplikasi dibuka ulang', () async {
    final dir = await databaseFactoryFfi.getDatabasesPath();
    final path = '$dir/titik_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final server = DemoBackend(autoPayAfter: null);
    final tokens = MemoryTokenStore();

    final a = AppState(store: SqliteStore(path: path), tokens: tokens)..auth = server;
    await a.init();
    await a.login('sari@kopisudut.id', 'rahasia123');
    await a.applyChanges('category', await server.changes('category', null));
    await a.applyChanges('product', await server.changes('product', null));
    await a.applyChanges('stock', await server.changes('stock', null));
    await a.openShift(100000);
    a.add('p1', 2);
    final t = await a.checkout(PayMethod.cash, 40000);
    await a.store.close();

    final b = AppState(store: SqliteStore(path: path), tokens: tokens);
    await b.init();
    expect(b.loggedIn, isTrue);
    expect(b.txns.single.uuid, t.uuid);
    expect(b.outbox.where((o) => o.type == 'order').single.id, t.uuid);
    expect(b.stock['p1'], 40);
    expect(b.shiftOpen, isTrue);
    expect(b.cursors['product'], isNotNull);
    await b.store.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
}
