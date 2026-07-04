import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/api_helper.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Returned when a user picks a cover to order for or add a new cover.
class CoverSelectionResult {
  final TableCover cover;
  final String sessionId;
  CoverSelectionResult({required this.cover, required this.sessionId});
}

Future<CoverSelectionResult?> showCoverSelectionDialog({
  required BuildContext context,
  required WidgetRef ref,
  required CafeTable table,
  required String companyId,
  required String userId,
}) {
  return showModalBottomSheet<CoverSelectionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CoverSelectionSheet(
      table: table,
      companyId: companyId,
      userId: userId,
      parentRef: ref,
    ),
  );
}

class CoverSelectionSheet extends ConsumerStatefulWidget {
  final CafeTable table;
  final String companyId;
  final String userId;
  final WidgetRef parentRef;

  const CoverSelectionSheet({
    super.key,
    required this.table,
    required this.companyId,
    required this.userId,
    required this.parentRef,
  });

  @override
  ConsumerState<CoverSelectionSheet> createState() => _CoverSelectionSheetState();
}

class _CoverSelectionSheetState extends ConsumerState<CoverSelectionSheet> {
  List<TableCover> _covers = [];
  Map<String, double> _coverTotals = {};
  bool _loading = true;
  bool _saving = false;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.table.activeSessionId;
    _load();
  }

  Future<void> _load() async {
    if (_sessionId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        SupabaseService.getCoversForSession(_sessionId!),
        SupabaseService.getCoverTotals(_sessionId!),
      ]);
      setState(() {
        _covers = (results[0] as List<Map<String, dynamic>>)
            .map((e) => TableCover.fromJson(e))
            .toList();
        _coverTotals = results[1] as Map<String, double>;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addAndSelectCover() async {
    if (_sessionId == null) return;
    setState(() => _saving = true);
    try {
      final nextNumber = _covers.isEmpty ? 1 : _covers.last.coverNumber + 1;
      final data = await SupabaseService.createCover(
        sessionId: _sessionId!,
        companyId: widget.companyId,
        coverNumber: nextNumber,
      );
      if (mounted) {
        Navigator.of(context).pop(CoverSelectionResult(
          cover: TableCover.fromJson(data),
          sessionId: _sessionId!,
        ));
      }
    } catch (e) {
      if (mounted) AppFeedback.toastError(context, e);
      setState(() => _saving = false);
    }
  }

  void _selectCover(TableCover cover) {
    Navigator.of(context).pop(
      CoverSelectionResult(cover: cover, sessionId: _sessionId!),
    );
  }

  Future<void> _billCover(TableCover cover) async {
    final total = _coverTotals[cover.id] ?? 0;
    if (total == 0) {
      AppFeedback.warn(context, 'No orders for this cover yet');
      return;
    }
    final mode = await showDialog<String>(
      context: context,
      builder: (_) => _PaymentDialog(total: total, coverName: cover.displayName),
    );
    if (mode == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await SupabaseService.checkoutCover(
        coverId: cover.id,
        sessionId: _sessionId!,
        paymentMode: mode,
      );
      widget.parentRef.invalidate(tablesProvider(widget.companyId));
      await _load();
      if (mounted) {
        AppFeedback.success(
          context,
          '${cover.displayName} billed — ₹${total.toStringAsFixed(0)}',
        );
      }
    } catch (e) {
      if (mounted) AppFeedback.toastError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final activeCovers = _covers.where((c) => c.isActive).toList();
    final billedCovers = _covers.where((c) => c.isBilled).toList();

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.table_restaurant_rounded,
                    color: isDark ? AppColors.primaryAmber : AppColors.primaryOrange,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Table ${widget.table.tableName}',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!_loading)
                      Text(
                        '${activeCovers.length} active cover${activeCovers.length != 1 ? 's' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textWhiteMuted
                              : AppColors.textDarkMuted,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            )
          else ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.52,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  children: [
                    if (_covers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'No covers yet — tap "Add Cover" to start',
                          style: GoogleFonts.inter(
                            color: isDark
                                ? AppColors.textWhiteMuted
                                : AppColors.textDarkMuted,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ...activeCovers.map((cover) => _CoverCard(
                          cover: cover,
                          total: _coverTotals[cover.id] ?? 0,
                          isDark: isDark,
                          onOrder: () => _selectCover(cover),
                          onBill: () => _billCover(cover),
                        )),
                    if (billedCovers.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'BILLED',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: isDark
                                  ? AppColors.textWhiteMuted
                                  : AppColors.textDarkMuted,
                            ),
                          ),
                        ),
                      ),
                      ...billedCovers.map((cover) => _CoverCard(
                            cover: cover,
                            total: _coverTotals[cover.id] ?? 0,
                            isDark: isDark,
                            isBilled: true,
                          )),
                    ],
                  ],
                ),
              ),
            ),
            // Add Cover button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _addAndSelectCover,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    'Add Cover',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isDark ? AppColors.primaryAmber : AppColors.primaryOrange,
                    side: BorderSide(
                      color:
                          isDark ? AppColors.primaryAmber : AppColors.primaryOrange,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  final TableCover cover;
  final double total;
  final bool isDark;
  final bool isBilled;
  final VoidCallback? onOrder;
  final VoidCallback? onBill;

  const _CoverCard({
    required this.cover,
    required this.total,
    required this.isDark,
    this.isBilled = false,
    this.onOrder,
    this.onBill,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isBilled ? AppColors.success : AppColors.primaryOrange;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isBilled ? 0.05 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: isBilled ? 0.15 : 0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Cover number badge
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${cover.coverNumber}',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cover.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  total > 0
                      ? '₹${total.toStringAsFixed(0)}'
                      : 'No orders yet',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isBilled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Paid',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
            )
          else ...[
            TextButton(
              onPressed: onOrder,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Order',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.primaryAmber : AppColors.primaryOrange,
                ),
              ),
            ),
            if (total > 0)
              TextButton(
                onPressed: onBill,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Bill',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  final double total;
  final String coverName;
  const _PaymentDialog({required this.total, required this.coverName});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String _mode = 'CASH';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Bill ${widget.coverName}',
        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '₹${widget.total.toStringAsFixed(0)}',
            style: GoogleFonts.inter(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: ['CASH', 'UPI', 'CARD'].map((mode) {
              final selected = _mode == mode;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => setState(() => _mode = mode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryOrange
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        mode,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : null,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_mode),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(
            'Confirm Payment',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
