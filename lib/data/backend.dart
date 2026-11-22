import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Kegagalan panggilan server.
/// [permanent] true untuk data tidak valid / 4xx (jangan diulang); false untuk
/// jaringan, 5xx, 408/429 (diulang dengan exponential backoff).
class SyncException implements Exception {
  const SyncException(this.message,
      {this.permanent = false, this.status, this.authExpired = false});
  final String message;
  final bool permanent;
  final int? status;
  final bool authExpired;
  @override
  String toString() => 'SyncException($status): $message';
}

class PushResult {
  const PushResult({this.duplicate = false, this.flags = const []});

  /// UUID sudah pernah diproses; hasil sukses yang sama dikembalikan (BR-05).
  final bool duplicate;

  /// Mis. `negative_stock`: transaksi sah tetapi perlu ditinjau (BR-06).
  final List<String> flags;
}

class ChangePage {
  const ChangePage({this.items = const [], this.deletedIds = const [], this.nextCursor, this.hasMore = false});
  final List<Map<String, dynamic>> items;
  final List<String> deletedIds; // tombstone (BR-12)
  final String? nextCursor;
  final bool hasMore;
}

/// Jenis data yang di-pull: kategori, produk, harga, stok.
class SyncKind {
  static const category = 'category';
  static const product = 'product';
  static const price = 'price';
  static const stock = 'stock';
  static const all = [category, product, price, stock];
}

abstract class SyncApi {
  /// POST /sync/push. Idempoten berdasarkan [OutboxItem.id].
  Future<PushResult> push(OutboxItem item);

  /// GET /sync/changes?kind=..&since=<kursor>. Kursor kosong = unduhan awal.
  Future<ChangePage> changes(String kind, String? cursor, {int limit = 200});
}

abstract class AuthApi {
  Future<(Session, AuthTokens)> login(String email, String password);
  Future<AuthTokens> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
}

enum QrisState { pending, paid, expired }

class QrisCharge {
  const QrisCharge(
      {required this.id, required this.qrString, required this.amount, required this.expiresAt});
  final String id;
  final String qrString; // isi QR dinamis
  final int amount;
  final DateTime expiresAt;
}

abstract class PaymentGateway {
  /// QR dinamis per transaksi. Memerlukan internet.
  Future<QrisCharge> createQris({required String orderUuid, required int amount});

  /// Status diperbarui oleh webhook server yang sudah diverifikasi (BR-10).
  Future<QrisState> status(String chargeId);
}

/// Hash PIN manajer: SHA-256 berulang dengan salt. Server memakai fungsi sama.
String hashPin(String salt, String pin) {
  List<int> d = utf8.encode('$salt:$pin');
  for (var i = 0; i < 2000; i++) {
    d = sha256.convert(d).bytes;
  }
  return base64Url.encode(d);
}

/// Penyimpanan token. Di perangkat memakai Keystore/Keychain.
abstract class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens t);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<AuthTokens?> read() async {
    final a = await _s.read(key: 'access');
    final r = await _s.read(key: 'refresh');
    return a == null || r == null ? null : AuthTokens(a, r);
  }

  @override
  Future<void> write(AuthTokens t) async {
    await _s.write(key: 'access', value: t.access);
    await _s.write(key: 'refresh', value: t.refresh);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: 'access');
    await _s.delete(key: 'refresh');
  }
}

class MemoryTokenStore implements TokenStore {
  AuthTokens? _t;
  @override
  Future<AuthTokens?> read() async => _t;
  @override
  Future<void> write(AuthTokens t) async => _t = t;
  @override
  Future<void> clear() async => _t = null;
}
