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

// ─── Validators ─────────────────────────────────────────────────────────────

final _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
final _gstinRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');

String? _validatePan(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  if (!_panRegex.hasMatch(v.trim())) return 'Invalid PAN (e.g. ABCDE1234F)';
  return null;
}

String? _validateGstin(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  if (!_gstinRegex.hasMatch(v.trim())) return 'Invalid GSTIN (15 chars)';
  return null;
}

String? _validatePhone(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final digits = v.trim().replaceAll(RegExp(r'\D'), '');
  if (digits.length != 10) return 'Enter a valid 10-digit number';
  return null;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

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
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _gstinController;
  late final TextEditingController _panController;

  // Focus nodes — chain with textInputAction: TextInputAction.next
  final _nameFocus    = FocusNode();
  final _codeFocus    = FocusNode();
  final _emailFocus   = FocusNode();
  final _phoneFocus   = FocusNode();
  final _addressFocus = FocusNode();
  final _gstinFocus   = FocusNode();
  final _panFocus     = FocusNode();

  String _selectedCountry = 'India';
  String? _selectedState;
  String? _selectedDistrict;
  bool _hasGst = false;
  bool _hasTableManagement = true;
  bool _hasItemVariants = false;

  @override
  void initState() {
    super.initState();
    _nameController    = TextEditingController();
    _codeController    = TextEditingController();
    _emailController   = TextEditingController();
    _phoneController   = TextEditingController();
    _addressController = TextEditingController();
    _cityController    = TextEditingController();
    _gstinController   = TextEditingController();
    _panController     = TextEditingController();
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
    _nameFocus.dispose();
    _codeFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _addressFocus.dispose();
    _gstinFocus.dispose();
    _panFocus.dispose();
    super.dispose();
  }

  // ─── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadCompanyData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      final data = await SupabaseService.getCompany(user.companyId)
          .timeout(const Duration(seconds: 15));
      if (data != null && mounted) {
        _company = Company.fromJson(data);
        _nameController.text    = _company!.companyName;
        _codeController.text    = _company!.companyCode;
        _emailController.text   = data['email']      ?? '';
        _phoneController.text   = data['phone']      ?? '';
        _addressController.text = data['address']    ?? '';
        _cityController.text    = data['city']       ?? '';
        _gstinController.text   = data['gstin']      ?? '';
        _panController.text     = data['pan_number'] ?? '';
        _hasGst              = data['has_gst']              ?? false;
        _hasTableManagement  = data['has_table_management'] ?? true;
        _hasItemVariants     = data['has_item_variants']    ?? false;
        _selectedCountry     = data['country'] ?? 'India';
        _selectedState       = data['state'];
        _selectedDistrict    = data['city'];
        setState(() {});
      } else if (mounted) {
        _showError('Company data not found.', onRetry: _loadCompanyData);
      }
    } on TimeoutException {
      if (mounted) _showError('Connection timed out.', onRetry: _loadCompanyData);
    } catch (e) {
      if (mounted) _showError('Failed to load: $e', onRetry: _loadCompanyData);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    if (_isLoading) return;
    if (_company == null) {
      _showError('Company data not loaded. Please wait.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final updatedData = {
      'company_name': _nameController.text.trim(),
      'company_code': _codeController.text.trim(),
      'email':        _emailController.text.trim(),
      'phone':        _phoneController.text.trim(),
      'address':      _addressController.text.trim(),
      'city':         _selectedDistrict ?? _cityController.text.trim(),
      'state':        _selectedState,
      'country':      _selectedCountry,
      'has_gst':      _hasGst,
      'gstin':        _gstinController.text.trim(),
      'pan_number':   _panController.text.trim(),
      'has_table_management': _hasTableManagement,
      'has_item_variants':    _hasItemVariants,
    };
    try {
      await SupabaseService.updateCompany(_company!.id, updatedData)
          .timeout(const Duration(seconds: 15));
      if (mounted) _showSuccess('Company details updated successfully.');
    } on TimeoutException {
      if (mounted) _showError('Request timed out. Check your connection.', onRetry: _saveChanges);
    } catch (e) {
      if (mounted) _showError('Failed to update: $e', onRetry: _saveChanges);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Feedback ──────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String msg, {VoidCallback? onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 6),
      action: onRetry != null
          ? SnackBarAction(label: 'RETRY', textColor: Colors.white, onPressed: onRetry)
          : null,
    ));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final isWide = screenW >= 600;
    final hPad = isWide ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF0F2F5),
      appBar: _buildAppBar(isDark),
      body: _isLoading && _company == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  hPad, 20, hPad, 24 + mq.padding.bottom,
                ),
                children: [
                  _buildProfileHeader(isDark, isWide),
                  const SizedBox(height: 20),

                  // On wide screens, show General + Address side-by-side
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _generalSection(isDark)),
                        const SizedBox(width: 16),
                        Expanded(child: _addressSection(isDark)),
                      ],
                    )
                  else ...[
                    _generalSection(isDark),
                    const SizedBox(height: 16),
                    _addressSection(isDark),
                  ],

                  const SizedBox(height: 16),
                  _taxSection(isDark),
                  const SizedBox(height: 16),
                  _operationsSection(isDark),
                  const SizedBox(height: 28),
                  _saveButton(isDark, isWide),
                  SizedBox(height: mq.padding.bottom > 0 ? 0 : 8),
                ],
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
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
    );
  }

  // ─── Profile Header ────────────────────────────────────────────────────────

  Widget _buildProfileHeader(bool isDark, bool isWide) {
    final initial = _nameController.text.isNotEmpty
        ? _nameController.text[0].toUpperCase()
        : '?';
    return Container(
      padding: EdgeInsets.all(isWide ? 24 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryOrange.withValues(alpha: 0.85),
            AppColors.primaryAmber.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryOrange.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isWide ? 72 : 60,
            height: isWide ? 72 : 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: GoogleFonts.inter(
                  fontSize: isWide ? 28 : 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameController.text.isNotEmpty
                      ? _nameController.text
                      : 'Your Company',
                  style: GoogleFonts.inter(
                    fontSize: isWide ? 20 : 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_codeController.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _codeController.text,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    _headerChip(
                      _hasTableManagement ? 'Tables ON' : 'Tables OFF',
                      _hasTableManagement ? Icons.table_restaurant_rounded : Icons.table_restaurant_outlined,
                    ),
                    const SizedBox(width: 8),
                    _headerChip(
                      _hasGst ? 'GST ON' : 'GST OFF',
                      _hasGst ? Icons.receipt_rounded : Icons.receipt_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerChip(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );

  // ─── Sections ──────────────────────────────────────────────────────────────

  Widget _generalSection(bool isDark) {
    return _SectionCard(
      title: 'General Information',
      icon: Icons.store_rounded,
      accentColor: AppColors.primaryAmber,
      isDark: isDark,
      children: [
        _field(
          controller: _nameController,
          focusNode: _nameFocus,
          nextFocus: _codeFocus,
          label: 'Company Name',
          icon: Icons.business_rounded,
          validator: (v) => v!.trim().isEmpty ? 'Required' : null,
          isDark: isDark,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _field(
          controller: _codeController,
          focusNode: _codeFocus,
          nextFocus: _emailFocus,
          label: 'Company Code',
          icon: Icons.tag_rounded,
          validator: (v) => v!.trim().isEmpty ? 'Required' : null,
          isDark: isDark,
          formatters: [UpperCaseTextFormatter()],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _field(
          controller: _emailController,
          focusNode: _emailFocus,
          nextFocus: _phoneFocus,
          label: 'Email Address',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: (v) => v!.isNotEmpty && !v.contains('@') ? 'Invalid email' : null,
          isDark: isDark,
        ),
        const SizedBox(height: 14),
        _field(
          controller: _phoneController,
          focusNode: _phoneFocus,
          nextFocus: _addressFocus,
          label: 'Phone Number',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          validator: _validatePhone,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          isDark: isDark,
          helperText: '10-digit mobile number',
        ),
      ],
    );
  }

  Widget _addressSection(bool isDark) {
    return _SectionCard(
      title: 'Address & Location',
      icon: Icons.location_on_rounded,
      accentColor: AppColors.accentTeal,
      isDark: isDark,
      children: [
        _field(
          controller: _addressController,
          focusNode: _addressFocus,
          label: 'Full Address',
          icon: Icons.map_outlined,
          maxLines: 2,
          isDark: isDark,
          textInputAction: TextInputAction.newline,
        ),
        const SizedBox(height: 14),
        _dropdown(
          label: 'Country',
          icon: Icons.public_rounded,
          value: _selectedCountry,
          items: const ['India', 'Other'],
          onChanged: (v) => setState(() => _selectedCountry = v!),
          isDark: isDark,
        ),
        const SizedBox(height: 14),
        _dropdown(
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
        if (_selectedState != null) ...[
          const SizedBox(height: 14),
          _dropdown(
            label: 'District',
            icon: Icons.location_city_rounded,
            value: _selectedDistrict,
            items: IndiaData.getDistricts(_selectedState!),
            hint: 'Select District',
            onChanged: (v) => setState(() => _selectedDistrict = v),
            isDark: isDark,
          ),
        ],
      ],
    );
  }

  Widget _taxSection(bool isDark) {
    return _SectionCard(
      title: 'Tax & Compliance',
      icon: Icons.account_balance_rounded,
      accentColor: AppColors.info,
      isDark: isDark,
      children: [
        _switchRow(
          title: 'Enable GST',
          subtitle: 'Calculate CGST & SGST on bills',
          value: _hasGst,
          onChanged: (v) => setState(() => _hasGst = v),
          isDark: isDark,
          activeColor: AppColors.info,
        ),
        if (_hasGst) ...[
          const SizedBox(height: 14),
          _field(
            controller: _gstinController,
            focusNode: _gstinFocus,
            nextFocus: _panFocus,
            label: 'GSTIN',
            icon: Icons.receipt_long_rounded,
            maxLength: 15,
            validator: _validateGstin,
            formatters: [UpperCaseTextFormatter()],
            isDark: isDark,
            helperText: 'e.g. 29ABCDE1234F1Z5',
          ),
        ],
        const SizedBox(height: 14),
        _field(
          controller: _panController,
          focusNode: _panFocus,
          label: 'PAN Number',
          icon: Icons.credit_card_rounded,
          maxLength: 10,
          validator: _validatePan,
          formatters: [UpperCaseTextFormatter()],
          isDark: isDark,
          helperText: 'e.g. ABCDE1234F',
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _operationsSection(bool isDark) {
    return _SectionCard(
      title: 'Operational Settings',
      icon: Icons.tune_rounded,
      accentColor: AppColors.accentCoral,
      isDark: isDark,
      children: [
        _switchRow(
          title: 'Table Management',
          subtitle: 'Restaurant floor plan with table sessions',
          value: _hasTableManagement,
          onChanged: (v) => setState(() => _hasTableManagement = v),
          isDark: isDark,
          activeColor: AppColors.accentCoral,
        ),
        const SizedBox(height: 4),
        Divider(
          height: 20,
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        _switchRow(
          title: 'Item Variants',
          subtitle: 'Multiple sizes or portions per item',
          value: _hasItemVariants,
          onChanged: (v) => setState(() => _hasItemVariants = v),
          isDark: isDark,
          activeColor: AppColors.accentCoral,
        ),
      ],
    );
  }

  // ─── Save Button ───────────────────────────────────────────────────────────

  Widget _saveButton(bool isDark, bool isWide) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: _isLoading
                  ? LinearGradient(
                      colors: [
                        AppColors.primaryOrange.withValues(alpha: 0.4),
                        AppColors.primaryAmber.withValues(alpha: 0.4),
                      ],
                    )
                  : const LinearGradient(
                      colors: [AppColors.primaryOrange, AppColors.primaryAmber],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: _isLoading
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.primaryOrange.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
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
                        const Icon(Icons.check_circle_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'SAVE CHANGES',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Field Builders ────────────────────────────────────────────────────────

  Widget _field({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    required String label,
    required IconData icon,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? formatters,
    required bool isDark,
    String? helperText,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction ??
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
        helperText: helperText,
        helperStyle: GoogleFonts.inter(
          fontSize: 11,
          color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
        ),
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
          borderSide: const BorderSide(color: AppColors.primaryAmber, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkBg : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _dropdown({
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
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: GoogleFonts.inter(fontSize: 14)),
              ))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 13),
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryAmber, width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkBg : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
    required bool isDark,
    required Color activeColor,
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
                  color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: activeColor,
          activeTrackColor: activeColor.withValues(alpha: 0.35),
        ),
      ],
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isDark;
  final List<Widget> children;

  const _SectionCard({
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.1 : 0.06),
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                  left: BorderSide(color: accentColor, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: accentColor),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
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
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
