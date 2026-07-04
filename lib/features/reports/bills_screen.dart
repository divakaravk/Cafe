import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../providers/report_provider.dart';
import '../../providers/providers.dart'
    show allItemsProvider, permissionsProvider, companyProvider;
import '../../core/services/supabase_service.dart';
import '../../core/utils/api_helper.dart';
import 'widgets/report_widgets.dart';

class BillsScreen extends ConsumerStatefulWidget {
  final String companyId;
  const BillsScreen({super.key, required this.companyId});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  String _searchQuery = '';
  String _selectedPaymentFilter = 'ALL'; // 'ALL', 'CASH', 'UPI', 'CARD'
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reportState = ref.watch(reportProvider(widget.companyId));
    final reportNotifier = ref.read(reportProvider(widget.companyId).notifier);
    final dateFormat = DateFormat('dd MMM, hh:mm a');
    final itemsAsync = ref.watch(allItemsProvider(widget.companyId));

    // Map item category
    final Map<String, String> itemToCategory = {};
    if (itemsAsync.hasValue) {
      for (final item in itemsAsync.value!) {
        itemToCategory[item.id] = item.sectionLabel ?? 'Uncategorized';
      }
    }

    // Category Sales
    final Map<String, double> categorySales = {};
    for (var bill in reportState.bills) {
      for (var item in bill.items) {
        final category = itemToCategory[item.itemId] ?? 'Uncategorized';
        categorySales[category] = (categorySales[category] ?? 0.0) + item.total;
      }
    }

    // Top Items
    final Map<String, int> itemQuantities = {};
    final Map<String, double> itemRevenues = {};
    for (var bill in reportState.bills) {
      for (var item in bill.items) {
        final name = item.itemName ?? 'Unknown Item';
        itemQuantities[name] = (itemQuantities[name] ?? 0) + item.qty.toInt();
        itemRevenues[name] = (itemRevenues[name] ?? 0) + item.total;
      }
    }

    // Hourly sales
    final Map<int, double> hourlySales = {};
    for (var bill in reportState.bills) {
      if (bill.createdAt == null) continue;
      final hour = bill.createdAt!.toLocal().hour;
      hourlySales[hour] = (hourlySales[hour] ?? 0) + bill.totalAmount;
    }

    // Total tax and discount
    final totalTax = reportState.bills.fold<double>(
      0.0,
      (sum, b) => sum + b.taxAmount,
    );
    final totalDiscount = reportState.bills.fold<double>(
      0.0,
      (sum, b) => sum + b.discountAmount,
    );
    final aov = reportState.totalOrders > 0
        ? reportState.totalRevenue / reportState.totalOrders
        : 0.0;

    // Filter bills for ledger
    final filteredBills = reportState.bills.where((bill) {
      final matchesSearch =
          bill.billNumber?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
          false;
      final matchesPayment =
          _selectedPaymentFilter == 'ALL' ||
          bill.paymentMode.toUpperCase() == _selectedPaymentFilter;
      return matchesSearch && matchesPayment;
    }).toList();

    // Insights Highlights
    String paymentInsight = "";
    if (reportState.totalRevenue > 0) {
      final cashShare =
          (reportState.cashTotal / reportState.totalRevenue) * 100;
      final upiShare = (reportState.upiTotal / reportState.totalRevenue) * 100;
      final cardShare =
          (reportState.cardTotal / reportState.totalRevenue) * 100;

      if (upiShare > cashShare && upiShare > cardShare) {
        paymentInsight =
            "UPI is your most popular payment mode, contributing ${upiShare.toStringAsFixed(0)}% of total revenue.";
      } else if (cashShare > upiShare && cashShare > cardShare) {
        paymentInsight =
            "Cash transactions dominate, accounting for ${cashShare.toStringAsFixed(0)}% of total sales.";
      } else if (cardShare > cashShare && cardShare > upiShare) {
        paymentInsight =
            "Card payments are leading, making up ${cardShare.toStringAsFixed(0)}% of sales.";
      } else {
        paymentInsight =
            "Digital payments (UPI/Card) comprise the majority of sales.";
      }
    } else {
      paymentInsight = "No transactions recorded yet for this period.";
    }

