import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Nama tabel lokal.
class T {
  static const products = 'products';
  static const categories = 'categories';
  static const stock = 'stock'; // saldo dari server (turunan)
  static const movements = 'stock_movements';
  static const orders = 'orders';
  static const refunds = 'refunds';
  static const shifts = 'shifts';
  static const outbox = 'outbox';
  static const audit = 'audit_logs';
  static const meta = 'meta'; // kursor sinkron, sesi, urutan nomor
  static const all = [
    products, categories, stock, movements, orders, refunds, shifts, outbox, audit, meta,
  ];
}

/// Satu operasi tulis. Daftar operasi dijalankan atomik: semua atau tidak sama sekali.
class Op {
  const Op.put(this.table, this.id, Map<String, dynamic> this.data) : delete = false;
  const Op.del(this.table, this.id)
      : data = null,
        delete = true;
  final String table;
  final String id;
  final Map<String, dynamic>? data;
  final bool delete;
}

abstract class LocalStore {
  Future<void> open();
  Future<List<Map<String, dynamic>>> readAll(String table);

  /// Menjalankan [ops] dalam satu transaksi database.
  Future<void> apply(List<Op> ops);

  /// Menghapus seluruh data (ganti usaha / keluar akun).
  Future<void> wipe();
  Future<void> close();
}

/// Implementasi memori untuk tes dan mode tanpa penyimpanan.
class MemoryStore implements LocalStore {
  final Map<String, Map<String, String>> _t = {for (final n in T.all) n: {}};

  /// Hanya untuk tes: simulasi gagal tulis di tengah operasi.
  int? failAfterOps;

  @override
  Future<void> open() async {}

  @override
  Future<List<Map<String, dynamic>>> readAll(String table) async =>
      _t[table]!.values.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();

  @override
  Future<void> apply(List<Op> ops) async {
    // Terapkan ke salinan lalu tukar: meniru atomisitas transaksi.
    final copy = {for (final e in _t.entries) e.key: Map<String, String>.from(e.value)};
    var n = 0;
    for (final op in ops) {
      if (failAfterOps != null && n++ >= failAfterOps!) {
        throw StateError('Gagal tulis simulasi');
      }
      if (op.delete) {
        copy[op.table]!.remove(op.id);
      } else {
        copy[op.table]![op.id] = jsonEncode(op.data);
      }
    }
    for (final e in copy.entries) {
      _t[e.key] = e.value;
    }
  }

  @override
  Future<void> wipe() async {
    for (final n in T.all) {
      _t[n] = {};
    }
  }

  @override
  Future<void> close() async {}
}

/// SQLite (sqflite). Tiap tabel: id TEXT PRIMARY KEY, data TEXT (JSON), dengan
/// transaksi database untuk penulisan atomik.
class SqliteStore implements LocalStore {
  SqliteStore({this.path});
  final String? path; // null -> direktori database default
  Database? _db;

  @override
  Future<void> open() async {
    final dir = path ?? p.join(await getDatabasesPath(), 'titik.db');
    _db = await openDatabase(
      dir,
      version: 1,
      onCreate: (db, _) async {
        for (final n in T.all) {
          await db.execute(
              'CREATE TABLE $n (id TEXT PRIMARY KEY, data TEXT NOT NULL)');
        }
      },
    );
  }

  Database get db => _db!;

  @override
  Future<List<Map<String, dynamic>>> readAll(String table) async {
    final rows = await db.query(table);
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  @override
  Future<void> apply(List<Op> ops) async {
    await db.transaction((txn) async {
      final b = txn.batch();
      for (final op in ops) {
        if (op.delete) {
          b.delete(op.table, where: 'id = ?', whereArgs: [op.id]);
        } else {
          b.insert(op.table, {'id': op.id, 'data': jsonEncode(op.data)},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await b.commit(noResult: true);
    });
  }

  @override
  Future<void> wipe() async {
    await db.transaction((txn) async {
      for (final n in T.all) {
        await txn.delete(n);
      }
    });
  }

  @override
  Future<void> close() async => _db?.close();
}
