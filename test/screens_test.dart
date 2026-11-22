import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:titik_mobile/app.dart';
import 'package:titik_mobile/data/app_state.dart';
import 'package:titik_mobile/data/models.dart';
import 'package:titik_mobile/features/catalog_screens.dart';
import 'package:titik_mobile/features/payment_screens.dart';

import 'helpers.dart';

Widget _host(Widget home) => MaterialApp(
      home: home,
      onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => const Scaffold(), settings: s),
    );

void main() {
  testWidgets('katalog tampil dari database lokal saat offline, dengan pencarian dan indikator',
      (tester) async {
    final r = await Rig.create(online: false);
    AppState.I = r.state;
    await r.openShift();
    await r.sell('p1'); // satu transaksi menunggu sinkron

    await tester.pumpWidget(_host(const CatalogScreen()));
    await tester.pump();

    expect(find.text('Americano'), findsOneWidget);
    expect(find.textContaining('Offline'), findsWidgets);
    expect(find.textContaining('1 transaksi menunggu sinkron'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'matcha');
    await tester.pump();
    expect(find.text('Matcha latte'), findsOneWidget);
    expect(find.text('Americano'), findsNothing);
  });

  testWidgets('tombol tambah produk memenuhi target sentuh minimal 44 px', (tester) async {
    final r = await Rig.create(online: false);
    AppState.I = r.state;
    await tester.pumpWidget(_host(const CatalogScreen()));
    await tester.pump();
    final size = tester.getSize(find.byTooltip('Tambah Americano'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('keranjang menampilkan diskon dan total sesuai aturan hitung', (tester) async {
    final r = await Rig.create(online: false);
    AppState.I = r.state;
    r.state
      ..add('p1', 2)
      ..add('p2');
    await tester.pumpWidget(_host(const CartScreen()));
    await tester.pump();
    expect(find.text('Rp51.000'), findsWidgets);
    expect(find.text('Pajak (0%)'), findsOneWidget);
    expect(find.text('Lanjut ke pembayaran'), findsOneWidget);
  });

  testWidgets('struk memakai snapshot nama dan harga', (tester) async {
    final r = await Rig.create(online: false);
    AppState.I = r.state;
    await r.openShift();
    final t = await r.sell('p3', qty: 2);
    await tester.pumpWidget(_host(Scaffold(body: ReceiptCard(txn: t))));
    expect(find.text('2× Cappuccino'), findsOneWidget);
    expect(find.text('Rp44.000'), findsWidgets);
  });

  test('semua rute terdaftar', () {
    expect(Routes.qris, '/qris');
    expect(PayMethod.values.length, 2);
  });
}
