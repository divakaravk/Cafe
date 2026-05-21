import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/api_helper.dart';
import '../../../core/widgets/pos_widgets.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../core/services/local_parser_service.dart';

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
  bool _isGroupsOn = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Cart Animation State
  String? _lastAddedItemName;
  bool _showCartAnimation = false;
  bool _isCartExpanded = false;
  DateTime? _lastAddEvent;

  // Top bar filter panel
  bool _showFilters = false;

  // Voice AI State
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _isProcessingAI = false;
  bool _isVoiceAIEnabled = false;
  String _lastWords = '';
  final _localParser = LocalParserService();

  @override
  void initState() {
    super.initState();
    _initSpeech();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
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
      final user = ref.read(authStateProvider).value;
      if (user == null) return;

      final itemsAsync = ref.read(allItemsProvider(user.companyId));
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
      for (final order in orders) {
        final itemName = (order['item'] as String).toLowerCase().trim();
        final qty = (order['qty'] as num).toInt();

        Item? matchedItem;
        ItemVariant? matchedVariant;

        for (final item in items) {
          if (item.itemName.toLowerCase().trim() == itemName) {
            matchedItem = item;
            break;
          }
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
            _triggerCartAnimation(matchedItem, matchedVariant);
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI added ${orders.length} items to order'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Cart parse error: $e');
    }
  }

  Future<void> _loadSettings() async {
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      final company = await ref.read(companyProvider(user.companyId).future);
      if (company != null) {
        // We keep it disabled by default as per requirement
        // setState(() => _isGroupsOn = company.hasItemVariants);
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
    final cart = ref.watch(cartProvider(null));
    final cartNotifier = ref.read(cartProvider(null).notifier);
    final authState = ref.watch(authStateProvider);
    final user = authState.value;

    if (user == null) return const SizedBox.shrink();

    final itemGroupsAsync = ref.watch(itemGroupsProvider(user.companyId));

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: Drawer(
        width: isTablet ? 400 : size.width * 0.85,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomLeft: Radius.circular(24),
          ),
        ),
        child: _buildBillingPanel(cart, cartNotifier, isDark, user),
      ),
      body: Stack(
        children: [
          Column(
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
                child: Stack(
                  children: [
                    itemGroupsAsync.when(
                      data: (items) => _buildMenuArea(
                        items,
                        cart,
                        cartNotifier,
                        isDark,
                        isTablet,
                      ),
                      loading: () => _buildSkeletonGrid(isDark),
                      error: (e, _) =>
                          Center(child: Text('Error loading items: $e')),
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
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
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
                                    onPlay: (controller) => controller.repeat(),
                                  )
                                  .fadeOut(duration: 800.ms)
                                  .fadeIn(duration: 800.ms),
                            FloatingActionButton(
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
            ],
          ),
          // Toggle arrows (Navigation ONLY)
          _buildSideToggles(isTablet),

          // Swiggy Cart Animation Overlay
          if (_showCartAnimation) _buildCartAnimationOverlay(cart, user),
        ],
      ),
      // Bottom sheet billing for mobile
      bottomSheet: !isTablet && cart.isNotEmpty
          ? _buildMobileOrderPanel(cart, user)
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
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
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
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/rasabhojan.png',
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  Text(
                    '${user.fullName} • ${user.role}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Theme switcher
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  ref.watch(isDarkModeProvider)
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  size: 20,
                ),
                onPressed: () => ref.read(isDarkModeProvider.notifier).toggle(),
              ),
            ),
            const SizedBox(width: 4),
            // Filter toggle button — reveals Voice & Groups chips
            GestureDetector(
              onTap: () => setState(() => _showFilters = !_showFilters),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _showFilters
                      ? (isDark
                            ? AppColors.primaryAmber
                            : AppColors.primaryOrange)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _showFilters
                        ? (isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.12)),
                  ),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: _showFilters
                      ? Colors.white
                      : (isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted),
                ),
              ),
            ),
            // Chips slide in when filter panel is open
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _showFilters
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 6),
                        _buildToggleChip(
                          icon: Icons.mic_rounded,
                          label: 'Voice',
                          value: _isVoiceAIEnabled,
                          isDark: isDark,
                          onTap: () => setState(
                            () => _isVoiceAIEnabled = !_isVoiceAIEnabled,
                          ),
                        ),
                        if (ref
                                .watch(companyProvider(user.companyId))
                                .value
                                ?.hasItemVariants ??
                            false) ...[
                          const SizedBox(width: 6),
                          _buildToggleChip(
                            icon: Icons.layers_rounded,
                            label: 'Groups',
                            value: _isGroupsOn,
                            isDark: isDark,
                            onTap: () => setState(() {
                              _isGroupsOn = !_isGroupsOn;
                              _selectedItem = null;
                              _selectedSection = null;
                            }),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ─── TOGGLE CHIP ────────────────────────────────────────
  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool value,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final active = value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.12)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active
                  ? Colors.white
                  : (isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active
                    ? Colors.white
                    : (isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted),
              ),
            ),
          ],
        ),
      ),
    );
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
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
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
        // Right Edge Toggle (Visual cue ONLY)
        if (isTablet)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeft,
                child: Container(
                  height: 60,
                  width: 6,
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.3),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── SKELETON LOADING GRID ──────────────────────────────
  Widget _buildSkeletonGrid(bool isDark) {
    final cols = _gridCols(MediaQuery.sizeOf(context).width);
    final base = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.11);

    Widget shimmerBox({double? width, double? height, double radius = 6}) {
      return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(radius),
            ),
          )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: const Duration(milliseconds: 1200),
            color: highlight,
          );
    }

    Widget skeletonCard() {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder.withValues(alpha: 0.12)
                : AppColors.lightBorder.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Expanded(
              flex: 3,
              child: shimmerBox(width: double.infinity, radius: 13),
            ),
            // Text placeholders
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    shimmerBox(width: double.infinity, height: 8),
                    const SizedBox(height: 6),
                    shimmerBox(width: 40, height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: cols * 4, // enough rows to fill the screen
      itemBuilder: (_, __) => skeletonCard(),
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

  // ─── Responsive grid column count ───────────────────────
  int _gridCols(double w) {
    if (w >= 900) return 7;
    if (w >= 680) return 6;
    if (w >= 480) return 5;
    return 4;
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
        crossAxisCount: _gridCols(MediaQuery.sizeOf(context).width),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
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
        crossAxisCount: _gridCols(MediaQuery.sizeOf(context).width),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: variants.length,
      itemBuilder: (context, index) {
        final v = variants[index];
        final cartItem = cart.firstWhere(
          (ci) => ci.item.id == master.id && ci.variant?.id == v.id,
          orElse: () => CartItem(item: master, variant: v, qty: 0),
        );

        return SimpleVariantTile(
              name: (v.variantName.toLowerCase() == 'default')
                  ? master.itemName
                  : v.variantName,
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
      final fullName =
          (variant == null || variant.variantName.toLowerCase() == 'default')
          ? master.itemName
          : '${master.itemName} ${variant.variantName}';
      return _searchQuery.isEmpty ||
          fullName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (filteredList.isEmpty) return _buildEmptyState(isDark);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridCols(MediaQuery.sizeOf(context).width),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
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

        final displayName =
            (variant == null || variant.variantName.toLowerCase() == 'default')
            ? master.itemName
            : variant.variantName;

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

  void _showBillingSheet(UserProfile user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final cart = ref.watch(cartProvider(null));
          final cartNotifier = ref.read(cartProvider(null).notifier);
          final isDark = ref.watch(isDarkModeProvider);

          final mq = MediaQuery.of(context);
          return Container(
            height: mq.size.height * 0.88,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: _buildBillingPanel(cart, cartNotifier, isDark, user),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── BILLING PANEL ─────────────────────────────────────
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
    final mq = MediaQuery.of(context);
    final sw = mq.size.width;
    final navBottom = mq.viewPadding.bottom;
    final compact = sw < 400;
    final hp = compact ? 14.0 : 20.0; // horizontal padding
    final vp = compact ? 12.0 : 16.0; // vertical padding for header/sections

    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.fromLTRB(hp, vp + 4, hp - 4, vp),
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
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  color:
                      (isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange)
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: compact ? 15 : 18,
                  color: isDark
                      ? AppColors.primaryAmber
                      : AppColors.primaryOrange,
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
              Text(
                'Current Bill',
                style: GoogleFonts.inter(
                  fontSize: compact ? 15 : 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              if (cart.isNotEmpty)
                TextButton.icon(
                  onPressed: () => cartNotifier.clear(),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: compact ? 14 : 16,
                  ),
                  label: Text(
                    'Clear',
                    style: GoogleFonts.inter(
                      fontSize: compact ? 11 : 12,
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 12,
                      vertical: compact ? 6 : 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                        size: 36,
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
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 12,
                    vertical: 6,
                  ),
                  itemCount: cart.length,
                  itemBuilder: (context, index) {
                    final ci = cart[index];
                    return CartItemRow(
                      cartItem: ci,
                      onIncrement: () => ref
                          .read(cartProvider(null).notifier)
                          .incrementQty(ci.item.id, ci.variant?.id),
                      onDecrement: () => ref
                          .read(cartProvider(null).notifier)
                          .decrementQty(ci.item.id, ci.variant?.id),
                      onRemove: () => ref
                          .read(cartProvider(null).notifier)
                          .removeItem(ci.item.id, ci.variant?.id),
                    );
                  },
                ),
        ),

        // Totals + Actions
        // navBottom ensures payment buttons never hide behind device nav bar
        if (cart.isNotEmpty)
          Container(
            padding: EdgeInsets.fromLTRB(hp, vp, hp, vp + navBottom),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkElevated : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, -6),
                ),
              ],
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.1)
                      : AppColors.lightBorder.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Discount row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Discount',
                      style: GoogleFonts.inter(fontSize: compact ? 12 : 13),
                    ),
                    SizedBox(
                      width: 72,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(fontSize: compact ? 12 : 13),
                        decoration: InputDecoration(
                          hintText: '0%',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
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
                SizedBox(height: compact ? 8 : 10),
                _totalRow('Subtotal', subtotal, isDark, compact: compact),
                if (discount > 0)
                  _totalRow(
                    'Discount (${discount.toStringAsFixed(0)}%)',
                    -discountAmount,
                    isDark,
                    isNeg: true,
                    compact: compact,
                  ),
                Divider(height: compact ? 12 : 16),
                _totalRow(
                  'Total',
                  total,
                  isDark,
                  isBold: true,
                  compact: compact,
                ),
                SizedBox(height: compact ? 10 : 14),
                // Payment buttons
                Row(
                  children: [
                    _paymentButton(
                      'Cash',
                      Icons.payments_rounded,
                      AppColors.success,
                      compact,
                      () => _completeBill('CASH', total, cart, user),
                    ),
                    SizedBox(width: compact ? 6 : 8),
                    _paymentButton(
                      'UPI',
                      Icons.qr_code_rounded,
                      AppColors.info,
                      compact,
                      () => _completeBill('UPI', total, cart, user),
                    ),
                    SizedBox(width: compact ? 6 : 8),
                    _paymentButton(
                      'Card',
                      Icons.credit_card_rounded,
                      AppColors.warning,
                      compact,
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
    bool compact = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isBold
                  ? (compact ? 14.0 : 16.0)
                  : (compact ? 11.0 : 13.0),
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
    bool compact,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: compact ? 14 : 17),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: compact ? 11 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: compact ? 10 : 13),
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
      await safeApiCall(
        () => SupabaseService.createBill(
          companyId: user.companyId,
          billedBy: user.id,
          subtotal: subtotal,
          discountAmount: discountAmount,
          totalAmount: total,
          paymentMode: paymentMode,
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
        ),
        timeout: const Duration(seconds: 20),
      );

      ref.read(cartProvider(null).notifier).clear();
      ref.read(discountProvider.notifier).reset();

      if (mounted) {
        AppFeedback.success(context, 'Bill created • ₹${total.toStringAsFixed(0)} via $paymentMode');
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, e);
    }
  }

  // ─── MOBILE BILLING BAR ───────────────────────────────-
  Widget _buildMobileOrderPanel(List<CartItem> cart, UserProfile user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = cart.fold<double>(0, (sum, ci) => sum + ci.total);
    return Container(
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
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          10 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${cart.length} item${cart.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                  ),
                ),
                Text(
                  '₹${total.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(
                    fontSize: 16,
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
              onPressed: () => _showBillingSheet(user),
              icon: const Icon(Icons.receipt_long_rounded, size: 15),
              label: Text(
                'View Bill',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CART ANIMATION TRIGGER ────────────────────────────
  void _triggerCartAnimation(Item item, ItemVariant? variant) {
    final cartNotifier = ref.read(cartProvider(null).notifier);
    cartNotifier.addItem(item, variant);

    final now = DateTime.now();
    _lastAddEvent = now;
    final displayName =
        (variant == null || variant.variantName.toLowerCase() == 'default')
        ? item.itemName
        : variant.variantName;

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

  Widget _buildCartAnimationOverlay(List<CartItem> cart, UserProfile user) {
    if (cart.isEmpty) return const SizedBox.shrink();

    final totalQty = cart.fold<int>(0, (sum, ci) => sum + ci.qty);
    final subtotal = cart.fold<double>(0, (sum, ci) => sum + ci.total);

    final mq = MediaQuery.of(context);
    final sw = mq.size.width;
    final isNarrow = sw < 400;
    // Position overlay above the compact panel (~50dp content + 10+10 padding + nav bar)
    final panelH = 70 + mq.viewPadding.bottom;

    return Positioned(
      bottom: panelH + 8,
      left: sw * 0.08,
      right: sw * 0.08,
      child: Center(
        child:
            AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 12 : 16,
                    vertical: isNarrow ? 8 : 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryAmber, AppColors.primaryOrange],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryOrange.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
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
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_basket_rounded,
                              color: AppColors.primaryOrange,
                              size: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Added ${_lastAddedItemName ?? 'Item'}',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: isNarrow ? 11 : 12,
                              ),
                              overflow: TextOverflow.ellipsis,
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
                                padding: const EdgeInsets.only(top: 8),
                                margin: const EdgeInsets.only(top: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () => _showBillingSheet(user),
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
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                          Text(
                                            '₹${subtotal.toStringAsFixed(0)} total',
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: isNarrow ? 10 : 11,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        'VIEW BILL',
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: isNarrow ? 9 : 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        color: Colors.white,
                                        size: 9,
                                      ),
                                    ],
                                  ),
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
