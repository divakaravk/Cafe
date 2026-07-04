import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/push_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/api_helper.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';

/// Dedicated dashboard for the platform/app owner. Lists every new-company
/// registration request with its approval OTP, and lets the owner approve a
/// company directly. The owner's device is registered for FCM so a push lands
/// here the moment someone registers.
class OwnerDashboardScreen extends ConsumerStatefulWidget {
  final UserProfile owner;
  const OwnerDashboardScreen({super.key, required this.owner});

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  bool _loading = true;
  String? _approvingId;
  List<Map<String, dynamic>> _items = [];
  StreamSubscription? _otpSub;

  @override
  void initState() {
    super.initState();
    // Make this device an OTP recipient, then load the queue.
    PushService.registerAsSuperAdmin(label: 'App Owner');
    // While the app is open, FCM messages don't pop a system tray notification,
    // so surface the OTP in-app and refresh the queue.
    _otpSub = PushService.listenRegistrationOtp((otp, company) {
      if (!mounted) return;
      _load();
      _showOtpDialog(otp, company);
    });
    _load();
  }

  @override
  void dispose() {
    _otpSub?.cancel();
    super.dispose();
  }

  void _showOtpDialog(String otp, String company) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: AppColors.primaryAmber,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'New registration',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                company,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'APPROVAL OTP',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                otp,
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: isDark
                      ? AppColors.primaryAmber
                      : AppColors.primaryOrange,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: otp));
                AppFeedback.toast(ctx, 'OTP copied');
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(
                'Copy',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Done',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await SupabaseService.listCompanyRegistrations();
      if (mounted) setState(() => _items = rows);
    } catch (e) {
      if (mounted) AppFeedback.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> reg) async {
    setState(() => _approvingId = reg['id'] as String);
    try {
      final res = await SupabaseService.approveCompanyRegistration(
        reg['id'] as String,
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        AppFeedback.success(
          context,
          '${reg['company_name'] ?? 'Company'} approved & activated.',
        );
        await _load();
      } else {
        AppFeedback.toast(context, 'Approval failed.', isError: true);
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, e);
    } finally {
      if (mounted) setState(() => _approvingId = null);
    }
  }

  Future<void> _logout() async {
    await ref.read(authStateProvider.notifier).signOut();
  }

  Future<void> _showChangePasswordSheet() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    var obscure = true;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> submit() async {
              if (next.text.length < 6) {
                AppFeedback.toast(
                  ctx,
                  'New password must be at least 6 characters',
                  isError: true,
                );
                return;
              }
              if (next.text != confirm.text) {
                AppFeedback.toast(ctx, 'Passwords do not match', isError: true);
                return;
              }
              setSheet(() => saving = true);
              try {
                final ok = await SupabaseService.changePassword(
                  userId: widget.owner.id,
                  currentPassword: current.text,
                  newPassword: next.text,
                );
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.pop(ctx);
                  if (mounted) AppFeedback.success(context, 'Password updated.');
                } else {
                  setSheet(() => saving = false);
                  AppFeedback.toast(
                    ctx,
                    'Current password is incorrect.',
                    isError: true,
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  setSheet(() => saving = false);
                  AppFeedback.error(ctx, e);
                }
              }
            }

            Widget field(TextEditingController c, String label) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: c,
                obscureText: obscure,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  labelText: label,
                  labelStyle: GoogleFonts.inter(fontSize: 13),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  filled: true,
                  fillColor: isDark ? AppColors.darkBg : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.primaryAmber,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            );

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Change password',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        tooltip: obscure ? 'Show' : 'Hide',
                        onPressed: () => setSheet(() => obscure = !obscure),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  field(current, 'Current password'),
                  field(next, 'New password'),
                  field(confirm, 'Confirm new password'),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Update password',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pending = _items.where((e) => e['status'] == 'pending').length;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF0F2F5),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Company Registrations',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.lock_reset_rounded),
            onPressed: _showChangePasswordSheet,
            tooltip: 'Change password',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: 'Sign out',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).padding.bottom,
                ),
                children: [
                  _header(isDark, pending),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    _empty(isDark)
                  else
                    ..._items.map((e) => _regCard(e, isDark)),
                ],
              ),
            ),
    );
  }

  Widget _header(bool isDark, int pending) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryOrange.withValues(alpha: 0.9),
            AppColors.primaryAmber.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${widget.owner.fullName}',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pending == 0
                      ? 'No pending approvals'
                      : '$pending pending approval${pending == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 56,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
          const SizedBox(height: 12),
          Text(
            'No company registrations yet',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _regCard(Map<String, dynamic> reg, bool isDark) {
    final status = (reg['status'] as String?) ?? 'pending';
    final otp = (reg['otp_code'] as String?) ?? '------';
    final companyName = (reg['company_name'] as String?) ?? 'Company';
    final ownerName = (reg['owner_name'] as String?) ?? '';
    final ownerEmail = (reg['owner_email'] as String?) ?? '';
    final ownerPhone = (reg['owner_phone'] as String?) ?? '';
    final isPending = status == 'pending';
    final (Color sc, String sl) = switch (status) {
      'verified' => (AppColors.success, 'APPROVED'),
      'expired' => (AppColors.error, 'EXPIRED'),
      _ => (AppColors.warning, 'PENDING'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    companyName,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sl,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: sc,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (ownerName.isNotEmpty)
              _line(Icons.person_outline_rounded, ownerName, isDark),
            if (ownerEmail.isNotEmpty)
              _line(Icons.email_outlined, ownerEmail, isDark),
            if (ownerPhone.isNotEmpty)
              _line(Icons.phone_outlined, ownerPhone, isDark),
            const SizedBox(height: 12),
            // OTP row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkBg
                    : AppColors.primaryAmber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primaryAmber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'OTP',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      otp,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        color: isDark
                            ? AppColors.primaryAmber
                            : AppColors.primaryOrange,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy OTP',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: otp));
                      AppFeedback.toast(context, 'OTP copied');
                    },
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _approvingId == reg['id']
                      ? null
                      : () => _approve(reg),
                  icon: _approvingId == reg['id']
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    'Approve & Activate',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
