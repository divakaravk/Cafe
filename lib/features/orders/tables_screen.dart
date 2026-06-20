import 'dart:math' show min;
import 'package:cafe/core/services/supabase_service.dart';
import 'package:cafe/core/utils/api_helper.dart';
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
  String? _selectedCoverId;
  String? _selectedCoverLabel;

  // Table overview state (shown when occupied table is tapped)
  bool _showTableOverview = false;
  bool _overviewLoading = false;
  bool _overviewSaving = false;
  List<TableCover> _overviewCovers = [];
  Map<String, double> _overviewCoverTotals = {};
  List<Map<String, dynamic>> _overviewItems = [];

  // Voice AI State
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _isProcessingAI = false;
  bool _isVoiceAIEnabled = false;
  String _lastWords = '';
  final _localParser = LocalParserService();
  bool _showCartTab = false;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Active-order checkout state
  String _checkoutPaymentMode = 'CASH';
  double _checkoutDiscount = 0;
  bool _isAddingMoreItems = false;
  Future<Map<String, dynamic>?>? _orderSummaryFuture;
  String? _orderSummaryTableId;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

                      // Free tables float to the top (and blink to invite
                      // seating); occupied tables sink to the bottom ordered by
                      // how long they've been occupied (longest-seated first).
                      final sortedTables = [...tables]..sort((a, b) {
                        if (a.isOccupied != b.isOccupied) {
                          return a.isOccupied ? 1 : -1;
                        }
                        if (a.isOccupied && b.isOccupied) {
                          final ta = a.occupiedSince;
                          final tb = b.occupiedSince;
                          if (ta != null && tb != null) return ta.compareTo(tb);
                          if (ta != null) return -1;
                          if (tb != null) return 1;
                        }
                        return _naturalTableCompare(a.tableNumber, b.tableNumber);
                      });

                      return GridView.builder(
                        padding: EdgeInsets.all(isTablet ? 20 : 8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 3 : 2,
                          childAspectRatio: isTablet ? 1.8 : 1.45,
                          crossAxisSpacing: isTablet ? 16 : 8,
                          mainAxisSpacing: isTablet ? 16 : 8,
                        ),
                        itemCount: sortedTables.length,
                        itemBuilder: (context, index) {
                          final table = sortedTables[index];
                          final isSelected = _selectedTable?.id == table.id;

                          return _TableCard(
                                table: table,
                                isDark: isDark,
                                isSelected: isSelected,
                                onTap: () => _handleTableTap(table),
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
              _showTableOverview
                  ? _buildTableOverviewPanel(size, isDark, isTablet, user)
                  : _buildQuickOrderPanel(size, isDark, isTablet, user),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTableTap(CafeTable table) async {
    if (table.isOccupied && table.activeSessionId != null) {
      setState(() {
        _selectedTable = table;
        _showTableOverview = true;
        _selectedCoverId = null;
        _selectedCoverLabel = null;
        _isAddingMoreItems = false;
        _overviewCovers = [];
        _overviewItems = [];
        _overviewCoverTotals = {};
      });
      _loadTableOverview(table.activeSessionId!);
    } else {
      setState(() {
        _selectedTable = table;
        _selectedCoverId = null;
        _selectedCoverLabel = 'Cover 1';
        _showTableOverview = false;
        _isAddingMoreItems = false;
        _selectedCategory = null;
        _showCartTab = false;
        _searchQuery = '';
        _searchController.clear();
        _checkoutDiscount = 0;
        _checkoutPaymentMode = 'CASH';
      });
      _refreshOrderSummary();
    }
  }

  Future<void> _loadTableOverview(String sessionId) async {
    setState(() => _overviewLoading = true);
    try {
      final results = await Future.wait([
        SupabaseService.getCoversForSession(sessionId),
        SupabaseService.getCoverTotals(sessionId),
        SupabaseService.getDetailedItemsForSession(sessionId),
      ]);
      if (mounted) {
        setState(() {
          _overviewCovers =
              (results[0] as List<Map<String, dynamic>>)
                  .map((e) => TableCover.fromJson(e))
                  .toList();
          _overviewCoverTotals = results[1] as Map<String, double>;
          _overviewItems = results[2] as List<Map<String, dynamic>>;
          _overviewLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _overviewLoading = false);
    }
  }

  void _startOrderForCover(TableCover cover) {
    setState(() {
      _showTableOverview = false;
      _selectedCoverId = cover.id;
      _selectedCoverLabel = cover.displayName;
      _isAddingMoreItems = true;
      _selectedCategory = null;
      _showCartTab = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Future<void> _billCoverFromOverview(TableCover cover) async {
    final total = _overviewCoverTotals[cover.id] ?? 0;
    final sessionId = _selectedTable?.activeSessionId;
    if (total == 0 || sessionId == null) return;

    final mode = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CoverPaymentSheet(total: total, coverName: cover.displayName),
    );
    if (mode == null || !mounted) return;

    setState(() => _overviewSaving = true);
    try {
      await SupabaseService.checkoutCover(
        coverId: cover.id,
        sessionId: sessionId,
        paymentMode: mode,
      );
      ref.invalidate(tablesProvider(widget.companyId));
      if (mounted) {
        AppFeedback.success(
          context,
          '${cover.displayName} paid — ₹${total.toStringAsFixed(0)}',
        );
        // Refresh or close if all covers billed
        final freshTables = ref.read(tablesProvider(widget.companyId)).value;
        final updatedTable = freshTables?.firstWhere(
          (t) => t.id == _selectedTable?.id,
          orElse: () => _selectedTable!,
        );
        if (updatedTable?.isOccupied == true) {
          await _loadTableOverview(sessionId);
        } else {
          setState(() {
            _selectedTable = null;
            _showTableOverview = false;
            _overviewCovers = [];
            _overviewItems = [];
            _overviewCoverTotals = {};
          });
        }
      }
    } catch (e) {
      if (mounted) AppFeedback.error(context, e);
    } finally {
      if (mounted) setState(() => _overviewSaving = false);
    }
  }

  Future<void> _addCoverFromOverview(UserProfile user) async {
    final sessionId = _selectedTable?.activeSessionId;
    if (sessionId == null) return;
    setState(() => _overviewSaving = true);
    try {
      final nextNumber = _overviewCovers.isEmpty
          ? 1
          : _overviewCovers
                  .map((c) => c.coverNumber)
                  .reduce((a, b) => a > b ? a : b) +
              1;
      final data = await SupabaseService.createCover(
        sessionId: sessionId,
        companyId: widget.companyId,
        coverNumber: nextNumber,
      );
      if (mounted) _startOrderForCover(TableCover.fromJson(data));
    } catch (e) {
      debugPrint('Error adding cover: $e');
      if (mounted) AppFeedback.error(context, e);
    } finally {
      if (mounted) setState(() => _overviewSaving = false);
    }
  }

  // ── Cover color palette ─────────────────────────────────────
  static const _kCoverColors = [
    Color(0xFFF97316), // orange  (C1)
    Color(0xFF3B82F6), // blue    (C2)
    Color(0xFF8B5CF6), // purple  (C3)
    Color(0xFF10B981), // teal    (C4)
    Color(0xFFEC4899), // pink    (C5)
    Color(0xFFEAB308), // yellow  (C6)
  ];
  Color _coverAccent(int? coverNumber) {
    if (coverNumber == null) return Colors.grey;
    return _kCoverColors[(coverNumber - 1) % _kCoverColors.length];
  }

  /// Compares table numbers so "T2" sorts before "T10" (numeric-aware).
  int _naturalTableCompare(String a, String b) {
    final na = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
    final nb = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  void _refreshOrderSummary() {
    final id = _selectedTable?.id;
    if (id == null || id == _orderSummaryTableId) return;
    _orderSummaryTableId = id;
    setState(() {
      _orderSummaryFuture = SupabaseService.getOrderSummaryForTable(id);
    });
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
    final cart = ref.watch(cartProvider(_selectedTable?.id));

    // Occupied table with no pending cart items → show active-order checkout
    if (cart.isEmpty &&
        (_selectedTable?.isOccupied ?? false) &&
        !_isAddingMoreItems) {
      return _buildActiveOrderCheckoutPanel(size, isDark, user);
    }

    final allItemsAsync = ref.watch(allItemsProvider(widget.companyId));
    final cartNotifier = ref.read(cartProvider(_selectedTable?.id).notifier);

    final bool isMobile = size.width < 600;
    final double panelWidth = isMobile
        ? size.width
        : min(360.0, size.width * 0.44);
    final double panelHeight = isMobile ? size.height * 0.62 : size.height;

    return Positioned(
      right: 0,
      bottom: 0,
      top: isMobile ? null : 0,
      left: isMobile ? 0 : null,
      child:
          Hero(
                tag: 'quickOrderPanel',
                child: Container(
                  width: panelWidth,
                  height: panelHeight,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.lightSurface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 30,
                        offset: isMobile
                            ? const Offset(0, -6)
                            : const Offset(-8, 0),
                      ),
                    ],
                    borderRadius: isMobile
                        ? const BorderRadius.vertical(top: Radius.circular(24))
                        : const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            bottomLeft: Radius.circular(24),
                          ),
                    border: Border(
                      left: isMobile
                          ? BorderSide.none
                          : BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder.withValues(alpha: 0.2)
                                  : AppColors.lightBorder.withValues(
                                      alpha: 0.4,
                                    ),
                            ),
                      top: isMobile
                          ? BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder.withValues(alpha: 0.2)
                                  : AppColors.lightBorder.withValues(
                                      alpha: 0.3,
                                    ),
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Drag handle for mobile
                      if (isMobile)
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 4),
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      // Panel Header
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          isMobile ? 4 : 16,
                          12,
                          isMobile ? 4 : 8,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedCoverLabel ?? 'Quick Order',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 14 : 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    Text(
                                      'Table: ${_selectedTable?.tableName}',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 11 : 12,
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
                                        .read(
                                          cartProvider(
                                            _selectedTable?.id,
                                          ).notifier,
                                        )
                                        .clear(),
                                    child: Text(
                                      'Clear',
                                      style: GoogleFonts.inter(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w700,
                                        fontSize: isMobile ? 12 : 13,
                                      ),
                                    ),
                                  ),
                                Transform.scale(
                                  scale: isMobile ? 0.8 : 1.0,
                                  child: Switch(
                                    value: _isVoiceAIEnabled,
                                    activeThumbColor: AppColors.primaryAmber,
                                    onChanged: (val) =>
                                        setState(() => _isVoiceAIEnabled = val),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _selectedCoverId != null
                                        ? Icons.arrow_back_rounded
                                        : Icons.close_rounded,
                                  ),
                                  iconSize: isMobile ? 20 : 24,
                                  onPressed: () {
                                    if (_selectedCoverId != null) {
                                      // Go back to table overview
                                      final sid =
                                          _selectedTable?.activeSessionId;
                                      setState(() {
                                        _showTableOverview = true;
                                        _isAddingMoreItems = false;
                                        _selectedCoverId = null;
                                        _selectedCoverLabel = null;
                                        _selectedCategory = null;
                                        _showCartTab = false;
                                        _searchQuery = '';
                                        _searchController.clear();
                                        _overviewCovers = [];
                                        _overviewItems = [];
                                        _overviewCoverTotals = {};
                                      });
                                      if (sid != null) {
                                        _loadTableOverview(sid);
                                      }
                                    } else {
                                      setState(() {
                                        _selectedTable = null;
                                        _selectedCoverId = null;
                                        _selectedCoverLabel = null;
                                        _selectedCategory = null;
                                        _showCartTab = false;
                                        _searchQuery = '';
                                        _searchController.clear();
                                        _orderSummaryTableId = null;
                                        _orderSummaryFuture = null;
                                      });
                                    }
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.05),
                                    padding: isMobile
                                        ? const EdgeInsets.all(6)
                                        : null,
                                    minimumSize: isMobile
                                        ? const Size(32, 32)
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isMobile ? 8 : 16),
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
                                      final filteredItems =
                                          _selectedCategory == null
                                          ? items
                                          : items
                                                .where(
                                                  (i) =>
                                                      i.sectionLabel ==
                                                      _selectedCategory,
                                                )
                                                .toList();

                                      // Flatten filtered items + variants
                                      final List<Map<String, dynamic>>
                                      flatList = [];
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

                                      // Apply search filter on top of category filter
                                      final searchQ = _searchQuery
                                          .toLowerCase();
                                      final searchFiltered = searchQ.isEmpty
                                          ? flatList
                                          : flatList.where((m) {
                                              final it = m['master'] as Item;
                                              final va =
                                                  m['variant'] as ItemVariant?;
                                              return it.itemName
                                                      .toLowerCase()
                                                      .contains(searchQ) ||
                                                  (va != null &&
                                                      va.variantName
                                                          .toLowerCase()
                                                          .contains(searchQ));
                                            }).toList();

                                      return Column(
                                        children: [
                                          // Search field
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              4,
                                              12,
                                              4,
                                            ),
                                            child: SizedBox(
                                              height: 36,
                                              child: TextField(
                                                controller: _searchController,
                                                onChanged: (v) => setState(
                                                  () => _searchQuery = v,
                                                ),
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText: 'Search items...',
                                                  hintStyle: GoogleFonts.inter(
                                                    fontSize: 13,
                                                  ),
                                                  prefixIcon: const Icon(
                                                    Icons.search_rounded,
                                                    size: 18,
                                                  ),
                                                  suffixIcon:
                                                      _searchQuery.isNotEmpty
                                                      ? IconButton(
                                                          icon: const Icon(
                                                            Icons.clear_rounded,
                                                            size: 16,
                                                          ),
                                                          onPressed: () =>
                                                              setState(() {
                                                                _searchQuery =
                                                                    '';
                                                                _searchController
                                                                    .clear();
                                                              }),
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(),
                                                        )
                                                      : null,
                                                  filled: true,
                                                  fillColor: isDark
                                                      ? Colors.white.withValues(
                                                          alpha: 0.07,
                                                        )
                                                      : Colors.black.withValues(
                                                          alpha: 0.05,
                                                        ),
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Category chips
                                          SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: isMobile ? 4 : 6,
                                            ),
                                            child: Row(
                                              children: [
                                                _buildPanelCategoryChip(
                                                  'All',
                                                  _selectedCategory == null,
                                                  isDark,
                                                  isTablet,
                                                  () => setState(
                                                    () => _selectedCategory =
                                                        null,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                ...categories.map(
                                                  (s) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 6,
                                                        ),
                                                    child: _buildPanelCategoryChip(
                                                      s,
                                                      _selectedCategory == s,
                                                      isDark,
                                                      isTablet,
                                                      () => setState(
                                                        () =>
                                                            _selectedCategory =
                                                                s,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Item Grid
                                          Expanded(
                                            child: searchFiltered.isEmpty
                                                ? Center(
                                                    child: Text(
                                                      'No items found',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        color: isDark
                                                            ? AppColors
                                                                  .textWhiteMuted
                                                            : AppColors
                                                                  .textDarkMuted,
                                                      ),
                                                    ),
                                                  )
                                                : GridView.builder(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                        ),
                                                    gridDelegate:
                                                        SliverGridDelegateWithFixedCrossAxisCount(
                                                          crossAxisCount:
                                                              isMobile ? 4 : 3,
                                                          crossAxisSpacing:
                                                              isMobile ? 6 : 8,
                                                          mainAxisSpacing:
                                                              isMobile ? 6 : 8,
                                                          childAspectRatio:
                                                              isMobile
                                                              ? 0.88
                                                              : 0.75,
                                                        ),
                                                    itemCount:
                                                        searchFiltered.length,
                                                    itemBuilder: (context, index) {
                                                      final master =
                                                          searchFiltered[index]['master']
                                                              as Item;
                                                      final variant =
                                                          searchFiltered[index]['variant']
                                                              as ItemVariant?;

                                                      final cartCount = cart
                                                          .firstWhere(
                                                            (ci) =>
                                                                ci.item.id ==
                                                                    master.id &&
                                                                ci
                                                                        .variant
                                                                        ?.id ==
                                                                    variant?.id,
                                                            orElse: () =>
                                                                CartItem(
                                                                  item: master,
                                                                  variant:
                                                                      variant,
                                                                  qty: 0,
                                                                ),
                                                          )
                                                          .qty;

                                                      return _CompactItemTile(
                                                            master: master,
                                                            variant: variant,
                                                            isDark: isDark,
                                                            cartCount:
                                                                cartCount,
                                                            onTap: () =>
                                                                cartNotifier
                                                                    .addItem(
                                                                      master,
                                                                      variant,
                                                                    ),
                                                          )
                                                          .animate()
                                                          .fadeIn(
                                                            delay:
                                                                (15 * index).ms,
                                                          )
                                                          .scale(
                                                            begin: const Offset(
                                                              0.9,
                                                              0.9,
                                                            ),
                                                            duration: 180.ms,
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
                                    error: (e, _) =>
                                        Center(child: Text('Error: $e')),
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
                                              padding: EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: CircularProgressIndicator(
                                                color: AppColors.primaryAmber,
                                              ),
                                            )
                                          else if (_isListening)
                                            Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                  margin: const EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.error
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Listening...',
                                                    style: GoogleFonts.inter(
                                                      color: AppColors.error,
                                                      fontSize: 8,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                                  _isListening
                                                      ? Icons.stop
                                                      : Icons.mic,
                                                ),
                                              )
                                              .animate(
                                                target: _isListening ? 1 : 0,
                                              )
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
                        SafeArea(
                          top: false,
                          child:
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkCard
                                      : AppColors.lightCard,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
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
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(
                                                color: isDark
                                                    ? AppColors.primaryAmber
                                                    : AppColors.primaryOrange,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: _saveOrder,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.receipt_outlined,
                                                    size: 13,
                                                    color: isDark
                                                        ? AppColors.primaryAmber
                                                        : AppColors
                                                              .primaryOrange,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'SAVE KOT',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: isDark
                                                          ? AppColors
                                                                .primaryAmber
                                                          : AppColors
                                                                .primaryOrange,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isDark
                                                  ? AppColors.primaryAmber
                                                  : AppColors.primaryOrange,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 10,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 0,
                                            ),
                                            onPressed: () =>
                                                _showTableBillingSheet(
                                                  context,
                                                  ref,
                                                  _selectedTable!,
                                                  cart,
                                                  user!,
                                                ),
                                            child: const FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.payment_rounded,
                                                    size: 13,
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'CHECKOUT',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ],
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
                        ),
                    ],
                  ),
                ),
              )
              .animate()
              .slideY(
                begin: isMobile ? 1.0 : 0.0,
                end: 0.0,
                duration: 350.ms,
                curve: Curves.easeOutCubic,
              )
              .slideX(
                begin: isMobile ? 0.0 : 1.0,
                end: 0.0,
                duration: 350.ms,
                curve: Curves.easeOutCubic,
              ),
    );
  }

  // ── TABLE OVERVIEW PANEL ────────────────────────────────────
  Widget _buildTableOverviewPanel(
    Size size,
    bool isDark,
    bool isTablet,
    UserProfile? user,
  ) {
    final bool isMobile = size.width < 600;
    final double panelWidth =
        isMobile ? size.width : min(390.0, size.width * 0.46);
    final double panelHeight =
        isMobile ? size.height * 0.88 : size.height;

    final activeCovers =
        _overviewCovers.where((c) => c.isActive).toList();
    final billedCovers =
        _overviewCovers.where((c) => c.isBilled).toList();
    final grandTotal =
        _overviewCoverTotals.values.fold(0.0, (a, b) => a + b);

    return Positioned(
      right: 0,
      bottom: 0,
      top: isMobile ? null : 0,
      left: isMobile ? 0 : null,
      child: Container(
        width: panelWidth,
        height: panelHeight,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset:
                  isMobile ? const Offset(0, -6) : const Offset(-8, 0),
            ),
          ],
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(24))
              : const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
        ),
        child: Column(
          children: [
            // Drag handle (mobile)
            if (isMobile)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                isMobile ? 4 : 20,
                8,
                10,
              ),
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
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedTable?.tableName ?? 'Table',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!_overviewLoading)
                          Text(
                            '${activeCovers.length} cover${activeCovers.length != 1 ? 's' : ''}'
                            '${grandTotal > 0 ? '  ·  ₹${grandTotal.toStringAsFixed(0)}' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.primaryAmber
                                  : AppColors.primaryOrange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => setState(() {
                      _selectedTable = null;
                      _showTableOverview = false;
                      _overviewCovers = [];
                      _overviewItems = [];
                      _overviewCoverTotals = {};
                    }),
                    style: IconButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Body
            if (_overviewLoading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  children: [
                    // ── Ordered items ─────────────────────────
                    if (_overviewItems.isNotEmpty) ...[
                      _ovLabel('WHAT\'S ORDERED', isDark),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          children: List.generate(
                            _overviewItems.length,
                            (i) => Column(
                              children: [
                                _buildOvItemRow(
                                  _overviewItems[i],
                                  isDark,
                                ),
                                if (i < _overviewItems.length - 1)
                                  Divider(
                                    height: 1,
                                    indent: 14,
                                    endIndent: 14,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.05),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        child: Text(
                          'No orders yet on this table',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.textWhiteMuted
                                : AppColors.textDarkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // ── Covers ────────────────────────────────
                    _ovLabel(
                      'COVERS  (${activeCovers.length} active)',
                      isDark,
                    ),
                    const SizedBox(height: 8),
                    if (activeCovers.isEmpty && billedCovers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No covers yet — tap "Add Cover" below',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.textWhiteMuted
                                : AppColors.textDarkMuted,
                          ),
                        ),
                      )
                    else ...[
                      ...activeCovers.map(
                        (c) => _buildOvCoverCard(c, isDark, false),
                      ),
                      if (billedCovers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ovLabel('BILLED', isDark),
                        const SizedBox(height: 6),
                        ...billedCovers.map(
                          (c) => _buildOvCoverCard(c, isDark, true),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

            // Footer – Add Cover button
            if (!_overviewLoading)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_overviewSaving || user == null)
                          ? null
                          : () => _addCoverFromOverview(user),
                      icon: _overviewSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.person_add_rounded, size: 16),
                      label: Text(
                        'Add Cover for Another Customer',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? AppColors.primaryAmber
                            : AppColors.primaryOrange,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      )
          .animate()
          .slideY(
            begin: isMobile ? 1.0 : 0.0,
            end: 0.0,
            duration: 350.ms,
            curve: Curves.easeOutCubic,
          )
          .slideX(
            begin: isMobile ? 0.0 : 1.0,
            end: 0.0,
            duration: 350.ms,
            curve: Curves.easeOutCubic,
          ),
    );
  }

  Widget _ovLabel(String text, bool isDark) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
      ),
    );
  }

  Widget _buildOvItemRow(Map<String, dynamic> item, bool isDark) {
    final name = item['item_name'] as String? ?? '—';
    final qty = item['qty'] as int? ?? 1;
    final rate = item['rate'] as double? ?? 0.0;
    final coverNumber = item['cover_number'] as int?;
    final coverLabel = item['cover_label'] as String?;
    final total = qty * rate;
    final color = _coverAccent(coverNumber);
    final badge = (coverLabel != null && coverLabel.isNotEmpty)
        ? coverLabel
        : (coverNumber != null ? 'C$coverNumber' : 'Table');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              badge,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '×$qty',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '₹${total.toStringAsFixed(0)}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmAndDeleteCover(TableCover cover) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
              isDark ? AppColors.darkSurface : AppColors.lightSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Remove Cover?',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Text(
            '${cover.displayName} has no orders and will be permanently removed from this table.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Delete',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return false;

    setState(() => _overviewSaving = true);
    try {
      await SupabaseService.deleteCover(cover.id);
      if (mounted) {
        setState(() {
          _overviewCovers.removeWhere((c) => c.id == cover.id);
          _overviewCoverTotals.remove(cover.id);
          _overviewSaving = false;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, e);
        setState(() => _overviewSaving = false);
      }
      return false;
    }
  }

  Widget _buildOvCoverCard(
    TableCover cover,
    bool isDark,
    bool isBilled,
  ) {
    final total = _overviewCoverTotals[cover.id] ?? 0;
    final color = isBilled
        ? AppColors.success
        : _coverAccent(cover.coverNumber);
    final canDelete = !isBilled && total == 0 && !_overviewSaving;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isBilled ? 0.05 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isBilled ? 0.15 : 0.28),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isBilled
                  ? Icon(Icons.check_rounded, color: color, size: 18)
                  : Text(
                      '${cover.coverNumber}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color,
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
                      : canDelete
                          ? 'Swipe left to remove'
                          : 'No orders yet',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: canDelete
                        ? AppColors.error.withValues(alpha: 0.7)
                        : isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isBilled)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
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
              onPressed:
                  _overviewSaving
                  ? null
                  : () => _startOrderForCover(cover),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Order',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.primaryAmber
                      : AppColors.primaryOrange,
                ),
              ),
            ),
            if (total > 0)
              TextButton(
                onPressed:
                    _overviewSaving
                    ? null
                    : () => _billCoverFromOverview(cover),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Bill',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ),
          ],
        ],
      ),
    );

    if (!canDelete) return card;

    return Dismissible(
      key: ValueKey(cover.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmAndDeleteCover(cover),
      onDismissed: (_) {},
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.error.withValues(alpha: 0.3),
          ),
        ),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Delete',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
          ],
        ),
      ),
      child: card,
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
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
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
              // Item thumbnail
              Builder(
                builder: (_) {
                  final imageUrl = ci.variant?.imageUrl ?? ci.item.imageUrl;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _cartImagePlaceholder(isDark),
                            )
                          : _cartImagePlaceholder(isDark),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ci.item.itemName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ci.variant != null &&
                        ci.variant!.variantName.toLowerCase() != 'default')
                      Text(
                        ci.variant!.variantName,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${ci.rate.toStringAsFixed(0)}',
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
              Row(
                children: [
                  _buildQtyButton(
                    Icons.remove_rounded,
                    () => cartNotifier.decrementQty(ci.item.id, ci.variant?.id),
                    isDark,
                    isTablet,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 12 : 8,
                    ),
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
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: isTablet ? 20 : 18,
                    ),
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

  Widget _cartImagePlaceholder(bool isDark) {
    return Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04),
      child: Icon(
        Icons.fastfood_rounded,
        size: 20,
        color: isDark
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.black.withValues(alpha: 0.2),
      ),
    );
  }

  Widget _buildQtyButton(
    IconData icon,
    VoidCallback onTap,
    bool isDark,
    bool isTablet,
  ) {
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
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 600;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 14 : 20,
          vertical: isMobile ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
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
            fontSize: isMobile ? 11 : 12,
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
          horizontal: isTablet ? 16 : 10,
          vertical: isTablet ? 8 : 5,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isTablet ? 12 : 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveOrderCheckoutPanel(
    Size size,
    bool isDark,
    UserProfile? user,
  ) {
    final bool isMobile = size.width < 600;
    final double panelWidth = isMobile
        ? size.width
        : min(360.0, size.width * 0.44);
    final double panelHeight = isMobile ? size.height * 0.75 : size.height;

    return Positioned(
      right: 0,
      bottom: 0,
      top: isMobile ? null : 0,
      left: isMobile ? 0 : null,
      child:
          Container(
                width: panelWidth,
                height: panelHeight,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 30,
                      offset: isMobile
                          ? const Offset(0, -6)
                          : const Offset(-8, 0),
                    ),
                  ],
                  borderRadius: isMobile
                      ? const BorderRadius.vertical(top: Radius.circular(24))
                      : const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          bottomLeft: Radius.circular(24),
                        ),
                ),
                child: Column(
                  children: [
                    if (isMobile)
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    // Header
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        isMobile ? 8 : 20,
                        12,
                        8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            color: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active Order',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Table: ${_selectedTable?.tableName}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppColors.primaryAmber
                                        : AppColors.primaryOrange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => setState(() {
                              _selectedTable = null;
                              _checkoutDiscount = 0;
                              _checkoutPaymentMode = 'CASH';
                              _isAddingMoreItems = false;
                              _orderSummaryTableId = null;
                              _orderSummaryFuture = null;
                            }),
                            style: IconButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Order details loaded from DB
                    Expanded(
                      child: FutureBuilder<Map<String, dynamic>?>(
                        future: _orderSummaryFuture,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snap.data == null) {
                            return Center(
                              child: Text(
                                'No active order found',
                                style: GoogleFonts.inter(
                                  color: isDark
                                      ? AppColors.textWhiteMuted
                                      : AppColors.textDarkMuted,
                                ),
                              ),
                            );
                          }
                          final bill = snap.data!;
                          final orderedItems =
                              (bill['ordered_items'] as List<dynamic>?) ?? [];
                          final subtotal =
                              (bill['subtotal'] as num?)?.toDouble() ?? 0.0;
                          final cgst =
                              (bill['cgst_amount'] as num?)?.toDouble() ?? 0.0;
                          final sgst =
                              (bill['sgst_amount'] as num?)?.toDouble() ?? 0.0;
                          final rawTotal = subtotal + cgst + sgst;

                          return StatefulBuilder(
                            builder: (ctx, setLocal) {
                              final discountAmt =
                                  rawTotal * (_checkoutDiscount / 100);
                              final finalTotal = rawTotal - discountAmt;
                              return SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Ordered items list ───────────────────
                                    Text(
                                      'Items Ordered',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppColors.textWhiteMuted
                                            : AppColors.textDarkMuted,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (orderedItems.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'No items recorded',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: isDark
                                                ? AppColors.textWhiteMuted
                                                : AppColors.textDarkMuted,
                                          ),
                                        ),
                                      )
                                    else
                                      ...orderedItems.map((raw) {
                                        final it = raw as Map<String, dynamic>;
                                        final name =
                                            it['item_name_snapshot']
                                                as String? ??
                                            '—';
                                        final qty =
                                            (it['qty'] as num?)?.toDouble() ??
                                            1.0;
                                        final rate =
                                            (it['rate_snapshot'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                        final lineTotal = qty * rate;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '×${qty.toInt()}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark
                                                      ? AppColors.textWhiteMuted
                                                      : AppColors.textDarkMuted,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                '₹${lineTotal.toStringAsFixed(0)}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    const Divider(height: 20),

                                    // ── Bill summary ─────────────────────────
                                    _summaryRow2('Subtotal', subtotal, isDark),
                                    if (cgst > 0)
                                      _summaryRow2('CGST', cgst, isDark),
                                    if (sgst > 0)
                                      _summaryRow2('SGST', sgst, isDark),
                                    const Divider(height: 20),

                                    // Discount field
                                    Text(
                                      'Discount %',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppColors.textWhiteMuted
                                            : AppColors.textDarkMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      height: 40,
                                      child: TextField(
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.inter(fontSize: 14),
                                        decoration: InputDecoration(
                                          hintText: '0',
                                          filled: true,
                                          fillColor: isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.06,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                          suffixText: '%',
                                        ),
                                        onChanged: (v) {
                                          final d = double.tryParse(v) ?? 0;
                                          setState(
                                            () => _checkoutDiscount = d.clamp(
                                              0,
                                              100,
                                            ),
                                          );
                                          setLocal(() {});
                                        },
                                      ),
                                    ),
                                    if (_checkoutDiscount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: _summaryRow2(
                                          'Discount',
                                          -discountAmt,
                                          isDark,
                                          isNeg: true,
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Total',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '₹${finalTotal.toStringAsFixed(0)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: isDark
                                                ? AppColors.primaryAmber
                                                : AppColors.primaryOrange,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // ── Payment mode ─────────────────────────
                                    Text(
                                      'Payment Mode',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppColors.textWhiteMuted
                                            : AppColors.textDarkMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: ['CASH', 'UPI', 'CARD'].map((
                                        mode,
                                      ) {
                                        final sel =
                                            _checkoutPaymentMode == mode;
                                        return Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: GestureDetector(
                                              onTap: () => setState(
                                                () =>
                                                    _checkoutPaymentMode = mode,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: sel
                                                      ? (isDark
                                                                ? AppColors
                                                                      .primaryAmber
                                                                : AppColors
                                                                      .primaryOrange)
                                                            .withValues(
                                                              alpha: 0.15,
                                                            )
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: sel
                                                        ? (isDark
                                                              ? AppColors
                                                                    .primaryAmber
                                                              : AppColors
                                                                    .primaryOrange)
                                                        : Colors.grey
                                                              .withValues(
                                                                alpha: 0.3,
                                                              ),
                                                    width: sel ? 1.5 : 1,
                                                  ),
                                                ),
                                                child: Text(
                                                  mode,
                                                  textAlign: TextAlign.center,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: sel
                                                        ? (isDark
                                                              ? AppColors
                                                                    .primaryAmber
                                                              : AppColors
                                                                    .primaryOrange)
                                                        : (isDark
                                                              ? AppColors
                                                                    .textWhiteMuted
                                                              : AppColors
                                                                    .textDarkMuted),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Add more items button ─────────────────
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(
                                            color: isDark
                                                ? AppColors.primaryAmber
                                                : AppColors.primaryOrange,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        onPressed: () => setState(
                                          () => _isAddingMoreItems = true,
                                        ),
                                        icon: Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: isDark
                                              ? AppColors.primaryAmber
                                              : AppColors.primaryOrange,
                                        ),
                                        label: Text(
                                          'Add More Items',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? AppColors.primaryAmber
                                                : AppColors.primaryOrange,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // ── Checkout button ───────────────────────
                                    SafeArea(
                                      top: false,
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.success,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            elevation: 0,
                                          ),
                                          onPressed: () =>
                                              _doCheckout(finalTotal),
                                          child: Text(
                                            'COMPLETE PAYMENT',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .slideY(
                begin: isMobile ? 1.0 : 0.0,
                end: 0.0,
                duration: 350.ms,
                curve: Curves.easeOutCubic,
              )
              .slideX(
                begin: isMobile ? 0.0 : 1.0,
                end: 0.0,
                duration: 350.ms,
                curve: Curves.easeOutCubic,
              ),
    );
  }

  Widget _summaryRow2(
    String label,
    double amount,
    bool isDark, {
    bool isNeg = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
          Text(
            '${isNeg ? '-' : ''}₹${amount.abs().toStringAsFixed(0)}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isNeg ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doCheckout(double finalTotal) async {
    if (_selectedTable == null) return;
    setState(() => _isProcessingAI = true);
    try {
      await safeApiCall(
        () => SupabaseService.checkoutTable(
          tableId: _selectedTable!.id,
          paymentMode: _checkoutPaymentMode,
          discountPercent: _checkoutDiscount,
        ),
        timeout: const Duration(seconds: 20),
      );
      if (mounted) {
        AppFeedback.success(
          context,
          'Payment complete — ${_selectedTable?.tableName} • ₹${finalTotal.toStringAsFixed(0)}',
        );
        setState(() {
          _selectedTable = null;
          _checkoutDiscount = 0;
          _checkoutPaymentMode = 'CASH';
          _orderSummaryFuture = null;
          _orderSummaryTableId = null;
        });
        ref.invalidate(tablesProvider(widget.companyId));
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.error(context, e, onRetry: () => _doCheckout(finalTotal));
      }
    } finally {
      if (mounted) setState(() => _isProcessingAI = false);
    }
  }

  Future<void> _saveOrder() async {
    if (_selectedTable == null) return;
    final cart = ref.read(cartProvider(_selectedTable!.id));
    if (cart.isEmpty) return;

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    setState(() => _isProcessingAI = true);

    try {
      final result = await safeApiCall(
        () => SupabaseService.saveOrderWithKot(
          companyId: user.companyId,
          tableId: _selectedTable!.id,
          openedBy: user.id,
          cart: cart,
          coverId: _selectedCoverId,
        ),
        timeout: const Duration(seconds: 25),
      );

      ref.read(cartProvider(_selectedTable!.id).notifier).clear();

      if (mounted) {
        final label =
            '${_selectedCoverLabel ?? 'Cover 1'} · ${_selectedTable?.tableName ?? ''}';
        AppFeedback.success(context, 'KOT sent to kitchen — $label');
        ref.invalidate(tablesProvider(widget.companyId));

        // Always go back to the table overview so staff can add more covers or bill.
        final sid = result.sessionId;
        final t = _selectedTable!;
        setState(() {
          // Patch the in-memory table with the now-known session id so
          // billing actions in the overview work before the provider re-fetches.
          _selectedTable = CafeTable(
            id: t.id,
            companyId: t.companyId,
            tableNumber: t.tableNumber,
            section: t.section,
            seatingCapacity: t.seatingCapacity,
            isActive: t.isActive,
            isOccupied: true,
            activeOrderTotal: t.activeOrderTotal,
            activeSessionId: sid,
            activeCoverCount: t.activeCoverCount,
          );
          _showTableOverview = true;
          _isAddingMoreItems = false;
          _selectedCoverId = null;
          _selectedCoverLabel = null;
          _selectedCategory = null;
          _showCartTab = false;
          _searchQuery = '';
          _searchController.clear();
          _overviewCovers = [];
          _overviewItems = [];
          _overviewCoverTotals = {};
          _orderSummaryTableId = null;
          _orderSummaryFuture = null;
        });
        _loadTableOverview(sid);
      }
    } catch (e, st) {
      debugPrint('SAVE_ORDER_ERROR: $e\n$st');
      if (mounted) AppFeedback.error(context, e, onRetry: _saveOrder);
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
    // Occupied: only show DB-persisted total; unsaved cart items are not yet ordered
    // Free: show cart total so the user can see what they're building
    final totalAmount = table.isOccupied
        ? table.activeOrderTotal
        : cart.fold<double>(0, (sum, ci) => sum + ci.total);

    final statusBgColor = _statusBgColor(status);
    final statusColor = _statusColor(status);

    final Widget card = Material(
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
                padding: EdgeInsets.all(isTablet ? 14 : 8),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Table Icon Section
                        _buildTableIcon(
                          table,
                          isDark,
                          status == 'OCCUPIED',
                          isTablet,
                        ),
                        const Spacer(),
                        // Status badge + how long the table has been occupied
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 14 : 6,
                            vertical: isTablet ? 7 : 3,
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
                            if (table.isOccupied &&
                                table.occupiedSince != null) ...[
                              SizedBox(height: isTablet ? 6 : 4),
                              _buildElapsedChip(table.occupiedSince!, isTablet),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Bottom row with Details
                    Row(
                      children: [
                        _buildDetailLabel(
                          _sizeLabel.toUpperCase(),
                          isDark,
                          isTablet,
                        ),
                        _buildSeparator(isDark, isTablet),
                        _buildDetailLabel(
                          '${table.seatingCapacity} PAX',
                          isDark,
                          isTablet,
                        ),
                        if (table.isOccupied && table.activeCoverCount > 0) ...[
                          _buildSeparator(isDark, isTablet),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 8 : 5,
                              vertical: isTablet ? 3 : 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${table.activeCoverCount}C',
                              style: GoogleFonts.inter(
                                fontSize: isTablet ? 10 : 8,
                                fontWeight: FontWeight.w800,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 10 : 5,
                            vertical: isTablet ? 4 : 1.5,
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

    // Available tables gently blink (pulse + soft fade) to invite seating.
    if (status == 'FREE') {
      return card
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fadeIn(begin: 0.6, duration: 900.ms, curve: Curves.easeInOut)
          .scaleXY(begin: 1.0, end: 1.02, duration: 900.ms, curve: Curves.easeInOut);
    }
    return card;
  }
}

String _elapsedLabel(DateTime since) {
  final d = DateTime.now().difference(since);
  if (d.isNegative || d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

Widget _buildElapsedChip(DateTime since, bool isTablet) {
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: isTablet ? 8 : 5,
      vertical: isTablet ? 3 : 1.5,
    ),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: isTablet ? 11 : 9, color: AppColors.error),
        const SizedBox(width: 3),
        Text(
          _elapsedLabel(since),
          style: GoogleFonts.inter(
            fontSize: isTablet ? 10 : 8,
            fontWeight: FontWeight.w700,
            color: AppColors.error,
          ),
        ),
      ],
    ),
  );
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

Widget _buildTableIcon(
  CafeTable table,
  bool isDark,
  bool isOccupied,
  bool isTablet,
) {
  final capacity = table.seatingCapacity;

  return SizedBox(
    width: isTablet ? 60 : 44,
    height: isTablet ? 50 : 36,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Dynamic Chairs placement
        ..._buildDynamicChairs(capacity, isDark, isOccupied, isTablet),

        // The Table Surface
        Container(
              width: isTablet ? 38 : 28,
              height: isTablet ? 28 : 20,
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
                borderRadius: BorderRadius.circular(isTablet ? 8 : 6),
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
                  fontSize: isTablet ? 10 : 8,
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

List<Widget> _buildDynamicChairs(
  int capacity,
  bool isDark,
  bool isOccupied,
  bool isTablet,
) {
  final List<Widget> chairs = [];

  // Simple distribution logic:
  // Left & Right (always for 2+)
  chairs.add(
    Positioned(
      left: 0,
      child: _buildChair(isDark, isOccupied, 0, isTablet: isTablet),
    ),
  );
  chairs.add(
    Positioned(
      right: 0,
      child: _buildChair(isDark, isOccupied, 1, isTablet: isTablet),
    ),
  );

  // Top & Bottom (for 4+)
  if (capacity >= 4) {
    chairs.add(
      Positioned(
        top: 0,
        child: _buildChair(
          isDark,
          isOccupied,
          2,
          horizontal: true,
          isTablet: isTablet,
        ),
      ),
    );
    chairs.add(
      Positioned(
        bottom: 0,
        child: _buildChair(
          isDark,
          isOccupied,
          3,
          horizontal: true,
          isTablet: isTablet,
        ),
      ),
    );
  }

  // Extra Chairs for 6+ (additional side chairs)
  if (capacity >= 6) {
    // Offset slightly from center
    chairs.add(
      Positioned(
        left: 0,
        top: isTablet ? 8 : 6,
        child: _buildChair(isDark, isOccupied, 4, isTablet: isTablet),
      ),
    );
    chairs.add(
      Positioned(
        right: 0,
        bottom: isTablet ? 8 : 6,
        child: _buildChair(isDark, isOccupied, 5, isTablet: isTablet),
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
  required bool isTablet,
}) {
  return Container(
        width: horizontal ? (isTablet ? 12 : 8) : (isTablet ? 6 : 4),
        height: horizontal ? (isTablet ? 6 : 4) : (isTablet ? 12 : 8),
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
    final isMobile = size.width < 600;

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
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(isMobile ? 4 : 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
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
                        borderRadius: BorderRadius.circular(8),
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
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                            borderRadius: BorderRadius.circular(6),
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
                              fontSize: isMobile ? 8 : (isTablet ? 8 : 10),
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 2 : 4),
              Text(
                name,
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 9 : 12,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '₹${price.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 8 : 11,
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
      final session = await safeApiCall(
        () => SupabaseService.createOrder(
          companyId: widget.user.companyId,
          tableId: widget.table.id,
          openedBy: widget.user.id,
        ),
      );

      await safeApiCall(
        () => SupabaseService.createBill(
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
        ),
        timeout: const Duration(seconds: 20),
      );

      ref.read(cartProvider(widget.table.id).notifier).clear();
      ref.read(discountProvider.notifier).reset();
      ref.invalidate(tablesProvider(widget.user.companyId));

      if (mounted) {
        Navigator.pop(context);
        AppFeedback.success(
          context,
          'Bill created — ${widget.table.tableName} • ₹${total.toStringAsFixed(0)}',
        );
      }
    } catch (e, st) {
      debugPrint('COMPLETE_BILL_ERROR: $e\n$st');
      if (mounted) AppFeedback.error(context, e, onRetry: _completeTableBill);
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


// ─── Cover Payment Dialog ───────────────────────────────────────────────────
class _CoverPaymentSheet extends StatefulWidget {
  final double total;
  final String coverName;
  const _CoverPaymentSheet({required this.total, required this.coverName});

  @override
  State<_CoverPaymentSheet> createState() => _CoverPaymentSheetState();
}

class _CoverPaymentSheetState extends State<_CoverPaymentSheet> {
  String _mode = 'CASH';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.lightSurface,
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
            style: GoogleFonts.inter(color: AppColors.error, fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_mode),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(
            'Confirm',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
