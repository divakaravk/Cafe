import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/api_helper.dart';
import '../../../../core/widgets/network_error_view.dart';
import '../../../../models/inventory_models.dart';
import '../../../../providers/providers.dart';
import '../../../../providers/inventory_providers.dart';
import 'stock_common.dart';

/// End-of-day physical count. Manager enters the actual counted stock per
/// material; the screen shows live variance vs the system's theoretical stock
/// and writes one adjustment ledger row per changed material on submit.
class DayEndCountScreen extends ConsumerStatefulWidget {
  const DayEndCountScreen({super.key});

  @override
  ConsumerState<DayEndCountScreen> createState() => _DayEndCountScreenState();
}

class _DayEndCountScreenState extends ConsumerState<DayEndCountScreen> {
  // actual-count controllers keyed by material id, pre-filled with theoretical.
  final Map<String, TextEditingController> _controllers = {};
  bool _submitting = false;
  List<_VarianceResult>? _summary; // non-null once submitted

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(CurrentStockRow row) {
    return _controllers.putIfAbsent(
      row.id,
      () => TextEditingController(text: _fmt(row.currentStock)),
    );
  }

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

  double? _actualFor(String id) {
    final t = _controllers[id]?.text.trim() ?? '';
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  /// Colour for a variance, by % of theoretical: green within ±5% (or 0),
  /// orange -5%..-15%, red worse than -15%.
  Color _varianceColor(double theoretical, double variance) {
    if (variance == 0) return AppColors.success;
    if (theoretical <= 0) {
      return variance > 0 ? AppColors.success : AppColors.error;
    }
    final pct = variance / theoretical * 100;
    if (pct >= -5) return AppColors.success;
    if (pct >= -15) return AppColors.warning;
    return AppColors.error;
  }

  List<_VarianceResult> _pendingVariances(List<CurrentStockRow> rows) {
    final out = <_VarianceResult>[];
    for (final r in rows) {
      final actual = _actualFor(r.id);
      if (actual == null) continue;
      final variance = actual - r.currentStock;
      if (variance == 0) continue; // skip no-op
      out.add(
        _VarianceResult(
          name: r.name,
          unit: r.unit,
          theoretical: r.currentStock,
          actual: actual,
          variance: variance,
          rawMaterialId: r.id,
        ),
      );
    }
    return out;
  }

  Future<void> _submit(List<CurrentStockRow> rows) async {
    if (_submitting) return;
    final pending = _pendingVariances(rows);
    if (pending.isEmpty) return;
    setState(() => _submitting = true);
    final user = ref.read(authStateProvider).value!;
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    try {
      for (final v in pending) {
        await SupabaseService.submitStockAdjustment(
          companyId: user.companyId,
          rawMaterialId: v.rawMaterialId,
          qty: v.variance,
          movementType: 'adjustment',
          note: 'day-end count $dateStr',
          shiftLabel: null,
          staffId: user.id,
        );
      }
      ref.invalidate(currentStockProvider(user.companyId));
      if (mounted) setState(() => _summary = pending);
    } catch (e) {
      if (mounted) AppFeedback.toastError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const SizedBox.shrink();

    if (_summary != null) {
      return _SummaryView(results: _summary!, isDark: isDark);
    }

    final stockAsync = ref.watch(currentStockProvider(user.companyId));

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: stockGradientAppBar('Day-End Count'),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => NetworkErrorView(
          error: e,
          onRetry: () => ref.invalidate(currentStockProvider(user.companyId)),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Text(
                'No materials to count yet.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
            );
          }
          final hasVariance = _pendingVariances(rows).isNotEmpty;
          return Column(
            children: [
              _buildHeaderRow(isDark),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _buildRow(isDark, rows[i]),
                ),
              ),
              _buildSubmitBar(isDark, rows, hasVariance),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderRow(bool isDark) {
    final style = GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('MATERIAL', style: style)),
          Expanded(
            flex: 2,
            child: Text('THEO.', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text('ACTUAL', style: style, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('VAR.', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(bool isDark, CurrentStockRow row) {
    final controller = _controllerFor(row);
    final actual = _actualFor(row.id);
    final variance = actual == null ? 0.0 : actual - row.currentStock;
    final color = _varianceColor(row.currentStock, variance);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              '${row.name}\n${row.unit}',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _fmt(row.currentStock),
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
              ],
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
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
          Expanded(
            flex: 2,
            child: Text(
              actual == null
                  ? '—'
                  : '${variance > 0 ? '+' : ''}${_fmt(variance)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitBar(
    bool isDark,
    List<CurrentStockRow> rows,
    bool hasVariance,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: (!hasVariance || _submitting) ? null : () => _submit(rows),
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded),
          label: Text(
            _submitting ? 'Submitting…' : 'Submit variances',
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
      ),
    );
  }
}

class _VarianceResult {
  final String name;
  final String unit;
  final double theoretical;
  final double actual;
  final double variance;
  final String rawMaterialId;

  const _VarianceResult({
    required this.name,
    required this.unit,
    required this.theoretical,
    required this.actual,
    required this.variance,
    required this.rawMaterialId,
  });
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.results, required this.isDark});
  final List<_VarianceResult> results;
  final bool isDark;

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${results.length} variance${results.length == 1 ? '' : 's'} submitted',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final r = results[i];
                  return ListTile(
                    title: Text(
                      r.name,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Theoretical ${_fmt(r.theoretical)} → Actual ${_fmt(r.actual)} ${r.unit}',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    trailing: Text(
                      '${r.variance > 0 ? '+' : ''}${_fmt(r.variance)}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        color: r.variance >= 0
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.maybePop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