    String hourlyInsight = "";
    if (hourlySales.isNotEmpty) {
      final sortedHours = hourlySales.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final peakHour = sortedHours.first.key;
      final displayHour = peakHour == 0
          ? '12 AM'
          : peakHour == 12
          ? '12 PM'
          : peakHour > 12
          ? '${peakHour - 12} PM'
          : '$peakHour AM';
      hourlyInsight =
          "Peak sales hour is $displayHour, bringing in ₹${sortedHours.first.value.toStringAsFixed(0)}.";
    } else {
      hourlyInsight = "Operating hours metrics will load once sales occur.";
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(
                context,
                isDark,
                reportNotifier,
                () => _exportReportPdf(context, reportState, itemToCategory),
              ),

              // Loading progress strip
              if (reportState.isLoading)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: isDark
                      ? AppColors.primaryAmber
                      : AppColors.primaryOrange,
                  backgroundColor: Colors.transparent,
                ),

              // Error banner
              if (!reportState.isLoading && reportState.error != null)
                _buildErrorBanner(reportState.error!, isDark, reportNotifier),

              // Date Filters
              if (_showFilters)
                _buildFilters(isDark, reportState, reportNotifier),

              // TabBar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder.withValues(alpha: 0.3)
                          : AppColors.lightBorder.withValues(alpha: 0.5),
                    ),
                  ),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    labelColor: isDark ? Colors.black : Colors.white,
                    unselectedLabelColor: isDark
                        ? AppColors.textWhiteMuted
                        : AppColors.textDarkMuted,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Insights'),
                      Tab(text: 'Audit Ledger'),
                    ],
                  ),
                ),
              ),

              // TabBarView
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Overview Dashboard
                    _buildOverviewTab(reportState, isDark, paymentInsight),

                    // Tab 2: Product & Category Insights
                    _buildInsightsTab(
                      reportState,
                      isDark,
                      categorySales,
                      itemQuantities,
                      itemRevenues,
                      hourlyInsight,
                    ),

                    // Tab 3: Operations & Audit
                    _buildAuditTab(
                      context,
                      reportState,
                      isDark,
                      filteredBills,
                      totalTax,
                      totalDiscount,
                      aov,
                      dateFormat,
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

  Widget _buildOverviewTab(
    ReportState reportState,
    bool isDark,
    String paymentInsight,
  ) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(reportProvider(widget.companyId).notifier).fetchReport(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          // Summary Cards
          _buildSummaryMetrics(reportState, isDark),
          const SizedBox(height: 20),

          // StatInsightCard
          StatInsightCard(
            insightText: paymentInsight,
            icon: Icons.lightbulb_outline_rounded,
            iconColor: AppColors.primaryAmber,
            isDark: isDark,
          ),
          const SizedBox(height: 20),

          // Charts Section
          _buildChartsSection(reportState, isDark),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInsightsTab(
    ReportState reportState,
    bool isDark,
    Map<String, double> categorySales,
    Map<String, int> itemQuantities,
    Map<String, double> itemRevenues,
    String hourlyInsight,
  ) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(reportProvider(widget.companyId).notifier).fetchReport(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          StatInsightCard(
            insightText: hourlyInsight,
            icon: Icons.query_builder_rounded,
            iconColor: AppColors.accentTeal,
            isDark: isDark,
          ),
          const SizedBox(height: 20),

          // Category sales distribution
          _buildChartContainer(
            title: 'Sales by Category',
            height: 250,
            isDark: isDark,
            child: CategoryPieChart(
              categorySales: categorySales,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 20),

          // Top selling items list
          _buildChartContainer(
            title: 'Top Selling Items',
            height: 250,
            isDark: isDark,
            child: SingleChildScrollView(
              child: TopSellingItemsList(
                itemQuantities: itemQuantities,
                itemRevenues: itemRevenues,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Table sales
          _buildChartContainer(
            title: 'Sales by Table',
            height: 250,
            isDark: isDark,
            child: TableSalesChart(
              tableSales: reportState.tableSales,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 20),

          // Cover sales
          _buildChartContainer(
            title: 'Cover-wise Sales',
            height: reportState.coverEntries.isEmpty
                ? 120
                : (reportState.coverEntries.length * 72.0 + 60).clamp(
                    120,
                    500,
                  ),
            isDark: isDark,
            child: SingleChildScrollView(
              child: CoverSalesWidget(
                coverEntries: reportState.coverEntries,
                totalRevenue: reportState.totalRevenue,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAuditTab(
    BuildContext context,
    ReportState reportState,
    bool isDark,
    List<Bill> filteredBills,
    double totalTax,
    double totalDiscount,
    double aov,
    DateFormat dateFormat,
  ) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(reportProvider(widget.companyId).notifier).fetchReport(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          // Busy hours hourly chart
          _buildChartContainer(
            title: 'Hourly Sales Peak (Busy Hours)',
            height: 250,
            isDark: isDark,
            child: HourlySalesChart(
              hourlySales: {
                for (var bill in reportState.bills)
                  if (bill.createdAt != null)
                    bill.createdAt!.toLocal().hour: reportState.bills
                        .where(
                          (b) =>
                              b.createdAt != null &&
                              b.createdAt!.toLocal().hour ==
                                  bill.createdAt!.toLocal().hour,
                        )
                        .fold<double>(0.0, (sum, b) => sum + b.totalAmount),
              },
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 20),

          // Tax and discounts breakdown card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder.withValues(alpha: 0.3)
                    : AppColors.lightBorder.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tax & Audit Summary',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 16),
                _detailRow(
                  'Gross Revenue',
                  '₹${reportState.totalRevenue.toStringAsFixed(2)}',
                  isDark,
                ),
                _detailRow(
                  'Gross Subtotal (Before Tax)',
                  '₹${reportState.totalGrossAmount.toStringAsFixed(2)}',
                  isDark,
                ),
                _detailRow(
                  'Total Tax Collected (CGST + SGST)',
                  '₹${totalTax.toStringAsFixed(2)}',
                  isDark,
                ),
                _detailRow(
                  'Total Discount Offered',
                  '₹${totalDiscount.toStringAsFixed(2)}',
                  isDark,
                  isError: true,
                ),
                _detailRow(
                  'Average Order Value (AOV)',
                  '₹${aov.toStringAsFixed(2)}',
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Ledger Title and Search
          Row(
            children: [
              Text(
                'Audit Ledger',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '${filteredBills.length} matched',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search ledger bar
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            decoration: InputDecoration(
              hintText: 'Search bill number...',
              hintStyle: GoogleFonts.inter(
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
              filled: true,
              fillColor: isDark ? AppColors.darkSurface : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.5)
                      : AppColors.lightBorder.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Filter chips for payment mode
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', 'CASH', 'UPI', 'CARD'].map((mode) {
                final isSel = _selectedPaymentFilter == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(mode),
                    selected: isSel,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedPaymentFilter = mode);
                      }
                    },
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSel
                          ? Colors.white
                          : (isDark
                                ? AppColors.textWhiteMuted
                                : AppColors.textDarkMuted),
                    ),
                    selectedColor: isDark
                        ? AppColors.primaryAmber
                        : AppColors.primaryOrange,
                    backgroundColor: isDark
                        ? AppColors.darkSurface
                        : Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Bills ledger list
          if (filteredBills.isEmpty)
            _buildEmptyState(isDark)
          else
            ...filteredBills.map(
              (bill) => _BillCard(
                bill: bill,
                isDark: isDark,
                dateFormat: dateFormat,
                onTap: () =>
                    _showBillDetails(context, bill, isDark, dateFormat),
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    ReportNotifier notifier,
    VoidCallback onExportPdf,
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
          Expanded(
            child: Text(
              'Reports Dashboard',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _showFilters
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
              color: _showFilters
                  ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                  : null,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            tooltip: 'Toggle Filters',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: onExportPdf,
            tooltip: 'Export PDF',
          ),
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
            label: 'This Week',
            isSelected: state.filter == ReportDateFilter.thisWeek,
            onTap: () => notifier.setFilter(ReportDateFilter.thisWeek),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          FilterChipWidget(
            label: 'Week Comparison',
            isSelected: state.filter == ReportDateFilter.weekComparison,
            onTap: () => notifier.setFilter(ReportDateFilter.weekComparison),
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          FilterChipWidget(
            label: 'Year Comparison',
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
                    state.startDate != null &&
                    state.endDate != null
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
    final totalRevenue = state.totalRevenue;
    final totalOrders = state.totalOrders;
    final aov = totalOrders > 0 ? totalRevenue / totalOrders : 0.0;

    double? revenueTrend;
    if (state.comparisonBills.isNotEmpty) {
      final prevRevenue = state.comparisonBills.fold<double>(
        0.0,
        (sum, b) => sum + b.totalAmount,
      );
      if (prevRevenue > 0) {
        revenueTrend = ((totalRevenue - prevRevenue) / prevRevenue) * 100;
      }
    }

    double? ordersTrend;
    if (state.comparisonBills.isNotEmpty) {
      final prevOrders = state.comparisonBills.length;
      if (prevOrders > 0) {
        ordersTrend = ((totalOrders - prevOrders) / prevOrders) * 100;
      }
    }

    final cashShare = totalRevenue > 0 ? (state.cashTotal / totalRevenue) : 0.0;
    final digitalShare = totalRevenue > 0
        ? ((state.upiTotal + state.cardTotal) / totalRevenue)
        : 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Total Revenue',
                value: '₹${state.totalRevenue.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet_rounded,
                gradient: const [Color(0xFF6A11CB), Color(0xFF2575FC)],
                isDark: isDark,
                subtext: 'Avg. Ticket: ₹${aov.toStringAsFixed(0)}',
                trendText: revenueTrend != null
                    ? '${revenueTrend >= 0 ? '+' : ''}${revenueTrend.toStringAsFixed(1)}%'
                    : null,
                isPositive: revenueTrend == null || revenueTrend >= 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: 'Orders Count',
                value: state.totalOrders.toString(),
                icon: Icons.shopping_basket_rounded,
                gradient: const [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
                isDark: isDark,
                subtext: 'Processed Bills',
                trendText: ordersTrend != null
                    ? '${ordersTrend >= 0 ? '+' : ''}${ordersTrend.toStringAsFixed(1)}%'
                    : null,
                isPositive: ordersTrend == null || ordersTrend >= 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Cash Sales',
                value: '₹${state.cashTotal.toStringAsFixed(0)}',
                icon: Icons.payments_rounded,
                gradient: const [Color(0xFF00B09B), Color(0xFF96C93D)],
                isDark: isDark,
                progress: cashShare,
                subtext:
                    '${(cashShare * 100).toStringAsFixed(0)}% of total sales',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: 'Digital (UPI/Card)',
                value:
                    '₹${(state.upiTotal + state.cardTotal).toStringAsFixed(0)}',
                icon: Icons.qr_code_rounded,
                gradient: const [Color(0xFFF2994A), Color(0xFFF2C94C)],
                isDark: isDark,
                progress: digitalShare,
                subtext:
                    '${(digitalShare * 100).toStringAsFixed(0)}% of total sales',
              ),
            ),
          ],
        ),
      ],
    ).animate().slideY(begin: 0.1, end: 0, duration: 600.ms);
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
          child: AnalysisChart(
            state: state,
            isDark: isDark,
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
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
              ),
              if (action != null) ...[const SizedBox(width: 8), action],
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(
    String error,
    bool isDark,
    ReportNotifier notifier,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => notifier.fetchReport(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
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
    final perms = ref.read(permissionsProvider);
    final canEdit = perms?.canEditBill ?? false;
    final canCancel = perms?.canCancelBill ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bill #${bill.billNumber ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        bill.createdAt != null
                            ? dateFormat.format(bill.createdAt!.toLocal())
                            : '-',
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
                const SizedBox(width: 12),
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
            if (bill.isCancelled) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cancel_rounded,
                      color: AppColors.error,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'This bill has been cancelled',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                        '${bi.qty.toStringAsFixed(0)}x',
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
            // Edit / Cancel actions — only for live bills the user is allowed
            // to modify. Cancelled bills are read-only.
            if (!bill.isCancelled && (canEdit || canCancel)) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  if (canEdit)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _editBill(bill, isDark, dateFormat);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark
                              ? AppColors.primaryAmber
                              : AppColors.primaryOrange,
                          side: BorderSide(
                            color: isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: Text(
                          'Edit Bill',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (canEdit && canCancel) const SizedBox(width: 12),
                  if (canCancel)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _cancelBill(sheetContext, bill),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.cancel_rounded, size: 18),
                        label: Text(
                          'Cancel Bill',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Confirms then cancels (voids) a bill. The [sheetContext] is the bill
  /// detail sheet, popped on success.
  Future<void> _cancelBill(BuildContext sheetContext, Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.cancel_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Cancel Bill?',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          content: Text(
            'Bill #${bill.billNumber ?? '-'} (₹${bill.totalAmount.toStringAsFixed(0)}) will be marked cancelled and removed from revenue totals. This cannot be undone.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Keep Bill',
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
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Cancel Bill',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await SupabaseService.cancelBill(billId: bill.id);
      await ref.read(reportProvider(widget.companyId).notifier).fetchReport();
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) {
        AppFeedback.success(
          context,
          'Bill #${bill.billNumber ?? '-'} cancelled',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.toast(context, 'Failed to cancel bill: $e', isError: true);
      }
    }
  }

  void _editBill(Bill bill, bool isDark, DateFormat dateFormat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillEditSheet(
        bill: bill,
        companyId: widget.companyId,
        isDark: isDark,
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

  Future<void> _exportReportPdf(
    BuildContext context,
    ReportState reportState,
    Map<String, String> itemToCategory,
  ) async {
    // ── Brand palette (restrained, corporate) ───────────────────────
    const slate = PdfColor.fromInt(0xFF0F172A); // header band / table head
    const orange = PdfColor.fromInt(0xFFEA580C); // brand accent
    const dark = PdfColor.fromInt(0xFF1F2937); // body text
    const muted = PdfColor.fromInt(0xFF6B7280); // secondary text
    const line = PdfColor.fromInt(0xFFE5E7EB); // hairlines / borders
    const stripe = PdfColor.fromInt(0xFFF8FAFC); // zebra rows
    const green = PdfColor.fromInt(0xFF059669);
    const blue = PdfColor.fromInt(0xFF2563EB);
    const amber = PdfColor.fromInt(0xFFD97706);
    const red = PdfColor.fromInt(0xFFDC2626);

    // ── Data (exclude cancelled bills from money figures) ───────────
    final company = ref.read(companyProvider(widget.companyId)).value;
    final companyName = company?.companyName ?? 'Sales Report';
    final validBills = reportState.validBills;

    final totalRevenue = reportState.totalRevenue;
    final totalOrders = reportState.totalOrders;
    final cashTotal = reportState.cashTotal;
    final upiTotal = reportState.upiTotal;
    final cardTotal = reportState.cardTotal;
    final totalTax = validBills.fold<double>(0.0, (s, b) => s + b.taxAmount);
    final totalDiscount =
        validBills.fold<double>(0.0, (s, b) => s + b.discountAmount);
    final aov = totalOrders > 0 ? totalRevenue / totalOrders : 0.0;

    String money(num v) => 'Rs ${v.toStringAsFixed(2)}';
    String moneyShort(num v) => 'Rs ${v.toStringAsFixed(0)}';
    String pct(num part) =>
        totalRevenue > 0 ? '${(part / totalRevenue * 100).toStringAsFixed(1)}%' : '0%';

    // Category sales
    final Map<String, double> categorySales = {};
    for (final bill in validBills) {
      for (final item in bill.items) {
        final c = itemToCategory[item.itemId] ?? 'Uncategorized';
        categorySales[c] = (categorySales[c] ?? 0.0) + item.total;
      }
    }
    final sortedCategories = categorySales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Top selling items (qty + revenue)
    final Map<String, int> itemQty = {};
    final Map<String, double> itemRev = {};
    for (final bill in validBills) {
      for (final item in bill.items) {
        final name = item.itemName ?? 'Unknown Item';
        itemQty[name] = (itemQty[name] ?? 0) + item.qty.toInt();
        itemRev[name] = (itemRev[name] ?? 0) + item.total;
      }
    }
    final topItems = itemQty.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final dateRangeStr =
        reportState.filter == ReportDateFilter.custom &&
            reportState.startDate != null &&
            reportState.endDate != null
        ? '${DateFormat('dd MMM yyyy').format(reportState.startDate!)} - ${DateFormat('dd MMM yyyy').format(reportState.endDate!)}'
        : reportState.filter
              .toString()
              .split('.')
              .last
              .replaceAllMapped(
                RegExp('[A-Z]'),
                (m) => ' ${m[0]}',
              )
              .trim()
              .toUpperCase();

    // ── Reusable PDF builders ───────────────────────────────────────
    pw.Widget kpiCard(String label, String value, PdfColor accent) {
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 4),
          padding: const pw.EdgeInsets.fromLTRB(12, 11, 12, 12),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: line, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    width: 7,
                    height: 7,
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        fontSize: 7,
                        color: muted,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 14,
                  color: dark,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    pw.Widget sectionTitle(String t) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(width: 3, height: 13, color: orange),
              pw.SizedBox(width: 8),
              pw.Text(
                t.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: slate,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Container(height: 0.8, color: line),
        ],
      ),
    );

    pw.Widget styledTable({
      required List<String> headers,
      required List<List<String>> data,
      Map<int, pw.Alignment>? alignments,
    }) {
      return pw.TableHelper.fromTextArray(
        headers: headers,
        data: data.isEmpty ? [List.filled(headers.length, '-')] : data,
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          fontSize: 8.5,
          letterSpacing: 0.3,
        ),
        headerDecoration: const pw.BoxDecoration(color: slate),
        headerHeight: 26,
        cellHeight: 22,
        cellStyle: const pw.TextStyle(fontSize: 9, color: dark),
        oddRowDecoration: const pw.BoxDecoration(color: stripe),
        cellAlignments: alignments,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: line, width: 0.5),
          bottom: pw.BorderSide(color: line, width: 0.5),
        ),
        headerAlignment: pw.Alignment.centerLeft,
      );
    }

    // Embed a real Unicode font. The pdf package's built-in Helvetica is a
    // non-embedded Type1 font that some Android print-preview rasterizers show
    // as a BLANK page — embedding NotoSans makes the report render everywhere
    // (and avoids missing-glyph crashes for ₹/extended characters).
    pw.ThemeData? theme;
    try {
      theme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
      );
    } catch (_) {
      theme = null; // offline / font fetch failed → fall back to default
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        footer: (ctx) => pw.Column(
          children: [
            pw.Container(height: 0.5, color: line),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: muted,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          ],
        ),
        build: (pw.Context context) => [
          // ── Branded header band ──────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: slate,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    // Brand monogram
                    pw.Container(
                      width: 36,
                      height: 36,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: orange,
                        borderRadius: pw.BorderRadius.circular(9),
                      ),
                      child: pw.Text(
                        companyName.isNotEmpty
                            ? companyName[0].toUpperCase()
                            : 'R',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Row(
                          children: [
                            pw.Text(
                              'SALES REPORT',
                              style: pw.TextStyle(
                                fontSize: 8,
                                color: orange,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            pw.Text(
                              '   ·   $dateRangeStr',
                              style: const pw.TextStyle(
                                fontSize: 8,
                                color: PdfColor.fromInt(0xFFCBD5E1),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'GENERATED',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColor.fromInt(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      DateFormat('dd MMM yyyy').format(DateTime.now()),
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      DateFormat('hh:mm a').format(DateTime.now()),
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColor.fromInt(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),

          // ── KPI cards ────────────────────────────────────────
          pw.Row(
            children: [
              kpiCard('Total Revenue', moneyShort(totalRevenue), green),
              kpiCard('Total Orders', '$totalOrders', blue),
              kpiCard('Avg Ticket', moneyShort(aov), orange),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              kpiCard('Tax Collected', moneyShort(totalTax), amber),
              kpiCard('Discounts', moneyShort(totalDiscount), red),
              kpiCard(
                'Net Subtotal',
                moneyShort(reportState.totalGrossAmount),
                blue,
              ),
            ],
          ),
          pw.SizedBox(height: 24),

          // ── Payment breakdown ────────────────────────────────
          sectionTitle('Payment Mode Breakdown'),
          styledTable(
            headers: ['Payment Mode', 'Amount', 'Share'],
            data: [
              ['Cash', money(cashTotal), pct(cashTotal)],
              ['UPI', money(upiTotal), pct(upiTotal)],
              ['Card', money(cardTotal), pct(cardTotal)],
              ['Total', money(totalRevenue), '100%'],
            ],
            alignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 24),

          // ── Category sales ───────────────────────────────────
          sectionTitle('Category Sales Breakdown'),
          styledTable(
            headers: ['Category / Section', 'Revenue', 'Share'],
            data: sortedCategories
                .map((e) => [e.key, money(e.value), pct(e.value)])
                .toList(),
            alignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 24),

          // ── Top selling items ────────────────────────────────
          sectionTitle('Top Selling Items'),
          styledTable(
            headers: ['#', 'Item Name', 'Qty Sold', 'Revenue'],
            data: [
              for (var i = 0; i < topItems.take(10).length; i++)
                [
                  '${i + 1}',
                  topItems[i].key,
                  '${topItems[i].value}',
                  money(itemRev[topItems[i].key] ?? 0),
                ],
            ],
            alignments: {
              0: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 24),

          // ── Bill ledger ──────────────────────────────────────
          sectionTitle('Bill Ledger (${reportState.bills.length})'),
          styledTable(
            headers: ['Bill #', 'Date', 'Mode', 'Amount', 'Status'],
            data: reportState.bills.map((b) {
              return [
                b.billNumber ?? '-',
                b.createdAt != null
                    ? DateFormat('dd/MM hh:mm a').format(b.createdAt!.toLocal())
                    : '-',
                b.paymentMode.toUpperCase(),
                money(b.totalAmount),
                b.isCancelled ? 'CANCELLED' : 'PAID',
              ];
            }).toList(),
            alignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.center,
            },
          ),
        ],
      ),
    );

    try {
      // Build the bytes up-front so any layout error is caught here.
      final bytes = await pdf.save();
      final filename =
          'Sales_Report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

      // Share/save the file directly instead of the in-app print PREVIEW —
      // the preview's rasterizer renders blank on some Android devices, but
      // the actual PDF bytes are valid. sharePdf hands them to the OS (save to
      // Files / open in a real PDF viewer / Drive), which is the reliable
      // "download" path.
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (context.mounted) {
        AppFeedback.toast(
          context,
          'Failed to generate report PDF: $e',
          isError: true,
        );
      }
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Bill #${bill.billNumber ?? '-'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              decoration: bill.isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (bill.isCancelled) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'CANCELLED',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ],
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

/// Editable bill sheet — adjust line quantities, remove items, then save.
/// Recomputes subtotal/tax/total live and persists via [SupabaseService.updateBill].
class _BillEditSheet extends ConsumerStatefulWidget {
  final Bill bill;
  final String companyId;
  final bool isDark;

  const _BillEditSheet({
    required this.bill,
    required this.companyId,
    required this.isDark,
  });

  @override
  ConsumerState<_BillEditSheet> createState() => _BillEditSheetState();
}

class _BillEditSheetState extends ConsumerState<_BillEditSheet> {
  // Working copy of quantities keyed by bill_item id, plus removed ids.
  late final Map<String, double> _qty;
  final Set<String> _removed = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qty = {for (final it in widget.bill.items) it.id: it.qty};
  }

  List<BillItem> get _remaining =>
      widget.bill.items.where((it) => !_removed.contains(it.id)).toList();

  double get _subtotal => _remaining.fold(
    0.0,
    (sum, it) => sum + (_qty[it.id] ?? it.qty) * it.rate,
  );

  double get _tax => _remaining.fold(
    0.0,
    (sum, it) =>
        sum + (_qty[it.id] ?? it.qty) * it.rate * (it.taxPercentage / 100),
  );

  double get _total {
    final t = _subtotal + _tax - widget.bill.discountAmount;
    return t < 0 ? 0 : t;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final items = _remaining
          .map(
            (it) => {
              'id': it.id,
              'qty': _qty[it.id] ?? it.qty,
              'rate': it.rate,
              'gst_rate': it.taxPercentage,
            },
          )
          .toList();

      await SupabaseService.updateBill(
        billId: widget.bill.id,
        items: items,
        removedItemIds: _removed.toList(),
        discountAmount: widget.bill.discountAmount,
      );
      await ref.read(reportProvider(widget.companyId).notifier).fetchReport();

      if (mounted) {
        Navigator.pop(context);
        AppFeedback.success(
          context,
          'Bill #${widget.bill.billNumber ?? '-'} updated',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.toast(context, 'Failed to update bill: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = isDark ? AppColors.primaryAmber : AppColors.primaryOrange;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
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
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.edit_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Edit Bill #${widget.bill.billNumber ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Item list
          Flexible(
            child: _remaining.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'All items removed — cancel the bill instead.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _remaining.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 16,
                      color: isDark
                          ? AppColors.darkBorder.withValues(alpha: 0.3)
                          : AppColors.lightBorder.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (context, index) {
                      final it = _remaining[index];
                      final qty = _qty[it.id] ?? it.qty;
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it.itemName ?? 'Item',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '₹${it.rate.toStringAsFixed(0)} each',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppColors.textWhiteMuted
                                        : AppColors.textDarkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Qty stepper
                          _qtyBtn(
                            Icons.remove_rounded,
                            isDark,
                            () {
                              final next = qty - 1;
                              setState(() {
                                if (next <= 0) {
                                  _removed.add(it.id);
                                } else {
                                  _qty[it.id] = next;
                                }
                              });
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              qty.toStringAsFixed(0),
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _qtyBtn(
                            Icons.add_rounded,
                            isDark,
                            () => setState(() => _qty[it.id] = qty + 1),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _removed.add(it.id)),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const Divider(height: 24),
          _editRow('Subtotal', _subtotal, isDark),
          if (_tax > 0) _editRow('Tax', _tax, isDark),
          if (widget.bill.discountAmount > 0)
            _editRow('Discount', -widget.bill.discountAmount, isDark),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'New Total',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '₹${_total.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_saving || _remaining.isEmpty) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
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
                  : Text(
                      'SAVE CHANGES',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, bool isDark, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _editRow(String label, double amount, bool isDark) {
    final neg = amount < 0;
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
            '${neg ? '-' : ''}₹${amount.abs().toStringAsFixed(0)}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: neg ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

