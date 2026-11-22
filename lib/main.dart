import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'bootstrap.dart';

/// DSN Sentry lewat `--dart-define=SENTRY_DSN=...`. Kosong = tidak melapor.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Future<void> run() async {
    try {
      await bootstrap();
      runApp(const TitikApp());
    } catch (e, st) {
      debugPrint('Startup gagal: $e\n$st');
      runApp(MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText('Aplikasi gagal dimulai.\n\n$e'),
            ),
          ),
        ),
      ));
    }
  }

  if (_sentryDsn.isEmpty) {
    await run();
  } else {
    await SentryFlutter.init((o) {
      o.dsn = _sentryDsn;
      o.sendDefaultPii = false; // tanpa data pribadi pelanggan
    }, appRunner: run);
  }
}
