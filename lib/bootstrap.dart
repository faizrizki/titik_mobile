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
  final state = AppState(store: SqliteStore(), tokens: tokens);
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
  await PrinterService.I.load();
  await sync.start();
}
