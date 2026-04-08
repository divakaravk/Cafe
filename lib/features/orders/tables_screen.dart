import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Tables management screen
class TablesScreen extends ConsumerWidget {
  final String companyId;
  const TablesScreen({super.key, required this.companyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tablesAsync = ref.watch(tablesProvider(companyId));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder.withValues(alpha: 0.2)
                        : AppColors.lightBorder.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.table_restaurant_rounded,
                    color: isDark
                        ? AppColors.primaryAmber
                        : AppColors.primaryOrange,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Tables',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () =>
                        ref.invalidate(tablesProvider(companyId)),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

            // Tables grid
            Expanded(
              child: tablesAsync.when(
                data: (tables) {
                  if (tables.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.table_restaurant_outlined,
                            size: 56,
                            color: isDark
                                ? AppColors.textWhiteMuted.withValues(alpha: 0.3)
                                : AppColors.textDarkMuted.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No tables configured',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: isDark
                                  ? AppColors.textWhiteMuted
                                  : AppColors.textDarkMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enable "Tables" in company settings',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textWhiteMuted.withValues(alpha: 0.5)
                                  : AppColors.textDarkMuted.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.1,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: tables.length,
                    itemBuilder: (context, index) {
                      final table = tables[index];
                      return _TableCard(
                        table: table,
                        isDark: isDark,
                        onTap: () =>
                            _showTableActions(context, ref, table, isDark),
                      ).animate().fadeIn(
                            delay: Duration(milliseconds: 40 * index),
                            duration: 300.ms,
                          );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTableActions(
      BuildContext context, WidgetRef ref, CafeTable table, bool isDark) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              table.tableName,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Status: ${table.status} • Seats: ${table.seatingCapacity}',
              style: GoogleFonts.inter(
                fontSize: 13,
                color:
                    isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
              ),
            ),
            const SizedBox(height: 20),
            if (table.isFree) ...[
              ListTile(
                leading: const Icon(Icons.restaurant_rounded,
                    color: AppColors.success),
                title: const Text('Start Order'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Navigate to order screen with this table
                },
              ),
            ],
            if (table.isOccupied) ...[
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded,
                    color: AppColors.info),
                title: const Text('View Running Order'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_rounded,
                    color: AppColors.success),
                title: const Text('Free Table'),
                onTap: () async {
                  await SupabaseService.updateTableStatus(
                      table.id, 'FREE');
                  ref.invalidate(tablesProvider(companyId));
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final CafeTable table;
  final bool isDark;
  final VoidCallback onTap;

  const _TableCard({
    required this.table,
    required this.isDark,
    required this.onTap,
  });

  Color get _statusColor {
    switch (table.status) {
      case 'FREE':
        return AppColors.tableFree;
      case 'OCCUPIED':
        return AppColors.tableOccupied;
      case 'RESERVED':
        return AppColors.tableReserved;
      default:
        return AppColors.tableFree;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _statusColor.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.table_restaurant_rounded,
                size: 32,
                color: _statusColor,
              ),
              const SizedBox(height: 8),
              Text(
                table.tableName,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  table.status,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
