import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/api_helper.dart';
import 'login_screen.dart'
    show AmbientBackground, FocusableTextField, ScaleButton;
import 'registration_otp_screen.dart';

/// Step 1 of new-company onboarding: collect company + owner details, then
/// create an unverified company and dispatch an approval OTP to the owner /
/// super-admin device(s) via FCM.
class CompanyRegistrationScreen extends StatefulWidget {
  const CompanyRegistrationScreen({super.key});

  @override
  State<CompanyRegistrationScreen> createState() =>
      _CompanyRegistrationScreenState();
}

class _CompanyRegistrationScreenState extends State<CompanyRegistrationScreen> {
  final _companyName = TextEditingController();
  final _companyCode = TextEditingController();
  final _ownerName = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _ownerPhone = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _companyName.dispose();
    _companyCode.dispose();
    _ownerName.dispose();
    _ownerEmail.dispose();
    _ownerPhone.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_companyName.text.trim().isEmpty) return 'Company name is required';
    if (_companyCode.text.trim().isEmpty) return 'Company code is required';
    if (_ownerName.text.trim().isEmpty) return 'Owner name is required';
    final email = _ownerEmail.text.trim();
    if (email.isEmpty || !email.contains('@'))
      return 'A valid email is required';
    final phone = _ownerPhone.text.trim();
    if (phone.isNotEmpty && phone.length != 10) return 'Enter a 10-digit phone';
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      AppFeedback.toast(context, err, isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await SupabaseService.requestCompanyRegistration(
        company: {
          'company_name': _companyName.text.trim(),
          'company_code': _companyCode.text.trim(),
          'email': _ownerEmail.text.trim(),
          'phone': _ownerPhone.text.trim(),
        },
        owner: {
          'owner_name': _ownerName.text.trim(),
          'owner_email': _ownerEmail.text.trim(),
          'owner_phone': _ownerPhone.text.trim(),
        },
      );
      final registrationId = res['registration_id'] as String;
      final companyId = res['company_id'] as String;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegistrationOtpScreen(
            registrationId: registrationId,
            companyId: companyId,
            companyName: _companyName.text.trim(),
          ),
        ),
      );
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
                child: _buildForm(isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    return Container(
      width: 460,
      constraints: const BoxConstraints(maxWidth: 460),
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
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Register your company',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.textWhite : AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'An approval OTP will be sent to the administrator for verification.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FocusableTextField(
            controller: _companyName,
            label: 'Company Name',
            prefixIcon: Icons.business_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _companyCode,
            label: 'Company Code',
            prefixIcon: Icons.tag_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _ownerName,
            label: 'Owner / Admin Name',
            prefixIcon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _ownerEmail,
            label: 'Owner Email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _ownerPhone,
            label: 'Owner Phone (optional)',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 28),
          ScaleButton(
            onTap: _submit,
            isLoading: _isLoading,
            child: Text(
              'Send OTP & Continue',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).moveY(begin: 12, end: 0);
  }
}
