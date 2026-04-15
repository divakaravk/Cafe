import 'dart:async';
import 'package:flutter/material.dart';
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

  // Controllers
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

  Future<void> _loadCompanyData() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        final data = await SupabaseService.getCompany(user.companyId);
        if (data != null) {
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
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Company data not found in database'),
                backgroundColor: AppColors.warning,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading company: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  Future<void> _saveChanges() async {
    if (_company == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Company data not loaded'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final updatedData = {
      'company_name': _nameController.text,
      'company_code': _codeController.text,
      'email': _emailController.text,
      'phone': _phoneController.text,
      'address': _addressController.text,
      'city': _selectedDistrict ?? _cityController.text,
      'state': _selectedState,
      'country': _selectedCountry,
      'has_gst': _hasGst,
      'gstin': _gstinController.text,
      'pan_number': _panController.text,
      'has_table_management': _hasTableManagement,
      'has_item_variants': _hasItemVariants,
    };

    try {
      await SupabaseService.updateCompany(
        _company!.id,
        updatedData,
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Company details updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Update timed out. Please check your connection.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Company Master',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            IconButton(
              onPressed: _saveChanges,
              icon: const Icon(Icons.check_rounded),
              tooltip: 'Save',
            ),
        ],
      ),
      body: _isLoading && _company == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader(
                          'General Information',
                          Icons.info_outline_rounded,
                          isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _nameController,
                          label: 'Company Name',
                          icon: Icons.business_rounded,
                          validator: (v) =>
                              v!.isEmpty ? 'Name is required' : null,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _codeController,
                          label: 'Company Code',
                          icon: Icons.tag_rounded,
                          validator: (v) =>
                              v!.isEmpty ? 'Code is required' : null,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _emailController,
                                label: 'Email',
                                icon: Icons.email_outlined,
                                validator: (v) =>
                                    v!.isNotEmpty && !v.contains('@')
                                    ? 'Invalid email'
                                    : null,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                controller: _phoneController,
                                label: 'Phone',
                                icon: Icons.phone_outlined,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                        _buildSectionHeader(
                          'Address & Location',
                          Icons.location_on_outlined,
                          isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _addressController,
                          label: 'Full Address',
                          icon: Icons.map_outlined,
                          maxLines: 2,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildDropdownField(
                          label: 'Country',
                          icon: Icons.public_rounded,
                          value: _selectedCountry,
                          items: ['India', 'Other'],
                          onChanged: (v) =>
                              setState(() => _selectedCountry = v!),
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdownField(
                                label: 'State',
                                icon: Icons.flag_outlined,
                                value: _selectedState,
                                items: IndiaData.states,
                                hint: 'Select State',
                                onChanged: (v) {
                                  setState(() {
                                    _selectedState = v;
                                    _selectedDistrict = null;
                                  });
                                },
                                isDark: isDark,
                              ),
                            ),
                            if (_selectedState != null) ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildDropdownField(
                                  label: 'District',
                                  icon: Icons.location_city_rounded,
                                  value: _selectedDistrict,
                                  items: IndiaData.getDistricts(
                                    _selectedState!,
                                  ),
                                  hint: 'Select District',
                                  onChanged: (v) =>
                                      setState(() => _selectedDistrict = v),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 32),
                        _buildSectionHeader(
                          'Tax & Business',
                          Icons.account_balance_rounded,
                          isDark,
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: Text(
                            'Enable GST',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Manage GSTIN and tax calculations',
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                          value: _hasGst,
                          activeColor: AppColors.primaryAmber,
                          onChanged: (v) => setState(() => _hasGst = v),
                        ),
                        if (_hasGst) ...[
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _gstinController,
                            label: 'GSTIN',
                            icon: Icons.receipt_long_rounded,
                            isDark: isDark,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _panController,
                          label: 'PAN Number',
                          icon: Icons.credit_card_rounded,
                          isDark: isDark,
                        ),

                        const SizedBox(height: 32),
                        _buildSectionHeader(
                          'Operational Settings',
                          Icons.settings_outlined,
                          isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildToggleSetting(
                          'Table Management',
                          'Enable restaurant floor and table sessions',
                          _hasTableManagement,
                          (v) => setState(() => _hasTableManagement = v),
                        ),
                        _buildToggleSetting(
                          'Item Variants',
                          'Allow items to have multiple rates (Size, Portion)',
                          _hasItemVariants,
                          (v) => setState(() => _hasItemVariants = v),
                        ),

                        const SizedBox(height: 100), // Space for button
                      ],
                    ),
                  ),
                ),
                if (_isLoading)
                  Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(24),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
          ),
          child: Text(
            _isLoading ? 'UPDATING...' : 'SAVE CHANGES',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryAmber),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
    required bool isDark,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? AppColors.darkElevated : AppColors.lightElevated,
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
      value: items.contains(value) ? value : null,
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
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? AppColors.darkElevated : AppColors.lightElevated,
      ),
    );
  }

  Widget _buildToggleSetting(
    String title,
    String subtitle,
    bool value,
    void Function(bool) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          title: Text(
            title,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
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
}
