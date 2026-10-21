import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// `InternetAddress.lookup` is dart:io-only and throws `UnsupportedError` on
/// web, so every screen using it as a pre-flight check was permanently
/// treating the web build as offline. There's no CORS-safe cross-platform
/// equivalent, so on web this just returns true and leaves the real
/// online/offline signal to the actual request's own error handling (every
/// caller already catches `SocketException`/`TimeoutException`).
Future<bool> hasNetwork() async {
  if (kIsWeb) return true;
  try {
    final result = await InternetAddress.lookup(
      'google.com',
    ).timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
