import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Bills history screen — shows all completed bills
class BillsScreen extends ConsumerWidget {
  final String companyId;
  const BillsScreen({super.key, required this.companyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final billsAsync = ref.watch(billsProvider(companyId));
    final dateFormat = DateFormat('dd MMM, hh:mm a');

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
                    Icons.receipt_long_rounded,
                    color: isDark
                        ? AppColors.primaryAmber
                        : AppColors.primaryOrange,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Bills',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () =>
                        ref.invalidate(billsProvider(companyId)),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

            // Bills list
            Expanded(
              child: billsAsync.when(
                data: (bills) {
                  if (bills.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_outlined,
                            size: 56,
                            color: isDark
                                ? AppColors.textWhiteMuted.withValues(alpha: 0.3)
                                : AppColors.textDarkMuted.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No bills yet',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: isDark
                                  ? AppColors.textWhiteMuted
                                  : AppColors.textDarkMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: bills.length,
                    itemBuilder: (context, index) {
                      final bill = bills[index];
                      return _BillCard(
                        bill: bill,
                        isDark: isDark,
                        dateFormat: dateFormat,
                        onTap: () =>
                            _showBillDetails(context, bill, isDark, dateFormat),
                      ).animate().fadeIn(
                            delay: Duration(milliseconds: 30 * index),
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

  void _showBillDetails(BuildContext context, Bill bill, bool isDark,
      DateFormat dateFormat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                children: [
                  Text(
                    'Bill #${bill.billNumber ?? '-'}',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (bill.isVoided)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'VOIDED',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                bill.createdAt != null
                    ? dateFormat.format(bill.createdAt!)
                    : '-',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
              const Divider(height: 24),

              // Bill items
              ...bill.items.map(
                (bi) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          bi.itemName ?? 'Item',
                          style: GoogleFonts.inter(fontSize: 14),
                        ),
                      ),
                      Text(
                        '×${bi.qty}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '₹${bi.total.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),

              _detailRow('Subtotal', '₹${bill.subtotal.toStringAsFixed(0)}',
                  isDark),
              if (bill.taxAmount > 0)
                _detailRow(
                    'Tax', '₹${bill.taxAmount.toStringAsFixed(0)}', isDark),
              if (bill.discountAmount > 0)
                _detailRow('Discount',
                    '-₹${bill.discountAmount.toStringAsFixed(0)}', isDark,
                    isDiscount: true),
              const Divider(height: 16),
              _detailRow(
                'Total',
                '₹${bill.totalAmount.toStringAsFixed(0)}',
                isDark,
                isBold: true,
              ),
              const SizedBox(height: 8),
              _detailRow('Payment', bill.paymentMode, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, bool isDark,
      {bool isBold = false, bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isBold ? 16 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: isBold ? 18 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              color: isDiscount
                  ? AppColors.error
                  : (isBold
                      ? (isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange)
                      : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  final Bill bill;
  final bool isDark;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _BillCard({
    required this.bill,
    required this.isDark,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _paymentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _paymentIcon,
                  color: _paymentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill #${bill.billNumber ?? '-'}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bill.createdAt != null
                          ? dateFormat.format(bill.createdAt!)
                          : '-',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${bill.totalAmount.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _paymentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      bill.paymentMode,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _paymentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _paymentColor {
    switch (bill.paymentMode) {
      case 'CASH':
        return AppColors.success;
      case 'UPI':
        return AppColors.info;
      case 'CARD':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  IconData get _paymentIcon {
    switch (bill.paymentMode) {
      case 'CASH':
        return Icons.payments_rounded;
      case 'UPI':
        return Icons.qr_code_rounded;
      case 'CARD':
        return Icons.credit_card_rounded;
      default:
        return Icons.payments_rounded;
    }
  }
}
