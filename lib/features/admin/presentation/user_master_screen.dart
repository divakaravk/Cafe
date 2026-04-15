import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';

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

  // Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  String _selectedRole = 'cashier';
  bool _isActive = true;
  XFile? _pickedImage;
  String? _avatarUrl;

  final List<String> _roles = [
    'admin',
    'manager',
    'cashier',
    'waiter',
    'kitchen',
  ];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        final data = await SupabaseService.getUsersForCompany(user.companyId);
        setState(() {
          _users = data.map((e) => UserProfile.fromJson(e)).toList();
        });
      }
    } catch (e) {
      _showSnackBar('Error loading users: $e', AppColors.error);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _startCreate() {
    setState(() {
      _isEditing = true;
      _selectedUser = null;
      _selectedPermissions = UserPermission(userId: const Uuid().v4());
      _clearForm();
    });
  }

  void _startEdit(UserProfile user) async {
    setState(() => _isLoading = true);
    try {
      final permsData = await SupabaseService.getUserPermissions(user.id);
      setState(() {
        _isEditing = true;
        _selectedUser = user;
        _selectedPermissions = permsData != null
            ? UserPermission.fromJson(permsData)
            : UserPermission(userId: user.id);

        _nameController.text = user.fullName;
        _codeController.text = user.employeeCode;
        _usernameController.text = user.username ?? '';
        _passwordController.text = ''; // Don't show password
        _phoneController.text = user.phone ?? '';
        _emailController.text = user.email ?? '';
        _selectedRole = user.role;
        _isActive = user.isActive;
        _avatarUrl = user.avatarUrl;
        _pickedImage = null;
      });
    } catch (e) {
      _showSnackBar('Error loading permissions: $e', AppColors.error);
    } finally {
      setState(() => _isLoading = false);
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
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (image != null) {
      setState(() => _pickedImage = image);
    }
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

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
        );
      }

      final userData = {
        'id': userId,
        'company_id': authUser.companyId,
        'full_name': _nameController.text,
        'employee_code': _codeController.text,
        'username': _usernameController.text,
        'role': _selectedRole,
        'phone': _phoneController.text,
        'email': _emailController.text,
        'is_active': _isActive,
        'avatar_url': currentAvatarUrl,
      };

      // Only update password if provided
      if (_passwordController.text.isNotEmpty) {
        userData['password_hash'] = _passwordController.text;
      } else if (_selectedUser == null) {
        throw 'Password is required for new users';
      }

      final permissions = _selectedPermissions!.toJson();
      permissions['user_id'] = userId;

      await SupabaseService.upsertUserWithPermissions(
        userData: userData,
        permissionData: permissions,
        isNew: _selectedUser == null,
      );

      _showSnackBar('User saved successfully', AppColors.success);
      setState(() => _isEditing = false);
      _loadUsers();
    } catch (e) {
      _showSnackBar('Error saving user: $e', AppColors.error);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Text(
          _isEditing
              ? (_selectedUser == null ? 'Create User' : 'Edit User')
              : 'User Master',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: _isEditing
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _isEditing = false),
              )
            : null,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.check_rounded),
              onPressed: _saveUser,
            )
          else if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: _startCreate,
            ),
        ],
      ),
      body: _isLoading && !_isEditing
          ? const Center(child: CircularProgressIndicator())
          : _isEditing
          ? _buildEditor(isDark)
          : _buildList(isDark),
    );
  }

  Widget _buildList(bool isDark) {
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 64,
              color: AppColors.textWhiteMuted.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: AppColors.textWhiteMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return Card(
          elevation: 0,
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryAmber.withOpacity(0.1),
              backgroundImage: user.avatarUrl != null
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
                  ? Text(
                      user.fullName[0].toUpperCase(),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryAmber,
                      ),
                    )
                  : null,
            ),
            title: Text(
              user.fullName,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            subtitle: Row(
              children: [
                _buildChip(user.role.toUpperCase(), isDark),
                const SizedBox(width: 8),
                Text(
                  user.employeeCode,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textWhiteMuted,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!user.isActive)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(
                      Icons.block_rounded,
                      color: AppColors.error,
                      size: 16,
                    ),
                  ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => _startEdit(user),
          ),
        );
      },
    );
  }

  Widget _buildChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryAmber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryAmber,
        ),
      ),
    );
  }

  Widget _buildEditor(bool isDark) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: 'Basic Information'),
              Tab(text: 'Permissions'),
            ],
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
            indicatorColor: AppColors.primaryAmber,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildBasicInfoTab(isDark),
                _buildPermissionsTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.primaryAmber.withOpacity(0.1),
                    backgroundImage: _pickedImage != null
                        ? FileImage(File(_pickedImage!.path))
                        : (_avatarUrl != null
                              ? NetworkImage(_avatarUrl!)
                              : null),
                    child: (_pickedImage == null && _avatarUrl == null)
                        ? const Icon(
                            Icons.person_rounded,
                            size: 50,
                            color: AppColors.primaryAmber,
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryAmber,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildTextField(
              controller: _nameController,
              label: 'Full Name',
              icon: Icons.person_outline_rounded,
              isDark: isDark,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _codeController,
                    label: 'Employee Code',
                    icon: Icons.badge_outlined,
                    isDark: isDark,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDropdownField(
                    label: 'Role',
                    value: _selectedRole,
                    items: _roles,
                    isDark: isDark,
                    onChanged: (v) => setState(() => _selectedRole = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _usernameController,
              label: 'Username',
              icon: Icons.alternate_email_rounded,
              isDark: isDark,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              isDark: isDark,
              obscureText: true,
              hintText: _selectedUser != null
                  ? 'Leave blank to keep current'
                  : null,
              validator: (v) =>
                  (_selectedUser == null && v!.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _phoneController,
                    label: 'Phone',
                    icon: Icons.phone_outlined,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(
                'Active Member',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                'Allow user to login and perform actions',
                style: GoogleFonts.inter(fontSize: 12),
              ),
              value: _isActive,
              activeColor: AppColors.primaryAmber,
              onChanged: (v) => setState(() => _isActive = v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsTab(bool isDark) {
    if (_selectedPermissions == null)
      return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildPermissionToggle(
          'Dashboard Access',
          'Can view management dashboard',
          _selectedPermissions!.canViewDashboard,
          (v) => _updatePerm(
            (p) => UserPermission.fromJson({
              ...p.toJson(),
              'can_view_dashboard': v,
            }),
          ),
        ),
        _buildPermissionToggle(
          'Billing: Create',
          'Can create new bills/KOTs',
          _selectedPermissions!.canCreateBill,
          (v) => _updatePerm(
            (p) =>
                UserPermission.fromJson({...p.toJson(), 'can_create_bill': v}),
          ),
        ),
        _buildPermissionToggle(
          'Billing: Edit',
          'Can modify existing items in bills',
          _selectedPermissions!.canEditBill,
          (v) => _updatePerm(
            (p) => UserPermission.fromJson({...p.toJson(), 'can_edit_bill': v}),
          ),
        ),
        _buildPermissionToggle(
          'Billing: Void',
          'Can void/remove items from active orders',
          _selectedPermissions!.canVoidItems,
          (v) => _updatePerm(
            (p) =>
                UserPermission.fromJson({...p.toJson(), 'can_void_items': v}),
          ),
        ),
        _buildPermissionToggle(
          'Billing: Cancel',
          'Can cancel saved bills',
          _selectedPermissions!.canCancelBill,
          (v) => _updatePerm(
            (p) =>
                UserPermission.fromJson({...p.toJson(), 'can_cancel_bill': v}),
          ),
        ),
        _buildPermissionToggle(
          'Discounts',
          'Can apply discounts to bills',
          _selectedPermissions!.canApplyDiscount,
          (v) => _updatePerm(
            (p) => UserPermission.fromJson({
              ...p.toJson(),
              'can_apply_discount': v,
            }),
          ),
        ),
        _buildPermissionToggle(
          'Manage Items',
          'Can add/edit menu items and groups',
          _selectedPermissions!.canManageItems,
          (v) => _updatePerm(
            (p) =>
                UserPermission.fromJson({...p.toJson(), 'can_manage_items': v}),
          ),
        ),
        _buildPermissionToggle(
          'Manage Tables',
          'Can manage floor layout and tables',
          _selectedPermissions!.canManageTables,
          (v) => _updatePerm(
            (p) => UserPermission.fromJson({
              ...p.toJson(),
              'can_manage_tables': v,
            }),
          ),
        ),
        _buildPermissionToggle(
          'Reports',
          'Can view sales and financial reports',
          _selectedPermissions!.canViewReports,
          (v) => _updatePerm(
            (p) =>
                UserPermission.fromJson({...p.toJson(), 'can_view_reports': v}),
          ),
        ),
        _buildPermissionToggle(
          'User Master',
          'Can create and manage other users',
          _selectedPermissions!.canManageUsers,
          (v) => _updatePerm(
            (p) =>
                UserPermission.fromJson({...p.toJson(), 'can_manage_users': v}),
          ),
        ),
        _buildPermissionToggle(
          'System Settings',
          'Can modify company settings',
          _selectedPermissions!.canManageSettings,
          (v) => _updatePerm(
            (p) => UserPermission.fromJson({
              ...p.toJson(),
              'can_manage_settings': v,
            }),
          ),
        ),
      ],
    );
  }

  void _updatePerm(UserPermission Function(UserPermission) updater) {
    setState(() {
      _selectedPermissions = updater(_selectedPermissions!);
    });
  }

  Widget _buildPermissionToggle(
    String title,
    String subtitle,
    bool value,
    void Function(bool) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          title: Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12)),
          value: value,
          onChanged: (v) => onChanged(v!),
          activeColor: AppColors.primaryAmber,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    String? hintText,
    required bool isDark,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? AppColors.darkElevated : AppColors.lightElevated,
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    required bool isDark,
  }) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : items.first,
      items: items
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(
                s.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.security_rounded, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? AppColors.darkElevated : AppColors.lightElevated,
      ),
    );
  }
}
