import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/pos_widgets.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';

/// Modern POS Screen — Tablet-first split layout
/// Left: Item categories + grid | Right: sticky billing panel
class ModernPosScreen extends ConsumerStatefulWidget {
  const ModernPosScreen({super.key});

  @override
  ConsumerState<ModernPosScreen> createState() => _ModernPosScreenState();
}

class _ModernPosScreenState extends ConsumerState<ModernPosScreen>
    with TickerProviderStateMixin {
  String? _selectedGroupId;
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
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final authState = ref.watch(authStateProvider);
    final user = authState.value;

    if (user == null) return const SizedBox.shrink();

    final itemGroupsAsync = ref.watch(itemGroupsProvider(user.companyId));

    return Scaffold(
      body: Row(
        children: [
          // ─── LEFT: Items Panel ──────────────────────────
          Expanded(
            flex: isTablet ? 3 : 2,
            child: Column(
              children: [
                // Top Bar
                _buildTopBar(isDark, user),
                // Search
                _buildSearchBar(isDark),
                // Category chips
                itemGroupsAsync.when(
                  data: (groups) => _buildCategoryBar(groups, isDark),
                  loading: () => const SizedBox(height: 48),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Error: $e'),
                  ),
                ),
                // Item grid
                Expanded(
                  child: itemGroupsAsync.when(
                    data: (groups) => _buildItemGrid(
                      groups,
                      cart,
                      cartNotifier,
                      isDark,
                      isTablet,
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Center(child: Text('Error loading items: $e')),
                  ),
                ),
              ],
            ),
          ),

          // ─── RIGHT: Billing Panel ──────────────────────
          if (isTablet)
            Container(
              width: 360,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                border: Border(
                  left: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder.withValues(alpha: 0.3)
                        : AppColors.lightBorder.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: _buildBillingPanel(cart, cartNotifier, isDark, user),
            ),
        ],
      ),
      // Bottom sheet billing for mobile
      bottomSheet: !isTablet && cart.isNotEmpty
          ? _buildMobileBillingBar(cart, isDark)
          : null,
    );
  }

  // ─── TOP BAR ────────────────────────────────────────────
  Widget _buildTopBar(bool isDark, UserProfile user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
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
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryAmber, AppColors.primaryOrange],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.restaurant_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CafePOS',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${user.fullName} • ${user.role}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Theme switcher
            IconButton(
              icon: Icon(
                ref.watch(isDarkModeProvider)
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                size: 20,
              ),
              onPressed: () {
                ref.read(isDarkModeProvider.notifier).toggle();
              },
            ),
            // UI mode switcher
            PopupMenuButton<String>(
              icon: const Icon(Icons.dashboard_customize_rounded, size: 20),
              onSelected: (value) {
                ref.read(selectedUiThemeProvider.notifier).setTheme(value);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'QUICK_BILL', child: Text('Quick Bill')),
                PopupMenuItem(value: 'MODERN', child: Text('Modern POS')),
                PopupMenuItem(value: 'CLASSIC', child: Text('Classic POS')),
              ],
            ),
            // Logout
            IconButton(
              icon: const Icon(Icons.logout_rounded, size: 20),
              onPressed: () => ref.read(authStateProvider.notifier).signOut(),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ─── SEARCH BAR ─────────────────────────────────────────
  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search items...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ─── CATEGORY BAR ──────────────────────────────────────
  Widget _buildCategoryBar(List<ItemGroup> groups, bool isDark) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          GroupChip(
            label: 'All',
            isSelected: _selectedGroupId == null,
            onTap: () => setState(() => _selectedGroupId = null),
          ),
          const SizedBox(width: 8),
          ...groups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GroupChip(
                label: g.groupName,
                isSelected: _selectedGroupId == g.id,
                onTap: () => setState(() => _selectedGroupId = g.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── ITEM GRID ─────────────────────────────────────────
  Widget _buildItemGrid(
    List<ItemGroup> groups,
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
    bool isTablet,
  ) {
    // Flatten items from groups
    List<Item> items = [];
    for (final group in groups) {
      if (_selectedGroupId != null && group.id != _selectedGroupId) continue;
      items.addAll(group.items.where((i) => i.isAvailable));
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      items = items
          .where((i) => i.itemName.toLowerCase().contains(_searchQuery))
          .toList();
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.restaurant_menu_rounded,
              size: 48,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No items found',
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

    final crossAxisCount = isTablet ? 4 : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isInCart = cart.any((ci) => ci.item.id == item.id);
        return ItemGridTile(
          item: item,
          isInCart: isInCart,
          onTap: () => _handleItemTap(item, groups, cartNotifier),
        ).animate().fadeIn(
          delay: Duration(milliseconds: 30 * (index % 12)),
          duration: 300.ms,
        );
      },
    );
  }

  void _handleItemTap(
    Item item,
    List<ItemGroup> groups,
    CartNotifier cartNotifier,
  ) {
    // Find item's group
    final group = groups.where((g) => g.id == item.itemGroupId).firstOrNull;

    if (group == null || group.isDirect) {
      // Direct — just add to cart
      cartNotifier.addItem(item);
      return;
    }

    // Grouped — show variant picker
    if (group.isGrouped && group.showSeparateItems) {
      // Show bottom sheet with variants
      _showVariantPicker(group, cartNotifier);
    } else {
      // Merged (single button billing)
      cartNotifier.addItem(item);
    }
  }

  void _showVariantPicker(ItemGroup group, CartNotifier cartNotifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.groupName,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a variant',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
            const SizedBox(height: 16),
            ...group.items
                .where((i) => i.isAvailable)
                .map(
                  (item) => ListTile(
                    title: Text(item.itemName),
                    trailing: Text(
                      '₹${item.rate.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.primaryAmber
                            : AppColors.primaryOrange,
                      ),
                    ),
                    onTap: () {
                      cartNotifier.addItem(item);
                      Navigator.pop(context);
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ─── BILLING PANEL (Tablet) ────────────────────────────
  Widget _buildBillingPanel(
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
    UserProfile user,
  ) {
    final discount = ref.watch(discountProvider);
    final subtotal = cart.fold<double>(0, (sum, ci) => sum + ci.total);
    final discountAmount = subtotal * (discount / 100);
    final total = subtotal - discountAmount;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
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
                size: 20,
                color: isDark
                    ? AppColors.primaryAmber
                    : AppColors.primaryOrange,
              ),
              const SizedBox(width: 8),
              Text(
                'Current Bill',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (cart.isNotEmpty)
                TextButton(
                  onPressed: () => cartNotifier.clear(),
                  child: Text(
                    'Clear',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Cart items
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 40,
                        color: isDark
                            ? AppColors.textWhiteMuted.withValues(alpha: 0.3)
                            : AppColors.textDarkMuted.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap items to add',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textWhiteMuted.withValues(alpha: 0.5)
                              : AppColors.textDarkMuted.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: cart.length,
                  itemBuilder: (context, index) {
                    final ci = cart[index];
                    return CartItemRow(
                      cartItem: ci,
                      onIncrement: () => cartNotifier.incrementQty(ci.item.id),
                      onDecrement: () => cartNotifier.decrementQty(ci.item.id),
                      onRemove: () => cartNotifier.removeItem(ci.item.id),
                    );
                  },
                ),
        ),

        // Totals + Actions
        if (cart.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkElevated.withValues(alpha: 0.5)
                  : AppColors.lightElevated.withValues(alpha: 0.5),
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
                // Discount row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Discount', style: GoogleFonts.inter(fontSize: 13)),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '0%',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (v) {
                          final d = double.tryParse(v) ?? 0;
                          ref.read(discountProvider.notifier).setDiscount(d);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Subtotal
                _totalRow('Subtotal', subtotal, isDark),
                if (discount > 0)
                  _totalRow(
                    'Discount (${discount.toStringAsFixed(0)}%)',
                    -discountAmount,
                    isDark,
                    isNeg: true,
                  ),
                const Divider(height: 16),
                _totalRow('Total', total, isDark, isBold: true),
                const SizedBox(height: 16),

                // Payment buttons
                Row(
                  children: [
                    _paymentButton(
                      'Cash',
                      Icons.payments_rounded,
                      AppColors.success,
                      () => _completeBill('CASH', total, cart, user),
                    ),
                    const SizedBox(width: 8),
                    _paymentButton(
                      'UPI',
                      Icons.qr_code_rounded,
                      AppColors.info,
                      () => _completeBill('UPI', total, cart, user),
                    ),
                    const SizedBox(width: 8),
                    _paymentButton(
                      'Card',
                      Icons.credit_card_rounded,
                      AppColors.warning,
                      () => _completeBill('CARD', total, cart, user),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 200.ms),
      ],
    );
  }

  Widget _totalRow(
    String label,
    double amount,
    bool isDark, {
    bool isBold = false,
    bool isNeg = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
            '${isNeg ? "-" : ""}₹${amount.abs().toStringAsFixed(0)}',
            style: GoogleFonts.inter(
              fontSize: isBold ? 18 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              color: isNeg
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

  Widget _paymentButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Future<void> _completeBill(
    String paymentMode,
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
        subtotal: subtotal,
        discountAmount: discountAmount,
        totalAmount: total,
        paymentMode: paymentMode,
        billItems: cart
            .map(
              (ci) => {
                'item_id': ci.item.id,
                'qty': ci.qty,
                'rate': ci.rate,
                'tax_percentage': 0,
              },
            )
            .toList(),
      );

      ref.read(cartProvider.notifier).clear();
      ref.read(discountProvider.notifier).reset();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Bill created • ₹${total.toStringAsFixed(0)} via $paymentMode',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─── MOBILE BILLING BAR ───────────────────────────────-
  Widget _buildMobileBillingBar(List<CartItem> cart, bool isDark) {
    final total = cart.fold<double>(0, (sum, ci) => sum + ci.total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.lightSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${cart.length} items',
                  style: GoogleFonts.inter(fontSize: 12),
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
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _showMobileCheckout(cart, isDark),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('View Bill'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMobileCheckout(List<CartItem> cart, bool isDark) {
    // Show fullscreen bottom sheet for mobile checkout
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          final user = ref.watch(authStateProvider).value;
          if (user == null) return const SizedBox.shrink();
          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: _buildBillingPanel(
              cart,
              ref.read(cartProvider.notifier),
              isDark,
              user,
            ),
          );
        },
      ),
    );
  }
}
