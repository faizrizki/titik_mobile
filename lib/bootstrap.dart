import 'package:flutter/foundation.dart' show kIsWeb;

import 'core/printer_service.dart';
import 'data/app_state.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/http_backend.dart';
import 'data/local_store.dart';
import 'data/sync_service.dart';

/// Alamat backend, mis. `--dart-define=API_BASE_URL=https://api.contoh.id`.
/// Kosong = server simulasi di dalam aplikasi (mode demo).
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Merakit database lokal, backend, dan worker sinkronisasi.
Future<void> bootstrap() async {
  final tokens = SecureTokenStore();
  // Web (pratinjau): SQLite tidak tersedia di browser, data hanya di memori
  // dan hilang saat halaman dimuat ulang. Perangkat Android memakai SQLite.
  final LocalStore store = kIsWeb ? MemoryStore() : SqliteStore();
  final state = AppState(store: store, tokens: tokens);
  AppState.I = state;

  final SyncApi api;
  if (apiBaseUrl.isEmpty) {
    AppState.demoMode = true;
    final demo = DemoBackend();
    api = demo;
    state
      ..auth = demo
      ..gateway = demo;
  } else {
    final http = HttpBackend(baseUrl: apiBaseUrl, tokens: tokens);
    api = http;
    state
      ..auth = http
      ..gateway = http;
  }

  await state.init();
  final sync = SyncService(state: state, api: api, probe: PlatformConnectivity());
  state.sync = sync;
  sync.addListener(state.touch);
  try {
    await PrinterService.I.load();
  } catch (_) {
    // Pengaturan printer opsional; jangan menggagalkan startup.
  }
  await sync.start();
}
