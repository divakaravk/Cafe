import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../core/services/supabase_service.dart';

class KitchenScreen extends ConsumerStatefulWidget {
  final String companyId;
  const KitchenScreen({super.key, required this.companyId});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  Timer? _refreshTimer;
  String _filterStatus = 'all'; // all | new | preparing | ready
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-refresh every 20 seconds, and rebuild UI every 1 second for ticking durations and live clock
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timer.tick % 20 == 0) {
        ref.invalidate(activeKotsProvider(widget.companyId));
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _formatTime() {
    final now = DateTime.now();
    final hour = now.hour > 12
        ? now.hour - 12
        : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  Future<void> _updateKotStatus(KotMaster kot, String newStatus) async {
    try {
      await SupabaseService.updateKotStatus(kot.id, newStatus);
      ref.invalidate(activeKotsProvider(widget.companyId));
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

  Future<void> _updateItemStatus(
    KotMaster kot,
    KotItem item,
    String newStatus,
  ) async {
    try {
      await SupabaseService.updateKotItemStatus(item.id, newStatus);
      ref.invalidate(activeKotsProvider(widget.companyId));
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kotsAsync = ref.watch(activeKotsProvider(widget.companyId));
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 700;
    final showSearchInHeader = size.width > 720;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark, kotsAsync),
            if (!showSearchInHeader)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: _buildSearchBar(isDark, width: double.infinity),
              ),
            kotsAsync.when(
              data: (kots) {
                final total = kots.length;
                final pending = kots
                    .where((k) => k.status == KotStatus.pending)
                    .length;
                final preparing = kots
                    .where((k) => k.status == KotStatus.inProgress)
                    .length;
                final done = kots
                    .where((k) => k.status == KotStatus.done)
                    .length;

                return _buildStatsPanel(
                  isDark,
                  total,
                  pending,
                  preparing,
                  done,
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            _buildFilterBar(isDark, kotsAsync),
            Expanded(
              child: kotsAsync.when(
                data: (kots) {
                  final filtered = _filterStatus == 'all'
                      ? kots
                      : kots.where((k) => k.status == _filterStatus).toList();

                  final searchFiltered = _searchQuery.isEmpty
                      ? filtered
                      : filtered.where((k) {
                          final query = _searchQuery.toLowerCase();
                          final matchesKotNo = k.kotNumber
                              .toLowerCase()
                              .contains(query);
                          final matchesTable =
                              k.tableName != null &&
                              k.tableName!.toLowerCase().contains(query);
                          final matchesItems = k.items.any(
                            (item) => item.itemNameSnapshot
                                .toLowerCase()
                                .contains(query),
                          );
                          return matchesKotNo || matchesTable || matchesItems;
                        }).toList();

                  if (searchFiltered.isEmpty) {
                    return _buildEmptyState(isDark);
                  }

                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(activeKotsProvider(widget.companyId)),
                    child: isTablet
                        ? _buildTabletGrid(searchFiltered, isDark)
                        : _buildMobileList(searchFiltered, isDark),
                  );
                },
                loading: () => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primaryOrange,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Fetching kitchen orders...',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textWhiteMuted
                              : AppColors.textDarkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 40,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 12),
                      Text('Failed to load KOTs', style: GoogleFonts.inter()),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          activeKotsProvider(widget.companyId),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, AsyncValue<List<KotMaster>> kotsAsync) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final showSearchInHeader = size.width > 720;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
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
            icon: Icon(Icons.menu_rounded, size: isMobile ? 22 : 24),
            onPressed: () => Scaffold.of(context).openDrawer(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(width: isMobile ? 8 : 12),
          Container(
            padding: EdgeInsets.all(isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: AppColors.primaryOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
            ),
            child: Icon(
              Icons.restaurant_rounded,
              color: AppColors.primaryOrange,
              size: isMobile ? 16 : 20,
            ),
          ),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kitchen Terminal',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 15 : 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  _formatTime(),
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 12,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (showSearchInHeader) ...[
            const SizedBox(width: 16),
            _buildSearchBar(isDark),
          ],
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: isMobile ? 22 : 24),
            onPressed: () =>
                ref.invalidate(activeKotsProvider(widget.companyId)),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, {double? width}) {
    return SizedBox(
      width: width ?? 260,
      height: 38,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.inter(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search items or tables...',
          hintStyle: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsPanel(
    bool isDark,
    int total,
    int pending,
    int preparing,
    int done,
  ) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Container(
      height: isMobile ? 66 : 74,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildStatCard(
            title: 'Active Orders',
            value: total.toString(),
            icon: Icons.assignment_rounded,
            color: isDark ? AppColors.primaryAmber : AppColors.primaryOrange,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            title: 'Pending',
            value: pending.toString(),
            icon: Icons.hourglass_empty_rounded,
            color: Colors.orange,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            title: 'Preparing',
            value: preparing.toString(),
            icon: Icons.soup_kitchen_rounded,
            color: Colors.blue,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            title: 'Ready',
            value: done.toString(),
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.2 : 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.textWhite : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark, AsyncValue<List<KotMaster>> kotsAsync) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final kots = kotsAsync.value ?? [];
    final counts = {
      'all': kots.length,
      KotStatus.pending: kots
          .where((k) => k.status == KotStatus.pending)
          .length,
      KotStatus.inProgress: kots
          .where((k) => k.status == KotStatus.inProgress)
          .length,
      KotStatus.done: kots.where((k) => k.status == KotStatus.done).length,
    };

    final filters = [
      ('all', 'All', null, Icons.all_inbox_rounded),
      (
        KotStatus.pending,
        'Pending',
        Colors.orange,
        Icons.hourglass_empty_rounded,
      ),
      (
        KotStatus.inProgress,
        'Preparing',
        Colors.blue,
        Icons.soup_kitchen_rounded,
      ),
      (
        KotStatus.done,
        'Done',
        AppColors.success,
        Icons.check_circle_outline_rounded,
      ),
    ];

    return Container(
      height: isMobile ? 32 : 38,
      color: Colors.transparent,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        children: filters.map((f) {
          final key = f.$1;
          final label = f.$2;
          final color = f.$3;
          final icon = f.$4;
          final count = counts[key] ?? 0;
          final isSelected = _filterStatus == key;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filterStatus = key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 12,
                  vertical: isMobile ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (color ?? AppColors.primaryOrange)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : (isDark
                              ? AppColors.darkBorder.withValues(alpha: 0.2)
                              : AppColors.lightBorder.withValues(alpha: 0.4)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: isMobile ? 11 : 13,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                                ? AppColors.textWhiteMuted
                                : AppColors.textDarkMuted),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 9.5 : 10.5,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                  ? AppColors.textWhiteMuted
                                  : AppColors.textDarkMuted),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.25)
                              : (color ?? AppColors.primaryOrange).withValues(
                                  alpha: 0.15,
                                ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 8 : 9,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? Colors.white
                                : (color ?? AppColors.primaryOrange),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabletGrid(List<KotMaster> kots, bool isDark) {
    final size = MediaQuery.of(context).size;
    final crossAxisCount = size.width > 1400
        ? 5
        : size.width > 1100
        ? 4
        : size.width > 800
        ? 3
        : 2;

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: size.width > 1400
            ? 0.98
            : size.width > 1100
            ? 0.94
            : size.width > 800
            ? 0.90
            : 0.85,
      ),
      itemCount: kots.length,
      itemBuilder: (context, i) => _KotCard(
        kot: kots[i],
        isDark: isDark,
        onStatusChange: _updateKotStatus,
        onItemStatusChange: _updateItemStatus,
      ).animate().fadeIn(delay: (40 * i).ms).slideY(begin: 0.04),
    );
  }

  Widget _buildMobileList(List<KotMaster> kots, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: kots.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _KotCard(
          kot: kots[i],
          isDark: isDark,
          shrinkWrap: true,
          onStatusChange: _updateKotStatus,
          onItemStatusChange: _updateItemStatus,
        ).animate().fadeIn(delay: (40 * i).ms).slideY(begin: 0.04),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.done_all_rounded,
                  size: 56,
                  color: AppColors.success,
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.05, 1.05),
                duration: 1500.ms,
              ),
          const SizedBox(height: 20),
          Text(
            'All caught up!',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.textWhite : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _filterStatus == 'all'
                ? 'No active orders right now'
                : 'No orders with "$_filterStatus" status',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── KOT CARD ─────────────────────────────────────────────

class _KotCard extends StatelessWidget {
  final KotMaster kot;
  final bool isDark;
  final bool shrinkWrap;
  final Future<void> Function(KotMaster, String) onStatusChange;
  final Future<void> Function(KotMaster, KotItem, String) onItemStatusChange;

  const _KotCard({
    required this.kot,
    required this.isDark,
    this.shrinkWrap = false,
    required this.onStatusChange,
    required this.onItemStatusChange,
  });

  Color get _statusColor {
    switch (kot.status) {
      case KotStatus.pending:
        return Colors.orange;
      case KotStatus.inProgress:
        return Colors.blue;
      case KotStatus.done:
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  LinearGradient get _headerGradient {
    switch (kot.status) {
      case KotStatus.pending:
        return const LinearGradient(
          colors: [Color(0xFFE65100), Color(0xFFFF8F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case KotStatus.inProgress:
        return const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF03A9F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case KotStatus.done:
        return const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Colors.grey, Colors.blueGrey],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  String get _statusLabel {
    switch (kot.status) {
      case KotStatus.pending:
        return 'NEW ORDER';
      case KotStatus.inProgress:
        return 'COOKING';
      case KotStatus.done:
        return 'READY ✓';
      default:
        return kot.status.toUpperCase();
    }
  }

  String _elapsed() {
    if (kot.createdAt == null) return '';
    final diff = DateTime.now().difference(kot.createdAt!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
  }

  bool _isUrgent() {
    if (kot.createdAt == null) return false;
    return DateTime.now().difference(kot.createdAt!).inMinutes >= 10;
  }

  String? get _nextAction {
    switch (kot.status) {
      case KotStatus.pending:
        return 'Start Preparing';
      case KotStatus.inProgress:
        return 'Mark All Done';
      default:
        return null;
    }
  }

  String? get _nextStatus {
    switch (kot.status) {
      case KotStatus.pending:
        return KotStatus.inProgress;
      case KotStatus.inProgress:
        return KotStatus.done;
      default:
        return null;
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Color _getAvatarColor(String name) {
    final hash = name.codeUnits.fold(0, (prev, elem) => prev + elem);
    final colors = [
      const Color(0xFF8D6E63), // Brown
      const Color(0xFFE65100), // Orange
      const Color(0xFFD84315), // Deep Orange
      const Color(0xFF00796B), // Teal
      const Color(0xFF2E7D32), // Green
      const Color(0xFF1565C0), // Blue
      const Color(0xFF6A1B9A), // Purple
      const Color(0xFFAD1457), // Pink
      const Color(0xFF0288D1), // Light Blue
      const Color(0xFFF57C00), // Tangerine
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 600;
    final bool urgent = _isUrgent();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _statusColor.withValues(alpha: isDark ? 0.25 : 0.2),
          width: urgent ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: urgent
                ? Colors.red.withValues(alpha: isDark ? 0.15 : 0.08)
                : Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: isMobile ? 6 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header with linear gradient
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 12,
              vertical: isMobile ? 8 : 10,
            ),
            decoration: BoxDecoration(
              gradient: _headerGradient,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kot.kotNumber,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 12 : 13.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.table_restaurant_rounded,
                            size: 13,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              kot.tableName != null
                                  ? 'Table ${kot.tableName}'
                                  : 'Take Away / Delivery',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 8 : 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (urgent) ...[
                          const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.white,
                                size: 11,
                              )
                              .animate(
                                onPlay: (controller) =>
                                    controller.repeat(reverse: true),
                              )
                              .scale(
                                begin: const Offset(1, 1),
                                end: const Offset(1.15, 1.15),
                                duration: 600.ms,
                              )
                              .fadeIn(duration: 600.ms),
                          const SizedBox(width: 4),
                        ],
                        Icon(
                          Icons.access_time_rounded,
                          size: isMobile ? 10 : 12,
                          color: urgent ? Colors.white : Colors.white70,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _elapsed(),
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 9 : 10,
                            fontWeight: urgent
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Preparation progress bar
          _buildProgressBar(isMobile),

          // Divider
          Divider(
            height: 1,
            color: isDark
                ? AppColors.darkBorder.withValues(alpha: 0.1)
                : AppColors.lightBorder.withValues(alpha: 0.2),
          ),

          // Items list
          if (shrinkWrap)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 10,
                vertical: isMobile ? 4 : 6,
              ),
              itemCount: kot.items.length,
              itemBuilder: (context, idx) =>
                  _buildItemRow(context, kot.items[idx], isMobile),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 8 : 10,
                  vertical: isMobile ? 4 : 6,
                ),
                itemCount: kot.items.length,
                itemBuilder: (context, idx) =>
                    _buildItemRow(context, kot.items[idx], isMobile),
              ),
            ),

          // Action button
          if (_nextAction != null) ...[
            Divider(
              height: 1,
              color: isDark
                  ? AppColors.darkBorder.withValues(alpha: 0.1)
                  : AppColors.lightBorder.withValues(alpha: 0.2),
            ),
            Padding(
              padding: EdgeInsets.all(isMobile ? 8 : 10),
              child: SizedBox(
                width: double.infinity,
                height: isMobile ? 30 : 36,
                child: ElevatedButton.icon(
                  icon: Icon(
                    kot.status == KotStatus.pending
                        ? Icons.play_arrow_rounded
                        : Icons.done_all_rounded,
                    size: isMobile ? 14 : 16,
                  ),
                  onPressed: () => onStatusChange(kot, _nextStatus!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _statusColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
                    ),
                    padding: EdgeInsets.zero,
                    textStyle: GoogleFonts.inter(
                      fontSize: isMobile ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_nextAction!),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar(bool isMobile) {
    final totalLines = kot.items.length;
    final doneLines = kot.items
        .where(
          (i) =>
              i.status == KotItemStatus.done ||
              i.status == KotItemStatus.voided,
        )
        .length;
    final progress = totalLines > 0 ? doneLines / totalLines : 0.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 12,
        vertical: 5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Preparation Progress',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 10,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$doneLines/$totalLines Items Ready',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 9 : 10,
                  fontWeight: FontWeight.w800,
                  color: progress == 1.0
                      ? AppColors.success
                      : (isDark ? AppColors.textWhite : AppColors.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(
                progress == 1.0 ? AppColors.success : _statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, KotItem item, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 2.5 : 3.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Visual Abbreviation Badge
              Container(
                width: isMobile ? 24 : 28,
                height: isMobile ? 24 : 28,
                decoration: BoxDecoration(
                  color: _getAvatarColor(
                    item.itemNameSnapshot,
                  ).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _getAvatarColor(
                      item.itemNameSnapshot,
                    ).withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _getInitials(item.itemNameSnapshot),
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 8.5 : 9.5,
                    fontWeight: FontWeight.w800,
                    color: _getAvatarColor(item.itemNameSnapshot),
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 6 : 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemNameSnapshot,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textWhite
                            : AppColors.textDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Quantity pill badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 5 : 6,
                  vertical: isMobile ? 2 : 3,
                ),
                margin: EdgeInsets.only(right: isMobile ? 4 : 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${item.qty}x',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 11,
                    fontWeight: FontWeight.w900,
                    color: isDark ? AppColors.textWhite : AppColors.textDark,
                  ),
                ),
              ),
              // Item status toggle chip
              GestureDetector(
                onTap: () => _cycleItemStatus(context, item),
                child: _buildStatusChip(item.status, isMobile),
              ),
            ],
          ),
          // Chef special notes highlighted
          if (item.notes != null && item.notes!.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(left: isMobile ? 30 : 36, top: 3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: isDark ? 0.3 : 0.25),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.feedback_rounded,
                      color: Colors.orange,
                      size: 10,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        item.notes!,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 9 : 10,
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status, bool isMobile) {
    final Color color = _itemStatusColor(status);
    final String label = _itemStatusLabel(status);

    IconData? statusIcon;
    switch (status) {
      case KotItemStatus.pending:
        statusIcon = Icons.hourglass_empty_rounded;
        break;
      case KotItemStatus.inProgress:
        statusIcon = Icons.soup_kitchen_rounded;
        break;
      case KotItemStatus.done:
        statusIcon = Icons.check_circle_rounded;
        break;
      case KotItemStatus.voided:
        statusIcon = Icons.cancel_outlined;
        break;
    }

    final isCooking = status == KotItemStatus.inProgress;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 6 : 8,
        vertical: isMobile ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: status == KotItemStatus.done
            ? color
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: status == KotItemStatus.done
              ? Colors.transparent
              : color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (statusIcon != null) ...[
            if (isCooking)
              const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.2,
                  color: Colors.blue,
                ),
              )
            else
              Icon(
                statusIcon,
                size: isMobile ? 9 : 11,
                color: status == KotItemStatus.done ? Colors.white : color,
              ),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 8 : 9,
              fontWeight: FontWeight.w800,
              color: status == KotItemStatus.done ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }

  void _cycleItemStatus(BuildContext context, KotItem item) {
    final next = _nextItemStatus(item.status);
    if (next != null) onItemStatusChange(kot, item, next);
  }

  String? _nextItemStatus(String current) {
    switch (current) {
      case KotItemStatus.pending:
        return KotItemStatus.inProgress;
      case KotItemStatus.inProgress:
        return KotItemStatus.done;
      default:
        return null;
    }
  }

  Color _itemStatusColor(String status) {
    switch (status) {
      case KotItemStatus.pending:
        return Colors.orange;
      case KotItemStatus.inProgress:
        return Colors.blue;
      case KotItemStatus.done:
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  String _itemStatusLabel(String status) {
    switch (status) {
      case KotItemStatus.pending:
        return 'PENDING';
      case KotItemStatus.inProgress:
        return 'COOKING';
      case KotItemStatus.done:
        return 'DONE';
      case KotItemStatus.voided:
        return 'VOID';
      default:
        return status.toUpperCase();
    }
  }
}
