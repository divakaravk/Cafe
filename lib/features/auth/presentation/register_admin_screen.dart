import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/api_helper.dart';
import '../../../models/models.dart';
import 'login_screen.dart' show AmbientBackground, FocusableTextField, ScaleButton;

/// Step 3: create the first ADMIN user for the freshly-verified company. The
/// new user is tagged with [companyId] and granted full permissions. On success
/// we return to the login screen so the admin can sign in for their company.
class RegisterAdminScreen extends StatefulWidget {
  final String companyId;
  final String companyName;

  const RegisterAdminScreen({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<RegisterAdminScreen> createState() => _RegisterAdminScreenState();
}

class _RegisterAdminScreenState extends State<RegisterAdminScreen> {
  final _fullName = TextEditingController();
  final _empCode = TextEditingController(text: 'ADMIN001');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullName.dispose();
    _empCode.dispose();
    _username.dispose();
    _password.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_fullName.text.trim().isEmpty) return 'Full name is required';
    if (_empCode.text.trim().isEmpty) return 'Employee code is required';
    if (_username.text.trim().isEmpty) return 'Username is required';
    if (_password.text.isEmpty) return 'Password is required';
    if (_password.text.length < 6) return 'Password must be at least 6 characters';
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
      final userId = const Uuid().v4();
      final userData = <String, dynamic>{
        'id': userId,
        'company_id': widget.companyId,
        'user_name': _fullName.text.trim(),
        'employee_code': _empCode.text.trim(),
        'username': _username.text.trim(),
        'user_role': 'admin',
        'mob_number': _phone.text.trim(),
        'user_email': _email.text.trim(),
        'user_active': true,
        'password': _password.text,
      };
      final permissions = UserPermission.all(userId).toJson();
      permissions['user_id'] = userId;

      await SupabaseService.upsertUserWithPermissions(
        userData: userData,
        permissionData: permissions,
        isNew: true,
      );

      if (!mounted) return;
      AppFeedback.success(
        context,
        'Admin created for ${widget.companyName}. Please sign in.',
      );
      // Back to the login screen (root of the navigator stack).
      Navigator.of(context).popUntil((route) => route.isFirst);
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
          Text(
            'Create admin account',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.textWhite : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'This is the first administrator for ${widget.companyName}.',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
          const SizedBox(height: 24),
          FocusableTextField(
            controller: _fullName,
            label: 'Full Name',
            prefixIcon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _empCode,
            label: 'Employee Code',
            prefixIcon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _username,
            label: 'Username',
            prefixIcon: Icons.alternate_email_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _password,
            label: 'Password',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _phone,
            label: 'Phone (optional)',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FocusableTextField(
            controller: _email,
            label: 'Email (optional)',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 28),
          ScaleButton(
            onTap: _submit,
            isLoading: _isLoading,
            child: Text(
              'Create Admin & Finish',
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
