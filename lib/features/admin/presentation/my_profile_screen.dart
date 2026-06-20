import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/models.dart';

// ─── Role helpers ─────────────────────────────────────────────────────────────

Color _roleColor(String role) => switch (role.toLowerCase()) {
  'admin' => const Color(0xFFD32F2F),
  'manager' => const Color(0xFF5C6BC0),
  'cashier' => const Color(0xFF388E3C),
  'waiter' => const Color(0xFFFF8F00),
  'kitchen' => const Color(0xFF00897B),
  _ => AppColors.primaryAmber,
};

IconData _roleIcon(String role) => switch (role.toLowerCase()) {
  'admin' => Icons.admin_panel_settings_rounded,
  'manager' => Icons.manage_accounts_rounded,
  'cashier' => Icons.point_of_sale_rounded,
  'waiter' => Icons.room_service_rounded,
  'kitchen' => Icons.restaurant_rounded,
  _ => Icons.person_rounded,
};

// ─── Screen ───────────────────────────────────────────────────────────────────

class MyProfileScreen extends StatefulWidget {
  final UserProfile user;
  const MyProfileScreen({super.key, required this.user});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  bool _isLoading = false;
  bool _isEditing = false;
  UserPermission? _permissions;
  XFile? _pickedImage;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();

  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.user;
    _loadPermissions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // ─── Network ──────────────────────────────────────────────────────────────

