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
import '../../admin/presentation/item_variant_screen.dart';

class ItemMasterScreen extends ConsumerStatefulWidget {
  const ItemMasterScreen({super.key});

  @override
  ConsumerState<ItemMasterScreen> createState() => _ItemMasterScreenState();
}

class _ItemMasterScreenState extends ConsumerState<ItemMasterScreen> {
  bool _isLoading = false;
  List<Item> _items = [];
  bool _isEditing = false;

  // Editor State
  Item? _selectedItem;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _descController = TextEditingController();
  final _rateController = TextEditingController();
  final _orderController = TextEditingController();
  final _sectionController = TextEditingController();
  final _colorTagController = TextEditingController();

  bool _isActive = true;
  bool _isTaxable = true;
  bool _hasVariants = false;
  String _foodType = 'veg';
  XFile? _pickedImage;
  String? _imageUrl;
  List<ItemVariant> _variants = [];

  // Metadata for dropdowns
  final List<String> _foodTypes = ['veg', 'egg', 'non-veg'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        final company = await ref.read(companyProvider(user.companyId).future);
        final itemsData = await SupabaseService.getAllItems(user.companyId);
        setState(() {
          _items = itemsData.map((e) => Item.fromJson(e)).toList();
          if (company != null && !company.hasItemVariants) {
            _hasVariants = false;
          }
        });
      }
    } catch (e) {
      _showSnackBar('Error loading data: $e', AppColors.error);
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

  void _startCreateItem() {
    setState(() {
      _isEditing = true;
      _selectedItem = null;
      _clearForm();
    });
  }

  void _startEditItem(Item item) {
    setState(() {
      _isEditing = true;
      _selectedItem = item;
      _nameController.text = item.itemName;
      _codeController.text = item.itemCode;
      _descController.text = item.description ?? '';
      _rateController.text = item.baseRate.toString();
      _orderController.text = item.displayOrder.toString();
      _sectionController.text = item.sectionLabel ?? '';
      _colorTagController.text = item.colorTag ?? '';
      _isActive = item.isActive;
      _isTaxable = item.isTaxable;
      _hasVariants = item.hasVariants;
      _foodType = item.foodType;
      _variants = List.from(item.variants);
      _imageUrl = item.imageUrl;
      _pickedImage = null;
    });
  }

  void _clearForm() {
    _nameController.clear();
    _codeController.clear();
    _descController.clear();
    _rateController.clear();
    _orderController.text = '0';
    _sectionController.clear();
    _colorTagController.clear();
    _isActive = true;
    _isTaxable = true;
    _hasVariants = false;
    _foodType = 'veg';
    _variants = [];
    _imageUrl = null;
    _pickedImage = null;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (image != null) setState(() => _pickedImage = image);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = ref.read(authStateProvider).value!;
      final id = _selectedItem?.id ?? const Uuid().v4();

      String? currentImageUrl = _imageUrl;
      if (_pickedImage != null) {
        final bytes = await _pickedImage!.readAsBytes();
        final ext = _pickedImage!.name.split('.').last;
        currentImageUrl = await SupabaseService.uploadItemImage(id, bytes, ext);
      }

      final companyAsync = ref.read(companyProvider(user.companyId));
      final hasCompanyVariants = companyAsync.value?.hasItemVariants ?? false;

      final itemData = {
        'id': id,
        'company_id': user.companyId,
        'item_code': _codeController.text,
        'item_name': _nameController.text,
        'description': _descController.text,
        'base_rate': double.tryParse(_rateController.text) ?? 0,
        'has_variants':
            hasCompanyVariants, // Always true if company supports it
        'is_taxable': _isTaxable,
        'is_active': _isActive,
        'display_order': int.tryParse(_orderController.text) ?? 0,
        'image_url': currentImageUrl,
        'section_label': _sectionController.text.isEmpty
            ? null
            : _sectionController.text,
        'color_tag': _colorTagController.text.isEmpty
            ? null
            : _colorTagController.text,
        'food_type': _foodType,
      };

      if (!hasCompanyVariants) {
        // FLAT MODE: Manage one default variant matching master
        final variantData = {
          'id': _selectedItem?.variants.isNotEmpty == true
              ? _selectedItem!.variants.first.id
              : const Uuid().v4(),
          'item_id': id,
          'variant_name': 'Default',
          'base_rate': double.tryParse(_rateController.text) ?? 0,
          'is_active': _isActive,
          'is_available': _isActive,
        };
        await SupabaseService.saveItemWithVariants(
          itemData: itemData,
          variants: [variantData],
        );
      } else {
        // MASTER MODE: Only save the master info. Variants are managed separately.
        await SupabaseService.client.from('item_master').upsert(itemData);

        // If it's a NEW item, we might want to create a default variant so it's usable in POS
        if (_selectedItem == null) {
          final defaultVariant = {
            'id': const Uuid().v4(),
            'item_id': id,
            'variant_name': 'Default',
            'base_rate': double.tryParse(_rateController.text) ?? 0,
            'is_active': true,
            'is_available': true,
          };
          await SupabaseService.upsertVariant(defaultVariant);
        }
      }

      _showSnackBar('Saved successfully', AppColors.success);
      ref.invalidate(itemGroupsProvider(user.companyId));
      ref.invalidate(allItemsProvider(user.companyId));
      setState(() => _isEditing = false);
      _loadData();
    } catch (e) {
      debugPrint('Error saving: $e');
      _showSnackBar('Error saving: $e', AppColors.error);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addVariant() {
    setState(() {
      _variants.add(
        ItemVariant(
          id: const Uuid().v4(),
          itemId: _selectedItem?.id ?? '',
          variantName: '',
          baseRate: 0,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).value;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Item Details' : 'Item Master',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        leading: _isEditing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _isEditing = false),
              )
            : null,
        actions: [
          if (_isEditing)
            IconButton(icon: const Icon(Icons.check_rounded), onPressed: _save)
          else
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: _startCreateItem,
            ),
        ],
      ),
      body: _isLoading && !_isEditing
          ? const Center(child: CircularProgressIndicator())
          : _isEditing
          ? _buildEditor(isDark, user)
          : _buildItemList(isDark, user),
    );
  }

  Widget _buildItemList(bool isDark, UserProfile user) {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: AppColors.primaryAmber.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No items found',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _startCreateItem,
              child: const Text('Add First Item'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
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
            leading: _buildImagePreview(item.imageUrl, 24),
            title: Row(
              children: [
                _buildFoodTypeDot(item.foodType),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.itemName,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${item.sectionLabel ?? 'No Category'} • ₹${item.baseRate}',
              style: GoogleFonts.inter(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.hasVariants) ...[
                  if (ref
                          .watch(companyProvider(user.companyId))
                          .value
                          ?.hasItemVariants ??
                      false)
                    IconButton(
                      icon: const Icon(
                        Icons.layers_rounded,
                        color: AppColors.primaryAmber,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ItemVariantScreen(item: item),
                        ),
                      ),
                      tooltip: 'Manage Variants',
                    )
                  else
                    const Icon(
                      Icons.layers_rounded,
                      size: 16,
                      color: AppColors.primaryAmber,
                    ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: () => _startEditItem(item),
                ),
              ],
            ),
            onTap: () => _startEditItem(item),
          ),
        );
      },
    );
  }

  Widget _buildFoodTypeDot(String type) {
    Color color = Colors.green;
    if (type == 'egg') color = Colors.amber;
    if (type == 'non-veg') color = Colors.red;

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildEditor(bool isDark, UserProfile user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImagePickerSection(),
            const SizedBox(height: 32),
            _buildTextField(
              controller: _nameController,
              label: 'Item Name',
              icon: Icons.title_rounded,
              isDark: isDark,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _codeController,
                    label: 'Item Code',
                    icon: Icons.qr_code_rounded,
                    isDark: isDark,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _foodType,
                    items: _foodTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _foodType = v!),
                    decoration: _inputDecoration(
                      'Food Type',
                      Icons.restaurant_menu,
                      isDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _sectionController,
                    label: 'Section/Category',
                    icon: Icons.category_rounded,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 16),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _rateController,
                    label: 'Base Rate',
                    icon: Icons.currency_rupee_rounded,
                    isDark: isDark,
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _descController,
              label: 'Description',
              icon: Icons.description_outlined,
              isDark: isDark,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _orderController,
                    label: 'Display Order',
                    icon: Icons.sort_rounded,
                    isDark: isDark,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _colorTagController,
                    label: 'Color Tag (hex)',
                    icon: Icons.color_lens_rounded,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildToggle(
              'Is Active',
              'Visible in POS',
              _isActive,
              (v) => setState(() => _isActive = v),
            ),
            _buildToggle(
              'Is Taxable',
              'Apply GST/Taxes',
              _isTaxable,
              (v) => setState(() => _isTaxable = v),
            ),

            // Only show Master/Variant toggle if company supports it
            // if enabled at company level, we treat the item as a master and manage variants separately
            if (ref
                    .watch(companyProvider(user.companyId))
                    .value
                    ?.hasItemVariants ??
                false) ...[
              const SizedBox(height: 16),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _selectedItem == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ItemVariantScreen(item: _selectedItem!),
                          ),
                        ),
                  icon: const Icon(Icons.layers_rounded),
                  label: const Text('MANAGE VARIANTS'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (_selectedItem == null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text(
                      'Save item first to manage variants',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
            ] else ...[
              _buildToggle(
                'Has Variants',
                'Multiple sizes/types',
                _hasVariants,
                (v) => setState(() => _hasVariants = v),
              ),

              if (_hasVariants) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Variants',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addVariant,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Variant'),
                    ),
                  ],
                ),
                ..._buildVariantList(isDark),
              ],
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerSection() {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.primaryAmber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              image: _pickedImage != null
                  ? DecorationImage(
                      image: FileImage(File(_pickedImage!.path)),
                      fit: BoxFit.cover,
                    )
                  : (_imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null),
            ),
            child: (_pickedImage == null && _imageUrl == null)
                ? const Icon(
                    Icons.image_outlined,
                    size: 40,
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
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primaryAmber,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String? url, double radius) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: AppColors.primaryAmber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        image: url != null
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: url == null
          ? const Icon(
              Icons.fastfood_outlined,
              size: 18,
              color: AppColors.primaryAmber,
            )
          : null,
    );
  }

  List<Widget> _buildVariantList(bool isDark) {
    return _variants.asMap().entries.map((entry) {
      final index = entry.key;
      final variant = entry.value;
      return Card(
        margin: const EdgeInsets.only(top: 12),
        color: isDark ? AppColors.darkElevated : AppColors.lightElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: variant.variantName,
                      onChanged: (v) =>
                          _variants[index] = _updateVariant(variant, name: v),
                      decoration: _inputDecoration(
                        'Variant Name',
                        null,
                        isDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: variant.baseRate.toString(),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _variants[index] = _updateVariant(
                        variant,
                        rate: double.tryParse(v),
                      ),
                      decoration: _inputDecoration('Rate', null, isDark),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.error,
                    ),
                    onPressed: () => setState(() => _variants.removeAt(index)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  ItemVariant _updateVariant(ItemVariant v, {String? name, double? rate}) {
    return ItemVariant(
      id: v.id,
      itemId: v.itemId,
      variantName: name ?? v.variantName,
      baseRate: rate ?? v.baseRate,
      isActive: v.isActive,
      displayOrder: v.displayOrder,
      isAvailable: v.isAvailable,
    );
  }

  Widget _buildToggle(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return SwitchListTile(
      title: Text(
        title,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12)),
      value: value,
      activeColor: AppColors.primaryAmber,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isDark = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 14),
      decoration: _inputDecoration(label, icon, isDark),
    );
  }

  InputDecoration _inputDecoration(String label, IconData? icon, bool isDark) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: isDark ? AppColors.darkElevated : AppColors.lightElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}
