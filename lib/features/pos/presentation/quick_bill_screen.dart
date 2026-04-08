import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';

import '../../../models/models.dart';
import '../../../providers/providers.dart';

/// Quick Bill Screen — tea shops, fast billing
/// Minimal UI — just a grid of items and instant billing
class QuickBillScreen extends ConsumerWidget {
  const QuickBillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final authState = ref.watch(authStateProvider);
    final user = authState.value;

    if (user == null) return const SizedBox.shrink();

    final itemGroupsAsync = ref.watch(itemGroupsProvider(user.companyId));
    final discount = ref.watch(discountProvider);
    final subtotal = cart.fold<double>(0, (sum, ci) => sum + ci.total);
    final discountAmount = subtotal * (discount / 100);
    final total = subtotal - discountAmount;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accentCoral,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bolt_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Quick Bill',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (cart.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primaryAmber.withValues(alpha: 0.15)
                            : AppColors.primaryOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '₹${total.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon:
                        const Icon(Icons.dashboard_customize_rounded, size: 20),
                    onSelected: (value) {
                      ref.read(selectedUiThemeProvider.notifier).setTheme(value);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'QUICK_BILL', child: Text('Quick Bill')),
                      PopupMenuItem(value: 'MODERN', child: Text('Modern POS')),
                      PopupMenuItem(
                          value: 'CLASSIC', child: Text('Classic POS')),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    onPressed: () =>
                        ref.read(authStateProvider.notifier).signOut(),
                  ),
                ],
              ),
            ),

            // ─── Item Grid ─────────────────────────────
            Expanded(
              child: itemGroupsAsync.when(
                data: (groups) {
                  final items = groups
                      .expand((g) => g.items)
                      .where((i) => i.isAvailable)
                      .toList();

                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'No items available',
                        style: GoogleFonts.inter(
                          color: isDark
                              ? AppColors.textWhiteMuted
                              : AppColors.textDarkMuted,
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.5,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final cartQty = cart
                          .where((ci) => ci.item.id == item.id)
                          .fold<int>(0, (sum, ci) => sum + ci.qty);

                      return _QuickItemTile(
                        item: item,
                        qty: cartQty,
                        onTap: () => cartNotifier.addItem(item),
                        isDark: isDark,
                      ).animate().fadeIn(
                            delay: Duration(milliseconds: 20 * (index % 16)),
                            duration: 250.ms,
                          );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),

            // ─── Bottom Billing Strip ──────────────────
            if (cart.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkElevated : AppColors.lightElevated,
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? AppColors.darkBorder.withValues(alpha: 0.2)
                          : AppColors.lightBorder.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // Cart summary
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: cart
                                .map((ci) => Chip(
                                      label: Text(
                                        '${ci.itemName} ×${ci.qty}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      deleteIcon:
                                          const Icon(Icons.close, size: 14),
                                      onDeleted: () =>
                                          cartNotifier.removeItem(ci.item.id),
                                      visualDensity: VisualDensity.compact,
                                    ))
                                .toList(),
                          ),
                        ),
                        TextButton(
                          onPressed: () => cartNotifier.clear(),
                          child: Text(
                            'Clear',
                            style: GoogleFonts.inter(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Total + Pay
                    Row(
                      children: [
                        Text(
                          'Total: ₹${total.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                          ),
                        ),
                        const Spacer(),
                        _quickPayBtn(
                          'Cash',
                          AppColors.success,
                          () => _pay(context, ref, 'CASH', total, cart, user),
                        ),
                        const SizedBox(width: 8),
                        _quickPayBtn(
                          'UPI',
                          AppColors.info,
                          () => _pay(context, ref, 'UPI', total, cart, user),
                        ),
                        const SizedBox(width: 8),
                        _quickPayBtn(
                          'Card',
                          AppColors.warning,
                          () => _pay(context, ref, 'CARD', total, cart, user),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 200.ms),
          ],
        ),
      ),
    );
  }

  Widget _quickPayBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, String mode,
      double total, List<CartItem> cart, UserProfile user) async {
    final discount = ref.read(discountProvider);
    final subtotal = cart.fold<double>(0, (sum, ci) => sum + ci.total);
    final discountAmount = subtotal * (discount / 100);
    try {
      await SupabaseService.createBill(
        companyId: user.companyId,
        subtotal: subtotal,
        discountAmount: discountAmount,
        totalAmount: total,
        paymentMode: mode,
        billItems: cart
            .map((ci) => {
                  'item_id': ci.item.id,
                  'qty': ci.qty,
                  'rate': ci.rate,
                  'tax_percentage': 0,
                })
            .toList(),
      );
      ref.read(cartProvider.notifier).clear();
      ref.read(discountProvider.notifier).reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ₹${total.toStringAsFixed(0)} via $mode'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

/// Quick item tile - compact, touch-friendly
class _QuickItemTile extends StatelessWidget {
  final Item item;
  final int qty;
  final VoidCallback onTap;
  final bool isDark;

  const _QuickItemTile({
    required this.item,
    required this.qty,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: qty > 0
                ? (isDark
                    ? AppColors.primaryAmber.withValues(alpha: 0.12)
                    : AppColors.primaryOrange.withValues(alpha: 0.08))
                : (isDark ? AppColors.darkCard : AppColors.lightCard),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: qty > 0
                  ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                  : (isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.3)
                      : AppColors.lightBorder.withValues(alpha: 0.4)),
              width: qty > 0 ? 1.5 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.itemName,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${item.rate.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                    ),
                  ),
                ],
              ),
              if (qty > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$qty',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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