  Future<bool> _hasNetwork() async {
    try {
      final r = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return r.isNotEmpty && r[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkNetworkAndWarn() async {
    if (!await _hasNetwork()) {
      _showError('No internet connection. Check your network and retry.');
      return false;
    }
    return true;
  }

  void _showError(String msg, {VoidCallback? onRetry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: onRetry != null
            ? SnackBarAction(
                label: 'RETRY',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(msg, style: GoogleFonts.inter(fontSize: 13)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadPermissions() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      if (!await _checkNetworkAndWarn()) return;
      final data = await SupabaseService.getUserPermissions(
        _profile.id,
      ).timeout(const Duration(seconds: 10));
      if (data != null && mounted) {
        setState(() => _permissions = UserPermission.fromJson(data));
      }
    } on TimeoutException {
      _showError('Request timed out.', onRetry: _loadPermissions);
    } on SocketException {
      _showError('Network error.', onRetry: _loadPermissions);
    } catch (e) {
      _showError('Failed to load: $e', onRetry: _loadPermissions);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startEdit() {
    _nameController.text = _profile.fullName;
    _phoneController.text = _profile.phone ?? '';
    _emailController.text = _profile.email ?? '';
    setState(() => _isEditing = true);
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _pickedImage = null;
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null && mounted) setState(() => _pickedImage = picked);
  }

  Future<void> _saveProfile() async {
    if (_isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!await _checkNetworkAndWarn()) return;

    setState(() => _isLoading = true);
    try {
      String? newAvatarUrl = _profile.avatarUrl;

      if (_pickedImage != null) {
        final bytes = await _pickedImage!.readAsBytes();
        final ext = _pickedImage!.path.split('.').last.toLowerCase();
        newAvatarUrl = await SupabaseService.uploadAvatar(
          _profile.id,
          bytes,
          ext,
        ).timeout(const Duration(seconds: 30));
      }

      await SupabaseService.client
          .from('user_profiles')
          .update({
            'user_name': _nameController.text.trim(),
            'mob_number': _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            'user_email': _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
            'avatar_url': newAvatarUrl,
          })
          .eq('id', _profile.id)
          .timeout(const Duration(seconds: 10));

      final updated = UserProfile(
        id: _profile.id,
        companyId: _profile.companyId,
        role: _profile.role,
        fullName: _nameController.text.trim(),
        employeeCode: _profile.employeeCode,
        username: _profile.username,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        avatarUrl: newAvatarUrl,
        isActive: _profile.isActive,
        createdAt: _profile.createdAt,
      );

      if (mounted) {
        setState(() {
          _profile = updated;
          _pickedImage = null;
          _isEditing = false;
        });
        _showSuccess('Profile updated successfully');
      }
    } on TimeoutException {
      _showError('Request timed out.', onRetry: _saveProfile);
    } on SocketException {
      _showError('Network error.', onRetry: _saveProfile);
    } catch (e) {
      _showError('Failed to save: $e', onRetry: _saveProfile);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rc = _roleColor(_profile.role);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: Column(
        children: [
          _buildHeader(isDark, rc),
          Expanded(
            child: _isEditing
                ? _buildEditForm(isDark, rc)
                : _buildViewBody(isDark, rc),
          ),
        ],
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark, Color rc) {
    final hasImage = _pickedImage != null;
    final hasAvatar =
        _profile.avatarUrl != null && _profile.avatarUrl!.isNotEmpty;
    final initials = _profile.fullName.isNotEmpty
        ? _profile.fullName
              .split(' ')
              .take(2)
              .map((w) => w.isNotEmpty ? w[0] : '')
              .join()
              .toUpperCase()
        : '?';

    return SizedBox(
      height: 260,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Gradient background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    rc.withValues(alpha: isDark ? 0.28 : 0.18),
                    rc.withValues(alpha: isDark ? 0.10 : 0.06),
                    (isDark ? AppColors.darkBg : AppColors.lightBg).withValues(
                      alpha: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Decorative circles
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rc.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            top: 20,
            left: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rc.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 60,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rc.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: rc.withValues(alpha: 0.15), width: 2),
              ),
            ),
          ),
          // AppBar row
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: isDark
                            ? AppColors.textWhite
                            : AppColors.textDark,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        'My Profile',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textWhite
                              : AppColors.textDark,
                        ),
                      ),
                    ),
                    if (_isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: rc,
                          ),
                        ),
                      )
                    else if (_isEditing) ...[
                      TextButton(
                        onPressed: _cancelEdit,
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            color: isDark
                                ? AppColors.textWhiteMuted
                                : AppColors.textDarkMuted,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saveProfile,
                        child: Text(
                          'Save',
                          style: GoogleFonts.inter(
                            color: rc,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ] else
                      IconButton(
                        icon: Icon(
                          Icons.edit_outlined,
                          color: isDark
                              ? AppColors.textWhiteMuted
                              : AppColors.textDarkMuted,
                        ),
                        onPressed: _startEdit,
                        tooltip: 'Edit Profile',
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Avatar + name block (centered)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Halo ring + avatar
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: rc.withValues(alpha: 0.25),
                          width: 3,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _isEditing ? _pickImage : null,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: rc, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: rc.withValues(alpha: 0.3),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: hasImage
                              ? Image.file(
                                  File(_pickedImage!.path),
                                  fit: BoxFit.cover,
                                )
                              : hasAvatar
                              ? Image.network(
                                  _profile.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _avatarFallback(rc, initials),
                                )
                              : _avatarFallback(rc, initials),
                        ),
                      ),
                    ),
                    if (_isEditing)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: rc,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? AppColors.darkBg
                                  : AppColors.lightBg,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // Name
                Text(
                  _profile.fullName,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.textWhite : AppColors.textDark,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 6),
                // Role chip + status
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: rc.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: rc.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_roleIcon(_profile.role), size: 13, color: rc),
                          const SizedBox(width: 4),
                          Text(
                            _profile.role.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: rc,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _profile.isActive
                            ? AppColors.success.withValues(alpha: 0.12)
                            : AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _profile.isActive
                              ? AppColors.success.withValues(alpha: 0.4)
                              : AppColors.error.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _profile.isActive ? 'Active' : 'Inactive',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _profile.isActive
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(Color rc, String initials) {
    return Container(
      color: rc.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.inter(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: rc,
          ),
        ),
      ),
    );
  }

  // ─── View mode ─────────────────────────────────────────────────────────────

  Widget _buildViewBody(bool isDark, Color rc) {
    return ListView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      children: [
        _ProfileCard(
          isDark: isDark,
          accentColor: rc,
          title: 'Personal Info',
          icon: Icons.badge_outlined,
          children: [
            _InfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Full Name',
              value: _profile.fullName,
              isDark: isDark,
            ),
            _InfoRow(
              icon: Icons.tag_rounded,
              label: 'Employee Code',
              value: _profile.employeeCode,
              isDark: isDark,
            ),
            if (_profile.username != null && _profile.username!.isNotEmpty)
              _InfoRow(
                icon: Icons.alternate_email_rounded,
                label: 'Username',
                value: '@${_profile.username}',
                isDark: isDark,
              ),
            if (_profile.createdAt != null)
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'Member Since',
                value: _formatDate(_profile.createdAt!),
                isDark: isDark,
              ),
            if (_profile.lastLogin != null)
              _InfoRow(
                icon: Icons.login_rounded,
                label: 'Last Login',
                value: _formatDateTime(_profile.lastLogin!),
                isDark: isDark,
              ),
          ],
        ),
        const SizedBox(height: 12),
        _ProfileCard(
          isDark: isDark,
          accentColor: AppColors.info,
          title: 'Contact Info',
          icon: Icons.contact_phone_outlined,
          children: [
            _InfoRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: _profile.phone?.isNotEmpty == true
                  ? _profile.phone!
                  : 'Not set',
              isDark: isDark,
              muted: _profile.phone?.isNotEmpty != true,
            ),
            _InfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: _profile.email?.isNotEmpty == true
                  ? _profile.email!
                  : 'Not set',
              isDark: isDark,
              muted: _profile.email?.isNotEmpty != true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPermissionsCard(isDark, rc),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${months[local.month - 1]} ${local.day}, ${local.year}  $h:$m $ampm';
  }

  Widget _buildPermissionsCard(bool isDark, Color rc) {
    return _ProfileCard(
      isDark: isDark,
      accentColor: const Color(0xFF7B1FA2),
      title: 'Permissions',
      icon: Icons.shield_outlined,
      trailing: _isLoading && _permissions == null
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: rc),
            )
          : null,
      children: [
        if (_permissions == null && !_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: _loadPermissions,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'Load permissions',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
              ),
            ),
          )
        else if (_permissions != null) ...[
          _PermGroup(
            label: 'Billing',
            color: AppColors.warning,
            isDark: isDark,
            perms: [
              _PermItem('Create Bill', _permissions!.canCreateBill),
              _PermItem('Edit Bill', _permissions!.canEditBill),
              _PermItem('Cancel Bill', _permissions!.canCancelBill),
              _PermItem('Apply Discount', _permissions!.canApplyDiscount),
              _PermItem('Void Items', _permissions!.canVoidItems),
            ],
          ),
          const SizedBox(height: 12),
          _PermGroup(
            label: 'Access',
            color: AppColors.info,
            isDark: isDark,
            perms: [
              _PermItem('View Dashboard', _permissions!.canViewDashboard),
              _PermItem('Manage Tables', _permissions!.canManageTables),
              _PermItem('View Reports', _permissions!.canViewReports),
              _PermItem('Manage Items', _permissions!.canManageItems),
            ],
          ),
          const SizedBox(height: 12),
          _PermGroup(
            label: 'Administration',
            color: const Color(0xFF5C6BC0),
            isDark: isDark,
            perms: [
              _PermItem('Manage Users', _permissions!.canManageUsers),
              _PermItem('Manage Settings', _permissions!.canManageSettings),
              _PermItem('Manage Stock', _permissions!.canManageStock),
            ],
          ),
        ] else
          const SizedBox(height: 8),
      ],
    );
  }

  // ─── Edit form ─────────────────────────────────────────────────────────────

  Widget _buildEditForm(bool isDark, Color rc) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          _ProfileCard(
            isDark: isDark,
            accentColor: rc,
            title: 'Edit Info',
            icon: Icons.edit_outlined,
            children: [
              const SizedBox(height: 4),
              _buildField(
                controller: _nameController,
                focusNode: _nameFocus,
                nextFocus: _phoneFocus,
                label: 'Full Name',
                icon: Icons.person_outline_rounded,
                isDark: isDark,
                rc: rc,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                nextFocus: _emailFocus,
                label: 'Phone',
                icon: Icons.phone_outlined,
                isDark: isDark,
                rc: rc,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final digits = v.replaceAll(RegExp(r'\D'), '');
                  if (digits.length != 10)
                    return 'Enter a valid 10-digit number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _emailController,
                focusNode: _emailFocus,
                label: 'Email',
                icon: Icons.email_outlined,
                isDark: isDark,
                rc: rc,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saveProfile(),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final emailRx = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$');
                  if (!emailRx.hasMatch(v.trim())) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 4),
            ],
          ),
          const SizedBox(height: 16),
          // Read-only info
          _ProfileCard(
            isDark: isDark,
            accentColor: AppColors.textDarkMuted,
            title: 'Read-Only Info',
            icon: Icons.lock_outline_rounded,
            children: [
              _InfoRow(
                icon: Icons.tag_rounded,
                label: 'Employee Code',
                value: _profile.employeeCode,
                isDark: isDark,
                muted: true,
              ),
              if (_profile.username != null && _profile.username!.isNotEmpty)
                _InfoRow(
                  icon: Icons.alternate_email_rounded,
                  label: 'Username',
                  value: '@${_profile.username}',
                  isDark: isDark,
                  muted: true,
                ),
              _InfoRow(
                icon: _roleIcon(_profile.role),
                label: 'Role',
                value: _profile.role.toUpperCase(),
                isDark: isDark,
                muted: true,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Save button
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [rc, rc.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: rc.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.save_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                  label: Text(
                    _isLoading ? 'Saving…' : 'Save Changes',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    required String label,
    required IconData icon,
    required bool isDark,
    required Color rc,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted:
          onFieldSubmitted ??
          (_) {
            if (nextFocus != null)
              FocusScope.of(context).requestFocus(nextFocus);
          },
      validator: validator,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: isDark ? AppColors.textWhite : AppColors.textDark,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
        ),
        prefixIcon: Icon(icon, size: 18, color: rc.withValues(alpha: 0.75)),
        filled: true,
        fillColor: isDark
            ? AppColors.darkElevated.withValues(alpha: 0.5)
            : AppColors.lightElevated.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: rc, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  const _ProfileCard({
    required this.isDark,
    required this.accentColor,
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: accentColor, width: 3),
                bottom: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1,
                ),
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: accentColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textWhite : AppColors.textDark,
                    letterSpacing: 0.2,
                  ),
                ),
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool muted;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = isDark
        ? AppColors.textWhiteMuted
        : AppColors.textDarkMuted;
    final valueColor = muted
        ? labelColor
        : (isDark ? AppColors.textWhite : AppColors.textDark);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: labelColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: valueColor,
                    fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermItem {
  final String label;
  final bool enabled;
  const _PermItem(this.label, this.enabled);
}

class _PermGroup extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;
  final List<_PermItem> perms;

  const _PermGroup({
    required this.label,
    required this.color,
    required this.isDark,
    required this.perms,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: perms.map((p) => _permChip(p)).toList(),
        ),
      ],
    );
  }

  Widget _permChip(_PermItem p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.enabled
            ? color.withValues(alpha: 0.12)
            : (isDark
                  ? AppColors.darkElevated.withValues(alpha: 0.5)
                  : AppColors.lightBg),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: p.enabled
              ? color.withValues(alpha: 0.4)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            p.enabled
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 12,
            color: p.enabled
                ? color
                : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted),
          ),
          const SizedBox(width: 5),
          Text(
            p.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: p.enabled ? FontWeight.w600 : FontWeight.w400,
              color: p.enabled
                  ? color
                  : (isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
