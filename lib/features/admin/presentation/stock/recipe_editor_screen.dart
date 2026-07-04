import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/api_helper.dart';
import '../../../../core/widgets/network_error_view.dart';
import '../../../../models/inventory_models.dart';
import '../../../../providers/providers.dart';
import '../../../../providers/inventory_providers.dart';

/// BOM (Bill of Materials) editor for a single item variant. Lists the recipe
/// lines (raw material + qty per unit sold) and lets the user add / edit /
/// remove them. Reached from the Item Variant screen via a push route.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({
    super.key,
    required this.itemVariantId,
    required this.variantName,
  });

  final String itemVariantId;
  final String variantName;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  String? _addMaterialId;
  final _qtyController = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    AppFeedback.toast(context, msg, isError: color == AppColors.error);
  }

  Future<void> _refresh() async {
    ref.invalidate(variantRecipeProvider(widget.itemVariantId));
    await ref.read(variantRecipeProvider(widget.itemVariantId).future);
  }

  Future<void> _addLine() async {
    final qty = double.tryParse(_qtyController.text.trim()) ?? 0;
    if (_addMaterialId == null) {
      _snack('Pick a raw material', AppColors.warning);
      return;
    }
    if (qty <= 0) {
      _snack('Quantity must be greater than 0', AppColors.warning);
      return;
    }
    setState(() => _adding = true);
    try {
      final line = VariantRecipe(
        id: const Uuid().v4(),
        itemVariantId: widget.itemVariantId,
        rawMaterialId: _addMaterialId!,
        qtyPerUnit: qty,
      );
      await SupabaseService.upsertRecipeLine(line.toJson());
      _qtyController.clear();
      setState(() => _addMaterialId = null);
      await _refresh();
      _snack('Ingredient added', AppColors.success);
    } catch (e) {
      _snack('Error: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _updateQty(VariantRecipe line, double qty) async {
    try {
      await SupabaseService.upsertRecipeLine(
        VariantRecipe(
          id: line.id,
          itemVariantId: line.itemVariantId,
          rawMaterialId: line.rawMaterialId,
          qtyPerUnit: qty,
        ).toJson(),
      );
      await _refresh();
      _snack('Quantity updated', AppColors.success);
    } catch (e) {
      _snack('Error: $e', AppColors.error);
    }
  }

  Future<void> _deleteLine(VariantRecipe line) async {
    try {
      await SupabaseService.deleteRecipeLine(line.id);
      await _refresh();
    } catch (e) {
      _snack('Error: $e', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const SizedBox.shrink();

    final recipeAsync = ref.watch(variantRecipeProvider(widget.itemVariantId));
    final materialsAsync = ref.watch(rawMaterialsProvider(user.companyId));
    final materials = materialsAsync.value ?? const <RawMaterial>[];
    final matById = {for (final m in materials) m.id: m};

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Text(
          'Recipe — ${widget.variantName}',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          overflow: TextOverflow.ellipsis,
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
      body: Column(
        children: [
          Expanded(
            child: recipeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => NetworkErrorView(
                error: e,
                onRetry: () =>
                    ref.invalidate(variantRecipeProvider(widget.itemVariantId)),
              ),
              data: (lines) {
                if (lines.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 56,
                          color: AppColors.primaryAmber.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No ingredients yet',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add ingredients below to build the recipe.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textDarkMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final line = lines[i];
                    final mat = matById[line.rawMaterialId];
                    return _RecipeLineTile(
                      key: ValueKey(line.id),
                      isDark: isDark,
                      materialName: mat?.name ?? 'Unknown material',
                      unit: mat?.unit ?? '',
                      qty: line.qtyPerUnit,
                      onSave: (q) => _updateQty(line, q),
                      onDelete: () => _deleteLine(line),
                    );
                  },
                );
              },
            ),
          ),
          _buildAddBar(isDark, materials, matById),
        ],
      ),
    );
  }

  Widget _buildAddBar(
    bool isDark,
    List<RawMaterial> materials,
    Map<String, RawMaterial> matById,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _addMaterialId,
              hint: const Text('Raw material'),
              items: materials
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        '${m.name} (${m.unit})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _addMaterialId = v),
              decoration: _dec(isDark),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _qtyController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
              ],
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _dec(
                isDark,
                label: 'Qty/unit',
                suffix: _addMaterialId != null
                    ? matById[_addMaterialId]?.unit
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _adding ? null : _addLine,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(bool isDark, {String? label, String? suffix}) =>
      InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? AppColors.darkElevated : AppColors.lightElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );
}

/// One recipe line with an inline editable quantity. Holds its own controller;
/// shows a save tick only while the value differs from what's saved.
class _RecipeLineTile extends StatefulWidget {
  const _RecipeLineTile({
    super.key,
    required this.isDark,
    required this.materialName,
    required this.unit,
    required this.qty,
    required this.onSave,
    required this.onDelete,
  });

  final bool isDark;
  final String materialName;
  final String unit;
  final double qty;
  final ValueChanged<double> onSave;
  final VoidCallback onDelete;

  @override
  State<_RecipeLineTile> createState() => _RecipeLineTileState();
}

class _RecipeLineTileState extends State<_RecipeLineTile> {
  late final TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.qty));
  }

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

  @override
  void didUpdateWidget(covariant _RecipeLineTile old) {
    super.didUpdateWidget(old);
    // Sync the field when the saved value changes from outside and the user
    // hasn't got pending edits.
    if (!_dirty && old.qty != widget.qty) {
      _controller.text = _fmt(widget.qty);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final q = double.tryParse(_controller.text.trim()) ?? 0;
    if (q <= 0) return;
    setState(() => _dirty = false);
    widget.onSave(q);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.materialName,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 88,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
              ],
              onChanged: (_) => setState(() => _dirty = true),
              onSubmitted: (_) => _save(),
              style: GoogleFonts.inter(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                suffixText: widget.unit,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _dirty ? Icons.check_circle_rounded : Icons.check_circle_outline,
              size: 20,
              color: _dirty ? AppColors.success : Colors.grey,
            ),
            onPressed: _dirty ? _save : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppColors.error,
            ),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
