import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'backend.dart';
import 'models.dart';

/// Klien REST ke backend Go. Kontrak endpoint:
///   POST /auth/login | /auth/refresh | /auth/logout
///   POST /sync/push            {type, id, payload}  -> {duplicate, flags[]}
///   GET  /sync/changes?kind=&since=&limit= -> {items[], deleted[], cursor, hasMore}
///   POST /payments/qris        {orderUuid, amount}  -> {id, qr, amount, expiresAt}
///   GET  /payments/{id}        -> {status: pending|paid|expired}
class HttpBackend implements SyncApi, AuthApi, PaymentGateway {
  HttpBackend({required this.baseUrl, required this.tokens, http.Client? client})
      : _c = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _c;
  static const _timeout = Duration(seconds: 20);

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: q);

  /// Pemetaan status HTTP -> sementara / permanen (spesifikasi sinkronisasi).
  SyncException _fail(http.Response r) {
    String msg = 'HTTP ${r.statusCode}';
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] != null) msg = '${j['error']}';
    } catch (_) {}
    final transient = r.statusCode >= 500 || r.statusCode == 408 || r.statusCode == 429;
    return SyncException(msg,
        permanent: !transient, status: r.statusCode, authExpired: r.statusCode == 401);
  }

  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> h) f,
      {bool auth = true}) async {
    Future<http.Response> once() async {
      final h = {'content-type': 'application/json'};
      if (auth) {
        final t = await tokens.read();
        if (t != null) h['authorization'] = 'Bearer ${t.access}';
      }
      try {
        return await f(h).timeout(_timeout);
      } on SocketException {
        throw const SyncException('Tidak ada koneksi');
      } on TimeoutException {
        throw const SyncException('Server tidak merespons');
      } on http.ClientException {
        throw const SyncException('Tidak ada koneksi');
      }
    }

    var r = await once();
    if (r.statusCode == 401 && auth) {
      final t = await tokens.read();
      if (t != null) {
        try {
          await tokens.write(await refresh(t.refresh));
          r = await once();
        } on SyncException {
          throw const SyncException('Sesi berakhir. Masuk kembali.',
              status: 401, authExpired: true); // transien: data aman di outbox
        }
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return r;
    throw _fail(r);
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  @override
  Future<(Session, AuthTokens)> login(String email, String password) async {
    final r = await _send(
        (h) => _c.post(_u('/auth/login'),
            headers: h, body: jsonEncode({'email': email.trim(), 'password': password})),
        auth: false);
    final j = _json(r);
    final tok = AuthTokens(j['accessToken'] as String, j['refreshToken'] as String);
    await tokens.write(tok);
    return (Session.fromJson((j['session'] as Map).cast<String, dynamic>()), tok);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    final r = await _send(
        (h) => _c.post(_u('/auth/refresh'),
            headers: h, body: jsonEncode({'refreshToken': refreshToken})),
        auth: false);
    final j = _json(r);
    return AuthTokens(j['accessToken'] as String, j['refreshToken'] as String);
  }

  @override
  Future<void> logout(String refreshToken) async {
    try {
      await _send(
          (h) => _c.post(_u('/auth/logout'),
              headers: h, body: jsonEncode({'refreshToken': refreshToken})),
          auth: false);
    } on SyncException {
      // Pencabutan di server best-effort; token lokal tetap dihapus.
    }
  }

  @override
  Future<PushResult> push(OutboxItem item) async {
    final r = await _send((h) => _c.post(_u('/sync/push'),
        headers: h,
        body: jsonEncode({'type': item.type, 'id': item.id, 'payload': item.payload})));
    final j = _json(r);
    return PushResult(
        duplicate: j['duplicate'] == true,
        flags: ((j['flags'] as List?) ?? const []).cast<String>());
  }

  @override
  Future<ChangePage> changes(String kind, String? cursor, {int limit = 200}) async {
    final r = await _send((h) => _c.get(
        _u('/sync/changes', {
          'kind': kind,
          'since': cursor ?? '',
          'limit': '$limit',
        }),
        headers: h));
    final j = _json(r);
    return ChangePage(
      items: ((j['items'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
      deletedIds: ((j['deleted'] as List?) ?? const []).cast<String>(),
      nextCursor: j['cursor'] as String?,
      hasMore: j['hasMore'] == true,
    );
  }

  @override
  Future<QrisCharge> createQris({required String orderUuid, required int amount}) async {
    final r = await _send((h) => _c.post(_u('/payments/qris'),
        headers: h, body: jsonEncode({'orderUuid': orderUuid, 'amount': amount})));
    final j = _json(r);
    return QrisCharge(
      id: j['id'] as String,
      qrString: j['qr'] as String,
      amount: (j['amount'] as num).toInt(),
      expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
    );
  }

  @override
  Future<QrisState> status(String chargeId) async {
    final r = await _send((h) => _c.get(_u('/payments/$chargeId'), headers: h));
    return switch (_json(r)['status']) {
      'paid' => QrisState.paid,
      'expired' => QrisState.expired,
      _ => QrisState.pending,
    };
  }
}
