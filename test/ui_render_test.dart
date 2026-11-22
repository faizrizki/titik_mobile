import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:titik_mobile/core/pricing.dart';
import 'package:titik_mobile/data/app_state.dart';
import 'package:titik_mobile/data/models.dart';
import 'package:titik_mobile/features/auth_screens.dart';
import 'package:titik_mobile/features/catalog_screens.dart';
import 'package:titik_mobile/features/history_screens.dart';
import 'package:titik_mobile/features/payment_screens.dart';
import 'package:titik_mobile/features/profile_screens.dart';

import 'helpers.dart';

/// Merender tiap layar di ukuran HP (390x844). Overflow atau galat build
/// membuat tes gagal.
Widget _host(Widget w) => MaterialApp(
      home: w,
      onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => const Scaffold(), settings: s),
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  // Font uji (Ahem) selebar 1 em per huruf; skala 0,55 mendekati lebar font Latin sungguhan.
  t.platformDispatcher.textScaleFactorTestValue = .55;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  testWidgets('semua layar kasir dirender tanpa overflow', (tester) async {
    _phone(tester);
    final r = await Rig.create(online: false);
    AppState.I = r.state;
    await r.openShift();
    final t = await r.sell('p1', qty: 2);
    r.state
      ..add('p1', 2)
      ..add('p2')
      ..setLineDiscount('p1', const Discount.percent(10));

    final screens = <String, Widget>{
      'login': const LoginScreen(),
      'buka shift': const OpenShiftScreen(),
      'katalog': const CatalogScreen(),
      'keranjang': const CartScreen(),
      'pembayaran': const PaymentScreen(),
      'berhasil': SuccessScreen(txnId: t.id),
      'riwayat': const HistoryScreen(),
      'detail': DetailScreen(txnId: t.id),
      'retur': ReturnScreen(txnId: t.id),
      'pin': ManagerPinScreen(
          request: ReturnRequest(
              txnId: t.id, fullVoid: true, items: const {}, reason: 'x', amount: t.total)),
      'profil': const ProfileScreen(),
      'printer': const PrinterScreen(),
      'sinkron': const SyncScreen(),
      'tutup shift': const CloseShiftScreen(),
    };
    for (final e in screens.entries) {
      await tester.pumpWidget(_host(e.value));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'layar ${e.key}');
    }
  });

  testWidgets('layar shift selesai dan sinkron dengan masalah dirender', (tester) async {
    _phone(tester);
    final r = await Rig.create(online: false);
    AppState.I = r.state;
    await r.openShift(200000);
    await r.sell('p1');
    await r.state.closeShift(210000, note: 'Kurang');
    await tester.pumpWidget(_host(const ShiftDoneScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Shift selesai'), findsOneWidget);
    expect(find.text('Keluar dari akun'), findsOneWidget);

    // item gagal permanen tampil di "Perlu ditinjau"
    final r2 = await Rig.create();
    AppState.I = r2.state;
    await r2.openShift();
    await r2.sync.syncNow();
    r2.probe.set(false);
    await r2.sell('p2');
    r2.probe.set(true);
    r2.server.failNext(1, permanent: true);
    await r2.sync.syncNow();
    await tester.pumpWidget(_host(const SyncScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Perlu ditinjau'), findsOneWidget);
    expect(find.text('Hubungi manajer'), findsOneWidget);
  });

  testWidgets('keypad PIN: tombol centang aktif setelah 4 digit', (tester) async {
    _phone(tester);
    final r = await Rig.create(online: false);
    AppState.I = r.state;
    await r.openShift();
    final t = await r.sell('p1');
    await tester.pumpWidget(_host(ManagerPinScreen(
        request: ReturnRequest(
            txnId: t.id, fullVoid: true, items: const {}, reason: 'Salah input', amount: t.total))));
    for (final d in ['1', '2', '3']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();
    var check = tester.widget<InkWell>(find
        .ancestor(of: find.byIcon(Icons.check_rounded), matching: find.byType(InkWell))
        .first);
    expect(check.onTap, isNull);
    await tester.tap(find.text('4'));
    await tester.pump();
    check = tester.widget<InkWell>(find
        .ancestor(of: find.byIcon(Icons.check_rounded), matching: find.byType(InkWell))
        .first);
    expect(check.onTap, isNotNull);
  });
}
