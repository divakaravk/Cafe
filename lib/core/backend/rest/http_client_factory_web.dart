import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Web build: the refresh token travels as an httpOnly cookie the backend
/// sets on `/v1/auth/*` (see backend/src/modules/auth/routes.ts) instead of
/// being readable by JS/localStorage. `withCredentials` makes the browser
/// attach/accept that cookie even when the API is on a different subdomain
/// than the app (`credentials: 'include'` under the hood); it's a no-op for
/// same-origin deployments.
http.Client createHttpClient() => BrowserClient()..withCredentials = true;
