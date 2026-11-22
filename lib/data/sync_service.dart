import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'app_state.dart';
import 'backend.dart';

/// Sumber status koneksi. Dipisah agar bisa diganti di tes.
abstract class ConnectivityProbe {
  Future<bool> isOnline();
  Stream<bool> get changes;
}

class PlatformConnectivity implements ConnectivityProbe {
  final _c = Connectivity();
  static bool _on(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);
  @override
  Future<bool> isOnline() async => _on(await _c.checkConnectivity());
  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(_on);
}

class ManualConnectivity implements ConnectivityProbe {
  ManualConnectivity([this._online = true]);
  bool _online;
  final _ctl = StreamController<bool>.broadcast();
  void set(bool v) {
    _online = v;
    _ctl.add(v);
  }

  @override
  Future<bool> isOnline() async => _online;
  @override
  Stream<bool> get changes => _ctl.stream;
}

/// Worker sinkronisasi (US-06, US-07).
///
/// Push: outbox dikirim BERURUTAN (seq). Kegagalan sementara menghentikan
/// putaran dan dijadwalkan ulang dengan exponential backoff; kegagalan
/// permanen menandai item dan lanjut ke item berikutnya. Server idempoten
/// per UUID, jadi pengiriman ulang aman (BR-05).
/// Pull: delta per jenis data dengan kursor dan pagination.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService({
    required this.state,
    required this.api,
    required this.probe,
    this.periodic = const Duration(seconds: 60),
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 5),
    this.pageSize = 200,
  });

  final AppState state;
  final SyncApi api;
  final ConnectivityProbe probe;
  final Duration periodic;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final int pageSize;

  bool online = true;
  bool syncing = false;
  String? lastError;
  bool authExpired = false;
  bool _again = false;
  Timer? _timer;
  Timer? _retryTimer;
  StreamSubscription<bool>? _sub;

  /// Mulai pemicu: koneksi kembali, aplikasi dibuka, timer berkala.
  Future<void> start() async {
    online = await probe.isOnline();
    _sub = probe.changes.listen((v) {
      online = v;
      notifyListeners();
      if (v) kick();
    });
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(periodic, (_) => kick());
    kick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) kick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryTimer?.cancel();
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Jadwalkan sinkron tanpa menunggu hasil. Galat tak terduga dilaporkan
  /// oleh zona error (Sentry), bukan membuat aplikasi berhenti.
  void kick() => unawaited(syncNow().catchError((Object e, StackTrace st) {
        lastError = '$e';
        Zone.current.handleUncaughtError(e, st);
      }));

  Duration backoff(int attempts) {
    final ms = baseBackoff.inMilliseconds * pow(2, attempts.clamp(0, 20)).toInt();
    return Duration(milliseconds: min(ms, maxBackoff.inMilliseconds));
  }

  Future<void>? _current;
  bool _againForce = false;

  /// Menjalankan putaran push lalu pull. [force] mengabaikan jeda backoff dan
  /// mengembalikan item gagal permanen ke antrean ("Ulangi"). Bila putaran
  /// sedang berjalan, pemanggil menunggu putaran itu (beserta putaran susulan
  /// bila ada permintaan baru selama berjalan).
  Future<void> syncNow({bool force = false}) {
    if (!state.loggedIn) return Future.value();
    if (_current != null) {
      _again = true;
      _againForce = _againForce || force;
      return _current!;
    }
    final f = _loop(force);
    _current = f;
    return f.whenComplete(() => _current = null);
  }

  Future<void> _loop(bool force) async {
    syncing = true;
    notifyListeners();
    try {
      var f = force;
      do {
        _again = false;
        f = f || _againForce;
        _againForce = false;
        await _once(f);
        f = false;
      } while (_again);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _once(bool force) async {
    lastError = null;
    online = await probe.isOnline();
    if (!online) {
      lastError = 'Offline';
      return;
    }
    if (force) await state.retryFailed();
    final ok = await _push(force);
    if (ok) await _pull();
    if (ok && lastError == null) {
      authExpired = false;
      await state.markSynced();
    }
  }

  Future<bool> _push(bool force) async {
    for (final item in state.pendingOutbox) {
      final due = DateTime.fromMillisecondsSinceEpoch(item.nextAttemptAt);
      if (!force && due.isAfter(state.now())) {
        _scheduleRetry(due);
        return false; // urutan dijaga: item di depan masih menunggu backoff
      }
      try {
        final res = await api.push(item);
        await state.outboxSucceeded(item, res);
      } on SyncException catch (e) {
        if (e.permanent) {
          await state.outboxFailed(item, e.message);
          continue; // lanjut ke item berikutnya
        }
        lastError = e.message;
        authExpired = e.authExpired;
        final next = state.now().add(backoff(item.attempts));
        await state.outboxRetry(item, e.message, next.millisecondsSinceEpoch);
        _scheduleRetry(next);
        return false;
      }
    }
    return true;
  }

  Future<void> _pull() async {
    for (final kind in SyncKind.all) {
      var cursor = state.cursors[kind];
      while (true) {
        try {
          final page = await api.changes(kind, cursor, limit: pageSize);
          await state.applyChanges(kind, page);
          cursor = page.nextCursor ?? cursor;
          if (!page.hasMore) break;
        } on SyncException catch (e) {
          lastError = e.message;
          authExpired = e.authExpired;
          return;
        }
      }
    }
  }

  void _scheduleRetry(DateTime at) {
    _retryTimer?.cancel();
    final d = at.difference(state.now());
    _retryTimer = Timer(d.isNegative ? Duration.zero : d, kick);
  }
}
