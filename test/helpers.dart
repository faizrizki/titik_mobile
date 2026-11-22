import 'package:titik_mobile/data/app_state.dart';
import 'package:titik_mobile/data/backend.dart';
import 'package:titik_mobile/data/demo_backend.dart';
import 'package:titik_mobile/data/local_store.dart';
import 'package:titik_mobile/data/models.dart';
import 'package:titik_mobile/data/sync_service.dart';

/// Perangkat kasir lengkap: database lokal, server simulasi, worker sinkron.
class Rig {
  Rig._(this.clock, this.store, this.tokens, this.server, this.probe, this.state, this.sync);

  final Clock clock;
  final MemoryStore store;
  final MemoryTokenStore tokens;
  final DemoBackend server;
  final ManualConnectivity probe;
  AppState state;
  SyncService sync;

  /// [online] awal. Kasir sudah masuk dan katalog sudah diunduh.
  static Future<Rig> create({bool online = true, DemoBackend? server, MemoryStore? store}) async {
    final clock = Clock();
    final st = store ?? MemoryStore();
    final tk = MemoryTokenStore();
    final srv = server ?? DemoBackend(now: clock.now, autoPayAfter: null);
    final probe = ManualConnectivity(true);
    final state = AppState(store: st, tokens: tk, now: clock.now)..auth = srv;
    await state.init();
    final sync = SyncService(
        state: state,
        api: srv,
        probe: probe,
        periodic: const Duration(days: 1),
        baseBackoff: const Duration(seconds: 2));
    state.sync = sync;
    await state.login('sari@kopisudut.id', 'rahasia123');
    await sync.syncNow(force: true); // unduhan awal
    final r = Rig._(clock, st, tk, srv, probe, state, sync);
    if (!online) probe.set(false);
    return r;
  }

  /// Simulasi aplikasi ditutup paksa lalu dibuka lagi pada database yang sama.
  Future<void> restart() async {
    final s = AppState(store: store, tokens: tokens, now: clock.now)..auth = server;
    await s.init();
    final sy = SyncService(
        state: s,
        api: server,
        probe: probe,
        periodic: const Duration(days: 1),
        baseBackoff: const Duration(seconds: 2));
    s.sync = sy;
    state = s;
    sync = sy;
  }

  Future<void> openShift([int cash = 200000]) => state.openShift(cash);

  /// Jual [qty] produk [pid] tunai. Mengembalikan transaksi.
  Future<Txn> sell(String pid, {int qty = 1, String? uuid}) async {
    state.add(pid, qty);
    return state.checkout(PayMethod.cash, state.total, uuid: uuid);
  }

  Approver get manager => state.session!.approvers.first;
}

class Clock {
  DateTime _t = DateTime(2026, 11, 23, 9);
  DateTime now() => _t;
  void advance(Duration d) => _t = _t.add(d);
}
