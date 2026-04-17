import 'package:cafe/core/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Tables management screen
class TablesScreen extends ConsumerStatefulWidget {
  final String companyId;
  const TablesScreen({super.key, required this.companyId});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  CafeTable? _selectedTable;
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tablesAsync = ref.watch(tablesProvider(widget.companyId));
    final user = ref.watch(authStateProvider).value;
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 800;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
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
                      IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                      const SizedBox(width: 4),
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
                            ref.invalidate(tablesProvider(widget.companyId)),
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
                        return _buildEmptyState(isDark);
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 6 : 3,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: tables.length,
                        itemBuilder: (context, index) {
                          final table = tables[index];
                          final isSelected = _selectedTable?.id == table.id;

                          return _TableCard(
                                table: table,
                                isDark: isDark,
                                isSelected: isSelected,
                                onTap: () {
                                  setState(() => _selectedTable = table);
                                },
                              )
                              .animate()
                              .fadeIn(
                                delay: Duration(milliseconds: 30 * index),
                                duration: 400.ms,
                              )
                              .scale(
                                begin: const Offset(0.9, 0.9),
                                curve: Curves.easeOutBack,
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

            // Quick Order Side Panel
            if (_selectedTable != null)
              _buildQuickOrderPanel(size, isDark, isTablet, user),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
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

  Widget _buildQuickOrderPanel(
    Size size,
    bool isDark,
    bool isTablet,
    UserProfile? user,
  ) {
    final allItemsAsync = ref.watch(allItemsProvider(widget.companyId));
    final cart = ref.watch(cartProvider(_selectedTable?.id));
    final cartNotifier = ref.read(cartProvider(_selectedTable?.id).notifier);

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Hero(
        tag: 'quickOrderPanel',
        child: Container(
          width: isTablet ? 450 : size.width * 0.9,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 40,
                offset: const Offset(-10, 0),
              ),
            ],
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              bottomLeft: Radius.circular(32),
            ),
            border: Border(
              left: BorderSide(
                color: isDark
                    ? AppColors.darkBorder.withValues(alpha: 0.2)
                    : AppColors.lightBorder.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            children: [
              // Panel Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 20, 10),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Order',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Table: ${_selectedTable?.tableName}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (cart.isNotEmpty)
                      TextButton(
                        onPressed: () => ref
                            .read(cartProvider(_selectedTable?.id).notifier)
                            .clear(),
                        child: Text(
                          'Clear',
                          style: GoogleFonts.inter(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          _selectedTable = null;
                          _selectedCategory = null;
                        });
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                  ],
                ),
              ),

              // Item Browser
              Expanded(
                child: allItemsAsync.when(
                  data: (items) {
                    // Get categories for chips
                    final categories = items
                        .map((i) => i.sectionLabel)
                        .whereType<String>()
                        .toSet()
                        .toList();
                    categories.sort();

                    // Filter items by category first
                    final filteredItems = _selectedCategory == null
                        ? items
                        : items
                              .where((i) => i.sectionLabel == _selectedCategory)
                              .toList();

                    // Flatten filtered items + variants
                    final List<Map<String, dynamic>> flatList = [];
                    for (final item in filteredItems) {
                      if (!item.hasVariants || item.variants.isEmpty) {
                        flatList.add({'master': item, 'variant': null});
                      } else {
                        for (final v in item.variants) {
                          flatList.add({'master': item, 'variant': v});
                        }
                      }
                    }

                    return Column(
                      children: [
                        // Quick Categories
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              _buildPanelCategoryChip(
                                'All',
                                _selectedCategory == null,
                                isDark,
                                () => setState(() => _selectedCategory = null),
                              ),
                              const SizedBox(width: 8),
                              ...categories.map(
                                (s) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _buildPanelCategoryChip(
                                    s,
                                    _selectedCategory == s,
                                    isDark,
                                    () => setState(() => _selectedCategory = s),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Grid
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 0.78,
                                ),
                            itemCount: flatList.length,
                            itemBuilder: (context, index) {
                              final master = flatList[index]['master'] as Item;
                              final variant =
                                  flatList[index]['variant'] as ItemVariant?;

                              // Calculate quantity in cart
                              final cartCount = cart
                                  .firstWhere(
                                    (ci) =>
                                        ci.item.id == master.id &&
                                        ci.variant?.id == variant?.id,
                                    orElse: () => CartItem(
                                      item: master,
                                      variant: variant,
                                      qty: 0,
                                    ),
                                  )
                                  .qty;

                              return _CompactItemTile(
                                    master: master,
                                    variant: variant,
                                    isDark: isDark,
                                    cartCount: cartCount,
                                    onTap: () {
                                      cartNotifier.addItem(master, variant);
                                    },
                                  )
                                  .animate()
                                  .fadeIn(delay: (20 * index).ms)
                                  .scale(
                                    begin: const Offset(0.9, 0.9),
                                    duration: 200.ms,
                                  );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ),

              // Cart Summary & Action
              if (cart.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${cart.length} items selected',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₹${cart.fold(0.0, (sum, ci) => sum + ci.total).toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppColors.primaryAmber
                                  : AppColors.primaryOrange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _showTableBillingSheet(
                            context,
                            ref,
                            _selectedTable!,
                            cart,
                            user!,
                          ),
                          child: const Text(
                            'CHECKOUT & BILL',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().slideY(
                  begin: 1.0,
                  duration: 300.ms,
                  curve: Curves.easeOutCubic,
                ),
            ],
          ),
        ),
      ).animate().slideX(begin: 1.0, duration: 400.ms, curve: Curves.easeOutQuart),
    );
  }

  Widget _buildPanelCategoryChip(
    String label,
    bool isSelected,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted),
          ),
        ),
      ),
    );
  }

