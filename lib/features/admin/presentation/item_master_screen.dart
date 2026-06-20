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
import '../../admin/presentation/item_variant_screen.dart';

/// Item Group management.
///
/// This screen manages ONLY Item Groups (e.g. "Dosa", "Idly", "Rice"). The
/// actual selling items live under each group as variants and are managed in
/// [ItemVariantScreen]. Groups are never sold directly.
class ItemMasterScreen extends ConsumerStatefulWidget {
  const ItemMasterScreen({super.key});

  @override
  ConsumerState<ItemMasterScreen> createState() => _ItemMasterScreenState();
}

class _ItemMasterScreenState extends ConsumerState<ItemMasterScreen> {
  bool _isLoading = false;
  List<Item> _items = [];
  List<Map<String, dynamic>> _hsns = [];
  bool _isEditing = false;

  // List search
  final _searchController = TextEditingController();
  String _searchQuery = '';

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
  String? _selectedHsnId;
  XFile? _pickedImage;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descController.dispose();
    _rateController.dispose();
    _orderController.dispose();
    _sectionController.dispose();
    _colorTagController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        final results = await Future.wait([
          SupabaseService.getItemGroups(user.companyId),
          SupabaseService.getCompanyHsns(user.companyId),
        ]);
        setState(() {
          _items = (results[0])
              .map((e) => Item.fromJson(e))
              .toList()
            ..sort((a, b) {
              final byOrder = a.displayOrder.compareTo(b.displayOrder);
              return byOrder != 0
                  ? byOrder
                  : a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
            });
          _hsns = results[1];
        });
      }
    } catch (e) {
      _showSnackBar('Error loading data: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      _rateController.text = item.baseRate.toStringAsFixed(
        item.baseRate.truncateToDouble() == item.baseRate ? 0 : 2,
      );
      _orderController.text = item.displayOrder.toString();
      _sectionController.text = item.sectionLabel ?? '';
      _colorTagController.text = item.colorTag ?? '';
      _isActive = item.isActive;
      _isTaxable = item.isTaxable;
      _selectedHsnId = item.hsnId;
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
    _selectedHsnId = null;
    _imageUrl = null;
    _pickedImage = null;
  }

  // ─── VALIDATION ─────────────────────────────────────────
  String? _validateName(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Item Group name is required' : null;

  String? _validateCode(String? v) {
    final code = (v ?? '').trim();
    if (code.isEmpty) return 'Item code is required';
    final duplicate = _items.any(
      (i) =>
          i.id != _selectedItem?.id &&
          i.itemCode.trim().toLowerCase() == code.toLowerCase(),
    );
    return duplicate ? 'This code is already used by another group' : null;
  }

  String? _validateRate(String? v) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return 'Base rate is required';
    final parsed = double.tryParse(raw);
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Base rate must be ≥ 0';
    return null;
  }

  String? _validateOrder(String? v) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 0) return 'Display order must be ≥ 0';
    return null;
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
    if (_isLoading) return; // guard against double-taps
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

      final baseRate = double.tryParse(_rateController.text.trim()) ?? 0;

      final itemData = {
        'id': id,
        'company_id': user.companyId,
        'item_code': _codeController.text.trim(),
        'item_name': _nameController.text.trim(),
        'description':
            _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        'base_rate': baseRate,
        // A group is a container of selling items.
        'has_variants': true,
        'is_taxable': _isTaxable,
        'is_active': _isActive,
        'display_order': int.tryParse(_orderController.text.trim()) ?? 0,
        'image_url': currentImageUrl,
        'section_label':
            _sectionController.text.trim().isEmpty ? null : _sectionController.text.trim(),
        'color_tag':
            _colorTagController.text.trim().isEmpty ? null : _colorTagController.text.trim(),
        'hsn_id': _selectedHsnId,
        'updated_by': user.id,
      };

      await SupabaseService.client.from('item_master').upsert(itemData);

      // Every group needs at least one sellable item. For a brand-new group
      // create an inheriting "Default" selling item so it is immediately
      // usable in the POS (base_rate 0 ⇒ inherits the group rate).
      if (_selectedItem == null) {
        final variantId = const Uuid().v4();
        await SupabaseService.upsertVariant({
          'id': variantId,
          'item_id': id,
          'variant_name': 'Default',
          'base_rate': 0,
          'is_active': true,
          'is_available': true,
          'is_default': true,
          'display_order': 0,
        });
        await SupabaseService.client
            .from('item_master')
            .update({'default_variant_id': variantId}).eq('id', id);
      }

      _showSnackBar('Item Group saved', AppColors.success);
      ref.invalidate(itemGroupsProvider(user.companyId));
      ref.invalidate(allItemsProvider(user.companyId));
      ref.invalidate(variantsByGroupProvider(id));
      setState(() => _isEditing = false);
      _loadData();
    } catch (e) {
      debugPrint('Error saving item group: $e');
      _showSnackBar('Error saving: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDelete(Item item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item Group?'),
        content: Text(
          'Delete "${item.itemName}" and all of its selling items? '
          'This cannot be undone.',
        ),
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
    if (confirm != true) return;
    try {
      await SupabaseService.deleteItemMaster(item.id);
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        ref.invalidate(itemGroupsProvider(user.companyId));
        ref.invalidate(allItemsProvider(user.companyId));
      }
      _showSnackBar('Item Group deleted', AppColors.success);
      _loadData();
    } catch (e) {
      _showSnackBar('Error deleting: $e', AppColors.error);
    }
  }

  void _openVariants(Item group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemVariantScreen(item: group),
      ),
    ).then((_) {
      // Refresh after returning so variant counts / default stay in sync.
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        ref.invalidate(itemGroupsProvider(user.companyId));
        ref.invalidate(variantsByGroupProvider(group.id));
      }
      _loadData();
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
          _isEditing
              ? (_selectedItem == null ? 'New Item Group' : 'Edit Item Group')
              : 'Item Group',
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
        leading: _isEditing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
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
                    onPressed: _save,
                  ),
        ],
      ),
      floatingActionButton: _isEditing
          ? null
          : FloatingActionButton.extended(
              onPressed: _startCreateItem,
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Add Group',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
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
              color: AppColors.primaryAmber.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No item groups yet',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _startCreateItem,
              child: const Text('Add First Group'),
            ),
          ],
        ),
      );
    }

    final q = _searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _items
        : _items.where((i) {
            return i.itemName.toLowerCase().contains(q) ||
                i.itemCode.toLowerCase().contains(q) ||
                (i.sectionLabel ?? '').toLowerCase().contains(q);
          }).toList();

    return Column(
      children: [
        _buildSearchBar(isDark, 'Search groups by name, code, section…'),
        Expanded(
          child: filtered.isEmpty
              ? _buildNoResults(isDark)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
          final sellableCount = item.sellableVariants.length;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _startEditItem(item),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    _buildImagePreview(item.imageUrl, 21),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.itemName,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!item.isActive) ...[
                                const SizedBox(width: 6),
                                _statusPill('Inactive', AppColors.error),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                '₹${item.baseRate.toStringAsFixed(0)}',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.sectionLabel ?? 'No Section',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  color: isDark
                                      ? AppColors.textWhiteMuted
                                      : AppColors.textDarkMuted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentTeal.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '$sellableCount item${sellableCount == 1 ? '' : 's'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accentTeal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      tooltip: 'Manage Selling Items',
                      icon: const Icon(
                        Icons.layers_rounded,
                        size: 19,
                        color: AppColors.primaryAmber,
                      ),
                      onPressed: () => _openVariants(item),
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
                      onPressed: () => _confirmDelete(item),
                    ),
                  ],
                ),
              ),
            ),
          );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isDark, String hint) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.inter(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
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

  Widget _buildNoResults(bool isDark) {
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

  Widget _buildEditor(bool isDark, UserProfile user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImagePickerSection(),
              const SizedBox(height: 32),
              _buildTextField(
                controller: _nameController,
                label: 'Item Group Name',
                icon: Icons.title_rounded,
                isDark: isDark,
                validator: _validateName,
              ),
              const SizedBox(height: 16),
              _buildResponsiveRow(
                isDark,
                _buildTextField(
                  controller: _codeController,
                  label: 'Item Code',
                  icon: Icons.qr_code_rounded,
                  isDark: isDark,
                  validator: _validateCode,
                ),
                _buildTextField(
                  controller: _rateController,
                  label: 'Base Rate (₹)',
                  icon: Icons.currency_rupee_rounded,
                  isDark: isDark,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  validator: _validateRate,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _selectedHsnId,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No HSN / Tax'),
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
                onChanged: (v) => setState(() => _selectedHsnId = v),
                decoration: _inputDecoration(
                  'Default HSN / GST (variants inherit)',
                  Icons.receipt_long_rounded,
                  isDark,
                ),
              ),
              const SizedBox(height: 16),
              _buildResponsiveRow(
                isDark,
                _buildTextField(
                  controller: _sectionController,
                  label: 'Section / Category',
                  icon: Icons.category_rounded,
                  isDark: isDark,
                ),
                _buildTextField(
                  controller: _orderController,
                  label: 'Display Order',
                  icon: Icons.sort_rounded,
                  isDark: isDark,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: _validateOrder,
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _colorTagController,
                label: 'Color Tag (hex, optional)',
                icon: Icons.color_lens_rounded,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _descController,
                label: 'Description',
                icon: Icons.description_outlined,
                isDark: isDark,
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              _buildToggle(
                'Active',
                'Visible in POS',
                _isActive,
                (v) => setState(() => _isActive = v),
              ),
              _buildToggle(
                'Taxable',
                'Apply GST / Taxes',
                _isTaxable,
                (v) => setState(() => _isTaxable = v),
              ),
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _selectedItem == null
                          ? null
                          : () => _openVariants(_selectedItem!),
                      icon: const Icon(Icons.layers_rounded),
                      label: const Text('MANAGE SELLING ITEMS'),
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
                    if (_selectedItem == null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'Save the group first to add selling items',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// Two fields side-by-side on wide screens, stacked on narrow ones.
  Widget _buildResponsiveRow(bool isDark, Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
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
              color: AppColors.primaryAmber.withValues(alpha: 0.1),
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
        color: AppColors.primaryAmber.withValues(alpha: 0.1),
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
      activeThumbColor: AppColors.primaryAmber,
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
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      inputFormatters: inputFormatters,
      autovalidateMode: AutovalidateMode.onUserInteraction,
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
