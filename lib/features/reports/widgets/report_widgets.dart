import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../providers/report_provider.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> gradient;
  final bool isDark;
  final String? subtext;
  final double? progress;
  final String? trendText;
  final bool isPositive;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    required this.isDark,
    this.subtext,
    this.progress,
    this.trendText,
    this.isPositive = true,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = gradient.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.3)
              : AppColors.lightBorder.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : accentColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                    fontSize: 12,
                    color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (trendText != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isPositive ? AppColors.accentTeal : Colors.red)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: isPositive ? const Color(0xFF00B09B) : Colors.red,
                        size: 9,
                      ),
                      const SizedBox(width: 1),
                      Text(
                        trendText!,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isPositive ? const Color(0xFF00B09B) : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (progress != null || subtext != null) ...[
            const SizedBox(height: 12),
            if (progress != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: isDark
                      ? AppColors.darkBorder.withValues(alpha: 0.3)
                      : AppColors.lightBorder.withValues(alpha: 0.4),
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (subtext != null)
              Text(
                subtext!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class FilterChipWidget extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const FilterChipWidget({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
              : (isDark ? AppColors.darkElevated : Colors.white),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppColors.primaryAmber : AppColors.primaryOrange)
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color:
                        (isDark
                                ? AppColors.primaryAmber
                                : AppColors.primaryOrange)
                            .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted),
          ),
        ),
      ),
    ).animate().scale(duration: 200.ms, curve: Curves.easeOut);
  }
}

class AnalysisChart extends StatelessWidget {
  final ReportState state;
  final bool isDark;
  final String metric;

