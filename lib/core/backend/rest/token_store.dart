import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the access token in memory (never persisted — a 30-min JWT, cheap to
/// re-fetch on cold start) and the refresh token in secure storage.
///
/// docs/backend-migration/PLAN.md §4.4 describes an HttpOnly cookie for the
/// web build specifically, as the more defensible answer for a *public* web
/// deployment. `flutter_secure_storage`'s web implementation falls back to
/// browser storage (its own docs: "not that secure" there), so this one
/// implementation is correct as shipped for mobile/desktop today and is the
/// thing to swap for a cookie-based flow before a public web launch — noted
/// here so that Phase W7 (docs/web-view/PLAN.md) tracks it, not forgotten.
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  static const _refreshKey = 'rest_refresh_token';
  final _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? get accessToken => _accessToken;
  void setAccessToken(String? token) => _accessToken = token;

  Future<void> saveRefreshToken(String token) => _storage.write(key: _refreshKey, value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> clear() async {
    _accessToken = null;
    await _storage.delete(key: _refreshKey);
  }
}
