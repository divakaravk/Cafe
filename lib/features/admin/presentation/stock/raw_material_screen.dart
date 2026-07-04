import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/api_helper.dart';
import '../../../../models/inventory_models.dart';
import '../../../../providers/providers.dart';
import '../../../../providers/inventory_providers.dart';

/// Raw materials list + add/edit. Mirrors the Item Group admin screen:
/// gradient app bar, card list, FAB, and a soft-delete flow. Add/edit uses a
/// modal bottom sheet (allowed by the spec) for a lighter form.
class RawMaterialScreen extends ConsumerStatefulWidget {
  const RawMaterialScreen({super.key});

  @override
  ConsumerState<RawMaterialScreen> createState() => _RawMaterialScreenState();
}

class _RawMaterialScreenState extends ConsumerState<RawMaterialScreen> {
  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    AppFeedback.toast(context, msg, isError: color == AppColors.error);
  }

  Future<void> _refresh(String companyId) async {
    ref.invalidate(rawMaterialsProvider(companyId));
    ref.invalidate(currentStockProvider(companyId));
    await ref.read(rawMaterialsProvider(companyId).future);
  }

  Future<void> _openEditor(String companyId, {RawMaterial? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _RawMaterialEditorSheet(companyId: companyId, existing: existing),
    );
    if (saved == true) {
      await _refresh(companyId);
      _showSnack('Material saved', AppColors.success);
    }
  }

  Future<void> _confirmDelete(RawMaterial m) async {
    // Warn if the material is still referenced by recipes.
    int usage = 0;
    try {
      usage = await SupabaseService.countRecipeLinesUsingMaterial(m.id);
    } catch (_) {}
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deactivate "${m.name}"?'),
        content: Text(
          usage > 0
              ? 'This material is used in $usage recipe line${usage == 1 ? '' : 's'}. '
                    'Deactivating will hide it from new recipes but won\'t affect '
                    'existing KOTs or historical data.'
              : 'Deactivating hides it from the active materials list. '
                    'Historical stock data is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Deactivate',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await SupabaseService.deleteRawMaterial(m.id);
      await _refresh(m.companyId);
      _showSnack('Material deactivated', AppColors.success);
    } catch (e) {
      _showSnack('Error: $e', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const SizedBox.shrink();
    final companyId = user.companyId;

    final materialsAsync = ref.watch(rawMaterialsProvider(companyId));
    final stockAsync = ref.watch(currentStockProvider(companyId));
    // Map current stock by material id for quick lookup.
    final stockById = <String, CurrentStockRow>{
      for (final r in stockAsync.value ?? const <CurrentStockRow>[]) r.id: r,
    };

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: _gradientAppBar('Raw Materials'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(companyId),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Material',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: materialsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(rawMaterialsProvider(companyId)),
        ),
        data: (materials) {
          if (materials.isEmpty) {
            return _EmptyState(onAdd: () => _openEditor(companyId));
          }
          return RefreshIndicator(
            onRefresh: () => _refresh(companyId),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: materials.length,
              itemBuilder: (context, i) {
                final m = materials[i];
                final stock = stockById[m.id];
                return _MaterialCard(
                  material: m,
                  current: stock?.currentStock,
                  isLow: stock?.isLowStock ?? false,
                  isDark: isDark,
                  onTap: () => _openEditor(companyId, existing: m),
                  onDelete: () => _confirmDelete(m),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─── MATERIAL CARD ───────────────────────────────────────
class _MaterialCard extends StatelessWidget {
  const _MaterialCard({
    required this.material,
    required this.current,
    required this.isLow,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  final RawMaterial material;
  final double? current;
  final bool isLow;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(material.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // we handle the soft delete + refresh ourselves
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
      ),
      child: Container(
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
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.science_outlined,
                    color: AppColors.primaryAmber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              material.name,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isLow) ...[
                            const SizedBox(width: 6),
                            _pill('Low', AppColors.error),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Current: ${_fmt(current)} ${material.unit}  •  '
                        'Reorder: ${_fmt(material.reorderLevel)}  •  '
                        '₹${_fmt(material.costPerUnit)}/${material.unit}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: isDark
                              ? AppColors.textWhiteMuted
                              : AppColors.textDarkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(double? v) {
    if (v == null) return '—';
    return v.truncateToDouble() == v
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
  }

  static Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
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

// ─── ADD / EDIT BOTTOM SHEET ─────────────────────────────
class _RawMaterialEditorSheet extends ConsumerStatefulWidget {
  const _RawMaterialEditorSheet({required this.companyId, this.existing});

  final String companyId;
  final RawMaterial? existing;

  @override
  ConsumerState<_RawMaterialEditorSheet> createState() =>
      _RawMaterialEditorSheetState();
}

class _RawMaterialEditorSheetState
    extends ConsumerState<_RawMaterialEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _opening;
  late final TextEditingController _reorder;
  late final TextEditingController _cost;
  late String _unit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _opening = TextEditingController(text: e == null ? '' : _n(e.openingStock));
    _reorder = TextEditingController(text: e == null ? '' : _n(e.reorderLevel));
    _cost = TextEditingController(text: e == null ? '' : _n(e.costPerUnit));
    _unit = e?.unit ?? kUnits.first;
  }

  static String _n(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _reorder.dispose();
    _cost.dispose();
    super.dispose();
  }

  String? _validateName(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Name is required' : null;

  String? _validateNonNeg(String? v) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return 'Required';
    final parsed = double.tryParse(raw);
    if (parsed == null) return 'Enter a number';
    if (parsed < 0) return 'Must be ≥ 0';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = widget.existing?.id ?? const Uuid().v4();
      final material = RawMaterial(
        id: id,
        companyId: widget.companyId,
        name: _name.text.trim(),
        unit: _unit,
        openingStock: double.tryParse(_opening.text.trim()) ?? 0,
        reorderLevel: double.tryParse(_reorder.text.trim()) ?? 0,
        costPerUnit: double.tryParse(_cost.text.trim()) ?? 0,
        isActive: widget.existing?.isActive ?? true,
      );
      await SupabaseService.upsertRawMaterial(material.toJson());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) AppFeedback.toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing == null ? 'New Material' : 'Edit Material',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateName,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _dec('Name', Icons.label_outline_rounded, isDark),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                items: kUnits
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) => setState(() => _unit = v ?? _unit),
                decoration: _dec('Unit', Icons.straighten_rounded, isDark),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _opening,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateNonNeg,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _dec(
                  'Opening stock',
                  Icons.inventory_2_outlined,
                  isDark,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reorder,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateNonNeg,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _dec(
                  'Reorder level',
                  Icons.notifications_active_outlined,
                  isDark,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateNonNeg,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _dec(
                  'Cost per unit ₹',
                  Icons.currency_rupee_rounded,
                  isDark,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon, bool isDark) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isDark ? AppColors.darkElevated : AppColors.lightElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

// ─── SHARED SMALL WIDGETS ────────────────────────────────
PreferredSizeWidget _gradientAppBar(String title) => AppBar(
  title: Text(
    title,
    style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white),
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
);

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.science_outlined,
            size: 64,
            color: AppColors.primaryAmber.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No raw materials yet',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: onAdd, child: const Text('Add First Material')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
