import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../../utils/api_helper.dart';
import '../app_config.dart';
import 'http_client_factory.dart' if (dart.library.js_interop) 'http_client_factory_web.dart';
import 'token_store.dart';

/// Thin HTTP client for the Node API: attaches the bearer token, retries once
/// through a single-flight refresh on a 401, and turns every non-2xx response
/// into the *same* [ApiException] type `api_helper.dart`'s `_classify` already
/// special-cases (`if (e is ApiException) return e;`) — so every existing
/// `safeApiCall`/`AppFeedback.error` call site needs no changes for REST mode.
///
/// Network failures (`SocketException`) and timeouts (`TimeoutException`) are
/// left to propagate as themselves — `_classify` already handles both.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _http = createHttpClient();
  static const _timeout = Duration(seconds: 20);

  // Single-flight refresh: concurrent 401s during the same dropped session
  // trigger exactly one refresh call, not one per in-flight request.
  Future<bool>? _refreshing;

  Uri _uri(String path, Map<String, String>? query) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    // Every route this client calls lives under /v1 (see
    // docs/backend-migration/PLAN.md §4.2's endpoint map) — baked in here
    // once rather than repeated in each of RestBackend's ~50 call sites.
    return base.replace(
      path: '${base.path}/v1$path',
      queryParameters: query,
    );
  }

  Map<String, String> _headers({bool auth = true, String? idempotencyKey}) {
    final headers = {'Content-Type': 'application/json'};
    // Tells the backend to hand the refresh token back as an httpOnly cookie
    // instead of a JSON field (see backend/src/modules/auth/routes.ts) — only
    // meaningful on /auth/login|refresh|logout, harmless elsewhere.
    if (kIsWeb) headers['X-Client-Platform'] = 'web';
    if (auth) {
      final token = TokenStore.instance.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    return headers;
  }

  Future<dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return Future.value(null);
    return Future.value(jsonDecode(res.body));
  }

  ApiException _errorFor(http.Response res) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // non-JSON error body (e.g. a proxy's HTML error page) — fall through
    }
    final err = body?['error'] as Map<String, dynamic>?;
    final code = err?['code'] as String?;
    final message = err?['message'] as String? ?? 'Request failed (${res.statusCode}).';
    final type = res.statusCode >= 500 || res.statusCode == 429
        ? ApiErrorType.serverError // 429 mapped as retryable, like a transient server condition
        : ApiErrorType.clientError;
    return ApiException(type, message, code: code ?? res.statusCode.toString());
  }

  Future<bool> _refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    // Native/desktop: the refresh token must come from secure storage — no
    // cookie exists there, so nothing to fall back on. Web: the token lives
    // only in the httpOnly cookie the browser attaches automatically
    // (`createHttpClient()`'s `withCredentials`), so a null here is normal,
    // not a reason to give up.
    final refreshToken = await TokenStore.instance.readRefreshToken();
    if (refreshToken == null && !kIsWeb) return false;
    try {
      final res = await _http
          .post(
            _uri('/auth/refresh', null),
            headers: _headers(auth: false),
            body: jsonEncode({if (refreshToken != null) 'refresh_token': refreshToken}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return false;
      final body = await _decode(res) as Map<String, dynamic>;
      TokenStore.instance.setAccessToken(body['access_token'] as String);
      final newRefreshToken = body['refresh_token'] as String?;
      if (newRefreshToken != null) await TokenStore.instance.saveRefreshToken(newRefreshToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = true,
    String? idempotencyKey,
    bool retried = false,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers(auth: auth, idempotencyKey: idempotencyKey);
    final encoded = body != null ? jsonEncode(body) : null;

    final http.Response res = await switch (method) {
      'GET' => _http.get(uri, headers: headers),
      'POST' => _http.post(uri, headers: headers, body: encoded),
      'PUT' => _http.put(uri, headers: headers, body: encoded),
      'PATCH' => _http.patch(uri, headers: headers, body: encoded),
      'DELETE' => _http.delete(uri, headers: headers, body: encoded),
      _ => throw ArgumentError('Unsupported method $method'),
    }
        .timeout(_timeout);

    if (res.statusCode == 401 && auth && !retried) {
      if (await _refreshAccessToken()) {
        return _send(method, path, body: body, query: query, auth: auth, idempotencyKey: idempotencyKey, retried: true);
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res);
    throw _errorFor(res);
  }

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) =>
      _send('GET', path, query: query, auth: auth);

  Future<dynamic> post(String path, {Map<String, dynamic>? body, bool auth = true, String? idempotencyKey}) =>
      _send('POST', path, body: body, auth: auth, idempotencyKey: idempotencyKey);

  Future<dynamic> put(String path, {Map<String, dynamic>? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<dynamic> patch(String path, {Map<String, dynamic>? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<dynamic> delete(String path, {Map<String, dynamic>? body, bool auth = true}) =>
      _send('DELETE', path, body: body, auth: auth);

  /// Multipart upload (avatars, item images) — bypasses the JSON `_send` path.
  Future<dynamic> uploadFile(
    String path, {
    required List<int> bytes,
    required String filename,
    Map<String, String>? query,
    bool retried = false,
  }) async {
    final uri = _uri(path, query);
    final request = http.MultipartRequest('POST', uri);
    final token = TokenStore.instance.accessToken;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes is Uint8List ? bytes : Uint8List.fromList(bytes), filename: filename));

    final streamed = await _http.send(request).timeout(_timeout);
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 401 && !retried) {
      if (await _refreshAccessToken()) {
        return uploadFile(path, bytes: bytes, filename: filename, query: query, retried: true);
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res);
    throw _errorFor(res);
  }
}
