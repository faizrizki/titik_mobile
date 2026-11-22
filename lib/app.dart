import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'data/models.dart';
import 'features/auth_screens.dart';
import 'features/catalog_screens.dart';
import 'features/history_screens.dart';
import 'features/payment_screens.dart';
import 'features/profile_screens.dart';

/// Nama rute. Urutan sama dengan alur prototipe (M01-M18).
class Routes {
  static const splash = '/';
  static const login = '/masuk';
  static const openShift = '/buka-shift';
  static const catalog = '/katalog';
  static const scan = '/scan';
  static const cart = '/keranjang';
  static const payment = '/pembayaran';
  static const qris = '/qris';
  static const success = '/berhasil';
  static const history = '/riwayat';
  static const detail = '/detail';
  static const returnReq = '/retur';
  static const managerPin = '/pin-manajer';
  static const profile = '/profil';
  static const printer = '/printer';
  static const sync = '/sinkronisasi';
  static const closeShift = '/tutup-shift';
  static const shiftDone = '/shift-selesai';
}

class TitikApp extends StatelessWidget {
  const TitikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'titik',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      initialRoute: Routes.splash,
      onGenerateRoute: (settings) {
        final args = settings.arguments;
        final Widget page = switch (settings.name) {
          Routes.splash => const SplashScreen(),
          Routes.login => const LoginScreen(),
          Routes.openShift => const OpenShiftScreen(),
          Routes.catalog => const CatalogScreen(),
          Routes.scan => const ScanScreen(),
          Routes.cart => const CartScreen(),
          Routes.payment => const PaymentScreen(),
          Routes.qris => const QrisScreen(),
          Routes.success => SuccessScreen(txnId: args as String),
          Routes.history => const HistoryScreen(),
          Routes.detail => DetailScreen(txnId: args as String),
          Routes.returnReq => ReturnScreen(txnId: args as String),
          Routes.managerPin => ManagerPinScreen(request: args as ReturnRequest),
          Routes.profile => const ProfileScreen(),
          Routes.printer => const PrinterScreen(),
          Routes.sync => const SyncScreen(),
          Routes.closeShift => const CloseShiftScreen(),
          Routes.shiftDone => const ShiftDoneScreen(),
          _ => const SplashScreen(),
        };
        return MaterialPageRoute(builder: (_) => page, settings: settings);
      },
    );
  }
}
