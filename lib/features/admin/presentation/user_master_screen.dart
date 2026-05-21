import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';

// ─── Role meta ───────────────────────────────────────────────────────────────

const _roles = ['admin', 'manager', 'cashier', 'waiter', 'kitchen'];

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

// ─── Screen ──────────────────────────────────────────────────────────────────

class UserMasterScreen extends ConsumerStatefulWidget {
  const UserMasterScreen({super.key});

  @override
  ConsumerState<UserMasterScreen> createState() => _UserMasterScreenState();
}

class _UserMasterScreenState extends ConsumerState<UserMasterScreen> {
  bool _isLoading = false;
  List<UserProfile> _users = [];
  bool _isEditing = false;
  UserProfile? _selectedUser;
  UserPermission? _selectedPermissions;

  // Form
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  // Focus chain: name → code → username → password → phone → email
  final _nameFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();

  String _selectedRole = 'cashier';
  bool _isActive = true;
  bool _showPassword = false;
  XFile? _pickedImage;
  String? _avatarUrl;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    _codeFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // ─── Network ───────────────────────────────────────────────────────────────

  Future<bool> _hasNetwork() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
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

  // ─── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadUsers() async {
    if (_isLoading) return;
    if (!await _checkNetworkAndWarn()) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      final data = await SupabaseService.getUsersForCompany(
        user.companyId,
      ).timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(
          () => _users = data.map((e) => UserProfile.fromJson(e)).toList(),
        );
      }
    } on TimeoutException {
      _showError('Request timed out. Check your connection.', onRetry: _loadUsers);
    } on SocketException {
      _showError('Network error. Check your connection.', onRetry: _loadUsers);
    } catch (e) {
      _showError('Failed to load users: $e', onRetry: _loadUsers);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCreate() {
    setState(() {
      _isEditing = true;
      _selectedTab = 0;
      _selectedUser = null;
      _selectedPermissions = UserPermission(userId: const Uuid().v4());
      _clearForm();
    });
  }

  Future<void> _startEdit(UserProfile user) async {
    if (_isLoading) return;
    if (!await _checkNetworkAndWarn()) return;
    setState(() => _isLoading = true);
    try {
      final permsData = await SupabaseService.getUserPermissions(
        user.id,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _isEditing = true;
        _selectedTab = 0;
        _selectedUser = user;
        _selectedPermissions = permsData != null
            ? UserPermission.fromJson(permsData)
            : UserPermission(userId: user.id);
        _nameController.text = user.fullName;
        _codeController.text = user.employeeCode;
        _usernameController.text = user.username ?? '';
        _passwordController.text = '';
        _phoneController.text = user.phone ?? '';
        _emailController.text = user.email ?? '';
        _selectedRole = user.role;
        _isActive = user.isActive;
        _avatarUrl = user.avatarUrl;
        _pickedImage = null;
        _showPassword = false;
      });
    } on TimeoutException {
      _showError('Request timed out.', onRetry: () => _startEdit(user));
    } on SocketException {
      _showError('Network error. Check your connection.', onRetry: () => _startEdit(user));
    } catch (e) {
      _showError('Failed to load user: $e', onRetry: () => _startEdit(user));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    _nameController.clear();
    _codeController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _phoneController.clear();
    _emailController.clear();
    _selectedRole = 'cashier';
    _isActive = true;
    _avatarUrl = null;
    _pickedImage = null;
    _showPassword = false;
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (image != null && mounted) setState(() => _pickedImage = image);
  }

  Future<void> _saveUser() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    if (!await _checkNetworkAndWarn()) return;

    setState(() => _isLoading = true);
    try {
      final authUser = ref.read(authStateProvider).value!;
      final userId = _selectedUser?.id ?? const Uuid().v4();

      String? currentAvatarUrl = _avatarUrl;
      if (_pickedImage != null) {
        final bytes = await _pickedImage!.readAsBytes();
        final ext = _pickedImage!.name.split('.').last;
        currentAvatarUrl = await SupabaseService.uploadAvatar(
          userId,
          bytes,
          ext,
        ).timeout(const Duration(seconds: 30));
      }

      final userData = {
        'id': userId,
        'company_id': authUser.companyId,
        'user_name': _nameController.text.trim(),
        'employee_code': _codeController.text.trim(),
        'username': _usernameController.text.trim(),
        'user_role': _selectedRole,
        'mob_number': _phoneController.text.trim(),
        'user_email': _emailController.text.trim(),
        'user_active': _isActive,
        'avatar_url': currentAvatarUrl,
      };

      if (_passwordController.text.isNotEmpty) {
        userData['password'] = _passwordController.text;
      } else if (_selectedUser == null) {
        throw 'Password is required for new users';
      }

      final permissions = _selectedPermissions!.toJson();
      permissions['user_id'] = userId;

      await SupabaseService.upsertUserWithPermissions(
        userData: userData,
        permissionData: permissions,
        isNew: _selectedUser == null,
      ).timeout(const Duration(seconds: 20));

      if (mounted) {
        _showSuccess(
          _selectedUser == null
              ? 'User created successfully.'
              : 'User updated successfully.',
        );
        setState(() => _isEditing = false);
        _loadUsers();
      }
    } on TimeoutException {
      _showError('Request timed out. Check your connection.', onRetry: _saveUser);
    } on SocketException {
      _showError('Network error. Check your connection.', onRetry: _saveUser);
    } catch (e) {
      _showError('Failed to save: $e', onRetry: _saveUser);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Feedback ──────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showError(String msg, {VoidCallback? onRetry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 6),
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

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF0F2F5),
      appBar: _buildAppBar(isDark),
      body: _isLoading && !_isEditing
          ? const Center(child: CircularProgressIndicator())
          : _isEditing
          ? _buildEditor(isDark)
          : _buildList(isDark),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      elevation: 0,
      title: Text(
        _isEditing
            ? (_selectedUser == null ? 'New User' : 'Edit User')
            : 'User Master',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      centerTitle: true,
      leading: _isEditing
          ? IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _isEditing = false),
            )
          : null,
      actions: [
        if (_isEditing)
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: _saveUser,
                  tooltip: 'Save',
                )
        else ...[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadUsers,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            onPressed: _startCreate,
            tooltip: 'Add User',
          ),
        ],
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
    );
  }

  // ─── List View ─────────────────────────────────────────────────────────────

  Widget _buildList(bool isDark) {
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.darkSurface : Colors.white),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 48,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _startCreate,
              icon: const Icon(Icons.person_add_rounded),
              label: Text('Add first user', style: GoogleFonts.inter()),
            ),
          ],
        ),
      );
    }

    final activeCount = _users.where((u) => u.isActive).length;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // Stats header
        _buildStatsHeader(isDark, activeCount),
        const SizedBox(height: 16),
        // User cards
        ..._users.map((u) => _buildUserCard(u, isDark)),
      ],
    );
  }

  Widget _buildStatsHeader(bool isDark, int activeCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryOrange.withValues(alpha: 0.85),
            AppColors.primaryAmber.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryOrange.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _statItem(
              'Total',
              _users.length.toString(),
              Icons.people_rounded,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _statItem(
              'Active',
              activeCount.toString(),
              Icons.check_circle_rounded,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _statItem(
              'Inactive',
              (_users.length - activeCount).toString(),
              Icons.block_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) => Column(
    children: [
      Icon(icon, size: 20, color: Colors.white70),
      const SizedBox(height: 4),
      Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.white70,
        ),
      ),
    ],
  );

  Widget _statDivider() => Container(
    width: 1,
    height: 50,
    color: Colors.white.withValues(alpha: 0.3),
  );

  Widget _buildUserCard(UserProfile user, bool isDark) {
    final rc = _roleColor(user.role);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Role accent bar
              Container(width: 4, color: rc),
              // Content
              Expanded(
                child: InkWell(
                  onTap: () => _startEdit(user),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Avatar
                        _buildAvatar(user, rc, radius: 22),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      user.fullName,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: isDark
                                            ? AppColors.textWhite
                                            : AppColors.textDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!user.isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'INACTIVE',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _roleChip(user.role, rc),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      user.username != null
                                          ? '${user.employeeCode}  ·  @${user.username}'
                                          : user.employeeCode,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
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
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark
                              ? AppColors.textWhiteMuted
                              : AppColors.textDarkMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(UserProfile user, Color roleColor, {double radius = 24}) {
    if (user.avatarUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(user.avatarUrl!),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: roleColor.withValues(alpha: 0.12),
      child: Text(
        user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
          color: roleColor,
        ),
      ),
    );
  }

  Widget _roleChip(String role, Color rc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: rc.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_roleIcon(role), size: 10, color: rc),
        const SizedBox(width: 3),
        Text(
          role.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: rc,
          ),
        ),
      ],
    ),
  );

  // ─── Editor ────────────────────────────────────────────────────────────────

  Widget _buildEditor(bool isDark) {
    final rc = _roleColor(_selectedRole);
    return Column(
      children: [
        // Gradient header with pill tabs
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [AppColors.darkSurface, AppColors.darkSurface]
                  : [rc.withValues(alpha: 0.08), const Color(0xFFF0F2F5)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Container(
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBg : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                _pillTab(0, 'Basic Info', Icons.person_rounded, isDark, rc),
                _pillTab(1, 'Permissions', Icons.security_rounded, isDark, rc),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedTab,
            children: [
              _buildBasicInfoTab(isDark),
              _buildPermissionsTab(isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pillTab(int idx, String label, IconData icon, bool isDark, Color rc) {
    final selected = _selectedTab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppColors.darkElevated : rc.withValues(alpha: 0.12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? rc
                    : (isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? rc
                      : (isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Basic Info Tab ────────────────────────────────────────────────────────

  Widget _buildBasicInfoTab(bool isDark) {
    final rc = _roleColor(_selectedRole);
    final mq = MediaQuery.of(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, 0, 0, 16 + mq.padding.bottom),
        children: [
          // Decorative profile header with circles
          SizedBox(
            height: 200,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Background gradient fill
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [AppColors.darkSurface, AppColors.darkBg]
                            : [rc.withValues(alpha: 0.18), rc.withValues(alpha: 0.03)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // Decorative circles — top right
                Positioned(
                  top: -55,
                  right: -45,
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rc.withValues(alpha: isDark ? 0.08 : 0.11),
                    ),
                  ),
                ),
                // Decorative circles — top left
                Positioned(
                  top: -35,
                  left: -55,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rc.withValues(alpha: isDark ? 0.06 : 0.08),
                    ),
                  ),
                ),
                // Small dot — bottom right
                Positioned(
                  bottom: 24,
                  right: 36,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rc.withValues(alpha: isDark ? 0.05 : 0.09),
                    ),
                  ),
                ),
                // Ring outline — bottom left
                Positioned(
                  bottom: -18,
                  left: 24,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: rc.withValues(alpha: isDark ? 0.1 : 0.14),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                // Outer avatar halo ring
                Center(
                  child: Container(
                    width: 114,
                    height: 114,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: rc.withValues(alpha: 0.22),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                // Avatar + camera button
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: rc, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: rc.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _pickedImage != null
                              ? Image.file(File(_pickedImage!.path), fit: BoxFit.cover)
                              : _avatarUrl != null
                                  ? Image.network(_avatarUrl!, fit: BoxFit.cover)
                                  : Container(
                                      color: rc.withValues(alpha: isDark ? 0.15 : 0.08),
                                      child: Icon(Icons.person_rounded, size: 46, color: rc),
                                    ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: rc,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? AppColors.darkBg : Colors.white,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: rc.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              children: [
                const SizedBox(height: 16),

                // Identity section
                _EditorCard(
                  title: 'Identity',
                  icon: Icons.badge_rounded,
                  accentColor: AppColors.primaryAmber,
                  isDark: isDark,
                  children: [
                    _field(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      nextFocus: _codeFocus,
                      label: 'Full Name',
                      icon: Icons.person_outline_rounded,
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            controller: _codeController,
                            focusNode: _codeFocus,
                            nextFocus: _usernameFocus,
                            label: 'Employee Code',
                            icon: Icons.numbers_rounded,
                            validator: (v) =>
                                v!.trim().isEmpty ? 'Required' : null,
                            isDark: isDark,
                            formatters: [UpperCaseTextFormatter()],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _roleDropdown(isDark)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Login credentials section
                _EditorCard(
                  title: 'Login Credentials',
                  icon: Icons.lock_rounded,
                  accentColor: AppColors.info,
                  isDark: isDark,
                  children: [
                    _field(
                      controller: _usernameController,
                      focusNode: _usernameFocus,
                      nextFocus: _passwordFocus,
                      label: 'Username',
                      icon: Icons.alternate_email_rounded,
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                      isDark: isDark,
                      formatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_.]'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _passwordField(isDark),
                  ],
                ),
                const SizedBox(height: 14),

                // Contact section
                _EditorCard(
                  title: 'Contact',
                  icon: Icons.contact_phone_rounded,
                  accentColor: AppColors.accentTeal,
                  isDark: isDark,
                  children: [
                    _field(
                      controller: _phoneController,
                      focusNode: _phoneFocus,
                      nextFocus: _emailFocus,
                      label: 'Phone Number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        if (v.trim().length != 10) return '10 digits required';
                        return null;
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    _field(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      label: 'Email Address',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v!.isNotEmpty && !v.contains('@')
                          ? 'Invalid email'
                          : null,
                      isDark: isDark,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Status section
                _EditorCard(
                  title: 'Account Status',
                  icon: Icons.toggle_on_rounded,
                  accentColor: _isActive ? AppColors.success : AppColors.error,
                  isDark: isDark,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Active Member',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.textWhite
                                      : AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Allow user to login and perform actions',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppColors.textWhiteMuted
                                      : AppColors.textDarkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          activeThumbColor: AppColors.success,
                          activeTrackColor: AppColors.success.withValues(
                            alpha: 0.35,
                          ),
                          inactiveThumbColor: AppColors.error,
                          inactiveTrackColor: AppColors.error.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Save button
                SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: _isLoading
                              ? LinearGradient(
                                  colors: [
                                    AppColors.primaryOrange.withValues(
                                      alpha: 0.4,
                                    ),
                                    AppColors.primaryAmber.withValues(
                                      alpha: 0.4,
                                    ),
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    AppColors.primaryOrange,
                                    AppColors.primaryAmber,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _selectedUser == null
                                          ? 'CREATE USER'
                                          : 'SAVE CHANGES',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        letterSpacing: 1,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ), // closes Padding
        ],
      ),
    );
  }

  Widget _passwordField(bool isDark) {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      obscureText: !_showPassword,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
      validator: (v) => (_selectedUser == null && (v == null || v.isEmpty))
          ? 'Required'
          : null,
      style: GoogleFonts.inter(fontSize: 14),
      decoration: InputDecoration(
        labelText: 'Password',
        hintText: _selectedUser != null ? 'Leave blank to keep current' : null,
        labelStyle: GoogleFonts.inter(fontSize: 13),
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
        suffixIcon: IconButton(
          icon: Icon(
            _showPassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            size: 18,
          ),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryAmber,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkBg : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _roleDropdown(bool isDark) {
    return DropdownButtonFormField<String>(
      initialValue: _roles.contains(_selectedRole)
          ? _selectedRole
          : _roles.first,
      isExpanded: true,
      items: _roles
          .map(
            (r) => DropdownMenuItem(
              value: r,
              child: Row(
                children: [
                  Icon(_roleIcon(r), size: 14, color: _roleColor(r)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _roleColor(r),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedRole = v!),
      decoration: InputDecoration(
        labelText: 'Role',
        labelStyle: GoogleFonts.inter(fontSize: 13),
        prefixIcon: const Icon(Icons.security_rounded, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryAmber,
            width: 1.5,
          ),
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkBg : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  // ─── Permissions Tab ───────────────────────────────────────────────────────

  Widget _buildPermissionsTab(bool isDark) {
    if (_selectedPermissions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = _selectedPermissions!;
    final mq = MediaQuery.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + mq.padding.bottom),
      children: [
        // Quick actions row
        Row(
          children: [
            Expanded(
              child: _quickPermBtn(
                'Grant All',
                Icons.done_all_rounded,
                AppColors.success,
                isDark,
                () => _setAllPerms(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _quickPermBtn(
                'Revoke All',
                Icons.remove_done_rounded,
                AppColors.error,
                isDark,
                () => _setAllPerms(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Billing group
        _PermGroup(
          title: 'Billing',
          icon: Icons.receipt_long_rounded,
          accentColor: AppColors.primaryOrange,
          isDark: isDark,
          items: [
            _PermItem(
              'Create Bills / KOTs',
              Icons.add_circle_outline_rounded,
              p.canCreateBill,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_create_bill': v,
                }),
              ),
            ),
            _PermItem(
              'Edit Bill Items',
              Icons.edit_rounded,
              p.canEditBill,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_edit_bill': v,
                }),
              ),
            ),
            _PermItem(
              'Void Items',
              Icons.remove_circle_outline_rounded,
              p.canVoidItems,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_void_items': v,
                }),
              ),
            ),
            _PermItem(
              'Cancel Bills',
              Icons.cancel_outlined,
              p.canCancelBill,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_cancel_bill': v,
                }),
              ),
            ),
            _PermItem(
              'Apply Discounts',
              Icons.discount_rounded,
              p.canApplyDiscount,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_apply_discount': v,
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Access group
        _PermGroup(
          title: 'Access',
          icon: Icons.dashboard_rounded,
          accentColor: AppColors.info,
          isDark: isDark,
          items: [
            _PermItem(
              'View Dashboard',
              Icons.bar_chart_rounded,
              p.canViewDashboard,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_view_dashboard': v,
                }),
              ),
            ),
            _PermItem(
              'View Reports',
              Icons.assessment_rounded,
              p.canViewReports,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_view_reports': v,
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Administration group
        _PermGroup(
          title: 'Administration',
          icon: Icons.admin_panel_settings_rounded,
          accentColor: const Color(0xFF5C6BC0),
          isDark: isDark,
          items: [
            _PermItem(
              'Manage Menu Items',
              Icons.restaurant_menu_rounded,
              p.canManageItems,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_manage_items': v,
                }),
              ),
            ),
            _PermItem(
              'Manage Tables',
              Icons.table_restaurant_rounded,
              p.canManageTables,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_manage_tables': v,
                }),
              ),
            ),
            _PermItem(
              'Manage Users',
              Icons.people_rounded,
              p.canManageUsers,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_manage_users': v,
                }),
              ),
            ),
            _PermItem(
              'System Settings',
              Icons.settings_rounded,
              p.canManageSettings,
              (v) => _updatePerm(
                (p) => UserPermission.fromJson({
                  ...p.toJson(),
                  'can_manage_settings': v,
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickPermBtn(
    String label,
    IconData icon,
    Color color,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setAllPerms(bool value) {
    setState(() {
      _selectedPermissions = UserPermission(
        userId: _selectedPermissions!.userId,
        canViewDashboard: value,
        canCreateBill: value,
        canEditBill: value,
        canCancelBill: value,
        canApplyDiscount: value,
        canManageItems: value,
        canManageTables: value,
        canViewReports: value,
        canManageUsers: value,
        canManageSettings: value,
        canVoidItems: value,
      );
    });
  }

  void _updatePerm(UserPermission Function(UserPermission) updater) {
    setState(() => _selectedPermissions = updater(_selectedPermissions!));
  }

  // ─── Field builder ─────────────────────────────────────────────────────────

  Widget _field({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
    int? maxLength,
    required bool isDark,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction:
          textInputAction ??
          (nextFocus != null ? TextInputAction.next : TextInputAction.done),
      inputFormatters: formatters,
      onChanged: onChanged,
      onFieldSubmitted: (_) {
        if (nextFocus != null) {
          FocusScope.of(context).requestFocus(nextFocus);
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      style: GoogleFonts.inter(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 13),
        prefixIcon: Icon(icon, size: 18),
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryAmber,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkBg : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─── Editor Section Card ──────────────────────────────────────────────────────

class _EditorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isDark;
  final List<Widget> children;

  const _EditorCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.1 : 0.06),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                  left: BorderSide(color: accentColor, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: accentColor),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Permission Group ─────────────────────────────────────────────────────────

class _PermItem {
  final String title;
  final IconData icon;
  final bool value;
  final void Function(bool) onChanged;

  const _PermItem(this.title, this.icon, this.value, this.onChanged);
}

class _PermGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isDark;
  final List<_PermItem> items;

  const _PermGroup({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.isDark,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.1 : 0.06),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                  left: BorderSide(color: accentColor, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: accentColor),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),
            // Permission rows
            ...items.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              return Column(
                children: [
                  if (idx > 0)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(item.icon, size: 14, color: accentColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.textWhite
                                  : AppColors.textDark,
                            ),
                          ),
                        ),
                        Switch(
                          value: item.value,
                          onChanged: item.onChanged,
                          activeThumbColor: accentColor,
                          activeTrackColor: accentColor.withValues(alpha: 0.35),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── Formatters ───────────────────────────────────────────────────────────────

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
