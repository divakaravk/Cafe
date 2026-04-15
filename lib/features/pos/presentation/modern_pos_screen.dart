import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/pos_widgets.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../admin/presentation/company_master_screen.dart';
import '../../admin/presentation/user_master_screen.dart';
import '../../admin/presentation/item_master_screen.dart';

/// Modern POS Screen — Tablet-first split layout
/// Left: Item categories + grid | Right: sticky billing panel
class ModernPosScreen extends ConsumerStatefulWidget {
  const ModernPosScreen({super.key});

  @override
  ConsumerState<ModernPosScreen> createState() => _ModernPosScreenState();
}

class _ModernPosScreenState extends ConsumerState<ModernPosScreen>
    with TickerProviderStateMixin {
  String? _selectedSection;
  Item? _selectedItem;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _showBillingPanel = true;
  bool _isGroupsOn = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Cart Animation State
  String? _lastAddedItemName;
  bool _showCartAnimation = false;
  bool _isCartExpanded = false;
  DateTime? _lastAddEvent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  Future<void> _loadSettings() async {
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      final company = await ref.read(companyProvider(user.companyId).future);
      if (company != null) {
        setState(() => _isGroupsOn = company.hasItemVariants);
      }
    }
  }

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
      key: _scaffoldKey,
      body: Stack(
        children: [
          Row(
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
                    // Navigation Bar - section chips (Groups OFF) or item group chips (Groups ON)
                    itemGroupsAsync.when(
                      data: (items) => _isGroupsOn
                          ? _buildItemGroupNav(items, isDark)
                          : const SizedBox.shrink(),
                      loading: () => _isGroupsOn
                          ? const SizedBox(height: 56)
                          : const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    // Menu area
                    Expanded(
                      child: itemGroupsAsync.when(
                        data: (items) => _buildMenuArea(
                          items,
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
                    // Mobile Bottom Panel
                    if (!isTablet && cart.isNotEmpty)
                      _buildMobileOrderPanel(cart, isDark),
                  ],
                ),
              ),

              // ─── RIGHT: Billing Panel ──────────────────────
              if (isTablet && _showBillingPanel)
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity > 300) {
                      // Swipe right → close billing panel
                      setState(() => _showBillingPanel = false);
                    } else if (velocity < -300) {
                      // Swipe left → open drawer
                      _scaffoldKey.currentState?.openDrawer();
                    }
                  },
                  child: Container(
                    width: 360,
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
                    child: _buildBillingPanel(cart, cartNotifier, isDark, user),
                  ),
                ).animate().slideX(begin: 1.0, end: 0.0, duration: 200.ms),
            ],
          ),
          // Toggle arrows
          _buildSideToggles(isTablet),

          // Swiggy Cart Animation Overlay
          if (_showCartAnimation) _buildCartAnimationOverlay(cart, isDark),
        ],
      ),
      // Bottom sheet billing for mobile
      bottomSheet: !isTablet && cart.isNotEmpty
          ? _buildMobileOrderPanel(cart, isDark)
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
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            const SizedBox(width: 8),
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
              onPressed: () => ref.read(isDarkModeProvider.notifier).toggle(),
            ),
            // Item Groups Toggle (Hidden if company doesn't use variants)
            if (ref
                    .watch(companyProvider(user.companyId))
                    .value
                    ?.hasItemVariants ??
                false) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Groups',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: _isGroupsOn,
                      activeColor: AppColors.primaryAmber,
                      onChanged: (v) => setState(() {
                        _isGroupsOn = v;
                        _selectedItem = null;
                        _selectedSection =
                            null; // Clear category filter when flipping mode
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ─── SIDE TOGGLES ───────────────────────────────────────
  Widget _buildSideToggles(bool isTablet) {
    return Stack(
      children: [
        // Left Edge Toggle (Open Drawer)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: Container(
                height: 60,
                width: 14,
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.9),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: Icon(Icons.menu_rounded, color: Colors.white, size: 14),
              ),
            ),
          ),
        ),
        // Right Edge Toggle (Billing Panel)
        if (isTablet)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTap: () =>
                    setState(() => _showBillingPanel = !_showBillingPanel),
                child: Container(
                  height: 60,
                  width: 14,
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(-2, 0),
                      ),
                    ],
                  ),
                  child: Icon(
                    _showBillingPanel
                        ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
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

  // ─── TOP CATEGORY NAVIGATION (Groups OFF — section labels) ─────
  Widget _buildTopCategoryNav(List<Item> items, bool isDark) {
    final sections = items
        .map((i) => i.sectionLabel)
        .where((s) => s != null)
        .toSet()
        .toList();
    sections.sort();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ItemCategoryChip(
            label: 'All',
            isSelected: _selectedSection == null,
            onTap: () => setState(() {
              _selectedSection = null;
              _selectedItem = null;
            }),
          ),
          ...sections.map(
            (s) => ItemCategoryChip(
              label: s!,
              isSelected: _selectedSection == s,
              onTap: () => setState(() {
                _selectedSection = s;
                _selectedItem = null;
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ─── ITEM GROUP NAVIGATION (Groups ON — master items with variants) ─────
  Widget _buildItemGroupNav(List<Item> items, bool isDark) {
    // Only show items that have variants as "groups"
    final groups = items
        .where((i) => i.hasVariants && i.variants.isNotEmpty)
        .toList();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ItemCategoryChip(
            label: 'All',
            isSelected: _selectedItem == null,
            onTap: () => setState(() => _selectedItem = null),
          ),
          ...groups.map(
            (g) => ItemCategoryChip(
              label: g.itemName,
              isSelected: _selectedItem?.id == g.id,
              onTap: () => setState(() => _selectedItem = g),
            ),
          ),
        ],
      ),
    );
  }

  // ─── MENU AREA ──────────────────────────────────────────
  Widget _buildMenuArea(
    List<Item> masterItems,
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
    bool isTablet,
  ) {
    if (!_isGroupsOn) {
      // FLAT VIEW — show all items + variants flattened
      return _buildVariantGrid(
        masterItems,
        cart,
        cartNotifier,
        isDark,
        isTablet,
      );
    }

    // GROUPED VIEW
    if (_selectedItem != null) {
      // A specific group is selected → show its variants
      return _buildDrillDownVariants(
        _selectedItem!,
        cart,
        cartNotifier,
        isDark,
        isTablet,
      );
    }

    // No group selected → show all parent item groups as tiles
    return _buildGroupGrid(masterItems, cart, cartNotifier, isDark, isTablet);
  }

  // ─── Phase 1: Parent Item Grid ──────────────────────────
  Widget _buildGroupGrid(
    List<Item> masterItems,
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
    bool isTablet,
  ) {
    // Filter master items by section
    final filteredMasters = masterItems.where((i) {
      final matchesSection =
          _selectedSection == null || i.sectionLabel == _selectedSection;
      final matchesSearch =
          _searchQuery.isEmpty ||
          i.itemName.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSection && matchesSearch;
    }).toList();

    if (filteredMasters.isEmpty) return _buildEmptyState(isDark);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 6 : 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: filteredMasters.length,
      itemBuilder: (context, index) {
        final item = filteredMasters[index];
        final isInCart = cart.any((ci) => ci.item.id == item.id);

        return ItemGridTile(
              item: item,
              isInCart: isInCart,
              onTap: () {
                if (item.hasVariants && item.variants.isNotEmpty) {
                  setState(() => _selectedItem = item);
                } else {
                  _triggerCartAnimation(item, null);
                }
              },
            )
            .animate()
            .fadeIn(delay: (20 * index).ms)
            .scale(begin: const Offset(0.9, 0.9));
      },
    );
  }

  // ─── Phase 2: Variants Grid for selected item group ─────
  Widget _buildDrillDownVariants(
    Item master,
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
    bool isTablet,
  ) {
    final variants = master.variants.where((v) {
      return _searchQuery.isEmpty ||
          v.variantName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (variants.isEmpty) return _buildEmptyState(isDark);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 6 : 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: variants.length,
      itemBuilder: (context, index) {
        final v = variants[index];
        final cartItem = cart.firstWhere(
          (ci) => ci.item.id == master.id && ci.variant?.id == v.id,
          orElse: () => CartItem(item: master, variant: v, qty: 0),
        );

        return SimpleVariantTile(
              name: v.variantName,
              price: v.baseRate,
              foodType: master.foodType,
              imageUrl: v.imageUrl ?? master.imageUrl,
              cartCount: cartItem.qty,
              isAvailable: v.isActive,
              onTap: () => _triggerCartAnimation(master, v),
            )
            .animate()
            .fadeIn(delay: (20 * index).ms)
            .scale(begin: const Offset(0.9, 0.9));
      },
    );
  }

  // ─── VARIANT GRID (Consolidated All & Category view) ────
  Widget _buildVariantGrid(
    List<Item> masterItems,
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
    bool isTablet,
  ) {
    final isAllMode = _selectedSection == null;

    // Flatten items + variants based on selection
    final List<Map<String, dynamic>> flatList = [];

    final itemsToFlatten = isAllMode
        ? masterItems
        : masterItems.where((i) => i.sectionLabel == _selectedSection).toList();

    for (final item in itemsToFlatten) {
      if (!item.hasVariants || item.variants.isEmpty) {
        flatList.add({'master': item, 'variant': null});
      } else {
        for (final v in item.variants) {
          flatList.add({'master': item, 'variant': v});
        }
      }
    }

    // Filter by search
    final filteredList = flatList.where((entry) {
      final master = entry['master'] as Item;
      final variant = entry['variant'] as ItemVariant?;
      final fullName = variant != null
          ? '${master.itemName} ${variant.variantName}'
          : master.itemName;
      return _searchQuery.isEmpty ||
          fullName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (filteredList.isEmpty) return _buildEmptyState(isDark);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 6 : 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        final entry = filteredList[index];
        final master = entry['master'] as Item;
        final variant = entry['variant'] as ItemVariant?;

        final cartItem = cart.firstWhere(
          (ci) => ci.item.id == master.id && ci.variant?.id == variant?.id,
          orElse: () => CartItem(item: master, variant: variant, qty: 0),
        );

        final displayName = variant?.variantName ?? master.itemName;

        return SimpleVariantTile(
              name: displayName,
              price: variant?.baseRate ?? master.baseRate,
              foodType: master.foodType,
              imageUrl: variant?.imageUrl ?? master.imageUrl,
              cartCount: cartItem.qty,
              isAvailable: variant?.isActive ?? master.isActive,
              onTap: () => _triggerCartAnimation(master, variant),
            )
            .animate()
            .fadeIn(delay: (20 * index).ms)
            .scale(begin: const Offset(0.9, 0.9));
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.restaurant_menu_rounded,
            size: 48,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
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
              IconButton(
                icon: const Icon(Icons.menu_rounded, size: 20),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
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
                      onIncrement: () =>
                          cartNotifier.incrementQty(ci.item.id, ci.variant?.id),
                      onDecrement: () =>
                          cartNotifier.decrementQty(ci.item.id, ci.variant?.id),
                      onRemove: () =>
                          cartNotifier.removeItem(ci.item.id, ci.variant?.id),
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
  Widget _buildMobileOrderPanel(List<CartItem> cart, bool isDark) {
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

  // ─── CART ANIMATION TRIGGER ────────────────────────────
  void _triggerCartAnimation(Item item, ItemVariant? variant) {
    final cartNotifier = ref.read(cartProvider.notifier);
    cartNotifier.addItem(item, variant);

    final now = DateTime.now();
    _lastAddEvent = now;
    final displayName = variant?.variantName ?? item.itemName;

    setState(() {
      _lastAddedItemName = displayName;
      _showCartAnimation = true;
      _isCartExpanded = false;
    });

    // Sequence:
    // 1. Move into view (handled by flutter_animate automatically via build)
    // 2. Wait 400ms then expand
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_lastAddEvent == now && mounted) {
        setState(() => _isCartExpanded = true);
      }
    });

    // 3. Hide after 3 seconds
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (_lastAddEvent == now && mounted) {
        setState(() => _showCartAnimation = false);
      }
    });
  }

  Widget _buildCartAnimationOverlay(List<CartItem> cart, bool isDark) {
    if (cart.isEmpty) return const SizedBox.shrink();

    final totalQty = cart.fold<int>(0, (sum, ci) => sum + ci.qty);
    final subtotal = cart.fold<double>(0, (sum, ci) => sum + ci.total);

    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child:
            AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryAmber, AppColors.primaryOrange],
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryOrange.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Main row (Always visible)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_basket_rounded,
                              color: AppColors.primaryOrange,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Added ${_lastAddedItemName ?? 'Item'}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),

                      // Expanded content
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: _isCartExpanded
                            ? Container(
                                padding: const EdgeInsets.only(top: 12),
                                margin: const EdgeInsets.only(top: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$totalQty ITEMS IN CART',
                                          style: GoogleFonts.inter(
                                            color: Colors.white.withValues(
                                              alpha: 0.8,
                                            ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        Text(
                                          '₹${subtotal.toStringAsFixed(0)} total',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 30),
                                    Text(
                                      'VIEW CART',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      color: Colors.white,
                                      size: 10,
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                )
                .animate()
                .slideY(
                  begin: 1.5,
                  end: 0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: const Duration(milliseconds: 300))
                .shimmer(
                  delay: const Duration(milliseconds: 600),
                  duration: const Duration(milliseconds: 1000),
                ),
      ),
    );
  }
}
