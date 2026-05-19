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

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 22,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
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
                            .withOpacity(0.3),
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
    final prevPeriodBills = state.comparisonBills;

    // Group previous bills by relative day (0-6)
    final Map<int, double> prevTrends = {};
    for (var bill in prevPeriodBills) {
      if (bill.createdAt == null) continue;
      // This is simplified: we'll just map them to day sequence
      // In a real app, you'd align Monday with Monday.
    }

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
            if (index < 0 || index >= sortedDates.length)
              return const SizedBox();
            if (sortedDates.length > 10 &&
                index % (sortedDates.length ~/ 5) != 0)
              return const SizedBox();
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
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
    if (total == 0) return const Center(child: Text("No sales"));

    return PieChart(
      PieChartData(
        sectionsSpace: 4,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(
            color: AppColors.success,
            value: cash,
            title: cash > 0 ? 'Cash\n₹${cash.toStringAsFixed(0)}' : '',
            radius: 40,
            titleStyle: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: AppColors.info,
            value: upi,
            title: upi > 0 ? 'UPI\n₹${upi.toStringAsFixed(0)}' : '',
            radius: 40,
            titleStyle: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: AppColors.warning,
            value: card,
            title: card > 0 ? 'Card\n₹${card.toStringAsFixed(0)}' : '',
            radius: 40,
            titleStyle: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
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
    final displayEntries = sortedEntries.take(5).toList().reversed.toList();

    final maxSales = displayEntries.isEmpty
        ? 1.0
        : displayEntries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxSales * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= displayEntries.length)
                  return const SizedBox();
                return Text(
                  displayEntries[index].key,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textDark,
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
        barGroups: List.generate(displayEntries.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: displayEntries[i].value,
                color: isDark
                    ? AppColors.primaryAmber
                    : AppColors.primaryOrange,
                width: 14,
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