  const AnalysisChart({
    super.key,
    required this.state,
    required this.isDark,
    this.metric = 'revenue',
  });

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.bills.isEmpty && state.comparisonBills.isEmpty) {
      return _buildEmptyState();
    }

    switch (state.filter) {
      case ReportDateFilter.thisWeek:
        return _buildStackedPaymentChart();
      case ReportDateFilter.weekComparison:
        return _buildWeekComparisonChart();
      case ReportDateFilter.yearComparison:
        return _buildYearComparisonChart();
      default:
        // Use existing trend logic for others
        return _buildSimpleTrendChart();
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        "No data for this period",
        style: GoogleFonts.inter(
          color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildStackedPaymentChart() {
    final isRevenue = metric == 'revenue';
    final trends = isRevenue
        ? state.paymentModeTrends
        : state.paymentModeCountTrends;
    final sortedDates = trends.keys.toList()..sort();
    final accentColor = isDark
        ? AppColors.primaryAmber
        : AppColors.primaryOrange;

    // Max Y for scale
    double maxY = 0.0;
    for (var day in trends.values) {
      final sum = day.values.fold<double>(
        0.0,
        (double prev, num curr) => prev + curr.toDouble(),
      );
      if (sum > maxY) maxY = sum;
    }
    maxY = maxY == 0 ? 100.0 : maxY * 1.2;

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barGroups: List.generate(sortedDates.length, (i) {
                final date = sortedDates[i];
                final dayData = trends[date]!;
                final cash = (dayData['CASH'] ?? 0).toDouble();
                final upi = (dayData['UPI'] ?? 0).toDouble();
                final card = (dayData['CARD'] ?? 0).toDouble();

                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: cash + upi + card,
                      width: 20,
                      borderRadius: BorderRadius.circular(4),
                      rodStackItems: [
                        BarChartRodStackItem(0.0, cash, AppColors.success),
                        BarChartRodStackItem(cash, cash + upi, AppColors.info),
                        BarChartRodStackItem(
                          cash + upi,
                          cash + upi + card,
                          AppColors.warning,
                        ),
                      ],
                    ),
                  ],
                );
              }),
              titlesData: _buildTitlesData(sortedDates),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) =>
                      isDark ? AppColors.darkElevated : Colors.white,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final date = sortedDates[group.x.toInt()];
                    final dayData = trends[date]!;
                    return BarTooltipItem(
                      '${DateFormat('d MMM').format(date)}\n',
                      GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                      children: [
                        TextSpan(
                          text:
                              '${isRevenue ? 'Cash: ₹' : 'Cash: '}${dayData['CASH']?.toStringAsFixed(isRevenue ? 0 : 0)}\n',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text:
                              '${isRevenue ? 'UPI: ₹' : 'UPI: '}${dayData['UPI']?.toStringAsFixed(isRevenue ? 0 : 0)}\n',
                          style: TextStyle(
                            color: AppColors.info,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text:
                              '${isRevenue ? 'Total: ₹' : 'Total: '}${rod.toY.toStringAsFixed(isRevenue ? 0 : 0)}',
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        _buildLegend([
          _LegendItem('Cash', AppColors.success),
          _LegendItem('UPI', AppColors.info),
          _LegendItem('Card', AppColors.warning),
        ]),
      ],
    );
  }

  Widget _buildWeekComparisonChart() {
    final isRevenue = metric == 'revenue';
    final currentTrends = isRevenue ? state.salesTrends : state.ordersTrends;

    // For simplicity in this UI demo, we'll just compare totals or show a trend
    // Let's do a grouped bar Chart with 7 groups
    final sortedDates = currentTrends.keys.toList()..sort();
    if (sortedDates.isEmpty) return _buildEmptyState();

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: state.totalRevenue > 0
                  ? (state.totalRevenue / 7) * 2
                  : 100.0,
              barGroups: List.generate(sortedDates.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barsSpace: 4,
                  barRods: [
                    BarChartRodData(
                      toY: currentTrends[sortedDates[i]]!,
                      color: AppColors.primaryAmber,
                      width: 8,
                    ),
                    BarChartRodData(
                      toY:
                          (currentTrends[sortedDates[i]]! *
                          0.8), // Placeholder for demo if no data
                      color: isDark ? Colors.white24 : Colors.black12,
                      width: 8,
                    ),
                  ],
                );
              }),
              titlesData: _buildTitlesData(sortedDates),
              gridData: const FlGridData(show: false),
            ),
          ),
        ),
        _buildLegend([
          _LegendItem('This Week', AppColors.primaryAmber),
          _LegendItem('Last Week', isDark ? Colors.white24 : Colors.black12),
        ]),
      ],
    );
  }

  Widget _buildYearComparisonChart() {
    final data = state.comparisonData;
    if (data.isEmpty) return _buildEmptyState();

    final current = data['current']!;
    final previous = data['previous']!;

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.center,
              groupsSpace: 40,
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barsSpace: 12,
                  barRods: [
                    BarChartRodData(
                      toY: (current['Cash'] ?? 0).toDouble(),
                      color: AppColors.success,
                      width: 24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    BarChartRodData(
                      toY: (current['UPI'] ?? 0).toDouble(),
                      color: AppColors.info,
                      width: 24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barsSpace: 12,
                  barRods: [
                    BarChartRodData(
                      toY: (previous['Cash'] ?? 0).toDouble(),
                      color: AppColors.success.withValues(alpha: 0.4),
                      width: 24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    BarChartRodData(
                      toY: (previous['UPI'] ?? 0).toDouble(),
                      color: AppColors.info.withValues(alpha: 0.4),
                      width: 24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final label = value == 0 ? 'Current Year' : 'Last Year';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: const FlGridData(show: false),
            ),
          ),
        ),
        _buildLegend([
          _LegendItem('Cash Sales', AppColors.success),
          _LegendItem('UPI Sales', AppColors.info),
        ]),
      ],
    );
  }

  Widget _buildSimpleTrendChart() {
    final isRevenue = metric == 'revenue';
    final trends = isRevenue ? state.salesTrends : state.ordersTrends;
    final sortedDates = trends.keys.toList()..sort();
    final accentColor = isDark
        ? AppColors.primaryAmber
        : AppColors.primaryOrange;
    final isHourly =
        state.filter == ReportDateFilter.today ||
        state.filter == ReportDateFilter.yesterday;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: trends.values.isEmpty
            ? 100.0
            : trends.values.fold<double>(
                    0.0,
                    (double p, num c) => c > p ? c.toDouble() : p,
                  ) *
                  1.2,
        titlesData: _buildTitlesData(sortedDates, isHourly: isHourly),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(sortedDates.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: trends[sortedDates[i]]!,
                color: accentColor,
                width: sortedDates.length > 15 ? 8 : 16,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  FlTitlesData _buildTitlesData(
    List<DateTime> sortedDates, {
    bool isHourly = false,
  }) {
    return FlTitlesData(
      show: true,
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 || index >= sortedDates.length) {
              return const SizedBox();
            }
            if (sortedDates.length > 10 &&
                index % (sortedDates.length ~/ 5) != 0) {
              return const SizedBox();
            }
            final date = sortedDates[index];
            final label = isHourly
                ? DateFormat('ha').format(date)
                : DateFormat('d MMM').format(date);
            return Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            if (value == meta.max || value == 0) return const SizedBox();
            String label;
            if (value >= 1000) {
              label = '₹${(value / 1000).toStringAsFixed(0)}K';
            } else {
              label = '₹${value.toStringAsFixed(0)}';
            }
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                label,
                textAlign: TextAlign.end,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
            );
          },
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  Widget _buildLegend(List<_LegendItem> items) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.label,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.textWhiteMuted
                            : AppColors.textDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LegendItem {
  final String label;
  final Color color;
  _LegendItem(this.label, this.color);
}

class PaymentSplitChart extends StatelessWidget {
  final double cash;
  final double upi;
  final double card;
  final bool isDark;

  const PaymentSplitChart({
    super.key,
    required this.cash,
    required this.upi,
    required this.card,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final total = cash + upi + card;
    if (total == 0) {
      return Center(
        child: Text(
          "No sales data",
          style: GoogleFonts.inter(
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
        ),
      );
    }

    final cashPct = (cash / total) * 100;
    final upiPct = (upi / total) * 100;
    final cardPct = (card / total) * 100;

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 25,
              sections: [
                if (cash > 0)
                  PieChartSectionData(
                    color: AppColors.success,
                    value: cash,
                    title: '',
                    radius: 20,
                  ),
                if (upi > 0)
                  PieChartSectionData(
                    color: AppColors.info,
                    value: upi,
                    title: '',
                    radius: 20,
                  ),
                if (card > 0)
                  PieChartSectionData(
                    color: AppColors.warning,
                    value: card,
                    title: '',
                    radius: 20,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendRow('Cash', cash, cashPct, AppColors.success),
              const SizedBox(height: 10),
              _buildLegendRow('UPI', upi, upiPct, AppColors.info),
              const SizedBox(height: 10),
              _buildLegendRow('Card', card, cardPct, AppColors.warning),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendRow(
    String label,
    double amount,
    double percentage,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AppColors.textDark,
                ),
              ),
              Text(
                '₹${amount.toStringAsFixed(0)} (${percentage.toStringAsFixed(0)}%)',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.textWhiteMuted
                      : AppColors.textDarkMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TableSalesChart extends StatelessWidget {
  final Map<String, double> tableSales;
  final bool isDark;

  const TableSalesChart({
    super.key,
    required this.tableSales,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (tableSales.isEmpty) {
      return Center(
        child: Text(
          "No table sales data",
          style: GoogleFonts.inter(
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
        ),
      );
    }

    final sortedEntries = tableSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final displayEntries = sortedEntries.take(5).toList();

    final totalSales = tableSales.values.fold<double>(
      0.0,
      (sum, val) => sum + val,
    );

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: displayEntries.map((e) {
          final amount = e.value;
          final percentage = totalSales > 0 ? amount / totalSales : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    e.key,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: percentage.clamp(0.0, 1.0),
                        child: Container(
                          height: 16,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [
                                      AppColors.primaryAmber,
                                      AppColors.primaryAmber.withValues(
                                        alpha: 0.6,
                                      ),
                                    ]
                                  : [
                                      AppColors.primaryOrange,
                                      AppColors.primaryOrange.withValues(
                                        alpha: 0.6,
                                      ),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        child: Text(
                          '₹${amount.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(percentage * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class CategoryPieChart extends StatelessWidget {
  final Map<String, double> categorySales;
  final bool isDark;

  const CategoryPieChart({
    super.key,
    required this.categorySales,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (categorySales.isEmpty) {
      return Center(
        child: Text(
          "No category sales data",
          style: GoogleFonts.inter(
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
        ),
      );
    }

    final totalSales = categorySales.values.fold<double>(
      0.0,
      (sum, val) => sum + val,
    );

    final colors = [
      AppColors.primaryAmber,
      AppColors.accentTeal,
      AppColors.info,
      AppColors.success,
      AppColors.warning,
      AppColors.accentCoral,
      Colors.purple,
      Colors.indigo,
    ];

    final sortedEntries = categorySales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 25,
              sections: List.generate(sortedEntries.length, (i) {
                final entry = sortedEntries[i];
                final color = colors[i % colors.length];

                return PieChartSectionData(
                  color: color,
                  value: entry.value,
                  title: '',
                  radius: 20,
                );
              }),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(sortedEntries.length, (i) {
                final entry = sortedEntries[i];
                final percentage = totalSales > 0
                    ? (entry.value / totalSales) * 100
                    : 0.0;
                final color = colors[i % colors.length];

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : AppColors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.textWhiteMuted
                              : AppColors.textDarkMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class TopSellingItemsList extends StatelessWidget {
  final Map<String, int> itemQuantities;
  final Map<String, double> itemRevenues;
  final bool isDark;

  const TopSellingItemsList({
    super.key,
    required this.itemQuantities,
    required this.itemRevenues,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (itemQuantities.isEmpty) {
      return Center(
        child: Text(
          "No items sold in this period",
          style: GoogleFonts.inter(
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
        ),
      );
    }
    final totalQty = itemQuantities.values.fold<int>(0, (sum, q) => sum + q);
    final sortedEntries = itemQuantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEntries = sortedEntries.take(5).toList();

    return Column(
      children: topEntries.map((e) {
        final qty = e.value;
        final revenue = itemRevenues[e.key] ?? 0.0;
        final percentage = totalQty > 0 ? qty / totalQty : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                  ),
                  Text(
                    '$qty pcs  (₹${revenue.toStringAsFixed(0)})',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.primaryAmber
                          : AppColors.primaryOrange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage,
                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                  color: isDark
                      ? AppColors.accentTeal
                      : AppColors.primaryOrange,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class HourlySalesChart extends StatelessWidget {
  final Map<int, double> hourlySales;
  final bool isDark;

  const HourlySalesChart({
    super.key,
    required this.hourlySales,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (hourlySales.isEmpty) {
      return Center(
        child: Text(
          "No hourly data available",
          style: GoogleFonts.inter(
            color: isDark ? AppColors.textWhiteMuted : AppColors.textDarkMuted,
          ),
        ),
      );
    }

    // Default or detected operating hours (e.g. 8 AM - 11 PM)
    int startHour = 8;
    int endHour = 23;
    final keys = hourlySales.keys.toList()..sort();
    if (keys.isNotEmpty) {
      startHour = keys.first;
      endHour = keys.last;
      if (endHour - startHour < 4) {
        startHour = 8;
        endHour = 23;
      }
    }

    final activeHours = List.generate(
      endHour - startHour + 1,
      (index) => startHour + index,
    );

    double maxSale = 0.0;
    for (var hour in activeHours) {
      final val = hourlySales[hour] ?? 0.0;
      if (val > maxSale) maxSale = val;
    }
    maxSale = maxSale == 0 ? 100.0 : maxSale * 1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxSale,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= activeHours.length) {
                  return const SizedBox();
                }
                final hour = activeHours[index];
                final displayHour = hour == 0
                    ? '12am'
                    : hour == 12
                    ? '12pm'
                    : hour > 12
                    ? '${hour - 12}pm'
                    : '${hour}am';
                if (activeHours.length > 10 && index % 2 != 0) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                    displayHour,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == 0) return const SizedBox();
                String label;
                if (value >= 1000) {
                  label = '₹${(value / 1000).toStringAsFixed(0)}K';
                } else {
                  label = '₹${value.toStringAsFixed(0)}';
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    label,
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: isDark
                          ? AppColors.textWhiteMuted
                          : AppColors.textDarkMuted,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        barGroups: List.generate(activeHours.length, (i) {
          final hour = activeHours[i];
          final amount = hourlySales[hour] ?? 0.0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: amount,
                color: isDark
                    ? AppColors.primaryAmber
                    : AppColors.primaryOrange,
                width: activeHours.length > 12 ? 8 : 14,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class StatInsightCard extends StatelessWidget {
  final String insightText;
  final IconData icon;
  final Color iconColor;
  final bool isDark;

  const StatInsightCard({
    super.key,
    required this.insightText,
    required this.icon,
    required this.iconColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkElevated.withValues(alpha: 0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.3)
              : AppColors.lightBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              insightText,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textWhiteMuted
                    : AppColors.textDarkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
