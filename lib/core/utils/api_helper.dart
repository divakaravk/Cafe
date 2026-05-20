import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Error Types ──────────────────────────────────────────────────────────────

enum ApiErrorType { network, timeout, serverError, clientError, unknown }

class ApiException implements Exception {
  final ApiErrorType type;
  final String message;
  final String? code;

  ApiException(this.type, this.message, {this.code});

  String get userMessage {
    switch (type) {
      case ApiErrorType.network:
        return 'No internet. Check your connection and retry.';
      case ApiErrorType.timeout:
        return 'Request timed out. Please try again.';
      case ApiErrorType.serverError:
        return 'Server error (${code ?? '500'}). Try again in a moment.';
      case ApiErrorType.clientError:
        return message.isNotEmpty ? message : 'Invalid request. Please check inputs.';
      case ApiErrorType.unknown:
        return 'Something went wrong. Please try again.';
    }
  }

  IconData get icon {
    switch (type) {
      case ApiErrorType.network:
        return Icons.wifi_off_rounded;
      case ApiErrorType.timeout:
        return Icons.timer_off_rounded;
      case ApiErrorType.serverError:
        return Icons.dns_rounded;
      case ApiErrorType.clientError:
        return Icons.warning_amber_rounded;
      case ApiErrorType.unknown:
        return Icons.error_outline_rounded;
    }
  }

  bool get isRetryable =>
      type == ApiErrorType.network ||
      type == ApiErrorType.timeout ||
      type == ApiErrorType.serverError;
}

// ─── Classifier ───────────────────────────────────────────────────────────────

ApiException _classify(Object e) {
  if (e is ApiException) return e;
  if (e is SocketException) {
    return ApiException(ApiErrorType.network, e.message);
  }
  if (e is TimeoutException) {
    return ApiException(ApiErrorType.timeout, 'Request timed out');
  }
  if (e is PostgrestException) {
    final code = e.code ?? '';
    // HTTP 5xx or Postgres server-side errors (P0001 = raise exception, others)
    if (code.startsWith('5') || code == 'P0001' || code.isEmpty && e.message.contains('500')) {
      return ApiException(ApiErrorType.serverError, e.message, code: code);
    }
    // Unique violation, FK violation → client error
    return ApiException(ApiErrorType.clientError, _pgMessage(e.message, code), code: code);
  }
  if (e is AuthException) {
    return ApiException(ApiErrorType.clientError, e.message);
  }
  final msg = e.toString();
  // Catch network-style strings from the HTTP layer
  if (msg.contains('SocketException') || msg.contains('Connection refused') || msg.contains('Network is unreachable')) {
    return ApiException(ApiErrorType.network, msg);
  }
  if (msg.contains('TimeoutException')) {
    return ApiException(ApiErrorType.timeout, 'Request timed out');
  }
  return ApiException(ApiErrorType.unknown, msg);
}

String _pgMessage(String msg, String code) {
  // Map common Postgres codes to readable messages
  switch (code) {
    case '23505': return 'Duplicate entry. This record already exists.';
    case '23503': return 'Cannot complete — a linked record is missing.';
    case '42501': return 'Permission denied.';
    default: return msg.isNotEmpty ? msg : 'Database error ($code)';
  }
}

// ─── Core Wrapper ─────────────────────────────────────────────────────────────

/// Wraps any async call with a typed timeout and classified error.
/// Default timeout is 15 s. Use 25 s for multi-step operations (KOT, bill).
Future<T> safeApiCall<T>(
  Future<T> Function() fn, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    return await fn().timeout(timeout);
  } catch (e) {
    throw _classify(e);
  }
}

// ─── UI Feedback ──────────────────────────────────────────────────────────────

class AppFeedback {
  /// Green success snackbar
  static void success(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(
        message: message,
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF22C55E),
      ),
    );
  }

  /// Red error snackbar with icon and optional retry button
  static void error(
    BuildContext context,
    Object e, {
    VoidCallback? onRetry,
  }) {
    if (!context.mounted) return;
    final err = e is ApiException ? e : _classify(e);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(
        message: err.userMessage,
        icon: err.icon,
        color: const Color(0xFFEF4444),
        duration: const Duration(seconds: 5),
        action: (err.isRetryable && onRetry != null)
            ? SnackBarAction(
                label: 'RETRY',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// Amber warning snackbar
  static void warn(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(
        message: message,
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFF59E0B),
      ),
    );
  }

  static SnackBar _snack({
    required String message,
    required IconData icon,
    required Color color,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    return SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: duration,
      action: action,
    );
  }
}
