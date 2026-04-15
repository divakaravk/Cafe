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

class ItemVariantScreen extends ConsumerStatefulWidget {
  final Item? item;
  const ItemVariantScreen({super.key, this.item});

  @override
  ConsumerState<ItemVariantScreen> createState() => _ItemVariantScreenState();
}

class _ItemVariantScreenState extends ConsumerState<ItemVariantScreen> {
  bool _isLoading = false;
  List<ItemVariant> _variants = [];
  List<Map<String, dynamic>> _masterItems = [];
  List<Map<String, dynamic>> _hsns = [];

  String? _selectedMasterId;
  Map<String, dynamic>? _selectedMasterData;

  @override
  void initState() {
    super.initState();
    _selectedMasterId = widget.item?.id;
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      // Parallel fetch
      final results = await Future.wait([
        SupabaseService.getMasterItemsForVariants(user.companyId),
        SupabaseService.getCompanyHsns(user.companyId),
      ]);

      setState(() {
        _masterItems = results[0];
        _hsns = results[1];

        if (_selectedMasterId != null) {
          _selectedMasterData = _masterItems.firstWhere(
            (m) => m['id'] == _selectedMasterId,
            orElse: () => {},
          );
          if (_selectedMasterData?.isEmpty ?? true) _selectedMasterData = null;
        }
      });

      if (_selectedMasterId != null) {
        await _loadVariants();
      }
    } catch (e) {
      _showError('Load error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVariants() async {
    if (_selectedMasterId == null) return;
    try {
      final items = await SupabaseService.getAllItems(
        ref.read(authStateProvider).value!.companyId,
      );
      final currentItemData = items.firstWhere(
        (i) => i['id'] == _selectedMasterId,
      );
      final currentItem = Item.fromJson(currentItemData);

      setState(() {
        _variants = currentItem.variants;
        _selectedMasterData = currentItemData;
      });
    } catch (e) {
      _showError('Variant load error: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  void _addOrEditVariant([ItemVariant? variant]) {
    if (_selectedMasterId == null) {
      _showError('Please select a Master Item first');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Form State
    final nameController = TextEditingController(
      text: variant?.variantName ?? '',
    );
    final rateController = TextEditingController(
      text: variant?.baseRate.toString() ?? '',
    );
    final inclusiveRateController = TextEditingController(
      text: variant?.inclusiveRate.toString() ?? '0',
    );
    final descController = TextEditingController(
      text: variant?.description ?? '',
    );
    final orderController = TextEditingController(
      text: variant?.displayOrder.toString() ?? '0',
    );

    String? selectedHsnId = variant?.hsnId ?? _selectedMasterData?['hsn_id'];
    bool isRateInclusive =
        variant?.isRateInclusive ??
        _selectedMasterData?['is_rate_inclusive'] ??
        false;
    bool isAvailable = variant?.isAvailable ?? true;
    bool isActive = variant?.isActive ?? true;
    XFile? pickedImage;
    String? currentImageUrl = variant?.imageUrl;

    // If adding new, inherit base rate if empty
    if (variant == null && rateController.text == '0.0' ||
        rateController.text.isEmpty) {
      rateController.text = (_selectedMasterData?['base_rate'] ?? 0).toString();
      inclusiveRateController.text =
          (_selectedMasterData?['inclusive_rate'] ?? 0).toString();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      variant == null ? 'New Variant' : 'Edit Variant',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      // Image Section
                      Center(
                        child: GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 50,
                            );
                            if (img != null)
                              setModalState(() => pickedImage = img);
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
                                      image: FileImage(File(pickedImage!.path)),
                                      fit: BoxFit.cover,
                                    )
                                  : (currentImageUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(
                                              currentImageUrl!,
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : null),
                            ),
                            child:
                                (pickedImage == null && currentImageUrl == null)
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

                      _buildField(
                        'Variant Name',
                        nameController,
                        Icons.label_important_rounded,
                        isDark,
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _buildField(
                              'Base Rate',
                              rateController,
                              Icons.currency_rupee_rounded,
                              isDark,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildField(
                              'Inclusive Rate',
                              inclusiveRateController,
                              Icons.payments_rounded,
                              isDark,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // HSN Dropdown
                      DropdownButtonFormField<String>(
                        value: selectedHsnId,
                        items: _hsns
                            .map(
                              (h) => DropdownMenuItem(
                                value: h['id'] as String,
                                child: Text(
                                  '${h['hsn_code']} - ${h['description']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setModalState(() => selectedHsnId = v),
                        decoration: _inputDecoration(
                          'HSN Code',
                          Icons.receipt_long_rounded,
                          isDark,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildField(
                        'Description',
                        descController,
                        Icons.description_rounded,
                        isDark,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      _buildField(
                        'Display Order',
                        orderController,
                        Icons.sort_rounded,
                        isDark,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 24),

                      _buildToggle(
                        'Is Rate Inclusive',
                        isRateInclusive,
                        (v) => setModalState(() => isRateInclusive = v),
                        isDark,
                      ),
                      _buildToggle(
                        'Is Available',
                        isAvailable,
                        (v) => setModalState(() => isAvailable = v),
                        isDark,
                      ),
                      _buildToggle(
                        'Is Active',
                        isActive,
                        (v) => setModalState(() => isActive = v),
                        isDark,
                      ),

                      const SizedBox(height: 32),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          final id = variant?.id ?? const Uuid().v4();
                          String? finalImageUrl = currentImageUrl;

                          if (pickedImage != null) {
                            final bytes = await pickedImage!.readAsBytes();
                            final ext = pickedImage!.name.split('.').last;
                            finalImageUrl =
                                await SupabaseService.uploadItemImage(
                                  id,
                                  bytes,
                                  ext,
                                );
                          }

                          final data = {
                            'id': id,
                            'item_id': _selectedMasterId,
                            'variant_name': nameController.text,
                            'base_rate':
                                double.tryParse(rateController.text) ?? 0,
                            'inclusive_rate':
                                double.tryParse(inclusiveRateController.text) ??
                                0,
                            'is_rate_inclusive': isRateInclusive,
                            'hsn_id': selectedHsnId,
                            'description': descController.text,
                            'display_order':
                                int.tryParse(orderController.text) ?? 0,
                            'is_available': isAvailable,
                            'is_active': isActive,
                          };

                          await SupabaseService.upsertVariant(data);
                          await _loadVariants();
                          if (context.mounted) Navigator.pop(context);
                          ref.invalidate(
                            itemGroupsProvider(
                              ref.read(authStateProvider).value!.companyId,
                            ),
                          );
                          ref.invalidate(
                            allItemsProvider(
                              ref.read(authStateProvider).value!.companyId,
                            ),
                          );
                        },
                        child: const Text('SAVE VARIANT'),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Text(
          'Variant Manager',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_selectedMasterId != null)
            IconButton(
              onPressed: _addOrEditVariant,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          // Master Item Selector
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            child: DropdownButtonFormField<String>(
              value: _selectedMasterId,
              items: _masterItems
                  .map(
                    (m) => DropdownMenuItem(
                      value: m['id'] as String,
                      child: Text(
                        '${m['item_name']} (${m['item_code'] ?? 'N/A'})',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedMasterId = v);
                _loadVariants();
              },
              decoration: _inputDecoration(
                'Select Master Item',
                Icons.inventory_2_rounded,
                isDark,
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedMasterId == null
                ? _buildSelectPrompt(isDark)
                : _variants.isEmpty
                ? _buildEmptyState(isDark)
                : _buildVariantList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectPrompt(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 64,
            color: Colors.grey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Select an item to manage its variants',
            style: GoogleFonts.inter(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.layers_clear_rounded,
            size: 64,
            color: Colors.grey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No variants for this item',
            style: GoogleFonts.inter(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addOrEditVariant,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add First Variant'),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _variants.length,
      itemBuilder: (context, index) {
        final v = _variants[index];
        final hsn = _hsns.firstWhere(
          (h) => h['id'] == v.hsnId,
          orElse: () => {},
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg : AppColors.lightBg,
                borderRadius: BorderRadius.circular(10),
                image: v.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(v.imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: v.imageUrl == null
                  ? const Icon(Icons.image_outlined, size: 20)
                  : null,
            ),
            title: Text(
              v.variantName,
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${v.baseRate.toStringAsFixed(0)}${v.isRateInclusive ? ' (Inc)' : ''}',
                  style: GoogleFonts.inter(color: AppColors.primaryAmber),
                ),
                if (hsn.isNotEmpty)
                  Text(
                    'HSN: ${hsn['hsn_code']}',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  onPressed: () => _addOrEditVariant(v),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                  onPressed: () => _deleteVariant(v.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isDark, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _inputDecoration(label, icon, isDark),
      style: GoogleFonts.inter(fontSize: 14),
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
      activeColor: AppColors.primaryAmber,
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

  Future<void> _deleteVariant(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Variant?'),
        content: const Text('This action cannot be undone.'),
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
      await SupabaseService.deleteVariant(id);
      await _loadVariants();
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        ref.invalidate(itemGroupsProvider(user.companyId));
        ref.invalidate(allItemsProvider(user.companyId));
      }
    }
  }
}
