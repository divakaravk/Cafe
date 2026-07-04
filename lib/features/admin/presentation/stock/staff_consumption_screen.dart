import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/network_error_view.dart';
import '../../../../models/inventory_models.dart';
import '../../../../providers/providers.dart';
import '../../../../providers/inventory_providers.dart';
import 'stock_common.dart';

/// Theoretical per-staff, per-material consumption (KOT qty × recipe). Filter
/// by date range and staff; sortable by amount consumed.
class StaffConsumptionScreen extends ConsumerStatefulWidget {
  const StaffConsumptionScreen({super.key});

  @override
  ConsumerState<StaffConsumptionScreen> createState() =>
      _StaffConsumptionScreenState();
}

class _StaffConsumptionScreenState
    extends ConsumerState<StaffConsumptionScreen> {
  late DateTimeRange _range;
  String? _staffId; // null = all staff
  bool _sortDesc = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: start, end: now);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) {
      // Extend the end to the end of that day so the full day is included.
      final end = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
      setState(() => _range = DateTimeRange(start: picked.start, end: end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const SizedBox.shrink();

    final args = (
      companyId: user.companyId,
      from: _range.start,
      to: _range.end,
      staffId: _staffId,
    );
    final consumptionAsync = ref.watch(staffConsumptionProvider(args));
    final usersAsync = ref.watch(companyUsersProvider(user.companyId));

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: stockGradientAppBar('Staff Consumption'),
      body: Column(
        children: [
          _buildControls(isDark, usersAsync.value ?? const []),
          _buildNote(isDark),
          Expanded(
            child: consumptionAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => NetworkErrorView(
                error: e,
                onRetry: () => ref.invalidate(staffConsumptionProvider(args)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      'No consumption data for this period.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                      ),
                    ),
                  );
                }
                final sorted = [...rows]..sort(
                  (a, b) => _sortDesc
                      ? b.totalConsumed.compareTo(a.totalConsumed)
                      : a.totalConsumed.compareTo(b.totalConsumed),
                );
                return _buildTable(isDark, sorted);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(bool isDark, List<dynamic> users) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: Text(
                '${_fmtDate(_range.start)} – ${_fmtDate(_range.end)}',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: _staffId,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All staff'),
                ),
                ...users.map(
                  (u) => DropdownMenuItem<String?>(
                    value: u.id as String,
                    child: Text(
                      u.fullName as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _staffId = v),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurface
                    : AppColors.lightSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNote(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Theoretical figures based on KOT quantities × recipe. Pair with '
              'Shift Handover to see actual vs theoretical per staff.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(bool isDark, List<StaffConsumptionRow> rows) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: DataTable(
          sortColumnIndex: 2,
          sortAscending: !_sortDesc,
          columns: [
            DataColumn(
              label: Text(
                'Staff',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            DataColumn(
              label: Text(
                'Raw material',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            DataColumn(
              numeric: true,
              onSort: (_, __) => setState(() => _sortDesc = !_sortDesc),
              label: Text(
                'Total consumed',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
            DataColumn(
              label: Text(
                'Unit',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          rows: rows
              .map(
                (r) => DataRow(
                  cells: [
                    DataCell(Text(r.staffName ?? '—')),
                    DataCell(Text(r.rawMaterialName)),
                    DataCell(
                      Text(
                        r.totalConsumed.truncateToDouble() == r.totalConsumed
                            ? r.totalConsumed.toStringAsFixed(0)
                            : r.totalConsumed.toStringAsFixed(2),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(Text(r.unit)),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
