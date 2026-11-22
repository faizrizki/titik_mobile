import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:titik_mobile/core/format.dart';
import 'package:titik_mobile/core/pricing.dart';
import 'package:titik_mobile/core/receipt.dart';
import 'package:titik_mobile/data/backend.dart';
import 'package:titik_mobile/data/demo_backend.dart';
import 'package:titik_mobile/data/http_backend.dart';
import 'package:titik_mobile/data/models.dart';

import 'helpers.dart';

Txn _txn({PayMethod method = PayMethod.cash}) {
  final lines = [
    TxnLine(productId: 'p1', name: 'Kopi susu gula aren dengan nama sangat panjang sekali', unitPrice: 18000, qty: 2, discount: const Discount.percent(10)),
    TxnLine(productId: 'p2', name: 'Americano', unitPrice: 15000, qty: 1),
  ];
  final t = computeTotals(lines.map((l) => l.priced).toList(),
      txnDiscount: const Discount.amount(1000), taxBps: 1100);
  return Txn(
    uuid: 'u1',
    id: 'TRX-0001',
    time: DateTime(2026, 11, 23, 14, 5),
    method: method,
    lines: lines,
    totals: t,
    paid: 100000,
    txnDiscount: const Discount.amount(1000),
    taxBps: 1100,
    cashierName: 'Sari Lestari',
    note: 'Tanpa gula',
  );
}

