import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/api_helper.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';

/// Table Master — create and edit dining tables (table layout management).
///
/// Occupied tables (those with an open session) are locked from editing so a
/// table can't be renamed/resized mid-service. Follows the app's standard
/// network → loading → error-with-retry pattern.
class TableMasterScreen extends ConsumerStatefulWidget {
  const TableMasterScreen({super.key});

  @override
  ConsumerState<TableMasterScreen> createState() => _TableMasterScreenState();
}

class _TableMasterScreenState extends ConsumerState<TableMasterScreen> {
  bool _isLoading = false;
  List<CafeTable> _tables = [];
  Object? _loadError;

  // Common section presets surfaced as quick-pick chips in the editor.
  static const _sectionPresets = [
    'Main',
    'AC',
    'Non-AC',
    'Family',
    'Garden',
    'Rooftop',
    'Balcony',
  ];

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  // ─── Network ───────────────────────────────────────────────────────────────

  Future<bool> _hasNetwork() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkNetworkAndWarn() async {
    if (!await _hasNetwork()) {
      _showError('No internet connection. Check your network and retry.');
      return false;
    }
    return true;
  }

  // ─── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadTables() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      if (!await _hasNetwork()) throw const SocketException('offline');
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      final data = await SupabaseService.getTables(
        user.companyId,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _tables = data.map((e) => CafeTable.fromJson(e)).toList()
          ..sort(_compareTables);
      });
    } on TimeoutException {
      if (mounted) setState(() => _loadError = 'timeout');
    } on SocketException {
      if (mounted) setState(() => _loadError = 'network');
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Numeric-aware sort within a section so Table 2 comes before Table 10.
  int _compareTables(CafeTable a, CafeTable b) {
    final secA = (a.section ?? 'Main').toLowerCase();
    final secB = (b.section ?? 'Main').toLowerCase();
    final bySection = secA.compareTo(secB);
    if (bySection != 0) return bySection;
    final na = int.tryParse(a.tableNumber.replaceAll(RegExp(r'[^0-9]'), ''));
    final nb = int.tryParse(b.tableNumber.replaceAll(RegExp(r'[^0-9]'), ''));
    if (na != null && nb != null) return na.compareTo(nb);
    return a.tableNumber.toLowerCase().compareTo(b.tableNumber.toLowerCase());
  }

  /// Returns true when the table was saved, false on any failure (network,
  /// occupancy conflict, server error) so the editor can stay open.
  Future<bool> _saveTable({
    CafeTable? existing,
    required String tableNumber,
    required String section,
    required int capacity,
    required bool isActive,
  }) async {
    if (!await _checkNetworkAndWarn()) return false;

    final user = ref.read(authStateProvider).value;
    if (user == null) return false;

    setState(() => _isLoading = true);
    try {
      // Re-verify occupancy server-side before editing — the table may have
      // been seated since the list was loaded.
      if (existing != null) {
        final occupied = await SupabaseService.isTableOccupied(
          existing.id,
        ).timeout(const Duration(seconds: 10));
        if (occupied) {
          _showError('${existing.tableName} is occupied — finish the order '
              'before editing.');
          await _loadTables(); // reflect the new occupancy in the list
          return false;
        }
        await SupabaseService.updateTable(
          id: existing.id,
          tableNumber: tableNumber,
          section: section,
          seatingCapacity: capacity,
          isActive: isActive,
        ).timeout(const Duration(seconds: 15));
      } else {
        await SupabaseService.createTable(
          companyId: user.companyId,
          tableNumber: tableNumber,
          section: section,
          seatingCapacity: capacity,
          isActive: isActive,
        ).timeout(const Duration(seconds: 15));
      }

      if (mounted) {
        _showSuccess(
          existing == null
              ? 'Table "$tableNumber" added.'
              : 'Table "$tableNumber" updated.',
        );
      }
      // Refresh both this screen and the live Tables screen.
      ref.invalidate(tablesProvider(user.companyId));
      await _loadTables();
      return true;
    } on TimeoutException {
      _showError('Request timed out. Check your connection.');
    } on SocketException {
      _showError('Network error. Check your connection.');
    } catch (e) {
      _showError('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    return false;
  }

  // ─── Feedback ──────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    AppFeedback.success(context, msg);
  }

  void _showError(String msg, {VoidCallback? onRetry}) {
    if (!mounted) return;
    AppFeedback.toast(context, msg, isError: true, onRetry: onRetry);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF0F2F5),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Table Master',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadTables,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Table',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading && _tables.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _tables.isEmpty) {
      return _buildErrorState(isDark);
    }
    if (_tables.isEmpty) {
      return _buildEmptyState(isDark);
    }

    // Group by section, preserving the numeric-aware sort.
    final sections = <String, List<CafeTable>>{};
    for (final t in _tables) {
      sections.putIfAbsent(t.section ?? 'Main', () => []).add(t);
    }
    final sectionKeys = sections.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _loadTables,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          90 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          _buildStatsHeader(isDark),
          const SizedBox(height: 16),
          for (final sec in sectionKeys) ...[
            _buildSectionHeader(sec, sections[sec]!.length, isDark),
            const SizedBox(height: 8),
            ...sections[sec]!.map((t) => _buildTableCard(t, isDark)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsHeader(bool isDark) {
    final total = _tables.length;
    final occupied = _tables.where((t) => t.isOccupied).length;
    final inactive = _tables.where((t) => !t.isActive).length;
    final free = total - occupied - inactive;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryOrange.withValues(alpha: 0.9),
            AppColors.primaryAmber.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryOrange.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _statItem('Tables', total.toString(), Icons.table_bar_rounded),
          ),
          _statDivider(),
          Expanded(
            child: _statItem(
              'Available',
              free.toString(),
              Icons.event_available_rounded,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _statItem(
              'Occupied',
              occupied.toString(),
              Icons.event_busy_rounded,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _statItem(
              'Inactive',
              inactive.toString(),
              Icons.block_rounded,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _statItem(String label, String value, IconData icon) => Column(
    children: [
      Icon(icon, size: 19, color: Colors.white70),
      const SizedBox(height: 4),
      Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: Colors.white70,
        ),
      ),
    ],
  );

  Widget _statDivider() =>
      Container(width: 1, height: 44, color: Colors.white.withValues(alpha: 0.3));

  Widget _buildSectionHeader(String section, int count, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          Icon(
            Icons.chair_alt_rounded,
            size: 16,
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
          const SizedBox(width: 6),
          Text(
            section.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: isDark ? AppColors.textWhite : AppColors.textDark,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primaryOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard(CafeTable table, bool isDark) {
    final occupied = table.isOccupied;
    final inactive = !table.isActive;
    final (Color statusColor, String statusLabel, IconData statusIcon) =
        occupied
        ? (AppColors.error, 'OCCUPIED', Icons.lock_rounded)
        : inactive
        ? (AppColors.textDarkMuted, 'INACTIVE', Icons.block_rounded)
        : (AppColors.success, 'AVAILABLE', Icons.check_circle_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: InkWell(
                  onTap: () => _onEditTap(table),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Table number badge
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            table.tableNumber,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Table ${table.tableNumber}',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: isDark
                                      ? AppColors.textWhite
                                      : AppColors.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.people_alt_rounded,
                                    size: 13,
                                    color: isDark
                                        ? AppColors.textWhiteMuted
                                        : AppColors.textDarkMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${table.seatingCapacity} seats',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppColors.textWhiteMuted
                                          : AppColors.textDarkMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _statusPill(statusColor, statusLabel, statusIcon),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Edit affordance — locked icon when occupied.
                        Icon(
                          occupied ? Icons.lock_rounded : Icons.edit_rounded,
                          size: 18,
                          color: occupied
                              ? AppColors.error.withValues(alpha: 0.7)
                              : (isDark
                                    ? AppColors.textWhiteMuted
                                    : AppColors.textDarkMuted),
                        ),
                      ],
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

  Widget _statusPill(Color color, String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  void _onEditTap(CafeTable table) {
    if (table.isOccupied) {
      _showError(
        'Table ${table.tableNumber} is occupied — finish the order before '
        'editing.',
      );
      return;
    }
    _showEditor(table: table);
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.table_restaurant_rounded,
              size: 46,
              color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No tables yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => _showEditor(),
            icon: const Icon(Icons.add_rounded),
            label: Text('Add your first table', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    final isNetwork = _loadError == 'network' || _loadError == 'timeout';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isNetwork
                    ? Icons.wifi_off_rounded
                    : Icons.error_outline_rounded,
                size: 40,
                color: AppColors.primaryOrange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isNetwork ? 'No Internet Connection' : 'Failed to load tables',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textWhite : AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isNetwork
                  ? 'Check your network and tap Retry'
                  : 'Something went wrong. Please try again.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTables,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Retry',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Editor (bottom sheet) ───────────────────────────────────────────────────

  void _showEditor({CafeTable? table}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TableEditorSheet(
        existing: table,
        sectionPresets: _sectionPresets,
        existingNumbers: _tables
            .where((t) => t.id != table?.id)
            .map((t) => t.tableNumber.toLowerCase())
            .toSet(),
        onSave:
            ({
              required tableNumber,
              required section,
              required capacity,
              required isActive,
            }) => _saveTable(
              existing: table,
              tableNumber: tableNumber,
              section: section,
              capacity: capacity,
              isActive: isActive,
            ),
      ),
    );
  }
}

// ─── Editor Sheet ─────────────────────────────────────────────────────────────

class _TableEditorSheet extends StatefulWidget {
  final CafeTable? existing;
  final List<String> sectionPresets;
  final Set<String> existingNumbers;
  final Future<bool> Function({
    required String tableNumber,
    required String section,
    required int capacity,
    required bool isActive,
  })
  onSave;

  const _TableEditorSheet({
    required this.existing,
    required this.sectionPresets,
    required this.existingNumbers,
    required this.onSave,
  });

  @override
  State<_TableEditorSheet> createState() => _TableEditorSheetState();
}

class _TableEditorSheetState extends State<_TableEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numberController;
  late final TextEditingController _sectionController;
  late int _capacity;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _numberController = TextEditingController(text: e?.tableNumber ?? '');
    _sectionController = TextEditingController(text: e?.section ?? 'Main');
    _capacity = e?.seatingCapacity ?? 4;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _numberController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await widget.onSave(
      tableNumber: _numberController.text.trim(),
      section: _sectionController.text.trim(),
      capacity: _capacity,
      isActive: _isActive,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    // Keep the sheet open on failure so the user can fix and retry.
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + mq.padding.bottom),
        child: Form(
          key: _formKey,
          // Scrollable so fields lift above the on-screen keyboard instead of
          // overflowing — the Section field is otherwise hidden behind it.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isEdit
                          ? Icons.edit_rounded
                          : Icons.add_business_rounded,
                      color: AppColors.primaryOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEdit ? 'Edit Table' : 'Add Table',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Table number
              TextFormField(
                controller: _numberController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  LengthLimitingTextInputFormatter(10),
                ],
                style: GoogleFonts.inter(fontSize: 14),
                decoration: _dec(isDark, 'Table Number', Icons.tag_rounded),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Required';
                  if (widget.existingNumbers.contains(t.toLowerCase())) {
                    return 'Table "$t" already exists';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Section
              TextFormField(
                controller: _sectionController,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.inter(fontSize: 14),
                // Rebuild so the preset chips highlight the typed section.
                onChanged: (_) => setState(() {}),
                decoration: _dec(
                  isDark,
                  'Section / Area',
                  Icons.dashboard_customize_rounded,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.sectionPresets.map((s) {
                  final selected =
                      _sectionController.text.trim().toLowerCase() ==
                      s.toLowerCase();
                  return GestureDetector(
                    onTap: () => setState(() => _sectionController.text = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryOrange.withValues(alpha: 0.14)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.04)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.primaryOrange
                              : (isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder),
                        ),
                      ),
                      child: Text(
                        s,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.primaryOrange
                              : (isDark
                                    ? AppColors.textWhiteMuted
                                    : AppColors.textDarkMuted),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // Seating capacity stepper
              Row(
                children: [
                  Icon(
                    Icons.people_alt_rounded,
                    size: 18,
                    color: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Seating capacity',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textWhite : AppColors.textDark,
                    ),
                  ),
                  const Spacer(),
                  _stepperButton(
                    Icons.remove_rounded,
                    isDark,
                    _capacity > 1
                        ? () => setState(() => _capacity--)
                        : null,
                  ),
                  Container(
                    width: 44,
                    alignment: Alignment.center,
                    child: Text(
                      '$_capacity',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _stepperButton(
                    Icons.add_rounded,
                    isDark,
                    _capacity < 50
                        ? () => setState(() => _capacity++)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 24),

              // Active toggle
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textWhite
                                : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Inactive tables are hidden from billing',
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
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeThumbColor: AppColors.success,
                    activeTrackColor: AppColors.success.withValues(alpha: 0.35),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Save
              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primaryOrange.withValues(
                      alpha: 0.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isEdit
                                  ? Icons.check_circle_rounded
                                  : Icons.add_rounded,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isEdit ? 'SAVE CHANGES' : 'ADD TABLE',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
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

  Widget _stepperButton(IconData icon, bool isDark, VoidCallback? onTap) {
    return Material(
      color: onTap == null
          ? (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03))
          : AppColors.primaryOrange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? (isDark
                      ? AppColors.textWhiteMuted.withValues(alpha: 0.4)
                      : AppColors.textDarkMuted.withValues(alpha: 0.4))
                : AppColors.primaryOrange,
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(bool isDark, String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(fontSize: 13),
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: isDark ? AppColors.darkBg : const Color(0xFFF7F8FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryOrange, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
