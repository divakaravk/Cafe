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
import '../../providers/providers.dart' show allItemsProvider;
import 'widgets/report_widgets.dart';

class BillsScreen extends ConsumerStatefulWidget {
  final String companyId;
  const BillsScreen({super.key, required this.companyId});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  String _selectedTrendMetric = 'revenue'; // 'revenue' or 'count'
  String _searchQuery = '';
  String _selectedPaymentFilter = 'ALL'; // 'ALL', 'CASH', 'UPI', 'CARD'

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

              // Date Filters
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
          Text(
            'Reports Dashboard',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
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

  Future<void> _exportReportPdf(
    BuildContext context,
    ReportState reportState,
    Map<String, String> itemToCategory,
  ) async {
    final pdf = pw.Document();

    final totalRevenue = reportState.totalRevenue;
    final totalOrders = reportState.totalOrders;
    final cashTotal = reportState.cashTotal;
    final upiTotal = reportState.upiTotal;
    final cardTotal = reportState.cardTotal;
    final totalTax = reportState.bills.fold<double>(
      0.0,
      (sum, b) => sum + b.taxAmount,
    );
    final totalDiscount = reportState.bills.fold<double>(
      0.0,
      (sum, b) => sum + b.discountAmount,
    );
    final aov = totalOrders > 0 ? totalRevenue / totalOrders : 0.0;

    // Category Sales
    final Map<String, double> categorySales = {};
    for (var bill in reportState.bills) {
      for (var item in bill.items) {
        final category = itemToCategory[item.itemId] ?? 'Uncategorized';
        categorySales[category] = (categorySales[category] ?? 0.0) + item.total;
      }
    }

    // Top Selling Items
    final Map<String, int> itemQuantities = {};
    for (var bill in reportState.bills) {
      for (var item in bill.items) {
        final name = item.itemName ?? 'Unknown Item';
        itemQuantities[name] = (itemQuantities[name] ?? 0) + item.qty.toInt();
      }
    }
    final topItems = itemQuantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final dateRangeStr =
        reportState.filter == ReportDateFilter.custom &&
            reportState.startDate != null
        ? '${DateFormat('dd MMM yyyy').format(reportState.startDate!)} - ${DateFormat('dd MMM yyyy').format(reportState.endDate!)}'
        : 'Period: ${reportState.filter.toString().split('.').last.toUpperCase()}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CafePOS Sales Report',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      dateRangeStr,
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Generated on:',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          pw.Text(
            'Financial Summary',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ['Total Revenue', 'INR ${totalRevenue.toStringAsFixed(2)}'],
              ['Total Orders', '$totalOrders'],
              ['Average Ticket Size', 'INR ${aov.toStringAsFixed(2)}'],
              ['Cash Payments', 'INR ${cashTotal.toStringAsFixed(2)}'],
              ['UPI Payments', 'INR ${upiTotal.toStringAsFixed(2)}'],
              ['Card Payments', 'INR ${cardTotal.toStringAsFixed(2)}'],
              ['Tax Collected', 'INR ${totalTax.toStringAsFixed(2)}'],
              ['Discounts Given', 'INR ${totalDiscount.toStringAsFixed(2)}'],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 24),

          pw.Text(
            'Category Sales Breakdown',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Category / Section', 'Revenue (INR)', 'Share (%)'],
            data: categorySales.isEmpty
                ? [
                    ['No data available', '0.00', '0%'],
                  ]
                : categorySales.entries.map((e) {
                    final pct = totalRevenue > 0
                        ? (e.value / totalRevenue) * 100
                        : 0.0;
                    return [
                      e.key,
                      e.value.toStringAsFixed(2),
                      '${pct.toStringAsFixed(1)}%',
                    ];
                  }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 24),

          pw.Text(
            'Top Selling Items',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Item Name', 'Quantity Sold'],
            data: topItems.isEmpty
                ? [
                    ['No items sold', '0 pcs'],
                  ]
                : topItems
                      .take(10)
                      .map((e) => [e.key, '${e.value} pcs'])
                      .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

    final messenger = ScaffoldMessenger.of(context);
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'Sales_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to generate report PDF: $e')),
      );
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