void main() {
  group('QRIS dan webhook (US-08, BR-10)', () {
    test('QR dinamis per transaksi; pending -> kedaluwarsa setelah 15 menit', () async {
      final clock = Clock();
      final s = DemoBackend(now: clock.now, autoPayAfter: null);
      final c = await s.createQris(orderUuid: 'o1', amount: 36000);
      expect(c.qrString, contains('o1'));
      expect(c.amount, 36000);
      expect(await s.status(c.id), QrisState.pending);
      clock.advance(const Duration(minutes: 16));
      expect(await s.status(c.id), QrisState.expired);
    });

    test('lunas hanya setelah webhook bertanda tangan valid; duplikat diproses sekali', () async {
      final s = DemoBackend(autoPayAfter: null);
      final c = await s.createQris(orderUuid: 'o1', amount: 1000);
      final body = jsonEncode({'eventId': 'evt-1', 'chargeId': c.id, 'status': 'paid'});

      expect(() => s.handleWebhook(body, 'tanda-tangan-palsu'),
          throwsA(isA<SyncException>().having((e) => e.status, 'status', 401)));
      expect(await s.status(c.id), QrisState.pending, reason: 'webhook palsu tidak mengubah status');

      expect(s.handleWebhook(body, DemoBackend.sign(body)), isTrue);
      expect(await s.status(c.id), QrisState.paid);
      expect(s.handleWebhook(body, DemoBackend.sign(body)), isFalse, reason: 'idempoten');
    });

    test('tanpa internet QRIS gagal dibuat dengan galat sementara', () async {
      final s = DemoBackend(autoPayAfter: null)..online = false;
      await expectLater(s.createQris(orderUuid: 'o', amount: 1),
          throwsA(isA<SyncException>().having((e) => e.permanent, 'permanent', isFalse)));
    });
  });

  group('klien HTTP: pemetaan galat sementara vs permanen', () {
    HttpBackend api(MockClient c, [TokenStore? t]) => HttpBackend(
        baseUrl: 'https://api.test', tokens: t ?? (MemoryTokenStore()..write(const AuthTokens('a', 'r'))), client: c);
    final item = OutboxItem(seq: 1, id: 'x', type: 'order', payload: const {}, createdAt: 0);

    test('5xx, 429, dan jaringan putus = sementara', () async {
      for (final code in [500, 503, 429, 408]) {
        final a = api(MockClient((_) async => http.Response('{}', code)));
        await expectLater(a.push(item),
            throwsA(isA<SyncException>().having((e) => e.permanent, '$code permanent', isFalse)));
      }
      final off = api(MockClient((_) async => throw const SocketException('mati')));
      await expectLater(off.push(item),
          throwsA(isA<SyncException>().having((e) => e.permanent, 'permanent', isFalse)));
    });

    test('4xx = permanen dengan pesan server', () async {
      final a = api(MockClient((_) async => http.Response('{"error":"harga tidak valid"}', 422)));
      await expectLater(
          a.push(item),
          throwsA(isA<SyncException>()
              .having((e) => e.permanent, 'permanent', isTrue)
              .having((e) => e.message, 'message', 'harga tidak valid')));
    });

    test('401: token disegarkan lalu permintaan diulang', () async {
      final calls = <String>[];
      final store = MemoryTokenStore()..write(const AuthTokens('lama', 'r1'));
      final a = api(
          MockClient((req) async {
            calls.add('${req.method} ${req.url.path} ${req.headers['authorization']}');
            if (req.url.path == '/auth/refresh') {
              return http.Response('{"accessToken":"baru","refreshToken":"r2"}', 200);
            }
            if (req.headers['authorization'] == 'Bearer lama') return http.Response('{}', 401);
            return http.Response('{"duplicate":true,"flags":["negative_stock"]}', 200);
          }),
          store);
      final res = await a.push(item);
      expect(res.duplicate, isTrue);
      expect(res.flags, ['negative_stock']);
      expect((await store.read())!.access, 'baru');
      expect(calls.last, contains('Bearer baru'));
    });

    test('sesi tidak bisa disegarkan = galat sementara bertanda authExpired (data aman di outbox)',
        () async {
      final a = api(MockClient((req) async => http.Response('{}', 401)));
      await expectLater(a.push(item),
          throwsA(isA<SyncException>().having((e) => e.authExpired, 'authExpired', isTrue)));
    });

    test('changes mem-parsing item, tombstone, dan kursor', () async {
      final a = api(MockClient((req) async {
        expect(req.url.queryParameters['kind'], 'product');
        expect(req.url.queryParameters['since'], '5');
        return http.Response(
            '{"items":[{"id":"p1"}],"deleted":["p9"],"cursor":"9","hasMore":true}', 200);
      }));
      final p = await a.changes('product', '5');
      expect(p.items.single['id'], 'p1');
      expect(p.deletedIds, ['p9']);
      expect(p.nextCursor, '9');
      expect(p.hasMore, isTrue);
    });
  });

  group('struk (US-05)', () {
    for (final mm in [58, 80]) {
      test('lebar tidak melebihi kolom kertas $mm mm dan memuat total', () {
        final o = ReceiptOptions(paperMm: mm, businessName: 'Kopi Sudut', branchName: 'Dipatiukur');
        final lines = receiptLines(_txn(), o);
        for (final (text, _) in lines) {
          expect(text.length, lessThanOrEqualTo(o.cols), reason: '"$text"');
        }
        final all = lines.map((l) => l.$1).join('\n');
        expect(all, contains('TOTAL'));
        expect(all, contains('Rp'));
        expect(all, contains('TRX-0001'));
        expect(all, contains('Kembalian'));
        expect(all, contains('Catatan: Tanpa gula'));
      });
    }

    test('ESC/POS diawali reset printer, ASCII murni, berakhir dengan potong kertas', () {
      final b = buildEscPos(_txn(), const ReceiptOptions());
      expect(b.sublist(0, 2), [0x1B, 0x40]);
      expect(b.sublist(b.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      // tidak ada byte non-ASCII di luar perintah kontrol (tanda minus Unicode diganti)
      expect(b.every((x) => x < 0x80), isTrue);
    });

    test('struk QRIS menampilkan metode dan tanpa kembalian', () {
      final txt = receiptLines(_txn(method: PayMethod.qris), const ReceiptOptions()).map((l) => l.$1).join('\n');
      expect(txt, contains('QRIS'));
      expect(txt, isNot(contains('Kembalian')));
    });

    test('PDF cadangan terbentuk', () async {
      final pdf = await buildReceiptPdf(_txn(), const ReceiptOptions());
      expect(String.fromCharCodes(pdf.sublist(0, 4)), '%PDF');
    });

    test('rupiah pada struk memakai format Indonesia', () {
      expect(rupiah(47064), 'Rp47.064');
    });
  });
}
