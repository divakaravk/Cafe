import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/api_helper.dart';
import '../../../../models/inventory_models.dart';
import '../../../../models/models.dart';
import '../../../../providers/providers.dart';
import '../../../../providers/inventory_providers.dart';
import 'stock_common.dart';

/// Per-staff, per-shift consumption variance, captured manually (no IoT).
///
/// Start of shift: record the starting stock (cached locally). End of shift:
/// enter the ending stock; the screen computes actual consumption
/// (start − end), compares it to the theoretical consumption (KOT × recipe)
/// for that staff today, and logs the variance as an adjustment.
class ShiftHandoverScreen extends ConsumerStatefulWidget {
  const ShiftHandoverScreen({super.key});

  @override
  ConsumerState<ShiftHandoverScreen> createState() =>
      _ShiftHandoverScreenState();
}

enum _Mode { start, end }

class _ShiftHandoverScreenState extends ConsumerState<ShiftHandoverScreen> {
  _Mode _mode = _Mode.start;
  String? _staffId;
  String _shift = 'morning';
  String? _materialId;

  final _startController = TextEditingController();
  final _endController = TextEditingController();
  bool _busy = false;
  double? _cachedStart; // loaded start-of-shift value in end mode

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  // ── SharedPreferences cache ──
  String get _todayStr {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _prefKey() => 'handover_${_staffId}_${_shift}_$_todayStr';

  Future<void> _saveStart(double value) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey());
    final map = raw != null
        ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
        : <String, dynamic>{};
    map[_materialId!] = value;
    await prefs.setString(_prefKey(), jsonEncode(map));
  }

  Future<double?> _loadStart() async {
    if (_staffId == null || _materialId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey());
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return (map[_materialId] as num?)?.toDouble();
  }

  Future<void> _clearStart() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey());
    if (raw == null) return;
    final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    map.remove(_materialId);
    if (map.isEmpty) {
      await prefs.remove(_prefKey());
    } else {
      await prefs.setString(_prefKey(), jsonEncode(map));
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    AppFeedback.toast(context, msg, isError: color == AppColors.error);
  }

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

  Color _varianceColor(double theoretical, double variance) {
    if (variance == 0) return AppColors.success;
    if (theoretical <= 0) {
      return variance.abs() <= 0 ? AppColors.success : AppColors.warning;
    }
    final pct = variance / theoretical * 100;
    if (pct.abs() <= 5) return AppColors.success;
    if (pct.abs() <= 15) return AppColors.warning;
    return AppColors.error;
  }

  // Filter materials to Milk & Oil for the first cut; fall back to all if none.
  List<RawMaterial> _scopedMaterials(List<RawMaterial> all) {
    final scoped = all
        .where(
          (m) =>
              m.name.toLowerCase().contains('milk') ||
              m.name.toLowerCase().contains('oil'),
        )
        .toList();
    return scoped.isEmpty ? all : scoped;
  }

  Future<void> _onMaterialChanged(String? id) async {
    setState(() => _materialId = id);
    if (_mode == _Mode.end) {
      final s = await _loadStart();
      if (mounted) {
        setState(() {
          _cachedStart = s;
          if (s != null) _startController.text = _fmt(s);
        });
      }
    }
  }

  Future<void> _saveStartOfShift(List<CurrentStockRow> stock) async {
    if (_staffId == null || _materialId == null) {
      _snack('Pick staff and material', AppColors.warning);
      return;
    }
    final start = double.tryParse(_startController.text.trim());
    if (start == null) {
      _snack('Enter the starting stock', AppColors.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await _saveStart(start);
      _snack('Start of shift recorded', AppColors.success);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEndOfShift(double theoretical) async {
    if (_staffId == null || _materialId == null) {
      _snack('Pick staff and material', AppColors.warning);
      return;
    }
    final start = double.tryParse(_startController.text.trim());
    final end = double.tryParse(_endController.text.trim());
    if (start == null || end == null) {
      _snack('Enter both starting and ending stock', AppColors.warning);
      return;
    }
    final actualConsumption = start - end;
    setState(() => _busy = true);
    final user = ref.read(authStateProvider).value!;
    try {
      await SupabaseService.submitStockAdjustment(
        companyId: user.companyId,
        rawMaterialId: _materialId!,
        qty: -actualConsumption, // negative: consumption
        movementType: 'adjustment',
        note: 'shift handover',
        shiftLabel: _shift,
        staffId: _staffId,
      );
      await _clearStart();
      ref.invalidate(currentStockProvider(user.companyId));
      if (mounted) {
        final variance = actualConsumption - theoretical;
        _snack(
          'Handover logged • actual ${_fmt(actualConsumption)}, '
          'variance ${variance >= 0 ? '+' : ''}${_fmt(variance)}',
          AppColors.success,
        );
        setState(() {
          _endController.clear();
          _startController.clear();
          _cachedStart = null;
        });
      }
    } catch (e) {
      _snack('Error: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const SizedBox.shrink();

    final usersAsync = ref.watch(companyUsersProvider(user.companyId));
    final materialsAsync = ref.watch(rawMaterialsProvider(user.companyId));
    final stockAsync = ref.watch(currentStockProvider(user.companyId));

    final users = usersAsync.value ?? const <UserProfile>[];
    final materials = _scopedMaterials(
      materialsAsync.value ?? const <RawMaterial>[],
    );
    final stock = stockAsync.value ?? const <CurrentStockRow>[];

    // Theoretical consumption for the selected staff today + material.
    double theoretical = 0;
    if (_staffId != null && _materialId != null) {
      final now = DateTime.now();
      final args = (
        companyId: user.companyId,
        from: DateTime(now.year, now.month, now.day),
        to: now,
        staffId: _staffId,
      );
      final consAsync = ref.watch(staffConsumptionProvider(args));
      final rows = consAsync.value ?? const <StaffConsumptionRow>[];
      for (final r in rows) {
        if (r.rawMaterialId == _materialId) theoretical += r.totalConsumed;
      }
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: stockGradientAppBar('Shift Handover'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          // Mode toggle
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.start, label: Text('Start of shift')),
              ButtonSegment(value: _Mode.end, label: Text('End of shift')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) async {
              setState(() => _mode = s.first);
              if (_mode == _Mode.end) await _onMaterialChanged(_materialId);
            },
          ),
          const SizedBox(height: 16),

          _label('Staff', isDark),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _staffId,
            hint: const Text('Select staff'),
            items: users
                .map(
                  (u) => DropdownMenuItem(
                    value: u.id,
                    child: Text(u.fullName, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _staffId = v),
            decoration: _dec(isDark),
          ),
          const SizedBox(height: 12),

          _label('Shift', isDark),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'morning', label: Text('Morning')),
              ButtonSegment(value: 'evening', label: Text('Evening')),
            ],
            selected: {_shift},
            onSelectionChanged: (s) async {
              setState(() => _shift = s.first);
              if (_mode == _Mode.end) await _onMaterialChanged(_materialId);
            },
          ),
          const SizedBox(height: 12),

          _label('Raw material', isDark),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _materialId,
            hint: const Text('Select material'),
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
            onChanged: _onMaterialChanged,
            decoration: _dec(isDark),
          ),
          const SizedBox(height: 16),

          if (_mode == _Mode.start)
            ..._buildStartMode(isDark, stock)
          else
            ..._buildEndMode(isDark, theoretical),
        ],
      ),
    );
  }

  List<Widget> _buildStartMode(bool isDark, List<CurrentStockRow> stock) {
    // Pre-fill starting stock from current stock for the chosen material.
    if (_materialId != null && _startController.text.isEmpty) {
      final row = stock.where((s) => s.id == _materialId);
      if (row.isNotEmpty) {
        _startController.text = _fmt(row.first.currentStock);
      }
    }
    return [
      _label('Starting stock', isDark),
      TextField(
        controller: _startController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
        ],
        decoration: _dec(isDark, hint: 'System value, edit if wrong'),
      ),
      const SizedBox(height: 20),
      _primaryButton(
        'Save start of shift',
        Icons.play_arrow_rounded,
        _busy ? null : () => _saveStartOfShift(stock),
      ),
    ];
  }

  List<Widget> _buildEndMode(bool isDark, double theoretical) {
    final start = double.tryParse(_startController.text.trim());
    final end = double.tryParse(_endController.text.trim());
    final actual = (start != null && end != null) ? start - end : null;
    final variance = actual != null ? actual - theoretical : null;

    return [
      if (_cachedStart == null && _materialId != null)
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'No start-of-shift record found for this staff/shift/material. '
            'Enter the starting stock manually below.',
            style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.warning),
          ),
        ),
      _label('Starting stock', isDark),
      TextField(
        controller: _startController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
        ],
        onChanged: (_) => setState(() {}),
        decoration: _dec(
          isDark,
          hint: _cachedStart != null ? 'Recorded at shift start' : null,
        ),
      ),
      const SizedBox(height: 12),
      _label('Ending stock', isDark),
      TextField(
        controller: _endController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
        ],
        onChanged: (_) => setState(() {}),
        decoration: _dec(isDark, hint: 'Actual weight/volume at shift end'),
      ),
      const SizedBox(height: 16),
      _computedRow('Actual consumption', actual, isDark),
      _computedRow('Theoretical (KOT × recipe)', theoretical, isDark),
      if (variance != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Variance',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                '${variance > 0 ? '+' : ''}${_fmt(variance)}',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _varianceColor(theoretical, variance),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 20),
      _primaryButton(
        'Submit handover',
        Icons.check_rounded,
        _busy ? null : () => _submitEndOfShift(theoretical),
      ),
    ];
  }

  Widget _computedRow(String label, double? value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
          Text(
            value == null ? '—' : _fmt(value),
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  Widget _primaryButton(String label, IconData icon, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(bool isDark, {String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled: true,
    fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}
