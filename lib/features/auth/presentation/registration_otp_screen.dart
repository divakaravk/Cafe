import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/api_helper.dart';
import 'login_screen.dart' show AmbientBackground, ScaleButton;
import 'register_admin_screen.dart';

/// Step 2: the prospect enters the 6-digit OTP that the owner/super-admin
/// received via push. On success the company is activated and we move on to
/// creating the first admin user.
class RegistrationOtpScreen extends StatefulWidget {
  final String registrationId;
  final String companyId;
  final String companyName;

  const RegistrationOtpScreen({
    super.key,
    required this.registrationId,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<RegistrationOtpScreen> createState() => _RegistrationOtpScreenState();
}

class _RegistrationOtpScreenState extends State<RegistrationOtpScreen> {
  final _otp = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      AppFeedback.toast(context, 'Enter the 6-digit OTP', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await SupabaseService.verifyCompanyRegistrationOtp(
        registrationId: widget.registrationId,
        code: code,
      );
      if (res['ok'] == true) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RegisterAdminScreen(
              companyId: widget.companyId,
              companyName: widget.companyName,
            ),
          ),
        );
      } else {
        final reason = switch (res['reason']) {
          'expired' => 'This OTP has expired. Please register again.',
          'invalid' => 'Incorrect OTP. Please try again.',
          'too_many_attempts' => 'Too many attempts. Please register again.',
          _ => 'Verification failed. Please try again.',
        };
        if (mounted) AppFeedback.toast(context, reason, isError: true);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: AmbientBackground(
        child: Container(
          color: isDark
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.4),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildCard(isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark) {
    return Container(
      width: 420,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.25)
              : AppColors.lightBorder.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryAmber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.primaryAmber,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Enter approval OTP',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.textWhite : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A 6-digit code for "${widget.companyName}" was sent to the '
            'administrator. Enter it below to activate your company.',
            style: GoogleFonts.outfit(
              fontSize: 13,
              height: 1.5,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _verify(),
            style: GoogleFonts.outfit(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 14,
              color: isDark ? AppColors.textWhite : AppColors.textDark,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: GoogleFonts.outfit(
                fontSize: 30,
                letterSpacing: 14,
                color: isDark
                    ? AppColors.textWhiteMuted.withValues(alpha: 0.4)
                    : AppColors.textDarkMuted.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: isDark
                  ? AppColors.darkCard.withValues(alpha: 0.7)
                  : Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.3)
                      : AppColors.lightBorder.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.primaryAmber,
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ScaleButton(
            onTap: _verify,
            isLoading: _isLoading,
            child: Text(
              'Verify & Continue',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                'Back',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).moveY(begin: 12, end: 0);
  }
}
