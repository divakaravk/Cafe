import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../utils/api_helper.dart';

/// True when [e] looks like a connectivity failure (vs a server/logic error).
bool isNetworkError(Object e) {
  if (e is SocketException) return true;
  if (e is ApiException && e.type == ApiErrorType.network) return true;
  final msg = e.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection refused') ||
      msg.contains('connection closed') ||
      msg.contains('connection reset') ||
      msg.contains('no internet') ||
      msg.contains('no address associated') ||
      msg.contains('clientexception') ||
      msg.contains('timeout');
}

/// Shared empty-state shown when a screen's data fails to load. Detects a
/// no-network error and shows an offline message + Retry; otherwise shows a
/// generic error + Retry. Use everywhere instead of `Text('Error: $e')`.
class NetworkErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  /// Tighter layout for small areas (panels, dialogs).
  final bool compact;

  const NetworkErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final net = isNetworkError(error);
    final color = net ? AppColors.primaryOrange : AppColors.error;
    final title = net ? 'No Internet Connection' : 'Something Went Wrong';
    final subtitle = net
        ? 'Check your network and tap Retry.'
        : 'Please try again in a moment.';
    final icon = net ? Icons.wifi_off_rounded : Icons.error_outline_rounded;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 14 : 20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 30 : 40, color: color),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textWhite : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: compact ? 12 : 13,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
            SizedBox(height: compact ? 16 : 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Retry',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 20 : 28,
                  vertical: compact ? 10 : 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
