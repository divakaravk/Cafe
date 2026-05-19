import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/report_provider.dart';
import 'widgets/report_widgets.dart';

class BillsScreen extends ConsumerStatefulWidget {
  final String companyId;
  const BillsScreen({super.key, required this.companyId});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isExpanded = false;
  String _selectedTrendMetric = 'revenue'; // 'revenue' or 'count'

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reportState = ref.watch(reportProvider(widget.companyId));
    final reportNotifier = ref.read(reportProvider(widget.companyId).notifier);
    final dateFormat = DateFormat('dd MMM, hh:mm a');

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, isDark, reportNotifier),

            // Date Filters
            _buildFilters(isDark, reportState, reportNotifier),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () => reportNotifier.fetchReport(),
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  children: [
                    // Summary Cards
                    _buildSummaryMetrics(reportState, isDark),

                    const SizedBox(height: 24),

                    // Charts Section
                    _buildChartsSection(reportState, isDark),

                    const SizedBox(height: 32),

                    // Bills List Title
                    Row(
                      children: [
                        Text(
                          'Recent Bills',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${reportState.bills.length} total',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.textWhiteMuted
                                : AppColors.textDarkMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Bills List
                    if (reportState.isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (reportState.bills.isEmpty)
                      _buildEmptyState(isDark)
                    else ...[
                      ...(_isExpanded
                              ? reportState.bills
                              : reportState.bills.take(5).toList())
                          .map(
                            (bill) =>
                                _BillCard(
                                      bill: bill,
                                      isDark: isDark,
                                      dateFormat: dateFormat,
                                      onTap: () => _showBillDetails(
                                        context,
                                        bill,
                                        isDark,
                                        dateFormat,
                                      ),
                                    )
                                    .animate()
                                    .fadeIn(duration: 400.ms)
                                    .slideY(begin: 0.1, end: 0),
                          ),

                      // Show View All / Show Less button
                      if (reportState.bills.length > 5)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _isExpanded = !_isExpanded;
                                });
                              },
                              borderRadius: BorderRadius.circular(30),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkElevated
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color:
                                        (isDark
                                                ? AppColors.primaryAmber
                                                : AppColors.primaryOrange)
                                            .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _isExpanded
                                          ? 'Show Less'
                                          : 'View All Bills',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppColors.primaryAmber
                                            : AppColors.primaryOrange,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      _isExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 20,
                                      color: isDark
                                          ? AppColors.primaryAmber
                                          : AppColors.primaryOrange,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    ReportNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
          IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.analytics_rounded,
            color: isDark ? AppColors.primaryAmber : AppColors.primaryOrange,
          ),
          const SizedBox(width: 10),
          Text(
            'Reports Dashboard',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => notifier.fetchReport(),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(
    bool isDark,
    ReportState state,
    ReportNotifier notifier,
  ) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          FilterChipWidget(
            label: 'Today',
            isSelected: state.filter == ReportDateFilter.today,
            onTap: () => notifier.setFilter(ReportDateFilter.today),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          FilterChipWidget(
            label: 'Current',
            isSelected: state.filter == ReportDateFilter.thisWeek,
            onTap: () => notifier.setFilter(ReportDateFilter.thisWeek),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          FilterChipWidget(
            label: 'Comparison',
            isSelected: state.filter == ReportDateFilter.weekComparison,
            onTap: () => notifier.setFilter(ReportDateFilter.weekComparison),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          FilterChipWidget(
            label: 'Yearly',
            isSelected: state.filter == ReportDateFilter.yearComparison,
            onTap: () => notifier.setFilter(ReportDateFilter.yearComparison),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          FilterChipWidget(
            label: 'This Month',
            isSelected: state.filter == ReportDateFilter.thisMonth,
            onTap: () => notifier.setFilter(ReportDateFilter.thisMonth),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          FilterChipWidget(
            label:
                state.filter == ReportDateFilter.custom &&
                    state.startDate != null
                ? '${DateFormat('d MMM').format(state.startDate!)} - ${DateFormat('d MMM').format(state.endDate!)}'
                : 'Custom Range',
            isSelected: state.filter == ReportDateFilter.custom,
            onTap: () => _selectCustomDateRange(context, state, notifier),
            isDark: isDark,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  Future<void> _selectCustomDateRange(
    BuildContext context,
    ReportState state,
    ReportNotifier notifier,
  ) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: state.startDate != null && state.endDate != null
          ? DateTimeRange(start: state.startDate!, end: state.endDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: AppColors.primaryAmber,
                    onPrimary: Colors.black,
                    surface: AppColors.darkSurface,
                    onSurface: Colors.white,
                  )
                : ColorScheme.light(
                    primary: AppColors.primaryOrange,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: AppColors.textDark,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      notifier.setFilter(
        ReportDateFilter.custom,
        start: picked.start,
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        ),
      );
    }
  }

  Widget _buildSummaryMetrics(ReportState state, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          MetricCard(
            title: 'Total Revenue',
            value: '₹${state.totalRevenue.toStringAsFixed(0)}',
            icon: Icons.account_balance_wallet_rounded,
            gradient: [const Color(0xFF6A11CB), const Color(0xFF2575FC)],
            isDark: isDark,
          ),
          const SizedBox(width: 16),
          MetricCard(
            title: 'Orders Count',
            value: state.totalOrders.toString(),
            icon: Icons.shopping_basket_rounded,
            gradient: [const Color(0xFFFF9A9E), const Color(0xFFFAD0C4)],
            isDark: isDark,
          ),
          const SizedBox(width: 16),
          MetricCard(
            title: 'Cash Sales',
            value: '₹${state.cashTotal.toStringAsFixed(0)}',
            icon: Icons.payments_rounded,
            gradient: [const Color(0xFF00B09B), const Color(0xFF96C93D)],
            isDark: isDark,
          ),
          const SizedBox(width: 16),
          MetricCard(
            title: 'Digital (UPI/Card)',
            value: '₹${(state.upiTotal + state.cardTotal).toStringAsFixed(0)}',
            icon: Icons.qr_code_rounded,
            gradient: [const Color(0xFFF2994A), const Color(0xFFF2C94C)],
            isDark: isDark,
          ),
        ],
      ),
    ).animate().slideX(begin: 0.1, end: 0, duration: 600.ms);
  }

  Widget _buildChartsSection(ReportState state, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        final salesTrend = _buildChartContainer(
          title: state.filter == ReportDateFilter.thisWeek
              ? 'Payment Mode Trend'
              : state.filter == ReportDateFilter.weekComparison
              ? 'Week-over-Week Comparison'
              : state.filter == ReportDateFilter.yearComparison
              ? 'Year-over-Year Sales'
              : 'Sales Analysis',
          height: 350,
          isDark: isDark,
          action: _buildMetricSelector(isDark),
          child: AnalysisChart(
            state: state,
            isDark: isDark,
            metric: _selectedTrendMetric,
          ),
        );

        final paymentModes = _buildChartContainer(
          title: 'Payment Modes',
          height: 250,
          isDark: isDark,
          child: PaymentSplitChart(
            cash: state.cashTotal,
            upi: state.upiTotal,
            card: state.cardTotal,
            isDark: isDark,
          ),
        );

        final tableSalesChart = _buildChartContainer(
          title: 'Table-wise Sales',
          height: 250,
          isDark: isDark,
          child: TableSalesChart(tableSales: state.tableSales, isDark: isDark),
        );

        if (isWide) {
          return Column(
            children: [
              salesTrend,
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: paymentModes),
                  const SizedBox(width: 16),
                  Expanded(child: tableSalesChart),
                ],
              ),
            ],
          );
        } else {
          return Column(
            children: [
              salesTrend,
              const SizedBox(height: 16),
              paymentModes,
              const SizedBox(height: 16),
              tableSalesChart,
            ],
          );
        }
      },
    );
  }

  Widget _buildChartContainer({
    required String title,
    required double height,
    required Widget child,
    required bool isDark,
    Widget? action,
  }) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.5)
              : AppColors.lightBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildMetricSelector(bool isDark) {
    final activeColor = isDark
        ? AppColors.primaryAmber
        : AppColors.primaryOrange;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MetricOption(
            icon: Icons.currency_rupee_rounded,
            isSelected: _selectedTrendMetric == 'revenue',
            onTap: () => setState(() => _selectedTrendMetric = 'revenue'),
            activeColor: activeColor,
            isDark: isDark,
          ),
          _MetricOption(
            icon: Icons.numbers_rounded,
            isSelected: _selectedTrendMetric == 'count',
            onTap: () => setState(() => _selectedTrendMetric = 'count'),
            activeColor: activeColor,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: isDark
                ? AppColors.textWhiteMuted.withValues(alpha: 0.2)
                : AppColors.textDarkMuted.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No bills found for this period',
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

  void _showBillDetails(
    BuildContext context,
    Bill bill,
    bool isDark,
    DateFormat dateFormat,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill #${bill.billNumber ?? '-'}',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      bill.createdAt != null
                          ? dateFormat.format(bill.createdAt!.toLocal())
                          : '-',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getPaymentColor(
                      bill.paymentMode,
                      isDark,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    bill.paymentMode.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _getPaymentColor(bill.paymentMode, isDark),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 40),
            // Items
            ...bill.items.map(
              (bi) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkElevated
                            : AppColors.lightBg,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${bi.qty}x',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        bi.itemName ?? 'Item',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '₹${bi.total.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 40),
            _detailRow(
              'Subtotal',
              '₹${bill.subtotal.toStringAsFixed(0)}',
              isDark,
            ),
            if (bill.taxAmount > 0)
              _detailRow(
                'Tax',
                '₹${bill.taxAmount.toStringAsFixed(0)}',
                isDark,
              ),
            if (bill.discountAmount > 0)
              _detailRow(
                'Discount',
                '-₹${bill.discountAmount.toStringAsFixed(0)}',
                isDark,
                isError: true,
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                        .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Amount',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '₹${bill.totalAmount.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    bool isDark, {
    bool isError = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark
                  ? AppColors.textWhiteMuted
                  : AppColors.textDarkMuted,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isError
                  ? AppColors.error
                  : (isDark ? Colors.white : AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPaymentColor(String mode, bool isDark) {
    switch (mode.toUpperCase()) {
      case 'CASH':
        return AppColors.success;
      case 'UPI':
        return AppColors.info;
      case 'CARD':
        return AppColors.warning;
      default:
        return isDark ? AppColors.primaryAmber : AppColors.primaryOrange;
    }
  }
}

class _BillCard extends StatelessWidget {
  final Bill bill;
  final bool isDark;
  final DateFormat dateFormat;
  final VoidCallback onTap;

  const _BillCard({
    required this.bill,
    required this.isDark,
    required this.dateFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _paymentColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.3)
              : AppColors.lightBorder.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_paymentIcon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill #${bill.billNumber ?? '-'}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bill.createdAt != null
                          ? dateFormat.format(bill.createdAt!.toLocal())
                          : '-',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${bill.totalAmount.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        bill.paymentMode.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _paymentColor {
    switch (bill.paymentMode.toUpperCase()) {
      case 'CASH':
        return AppColors.success;
      case 'UPI':
        return AppColors.info;
      case 'CARD':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  IconData get _paymentIcon {
    switch (bill.paymentMode.toUpperCase()) {
      case 'CASH':
        return Icons.payments_rounded;
      case 'UPI':
        return Icons.qr_code_rounded;
      case 'CARD':
        return Icons.credit_card_rounded;
      default:
        return Icons.payments_rounded;
    }
  }
}

class _MetricOption extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color activeColor;
  final bool isDark;

  const _MetricOption({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.activeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected
              ? (isDark ? Colors.black : Colors.white)
              : (isDark ? Colors.white38 : Colors.black38),
        ),
      ),
    );
  }
}
