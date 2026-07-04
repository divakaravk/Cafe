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
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _amber = Color(0xFFF59E0B);

  /// Green success toast (top, slides in from the left).
  static void success(BuildContext context, String message) =>
      _show(context, message, _green, Icons.check_circle_rounded);

  /// Amber warning toast.
  static void warn(BuildContext context, String message) =>
      _show(context, message, _amber, Icons.warning_amber_rounded);

  /// Red error toast with an optional RETRY action, classified for a friendly
  /// message.
  static void error(BuildContext context, Object e, {VoidCallback? onRetry}) {
    final err = e is ApiException ? e : _classify(e);
    _show(
      context,
      err.userMessage,
      _red,
      err.icon,
      onRetry: (err.isRetryable && onRetry != null) ? onRetry : null,
    );
  }

  /// Generic top toast. [isError] flips the colour/icon to the error style.
  static void toast(
    BuildContext context,
    String message, {
    bool isError = false,
    IconData? icon,
    VoidCallback? onRetry,
  }) {
    _show(
      context,
      message,
      isError ? _red : _green,
      icon ??
          (isError ? Icons.error_outline_rounded : Icons.check_circle_rounded),
      onRetry: onRetry,
    );
  }

  /// Top toast for an error object, classified into a friendly message.
  static void toastError(BuildContext context, Object e) {
    final err = e is ApiException ? e : _classify(e);
    _show(context, err.userMessage, _red, err.icon);
  }

  /// Inserts the top toast into the root overlay.
  static void _show(
    BuildContext context,
    String message,
    Color color,
    IconData icon, {
    VoidCallback? onRetry,
  }) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        message: message,
        color: color,
        icon: icon,
        onRetry: onRetry,
        onDismissed: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

/// A top-anchored toast that slides in from the left, holds, then slides out.
/// Inserted via [AppFeedback.toast] into the root overlay.
class _TopToast extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback onDismissed;
  final VoidCallback? onRetry;

  const _TopToast({
    required this.message,
    required this.color,
    required this.icon,
    required this.onDismissed,
    this.onRetry,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(-1.15, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    // Errors with a retry action linger a touch longer.
    _timer = Timer(
      Duration(milliseconds: widget.onRetry != null ? 4200 : 2600),
      _dismiss,
    );
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    if (mounted) await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    if (widget.onRetry != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          widget.onRetry!();
                          _dismiss();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'RETRY',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