  void _showTableBillingSheet(
    BuildContext context,
    WidgetRef ref,
    CafeTable table,
    List<CartItem> cart,
    UserProfile user,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _TableBillingSheet(table: table, cart: cart, user: user),
    );
  }
}

class _TableCard extends StatelessWidget {
  final CafeTable table;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;

  const _TableCard({
    required this.table,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  Color get _statusColor {
    switch (table.status) {
      case 'FREE':
        return AppColors.success;
      case 'OCCUPIED':
        return AppColors.error;
      case 'RESERVED':
        return AppColors.primaryAmber;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                      .withValues(alpha: 0.1)
                : (isDark ? AppColors.darkCard : AppColors.lightCard),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected
                  ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                  : _statusColor.withValues(alpha: 0.2),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color:
                      (isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange)
                          .withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.table_restaurant_rounded,
                    size: 24,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  table.tableName,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      size: 9,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${table.seatingCapacity} Seats',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    table.status,
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: _statusColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactItemTile extends StatelessWidget {
  final Item master;
  final ItemVariant? variant;
  final bool isDark;
  final int cartCount;
  final VoidCallback onTap;

  const _CompactItemTile({
    required this.master,
    this.variant,
    required this.isDark,
    required this.cartCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        (variant == null || variant!.variantName.toLowerCase() == 'default')
        ? master.itemName
        : variant!.variantName;
    final price = variant?.baseRate ?? master.baseRate;
    final imageUrl = variant?.imageUrl ?? master.imageUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cartCount > 0
                  ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                  : (isDark
                        ? AppColors.darkBorder.withValues(alpha: 0.1)
                        : AppColors.lightBorder.withValues(alpha: 0.2)),
              width: cartCount > 0 ? 1.5 : 1,
            ),
            boxShadow: [
              if (cartCount > 0)
                BoxShadow(
                  color:
                      (isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange)
                          .withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.fastfood),
                              )
                            : const Icon(Icons.fastfood, color: Colors.grey),
                      ),
                    ),
                    if (cartCount > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            '$cartCount',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '₹${price.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.primaryAmber
                      : AppColors.primaryOrange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableBillingSheet extends ConsumerStatefulWidget {
  final CafeTable table;
  final List<CartItem> cart;
  final UserProfile user;

  const _TableBillingSheet({
    required this.table,
    required this.cart,
    required this.user,
  });

  @override
  ConsumerState<_TableBillingSheet> createState() => _TableBillingSheetState();
}

class _TableBillingSheetState extends ConsumerState<_TableBillingSheet> {
  String _paymentMode = 'CASH';
  bool _isProcessing = false;

  Future<void> _completeTableBill() async {
    setState(() => _isProcessing = true);
    final subtotal = widget.cart.fold<double>(0, (sum, ci) => sum + ci.total);
    final discount = ref.read(discountProvider);
    final discountAmount = subtotal * (discount / 100);
    final total = subtotal - discountAmount;

    try {
      // 1. Create or Get Table Session
      final session = await SupabaseService.createOrder(
        companyId: widget.user.companyId,
        tableId: widget.table.id,
      );

      // 2. Create Bill
      await SupabaseService.createBill(
        companyId: widget.user.companyId,
        billedBy: widget.user.id,
        tableSessionId: session['id'],
        subtotal: subtotal,
        discountAmount: discountAmount,
        discountType: 'percent',
        totalAmount: total,
        paymentMode: _paymentMode,
        billType: 'dine_in',
        billItems: widget.cart
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

      // 3. Clear Table Cart
      ref.read(cartProvider(widget.table.id).notifier).clear();
      ref.read(discountProvider.notifier).reset();

      if (mounted) {
        Navigator.pop(context); // Close sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bill created for ${widget.table.tableName} • ₹${total.toStringAsFixed(0)}',
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
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtotal = widget.cart.fold<double>(0, (sum, ci) => sum + ci.total);
    final discount = ref.watch(discountProvider);
    final discountAmount = subtotal * (discount / 100);
    final total = subtotal - discountAmount;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Finalize Bill',
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Table ${widget.table.tableName}',
            style: GoogleFonts.inter(
              color: AppColors.primaryOrange,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Divider(height: 48),
          _summaryRow('Subtotal', subtotal),
          if (discount > 0)
            _summaryRow('Discount ($discount%)', -discountAmount, isNeg: true),
          const SizedBox(height: 12),
          _summaryRow('Total Amount', total, isBold: true),
          const SizedBox(height: 32),
          Row(
            children: [
              _payModeBtn('CASH', Icons.payments_rounded),
              const SizedBox(width: 12),
              _payModeBtn('UPI', Icons.qr_code_rounded),
              const SizedBox(width: 12),
              _payModeBtn('CARD', Icons.credit_card_rounded),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _completeTableBill,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'COMPLETE PAYMENT & CLOSE TABLE',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    double amount, {
    bool isBold = false,
    bool isNeg = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isBold ? 18 : 14,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
          Text(
            '₹${amount.abs().toStringAsFixed(0)}',
            style: GoogleFonts.inter(
              fontSize: isBold ? 20 : 14,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              color: isNeg ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payModeBtn(String mode, IconData icon) {
    final isSelected = _paymentMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryOrange.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryOrange
                  : Colors.grey.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primaryOrange : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                mode,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.primaryOrange : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
