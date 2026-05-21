import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/india_data.dart';
import '../../../providers/providers.dart';
import '../../../models/models.dart';

class CompanyMasterScreen extends ConsumerStatefulWidget {
  const CompanyMasterScreen({super.key});

  @override
  ConsumerState<CompanyMasterScreen> createState() =>
      _CompanyMasterScreenState();
}

class _CompanyMasterScreenState extends ConsumerState<CompanyMasterScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  Company? _company;

  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _gstinController;
  late TextEditingController _panController;

  String _selectedCountry = 'India';
  String? _selectedState;
  String? _selectedDistrict;
  bool _hasGst = false;
  bool _hasTableManagement = true;
  bool _hasItemVariants = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _codeController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _cityController = TextEditingController();
    _gstinController = TextEditingController();
    _panController = TextEditingController();
    _loadCompanyData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _gstinController.dispose();
    _panController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanyData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      final data = await SupabaseService.getCompany(
        user.companyId,
      ).timeout(const Duration(seconds: 15));
      if (data != null && mounted) {
        _company = Company.fromJson(data);
        _nameController.text = _company!.companyName;
        _codeController.text = _company!.companyCode;
        _emailController.text = data['email'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _addressController.text = data['address'] ?? '';
        _cityController.text = data['city'] ?? '';
        _gstinController.text = data['gstin'] ?? '';
        _panController.text = data['pan_number'] ?? '';
        _hasGst = data['has_gst'] ?? false;
        _hasTableManagement = data['has_table_management'] ?? true;
        _hasItemVariants = data['has_item_variants'] ?? false;
        _selectedCountry = data['country'] ?? 'India';
        _selectedState = data['state'];
        _selectedDistrict = data['city'];
      } else if (mounted) {
        _showError('Company data not found.', onRetry: _loadCompanyData);
      }
    } on TimeoutException {
      if (mounted)
        _showError('Connection timed out.', onRetry: _loadCompanyData);
    } catch (e) {
      if (mounted) _showError('Failed to load: $e', onRetry: _loadCompanyData);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    if (_isLoading) return; // guard against double tap
    if (_company == null) {
      _showError('Company data not loaded. Please wait.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final updatedData = {
      'company_name': _nameController.text.trim(),
      'company_code': _codeController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'city': _selectedDistrict ?? _cityController.text.trim(),
      'state': _selectedState,
      'country': _selectedCountry,
      'has_gst': _hasGst,
      'gstin': _gstinController.text.trim(),
      'pan_number': _panController.text.trim(),
      'has_table_management': _hasTableManagement,
      'has_item_variants': _hasItemVariants,
    };

    try {
      await SupabaseService.updateCompany(
        _company!.id,
        updatedData,
      ).timeout(const Duration(seconds: 15));
      if (mounted) _showSuccess('Company details updated successfully.');
    } on TimeoutException {
      if (mounted)
        _showError(
          'Request timed out. Check your connection.',
          onRetry: _saveChanges,
        );
    } catch (e) {
      if (mounted) _showError('Failed to update: $e', onRetry: _saveChanges);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccess(String msg) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF3F4F6),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Company Master',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      body: _isLoading && _company == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + bottomPadding),
                children: [
                  _SectionCard(
                    title: 'General Information',
                    icon: Icons.store_rounded,
                    isDark: isDark,
                    children: [
                      _buildTextField(
                        controller: _nameController,
                        label: 'Company Name',
                        icon: Icons.business_rounded,
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Name is required' : null,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _codeController,
                        label: 'Company Code',
                        icon: Icons.tag_rounded,
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Code is required' : null,
                        isDark: isDark,
                        inputFormatters: [UpperCaseTextFormatter()],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _emailController,
                              label: 'Email',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) =>
                                  v!.isNotEmpty && !v.contains('@')
                                  ? 'Invalid email'
                                  : null,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _phoneController,
                              label: 'Phone',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Address & Location',
                    icon: Icons.location_on_rounded,
                    isDark: isDark,
                    children: [
                      _buildTextField(
                        controller: _addressController,
                        label: 'Full Address',
                        icon: Icons.map_outlined,
                        maxLines: 2,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 14),
                      _buildDropdownField(
                        label: 'Country',
                        icon: Icons.public_rounded,
                        value: _selectedCountry,
                        items: const ['India', 'Other'],
                        onChanged: (v) => setState(() => _selectedCountry = v!),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdownField(
                              label: 'State',
                              icon: Icons.flag_outlined,
                              value: _selectedState,
                              items: IndiaData.states,
                              hint: 'Select State',
                              onChanged: (v) => setState(() {
                                _selectedState = v;
                                _selectedDistrict = null;
                              }),
                              isDark: isDark,
                            ),
                          ),
                          if (_selectedState != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'District',
                                icon: Icons.location_city_rounded,
                                value: _selectedDistrict,
                                items: IndiaData.getDistricts(_selectedState!),
                                hint: 'Select District',
                                onChanged: (v) =>
                                    setState(() => _selectedDistrict = v),
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Tax & Compliance',
                    icon: Icons.account_balance_rounded,
                    isDark: isDark,
                    children: [
                      _buildSwitch(
                        title: 'Enable GST',
                        subtitle: 'Manage GSTIN and tax calculations',
                        value: _hasGst,
                        onChanged: (v) => setState(() => _hasGst = v),
                        isDark: isDark,
                      ),
                      if (_hasGst) ...[
                        const SizedBox(height: 14),
                        _buildTextField(
                          controller: _gstinController,
                          label: 'GSTIN',
                          icon: Icons.receipt_long_rounded,
                          isDark: isDark,
                          inputFormatters: [UpperCaseTextFormatter()],
                        ),
                      ],
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _panController,
                        label: 'PAN Number',
                        icon: Icons.credit_card_rounded,
                        isDark: isDark,
                        inputFormatters: [UpperCaseTextFormatter()],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Operational Settings',
                    icon: Icons.tune_rounded,
                    isDark: isDark,
                    children: [
                      _buildSwitch(
                        title: 'Table Management',
                        subtitle: 'Enable restaurant floor and table sessions',
                        value: _hasTableManagement,
                        onChanged: (v) =>
                            setState(() => _hasTableManagement = v),
                        isDark: isDark,
                      ),
                      Divider(
                        height: 24,
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                      _buildSwitch(
                        title: 'Item Variants',
                        subtitle: 'Allow items with multiple sizes or portions',
                        value: _hasItemVariants,
                        onChanged: (v) => setState(() => _hasItemVariants = v),
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.primaryOrange
                              .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'SAVE CHANGES',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    required bool isDark,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.inter(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 13),
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
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

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    String? hint,
    required bool isDark,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : null,
      isExpanded: true,
      menuMaxHeight: 300,
      items: items
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(s, style: GoogleFonts.inter(fontSize: 14)),
            ),
          )
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 13),
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
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

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
    required bool isDark,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textWhite : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primaryAmber,
          activeTrackColor: AppColors.primaryAmber.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

/// Card container for each settings section
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isDark;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: AppColors.primaryAmber),
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
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
