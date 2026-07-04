import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/inventory_models.dart';
import '../../../../providers/providers.dart';
import '../../../../providers/inventory_providers.dart';
import 'stock_common.dart';
import 'raw_material_screen.dart';
import 'day_end_count_screen.dart';
import 'shift_handover_screen.dart';
import 'staff_consumption_screen.dart';

/// Tabbed container for the whole Stock section. This is what the drawer opens.
/// Each tab is a self-contained screen; an [IndexedStack] keeps their state
/// while switching, and a [NavigationBar] drives the index.
class StockSectionScreen extends StatefulWidget {
  const StockSectionScreen({super.key});

  @override
  State<StockSectionScreen> createState() => _StockSectionScreenState();
}

class _StockSectionScreenState extends State<StockSectionScreen> {
  int _index = 0;

  void _goToMaterials() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabs = [
      _StockDashboardTab(onGoToMaterials: _goToMaterials),
      const RawMaterialScreen(),
      const DayEndCountScreen(),
      const ShiftHandoverScreen(),
      const StaffConsumptionScreen(),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science_rounded),
            label: 'Materials',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Day-End',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz_rounded),
            label: 'Handover',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Staff',
          ),
        ],
      ),
    );
  }
}

/// Dashboard tab — current stock table + summary card.
class _StockDashboardTab extends ConsumerWidget {
  const _StockDashboardTab({required this.onGoToMaterials});
  final VoidCallback onGoToMaterials;

  static String _fmt(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).value;
    if (user == null) return const SizedBox.shrink();
    final companyId = user.companyId;
    final stockAsync = ref.watch(currentStockProvider(companyId));

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: stockGradientAppBar('Stock Dashboard'),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
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
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(currentStockProvider(companyId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(currentStockProvider(companyId));
              await ref.read(currentStockProvider(companyId).future);
            },
            child: rows.isEmpty
                ? _emptyState(isDark)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      _summaryCard(isDark, rows),
                      const SizedBox(height: 12),
                      _stockTable(isDark, rows),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _emptyState(bool isDark) {
    return ListView(
      // ListView so RefreshIndicator still works with the empty state.
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.inventory_2_outlined,
          size: 64,
          color: AppColors.primaryAmber.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No materials tracked yet',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ElevatedButton.icon(
            onPressed: onGoToMaterials,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Raw Materials'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(bool isDark, List<CurrentStockRow> rows) {
    final total = rows.length;
    final lowCount = rows.where((r) => r.isLowStock).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _metric(
              'Materials tracked',
              '$total',
              Icons.science_rounded,
              AppColors.primaryAmber,
              isDark,
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          Expanded(
            child: _metric(
              'Low stock items',
              '$lowCount',
              Icons.warning_amber_rounded,
              lowCount > 0 ? AppColors.error : AppColors.success,
              isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
        ),
      ],
    );
  }

  Widget _stockTable(bool isDark, List<CurrentStockRow> rows) {
    TextStyle head() =>
        GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          columns: [
            DataColumn(label: Text('Material', style: head())),
            DataColumn(label: Text('Unit', style: head())),
            DataColumn(label: Text('Opening', style: head()), numeric: true),
            DataColumn(label: Text('Current', style: head()), numeric: true),
            DataColumn(label: Text('Reorder', style: head()), numeric: true),
            DataColumn(label: Text('Status', style: head())),
          ],
          rows: rows.map((r) {
            return DataRow(
              cells: [
                DataCell(Text(r.name)),
                DataCell(Text(r.unit)),
                DataCell(Text(_fmt(r.openingStock))),
                DataCell(Text(_fmt(r.currentStock))),
                DataCell(Text(_fmt(r.reorderLevel))),
                DataCell(_statusPill(r.isLowStock)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _statusPill(bool isLow) {
    final color = isLow ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isLow ? 'Low' : 'OK',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
