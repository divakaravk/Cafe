import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/api_helper.dart';
import '../../../core/widgets/network_error_view.dart';
import '../../../core/widgets/pos_widgets.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';

/// Classic POS Screen — Traditional list-based UI
/// Left: Scrollable item list with groups | Right: Cart & bill
class ClassicPosScreen extends ConsumerStatefulWidget {
  const ClassicPosScreen({super.key});

  @override
  ConsumerState<ClassicPosScreen> createState() => _ClassicPosScreenState();
}

class _ClassicPosScreenState extends ConsumerState<ClassicPosScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 800;
    final cart = ref.watch(cartProvider(null));
    final cartNotifier = ref.read(cartProvider(null).notifier);
    final user = ref.watch(authStateProvider).value;

    if (user == null) return const SizedBox.shrink();

    final itemGroupsAsync = ref.watch(itemGroupsProvider(user.companyId));
    final discount = ref.watch(discountProvider);
    final subtotal = cart.fold<double>(0, (sum, ci) => sum + ci.total);
    final discountAmount = subtotal * (discount / 100);
    final total = subtotal - discountAmount;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // ─── LEFT: Item List ────────────────────────
            Expanded(
              flex: isTablet ? 3 : 2,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
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
                            color: AppColors.accentTeal,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.list_alt_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Classic POS',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.dashboard_customize_rounded,
                            size: 20,
                          ),
                          onSelected: (v) => ref
                              .read(selectedUiThemeProvider.notifier)
                              .setTheme(v),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'QUICK_BILL',
                              child: Text('Quick Bill'),
                            ),
                            PopupMenuItem(
                              value: 'MODERN',
                              child: Text('Modern POS'),
                            ),
                            PopupMenuItem(
                              value: 'CLASSIC',
                              child: Text('Classic POS'),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.menu_rounded, size: 20),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      ],
                    ),
                  ),

                  // Search
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search items...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  // Grouped item list
                  Expanded(
                    child: itemGroupsAsync.when(
                      data: (items) =>
                          _buildGroupedList(items, cart, cartNotifier, isDark),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => NetworkErrorView(
                        error: e,
                        onRetry: () =>
                            ref.invalidate(itemGroupsProvider(user.companyId)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── RIGHT: Cart Panel (Tablet) ────────────
            if (isTablet)
              Container(
                width: 340,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  border: Border(
                    left: BorderSide(
                      color: isDark
                          ? AppColors.darkBorder.withValues(alpha: 0.3)
                          : AppColors.lightBorder.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: _buildCartPanel(
                  cart,
                  cartNotifier,
                  subtotal,
                  total,
                  discountAmount,
                  discount,
                  isDark,
                  user,
                ),
              ),
          ],
        ),
      ),
      // Mobile bottom bar
      bottomSheet: !isTablet && cart.isNotEmpty
          ? _buildMobileBar(total, cart.length, isDark)
          : null,
    );
  }

  Widget _buildGroupedList(
    List<Item> masterItems,
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
  ) {
    final sections = masterItems
        .map((i) => i.sectionLabel ?? 'Other')
        .toSet()
        .toList();
    sections.sort();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: sections.length,
      itemBuilder: (context, gi) {
        final sectionName = sections[gi];
        final items = masterItems.where((i) {
          if (!i.isAvailable) return false;
          if (i.sectionLabel != (sectionName == 'Other' ? null : sectionName)) {
            if (sectionName == 'Other' && i.sectionLabel != null) return false;
            if (sectionName != 'Other' && i.sectionLabel != sectionName)
              return false;
          }
          if (_searchQuery.isNotEmpty) {
            return i.itemName.toLowerCase().contains(_searchQuery);
          }
          return true;
        }).toList();

        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: isDark
                  ? AppColors.darkBg.withValues(alpha: 0.6)
                  : AppColors.lightBg,
              child: Row(
                children: [
                  Text(
                    sectionName.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBorder.withValues(alpha: 0.3)
                          : AppColors.lightBorder.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${items.length}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Item rows
            ...items.asMap().entries.map((entry) {
              final item = entry.value;
              final cartQty = cart
                  .where((ci) => ci.item.id == item.id)
                  .fold<int>(0, (s, ci) => s + ci.qty);

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                title: Text(
                  item.itemName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const SizedBox(width: 12),
                    if (cartQty > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.primaryAmber.withValues(alpha: 0.15)
                              : AppColors.primaryOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '× $cartQty',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_rounded,
                        color: isDark
                            ? AppColors.primaryAmber
                            : AppColors.primaryOrange,
                      ),
                      onPressed: () => _handleItemTap(item, cartNotifier),
                    ),
                  ],
                ),
              ).animate().fadeIn(
                delay: Duration(milliseconds: 15 * entry.key),
                duration: 200.ms,
              );
            }),
          ],
        );
      },
    );
  }

  void _handleItemTap(Item item, CartNotifier cartNotifier) {
    final user = ref.read(authStateProvider).value;
    final company = user != null
        ? ref.read(companyProvider(user.companyId)).value
        : null;
    final hasCompanyVariants = company?.hasItemVariants ?? false;

    if (hasCompanyVariants && item.hasVariants && item.variants.isNotEmpty) {
      _showVariantPicker(item: item, cartNotifier: cartNotifier);
    } else {
      cartNotifier.addItem(item);
    }
  }

  void _showVariantPicker({
    required Item item,
    required CartNotifier cartNotifier,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.itemName,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose your option',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
            const SizedBox(height: 16),
            ...item.variants.map(
              (v) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  v.variantName,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                trailing: Text(
                  '₹${v.rate.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.primaryAmber
                        : AppColors.primaryOrange,
                  ),
                ),
                onTap: () {
                  cartNotifier.addItem(item, v);
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCartPanel(
    List<CartItem> cart,
    CartNotifier cartNotifier,
    double subtotal,
    double total,
    double discountAmount,
    double discount,
    bool isDark,
    UserProfile user,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(
                'Cart',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (cart.isNotEmpty)
                TextButton(
                  onPressed: () => ref.read(cartProvider(null).notifier).clear(),
                  child: Text(
                    'Clear',
                    style: GoogleFonts.inter(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Text(
                    'Cart empty',
                    style: GoogleFonts.inter(
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  children: cart.map((ci) {
                    return CartItemRow(
                      cartItem: ci,
                      onIncrement: () => ref.read(cartProvider(null).notifier).incrementQty(ci.item.id),
                      onDecrement: () => ref.read(cartProvider(null).notifier).decrementQty(ci.item.id),
                      onRemove: () => ref.read(cartProvider(null).notifier).removeItem(ci.item.id),
                    );
                  }).toList(),
                ),
        ),
        if (cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal', style: GoogleFonts.inter(fontSize: 13)),
                    Text(
                      '₹${subtotal.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '₹${total.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.primaryAmber
                            : AppColors.primaryOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _payBtn(
                      'Cash',
                      AppColors.success,
                      () => _pay('CASH', total, cart, user),
                    ),
                    const SizedBox(width: 6),
                    _payBtn(
                      'UPI',
                      AppColors.info,
                      () => _pay('UPI', total, cart, user),
                    ),
                    const SizedBox(width: 6),
                    _payBtn(
                      'Card',
                      AppColors.warning,
                      () => _pay('CARD', total, cart, user),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _payBtn(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildMobileBar(double total, int count, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.lightSurface,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Text(
            '$count items • ₹${total.toStringAsFixed(0)}',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ElevatedButton(onPressed: () {}, child: const Text('Pay')),
        ],
      ),
    );
  }

  Future<void> _pay(
    String mode,
    double total,
    List<CartItem> cart,
    UserProfile user,
  ) async {
    final discount = ref.read(discountProvider);
    final subtotal = cart.fold<double>(0, (sum, ci) => sum + ci.total);
    final discountAmount = subtotal * (discount / 100);
    try {
      await SupabaseService.createBill(
        companyId: user.companyId,
        billedBy: user.id,
        subtotal: subtotal,
        discountAmount: discountAmount,
        totalAmount: total,
        paymentMode: mode,
        billItems: cart
            .map(
              (ci) => {
                'item_id': ci.item.id,
                'variant_id': ci.variant?.id,
                'qty': ci.qty,
                'rate': ci.rate,
                'item_name': ci.itemName,
                'hsn_code': ci.variant?.hsnCode ?? ci.item.hsnCode,
                'gst_rate': ci.variant?.gstRate ?? ci.item.gstRate,
                'is_taxable': ci.item.isTaxable,
                'discount_item': 0,
                'notes': ci.notes,
              },
            )
            .toList(),
      );
      ref.read(cartProvider(null).notifier).clear();
      ref.read(discountProvider.notifier).reset();
      if (mounted) {
        AppFeedback.success(context, '₹${total.toStringAsFixed(0)} via $mode');
      }
    } catch (e) {
      if (mounted) AppFeedback.toastError(context, e);
    }
  }
}
