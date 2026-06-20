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

/// Manages the SELLING ITEMS (variants) that belong to one Item Group.
///
/// Example: open the "Dosa" group → Plain Dosa, Ghee Dosa, Masala Dosa…
/// A selling item with an empty/zero Override Rate inherits the group rate.
class ItemVariantScreen extends ConsumerStatefulWidget {
  final Item? item;
  const ItemVariantScreen({super.key, this.item});

  @override
  ConsumerState<ItemVariantScreen> createState() => _ItemVariantScreenState();
}

class _ItemVariantScreenState extends ConsumerState<ItemVariantScreen> {
  bool _isLoading = false;
  List<ItemVariant> _variants = [];
  List<Item> _groups = [];
  List<Map<String, dynamic>> _hsns = [];

  String? _selectedGroupId;
  Item? _selectedGroup;

  // List search
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.item?.id;
    _selectedGroup = widget.item;
    _initialLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      final results = await Future.wait([
        SupabaseService.getItemGroups(user.companyId),
        SupabaseService.getCompanyHsns(user.companyId),
      ]);

      final groups = results[0]
          .map((e) => Item.fromJson(e))
          .toList()
        ..sort(
          (a, b) => a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()),
        );

      setState(() {
        _groups = groups;
        _hsns = results[1];
        if (_selectedGroupId != null) {
          _selectedGroup = _groups.firstWhere(
            (g) => g.id == _selectedGroupId,
            orElse: () => _selectedGroup ?? _groups.first,
          );
        }
      });

      if (_selectedGroupId != null) await _loadVariants();
    } catch (e) {
      _showError('Load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVariants() async {
    if (_selectedGroupId == null) return;
    try {
      final rows = await SupabaseService.getVariantsByGroup(_selectedGroupId!);
      setState(() {
        _variants = rows.map((e) => ItemVariant.fromJson(e)).toList();
      });
    } catch (e) {
      _showError('Variant load error: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  double get _groupBaseRate => _selectedGroup?.baseRate ?? 0;

  void _addOrEditVariant([ItemVariant? variant]) {
    if (_selectedGroupId == null) {
      _showError('Please select an Item Group first');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();

    final nameController = TextEditingController(
      text: variant?.variantName ?? '',
    );
    // Show the override rate only when it actually overrides; otherwise leave
    // blank so the user sees it is inheriting the group rate.
    final rateController = TextEditingController(
      text: (variant != null && variant.hasPriceOverride)
          ? variant.baseRate.toStringAsFixed(
              variant.baseRate.truncateToDouble() == variant.baseRate ? 0 : 2,
            )
          : '',
    );
    final descController = TextEditingController(
      text: variant?.description ?? '',
    );
    final orderController = TextEditingController(
      text: variant?.displayOrder.toString() ?? '0',
    );

    String? selectedHsnId = variant?.hsnId ?? _selectedGroup?.hsnId;
    String foodType = variant?.foodType ?? 'veg';
    bool isAvailable = variant?.isAvailable ?? true;
    bool isActive = variant?.isActive ?? true;
    bool isDefault =
        variant?.isDefault ?? _variants.isEmpty; // first item defaults to true
    XFile? pickedImage;
    String? currentImageUrl = variant?.imageUrl;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            variant == null
                                ? 'New Selling Item'
                                : 'Edit Selling Item',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'in ${_selectedGroup?.itemName ?? ''}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        children: [
                          Center(
                            child: GestureDetector(
                              onTap: () async {
                                final picker = ImagePicker();
                                final img = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 50,
                                );
                                if (img != null) {
                                  setModalState(() => pickedImage = img);
                                }
                              },
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkBg
                                      : AppColors.lightBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                  image: pickedImage != null
                                      ? DecorationImage(
                                          image: FileImage(
                                            File(pickedImage!.path),
                                          ),
                                          fit: BoxFit.cover,
                                        )
                                      : (currentImageUrl != null
                                            ? DecorationImage(
                                                image: NetworkImage(
                                                  currentImageUrl,
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null),
                                ),
                                child:
                                    (pickedImage == null &&
                                        currentImageUrl == null)
                                    ? const Icon(
                                        Icons.add_a_photo_rounded,
                                        size: 32,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          TextFormField(
                            controller: nameController,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Variant name is required'
                                : null,
                            decoration: _inputDecoration(
                              'Variant Name',
                              Icons.label_important_rounded,
                              isDark,
                            ),
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          const SizedBox(height: 16),

                          // Food type — veg / egg / non-veg per selling item
                          _buildFoodTypeSelector(
                            foodType,
                            (v) => setModalState(() => foodType = v),
                            isDark,
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: rateController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'),
                              ),
                            ],
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) {
                              final raw = (v ?? '').trim();
                              if (raw.isEmpty) return null; // inherits
                              final parsed = double.tryParse(raw);
                              if (parsed == null) return 'Enter a valid number';
                              if (parsed < 0) {
                                return 'Override rate must be ≥ 0';
                              }
                              return null;
                            },
                            decoration: _inputDecoration(
                              'Override Base Rate',
                              Icons.currency_rupee_rounded,
                              isDark,
                            ).copyWith(
                              helperText:
                                  'Leave empty to inherit group rate '
                                  '(₹${_groupBaseRate.toStringAsFixed(0)})',
                            ),
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          const SizedBox(height: 16),

                          DropdownButtonFormField<String?>(
                            initialValue: selectedHsnId,
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Inherit group HSN'),
                              ),
                              ..._hsns.map(
                                (h) => DropdownMenuItem<String?>(
                                  value: h['id'] as String,
                                  child: Text(
                                    '${h['hsn_code']} • ${(h['gst_rate'] ?? 0)}%',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setModalState(() => selectedHsnId = v),
                            decoration: _inputDecoration(
                              'HSN Code',
                              Icons.receipt_long_rounded,
                              isDark,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: descController,
                            maxLines: 2,
                            decoration: _inputDecoration(
                              'Description',
                              Icons.description_rounded,
                              isDark,
                            ),
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: orderController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) {
                              final raw = (v ?? '').trim();
                              if (raw.isEmpty) return null;
                              final parsed = int.tryParse(raw);
                              if (parsed == null) return 'Enter a whole number';
                              if (parsed < 0) {
                                return 'Display order must be ≥ 0';
                              }
                              return null;
                            },
                            decoration: _inputDecoration(
                              'Display Order',
                              Icons.sort_rounded,
                              isDark,
                            ),
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          const SizedBox(height: 16),

                          _buildToggle(
                            'Default Variant',
                            isDefault,
                            (v) => setModalState(() => isDefault = v),
                            isDark,
                          ),
                          _buildToggle(
                            'Available',
                            isAvailable,
                            (v) => setModalState(() => isAvailable = v),
                            isDark,
                          ),
                          _buildToggle(
                            'Active',
                            isActive,
                            (v) => setModalState(() => isActive = v),
                            isDark,
                          ),
                          const SizedBox(height: 24),

                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    setModalState(() => isSaving = true);
                                    final ok = await _saveVariant(
                                      existing: variant,
                                      name: nameController.text.trim(),
                                      overrideRateRaw:
                                          rateController.text.trim(),
                                      hsnId: selectedHsnId,
                                      description: descController.text.trim(),
                                      displayOrder:
                                          int.tryParse(
                                            orderController.text.trim(),
                                          ) ??
                                          0,
                                      isAvailable: isAvailable,
                                      isActive: isActive,
                                      isDefault: isDefault,
                                      foodType: foodType,
                                      pickedImage: pickedImage,
                                      currentImageUrl: currentImageUrl,
                                    );
                                    if (ok && context.mounted) {
                                      Navigator.pop(context);
                                    } else {
                                      setModalState(() => isSaving = false);
                                    }
                                  },
                            child: isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('SAVE SELLING ITEM'),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _saveVariant({
    required ItemVariant? existing,
    required String name,
    required String overrideRateRaw,
    required String? hsnId,
    required String description,
    required int displayOrder,
    required bool isAvailable,
    required bool isActive,
    required bool isDefault,
    required String foodType,
    required XFile? pickedImage,
    required String? currentImageUrl,
  }) async {
    try {
      final user = ref.read(authStateProvider).value!;
      final id = existing?.id ?? const Uuid().v4();

      String? finalImageUrl = currentImageUrl;
      if (pickedImage != null) {
        final bytes = await pickedImage.readAsBytes();
        final ext = pickedImage.name.split('.').last;
        finalImageUrl = await SupabaseService.uploadItemImage(id, bytes, ext);
      }

      // Empty override => inherit (store 0); otherwise the variant overrides.
      final overrideRate =
          overrideRateRaw.isEmpty ? 0.0 : (double.tryParse(overrideRateRaw) ?? 0);

      await SupabaseService.upsertVariant({
        'id': id,
        'item_id': _selectedGroupId,
        'variant_name': name,
        'base_rate': overrideRate,
        'hsn_id': hsnId,
        'description': description.isEmpty ? null : description,
        'image_url': finalImageUrl,
        'display_order': displayOrder,
        'is_available': isAvailable,
        'is_active': isActive,
        'is_default': isDefault,
        'food_type': foodType,
        'updated_by': user.id,
      });

      // Enforce a single default per group + sync the group pointer.
      if (isDefault) {
        await SupabaseService.setDefaultVariant(
          itemId: _selectedGroupId!,
          variantId: id,
        );
      }

      await _loadVariants();
      _invalidateGroup();
      return true;
    } catch (e) {
      _showError('Save failed: $e');
      return false;
    }
  }

  void _invalidateGroup() {
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      ref.invalidate(itemGroupsProvider(user.companyId));
      ref.invalidate(allItemsProvider(user.companyId));
    }
    if (_selectedGroupId != null) {
      ref.invalidate(variantsByGroupProvider(_selectedGroupId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Text(
          'Item Variant',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryAmber, AppColors.primaryOrange],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      floatingActionButton: _selectedGroupId != null
          ? FloatingActionButton.extended(
              onPressed: () => _addOrEditVariant(),
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Add Item',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      body: Column(
        children: [
          // Group selector
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedGroupId,
                  isExpanded: true,
                  items: _groups
                      .map(
                        (g) => DropdownMenuItem(
                          value: g.id,
                          child: Text(
                            '${g.itemName} (${g.itemCode.isEmpty ? 'N/A' : g.itemCode})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedGroupId = v;
                      _selectedGroup = _groups.firstWhere((g) => g.id == v);
                      _variants = [];
                      _searchController.clear();
                      _searchQuery = '';
                    });
                    _loadVariants();
                  },
                  decoration: _inputDecoration(
                    'Item Group',
                    Icons.category_rounded,
                    isDark,
                  ),
                ),
                if (_selectedGroup != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAmber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primaryAmber.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: AppColors.primaryOrange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Group base rate ₹${_groupBaseRate.toStringAsFixed(0)} • '
                            'items without an override inherit this price',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.textWhiteMuted
                                  : AppColors.textDarkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_selectedGroupId != null && _variants.isNotEmpty)
            _buildSearchBar(isDark),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedGroupId == null
                ? _buildSelectPrompt()
                : _variants.isEmpty
                ? _buildEmptyState()
                : _buildVariantList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.inter(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search selling items…',
          hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          filled: true,
          fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
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
            borderSide: const BorderSide(color: AppColors.primaryAmber),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Select an Item Group to manage its selling items',
            style: GoogleFonts.inter(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.layers_clear_rounded,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No selling items in this group',
            style: GoogleFonts.inter(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _addOrEditVariant(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add First Selling Item'),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantList(bool isDark) {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _variants
        : _variants
              .where((v) => v.variantName.toLowerCase().contains(q))
              .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No matches for "$_searchQuery"',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadVariants,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final v = filtered[index];
          final hsn = _hsns.firstWhere(
            (h) => h['id'] == v.hsnId,
            orElse: () => {},
          );
          final effectiveRate =
              _selectedGroup?.effectiveRateFor(v) ?? v.baseRate;
          final inheriting = !v.hasPriceOverride;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: v.isDefault
                    ? AppColors.primaryAmber.withValues(alpha: 0.5)
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                width: v.isDefault ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _addOrEditVariant(v),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    // Thumbnail
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primaryAmber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9),
                        image: v.imageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(v.imageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: v.imageUrl == null
                          ? const Icon(
                              Icons.fastfood_rounded,
                              size: 18,
                              color: AppColors.primaryAmber,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    // Name + meta
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _foodTypeDot(v.foodType),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  v.variantName,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (v.isDefault) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryAmber,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    'DEFAULT',
                                    style: GoogleFonts.inter(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                '₹${effectiveRate.toStringAsFixed(0)}',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                              if (inheriting)
                                Text(
                                  ' inherited',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: isDark
                                        ? AppColors.textWhiteMuted
                                        : AppColors.textDarkMuted,
                                  ),
                                ),
                              if (hsn.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'HSN ${hsn['hsn_code']}',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: isDark
                                        ? AppColors.textWhiteMuted
                                        : AppColors.textDarkMuted,
                                  ),
                                ),
                              ],
                              if (!v.isActive) ...[
                                const SizedBox(width: 6),
                                _statusPill('Inactive', AppColors.error),
                              ] else if (!v.isAvailable) ...[
                                const SizedBox(width: 6),
                                _statusPill('Unavailable', AppColors.warning),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Actions
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: AppColors.info,
                      ),
                      onPressed: () => _addOrEditVariant(v),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.error,
                      ),
                      onPressed: () => _deleteVariant(v),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static const List<Map<String, dynamic>> _foodTypes = [
    {'value': 'veg', 'label': 'Veg', 'color': Colors.green},
    {'value': 'egg', 'label': 'Egg', 'color': Colors.amber},
    {'value': 'non-veg', 'label': 'Non-veg', 'color': Colors.red},
  ];

  Color _foodColor(String type) {
    if (type == 'egg') return Colors.amber;
    if (type == 'non-veg') return Colors.red;
    return Colors.green;
  }

  Widget _foodTypeDot(String type) {
    final color = _foodColor(type);
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _buildFoodTypeSelector(
    String selected,
    Function(String) onChanged,
    bool isDark,
  ) {
    return Row(
      children: _foodTypes.map((ft) {
        final value = ft['value'] as String;
        final label = ft['label'] as String;
        final color = ft['color'] as Color;
        final active = selected == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active
                      ? color.withValues(alpha: 0.12)
                      : (isDark ? AppColors.darkBg : AppColors.lightBg),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active
                        ? color
                        : (isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder),
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _foodTypeDot(value),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? color
                            : (isDark
                                  ? AppColors.textWhiteMuted
                                  : AppColors.textDarkMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToggle(
    String label,
    bool value,
    Function(bool) onChanged,
    bool isDark,
  ) {
    return SwitchListTile(
      title: Text(label, style: GoogleFonts.inter(fontSize: 13)),
      value: value,
      activeThumbColor: AppColors.primaryAmber,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, bool isDark) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      labelStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryAmber),
      ),
      filled: true,
      fillColor: isDark ? AppColors.darkBg : AppColors.lightBg,
    );
  }

  Future<void> _deleteVariant(ItemVariant v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selling Item?'),
        content: Text('Delete "${v.variantName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SupabaseService.deleteVariant(v.id);
        // If we removed the default, promote the next sellable item.
        if (v.isDefault) {
          await _loadVariants();
          final next = _variants.where((x) => x.isActive).toList();
          if (next.isNotEmpty) {
            await SupabaseService.setDefaultVariant(
              itemId: _selectedGroupId!,
              variantId: next.first.id,
            );
          }
        }
        await _loadVariants();
        _invalidateGroup();
      } catch (e) {
        _showError('Delete failed: $e');
      }
    }
  }
}
