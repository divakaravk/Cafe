import 'package:cafe/core/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/services/local_parser_service.dart';

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

  // Voice AI State
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _isProcessingAI = false;
  bool _isVoiceAIEnabled = false;
  String _lastWords = '';
  final _localParser = LocalParserService();
  bool _showCartTab = false; // Toggle between Item Grid and Cart View

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _startListening() async {
    await _speechToText.listen(onResult: _onSpeechResult);
    setState(() => _isListening = true);
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
      if (_lastWords.isNotEmpty && _isVoiceAIEnabled) {
        _processVoiceOrder(_lastWords);
      }
    });
  }

  void _onSpeechResult(result) {
    debugPrint('Speech result: ${result.recognizedWords}');
    setState(() {
      _lastWords = result.recognizedWords;
    });
  }

  Future<void> _processVoiceOrder(String text) async {
    if (text.isEmpty) return;
    setState(() => _isProcessingAI = true);

    try {
      final itemsAsync = ref.read(allItemsProvider(widget.companyId));
      final items = itemsAsync.value ?? [];

      final orders = _localParser.parseOrder(text, items);

      if (orders.isNotEmpty) {
        _applyVoiceOrderToCart(orders, items);
      }
    } finally {
      if (mounted) setState(() => _isProcessingAI = false);
    }
  }

  void _applyVoiceOrderToCart(List<dynamic> orders, List<Item> items) {
    try {
      final tableId = _selectedTable?.id;
      if (tableId == null) return;

      final cartNotifier = ref.read(cartProvider(tableId).notifier);

      for (final order in orders) {
        final itemName = (order['item'] as String).toLowerCase().trim();
        final qty = (order['qty'] as num).toInt();

        // Find Best Match
        Item? matchedItem;
        ItemVariant? matchedVariant;

        for (final item in items) {
          if (item.itemName.toLowerCase().trim() == itemName) {
            matchedItem = item;
            break;
          }
          // Check variants
          if (item.hasVariants) {
            for (final v in item.variants) {
              if (v.variantName.toLowerCase().trim() == itemName ||
                  "${item.itemName} ${v.variantName}".toLowerCase().trim() ==
                      itemName) {
                matchedItem = item;
                matchedVariant = v;
                break;
              }
            }
          }
          if (matchedItem != null) break;
        }

        // If no exact match, try simple contains fuzzy match
        if (matchedItem == null) {
          for (final item in items) {
            if (item.itemName.toLowerCase().contains(itemName) ||
                itemName.contains(item.itemName.toLowerCase())) {
              matchedItem = item;
              break;
            }
          }
        }

        if (matchedItem != null) {
          for (int i = 0; i < qty; i++) {
            cartNotifier.addItem(matchedItem, matchedVariant);
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI added ${orders.length} items to cart'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Cart parse error: $e');
    }
  }

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
                        padding: EdgeInsets.all(isTablet ? 20 : 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 3 : 2,
                          childAspectRatio: isTablet ? 1.8 : 1.25,
                          crossAxisSpacing: isTablet ? 16 : 12,
                          mainAxisSpacing: isTablet ? 16 : 12,
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
          width: isTablet ? 450 : size.width,
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
                child: Column(
                  children: [
                    Row(
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
                        Switch(
                          value: _isVoiceAIEnabled,
                          activeColor: AppColors.primaryAmber,
                          onChanged: (val) =>
                              setState(() => _isVoiceAIEnabled = val),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            setState(() {
                              _selectedTable = null;
                              _selectedCategory = null;
                              _showCartTab = false;
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
                    const SizedBox(height: 16),
                    // View Toggle (Browse vs Cart)
                    Row(
                      children: [
                        _buildTabButton(
                          'Items',
                          !_showCartTab,
                          isDark,
                          () => setState(() => _showCartTab = false),
                        ),
                        const SizedBox(width: 8),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildTabButton(
                              'Cart',
                              _showCartTab,
                              isDark,
                              () => setState(() => _showCartTab = true),
                            ),
                            if (cart.isNotEmpty)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryOrange,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Text(
                                    '${cart.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Item Browser / Cart View
              Expanded(
                child: _showCartTab
                    ? _buildCartView(cart, cartNotifier, isDark)
                    : Stack(
                        children: [
                          allItemsAsync.when(
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
                                        .where(
                                          (i) =>
                                              i.sectionLabel ==
                                              _selectedCategory,
                                        )
                                        .toList();

                              // Flatten filtered items + variants
                              final List<Map<String, dynamic>> flatList = [];
                              for (final item in filteredItems) {
                                if (!item.hasVariants ||
                                    item.variants.isEmpty) {
                                  flatList.add({
                                    'master': item,
                                    'variant': null,
                                  });
                                } else {
                                  for (final v in item.variants) {
                                    flatList.add({
                                      'master': item,
                                      'variant': v,
                                    });
                                  }
                                }
                              }

                              return Column(
                                children: [
                                  // Quick Categories
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isTablet ? 20 : 12,
                                      vertical: isTablet ? 10 : 8,
                                    ),
                                    child: Row(
                                      children: [
                                        _buildPanelCategoryChip(
                                          'All',
                                          _selectedCategory == null,
                                          isDark,
                                          isTablet,
                                          () => setState(
                                            () => _selectedCategory = null,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ...categories.map(
                                          (s) => Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: _buildPanelCategoryChip(
                                              s,
                                              _selectedCategory == s,
                                              isDark,
                                              isTablet,
                                              () => setState(
                                                () => _selectedCategory = s,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Grid
                                  Expanded(
                                    child: GridView.builder(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isTablet ? 20 : 12,
                                      ),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: isTablet ? 3 : 2,
                                            crossAxisSpacing: isTablet ? 10 : 8,
                                            mainAxisSpacing: isTablet ? 10 : 8,
                                            childAspectRatio: isTablet ? 0.78 : 0.85,
                                          ),
                                      itemCount: flatList.length,
                                      itemBuilder: (context, index) {
                                        final master =
                                            flatList[index]['master'] as Item;
                                        final variant =
                                            flatList[index]['variant']
                                                as ItemVariant?;

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
                                                cartNotifier.addItem(
                                                  master,
                                                  variant,
                                                );
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
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, _) => Center(child: Text('Error: $e')),
                          ),

                          // Floating Microphone Button
                          if (_isVoiceAIEnabled)
                            Positioned(
                              right: 20,
                              bottom: 20,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isProcessingAI)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: CircularProgressIndicator(
                                        color: AppColors.primaryAmber,
                                      ),
                                    )
                                  else if (_isListening)
                                    Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            'Listening...',
                                            style: GoogleFonts.inter(
                                              color: AppColors.error,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                        .animate(
                                          onPlay: (controller) =>
                                              controller.repeat(),
                                        )
                                        .fadeOut(duration: 800.ms)
                                        .fadeIn(duration: 800.ms),

                                  FloatingActionButton(
                                        heroTag: null,
                                        onPressed: _isListening
                                            ? _stopListening
                                            : _startListening,
                                        backgroundColor: _isListening
                                            ? AppColors.error
                                            : AppColors.primaryOrange,
                                        elevation: 8,
                                        child: Icon(
                                          _isListening ? Icons.stop : Icons.mic,
                                        ),
                                      )
                                      .animate(target: _isListening ? 1 : 0)
                                      .scale(
                                        begin: const Offset(1, 1),
                                        end: const Offset(1.1, 1.1),
                                        duration: 500.ms,
                                      ),
                                ],
                              ),
                            ),
                        ],
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
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: isDark
                                        ? AppColors.primaryAmber
                                        : AppColors.primaryOrange,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: _saveOrder,
                                child: Text(
                                  'SAVE ORDER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.primaryAmber
                                        : AppColors.primaryOrange,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
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
                                  'CHECKOUT',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildCartView(
    List<CartItem> cart,
    CartNotifier cartNotifier,
    bool isDark,
  ) {
    final isTablet = MediaQuery.of(context).size.width > 800;

    if (cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: isTablet ? 48 : 40,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'Your cart is empty',
              style: GoogleFonts.inter(
                fontSize: isTablet ? 14 : 13,
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
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 20 : 12,
        vertical: isTablet ? 10 : 8,
      ),
      itemCount: cart.length,
      itemBuilder: (context, index) {
        final ci = cart[index];
        return Container(
          margin: EdgeInsets.only(bottom: isTablet ? 12 : 8),
          padding: EdgeInsets.all(isTablet ? 16 : 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? AppColors.darkBorder.withValues(alpha: 0.1)
                  : AppColors.lightBorder.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ci.item.itemName,
                      style: GoogleFonts.inter(
                        fontSize: isTablet ? 15 : 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (ci.variant != null &&
                        ci.variant!.variantName.toLowerCase() != 'default')
                      Text(
                        ci.variant!.variantName,
                        style: GoogleFonts.inter(
                          fontSize: isTablet ? 12 : 11,
                          color: isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${ci.rate.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                        fontSize: isTablet ? 13 : 12,
                        color: isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _buildQtyButton(
                    Icons.remove_rounded,
                    () => cartNotifier.decrementQty(ci.item.id, ci.variant?.id),
                    isDark,
                    isTablet,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 8),
                    child: Text(
                      '${ci.qty}',
                      style: GoogleFonts.inter(
                        fontSize: isTablet ? 16 : 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _buildQtyButton(
                    Icons.add_rounded,
                    () => cartNotifier.incrementQty(ci.item.id, ci.variant?.id),
                    isDark,
                    isTablet,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: isTablet ? 20 : 18),
                    color: AppColors.error,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () =>
                        cartNotifier.removeItem(ci.item.id, ci.variant?.id),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(delay: (50 * index).ms).slideX(begin: 0.1);
      },
    );
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onTap, bool isDark, bool isTablet) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.all(isTablet ? 6 : 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: isTablet ? 18 : 20),
      ),
    );
  }

  Widget _buildTabButton(
    String label,
    bool isSelected,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.2)
                      : AppColors.lightBorder.withValues(alpha: 0.2)),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelCategoryChip(
    String label,
    bool isSelected,
    bool isDark,
    bool isTablet,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 16 : 12,
          vertical: isTablet ? 8 : 6,
        ),
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
            fontSize: isTablet ? 12 : 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted),
          ),
        ),
      ),
    );
  }

  Future<void> _saveOrder() async {
    if (_selectedTable == null) return;
    final cart = ref.read(cartProvider(_selectedTable!.id));
    if (cart.isEmpty) return;

    setState(
      () => _isProcessingAI = true,
    ); // Using this as a generic loading state

    try {
      // 1. Create or get table session
      // For now, we'll use a simplified logic to 'occupy' the table
      // In a full implementation, we'd create a table_session and bill_master/bill_items in 'open' status

      // Placeholder for actual database call
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order saved for ${_selectedTable?.tableName}'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _selectedTable = null;
          _showCartTab = false;
        });
      }
    } catch (e, st) {
      debugPrint('SAVE_ORDER_ERROR: $e');
      debugPrint(st.toString());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving order: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessingAI = false);
    }
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

class _TableCard extends ConsumerWidget {
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

  Color _statusBgColor(String status) {
    switch (status) {
      case 'OCCUPIED':
        return AppColors.error.withValues(alpha: 0.1);
      case 'RESERVED':
        return AppColors.primaryAmber.withValues(alpha: 0.1);
      default:
        return AppColors.success.withValues(alpha: 0.1);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
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

  String get _sizeLabel {
    if (table.seatingCapacity <= 4) return 'Small';
    if (table.seatingCapacity <= 6) return 'Medium';
    return 'Large';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 800;

    final cart = ref.watch(cartProvider(table.id));
    final hasItems = cart.isNotEmpty;
    final status = hasItems ? 'OCCUPIED' : table.status;
    final totalAmount = cart.fold<double>(0, (sum, ci) => sum + ci.total);

    final statusBgColor = _statusBgColor(status);
    final statusColor = _statusColor(status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? (isSelected
                        ? AppColors.primaryAmber.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1))
                  : (isSelected
                        ? AppColors.primaryOrange.withValues(alpha: 0.5)
                        : Colors.black.withValues(alpha: 0.05)),
              width: isSelected ? 1.5 : 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.02),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.6),
                      Colors.white.withValues(alpha: 0.3),
                    ],
            ),
          ),
          child: Stack(
            children: [
              // Inner Rim Highlight for depth
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white.withValues(alpha: 0.8),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(isTablet ? 14 : 10),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Table Icon Section
                        _buildTableIcon(table, isDark, status == 'OCCUPIED'),
                        const Spacer(),
                        // Status Badge
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 14 : 8,
                            vertical: isTablet ? 7 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.1),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: isTablet ? 6 : 4,
                                height: isTablet ? 6 : 4,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: isTablet ? 8 : 4),
                              Text(
                                status == 'FREE' ? 'Available' : status,
                                style: GoogleFonts.inter(
                                  fontSize: isTablet ? 10 : 8,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Bottom row with Details
                    Row(
                      children: [
                        _buildDetailLabel(_sizeLabel.toUpperCase(), isDark, isTablet),
                        _buildSeparator(isDark, isTablet),
                        _buildDetailLabel(
                          '${table.seatingCapacity} PAX',
                          isDark,
                          isTablet,
                        ),
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 10 : 6,
                            vertical: isTablet ? 4 : 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (isDark
                                        ? AppColors.primaryAmber
                                        : AppColors.primaryOrange)
                                    .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '₹${totalAmount.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: isTablet ? 15 : 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: isDark
                                  ? AppColors.primaryAmber
                                  : AppColors.primaryOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildSeparator(bool isDark, bool isTablet) {
  return Container(
    width: isTablet ? 3 : 2,
    height: isTablet ? 3 : 2,
    margin: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 6),
    decoration: BoxDecoration(
      color: isDark ? Colors.white24 : Colors.black12,
      shape: BoxShape.circle,
    ),
  );
}

Widget _buildDetailLabel(String text, bool isDark, bool isTablet) {
  return Text(
    text,
    style: GoogleFonts.inter(
      fontSize: isTablet ? 12 : 9,
      fontWeight: FontWeight.w600,
      color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
    ),
  );
}

Widget _buildTableIcon(CafeTable table, bool isDark, bool isOccupied) {
  final capacity = table.seatingCapacity;

  return SizedBox(
    width: 60,
    height: 50,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Dynamic Chairs placement
        ..._buildDynamicChairs(capacity, isDark, isOccupied),

        // The Table Surface
        Container(
              width: 38,
              height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.1),
                          Colors.white.withValues(alpha: 0.05),
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.02),
                        ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                table.tableNumber,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            )
            .animate(target: isOccupied ? 1 : 0)
            .shimmer(
              duration: 2000.ms,
              color: (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                  .withValues(alpha: 0.2),
            ),
      ],
    ),
  ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.8, 0.8));
}

List<Widget> _buildDynamicChairs(int capacity, bool isDark, bool isOccupied) {
  final List<Widget> chairs = [];

  // Simple distribution logic:
  // Left & Right (always for 2+)
  chairs.add(Positioned(left: 0, child: _buildChair(isDark, isOccupied, 0)));
  chairs.add(Positioned(right: 0, child: _buildChair(isDark, isOccupied, 1)));

  // Top & Bottom (for 4+)
  if (capacity >= 4) {
    chairs.add(
      Positioned(
        top: 0,
        child: _buildChair(isDark, isOccupied, 2, horizontal: true),
      ),
    );
    chairs.add(
      Positioned(
        bottom: 0,
        child: _buildChair(isDark, isOccupied, 3, horizontal: true),
      ),
    );
  }

  // Extra Chairs for 6+ (additional side chairs)
  if (capacity >= 6) {
    // Offset slightly from center
    chairs.add(
      Positioned(left: 0, top: 8, child: _buildChair(isDark, isOccupied, 4)),
    );
    chairs.add(
      Positioned(
        right: 0,
        bottom: 8,
        child: _buildChair(isDark, isOccupied, 5),
      ),
    );
  }

  return chairs;
}

Widget _buildChair(
  bool isDark,
  bool isOccupied,
  int index, {
  bool horizontal = false,
}) {
  return Container(
        width: horizontal ? 12 : 6,
        height: horizontal ? 6 : 12,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: isOccupied ? 0.3 : 0.1)
              : Colors.black.withValues(alpha: isOccupied ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isOccupied
                ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                      .withValues(alpha: 0.3)
                : Colors.transparent,
            width: 0.5,
          ),
        ),
      )
      .animate(
        target: isOccupied ? 1 : 0,
        onPlay: (controller) =>
            isOccupied ? controller.repeat(reverse: true) : null,
      )
      .custom(
        duration: 1500.ms,
        builder: (context, value, child) {
          return Transform.scale(scale: 1 + (value * 0.1), child: child);
        },
      );
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
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 800;

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
                              fontSize: isTablet ? 8 : 10,
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
                  fontSize: isTablet ? 11 : 13,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '₹${price.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  fontSize: isTablet ? 8 : 12,
                  fontWeight: FontWeight.w800,
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
        openedBy: widget.user.id,
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
    } catch (e, st) {
      debugPrint('COMPLETE_BILL_ERROR: $e');
      debugPrint(st.toString());
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

    final isTablet = MediaQuery.of(context).size.width > 800;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.all(isTablet ? 32 : 20),
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
    final isTablet = MediaQuery.of(context).size.width > 800;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMode = mode),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 12),
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
                size: isTablet ? 24 : 20,
              ),
              const SizedBox(height: 8),
              Text(
                mode,
                style: GoogleFonts.inter(
                  fontSize: isTablet ? 10 : 12,
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
