import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/models.dart';
import '../core/services/supabase_service.dart';

enum ReportDateFilter {
  today,
  yesterday,
  last7Days,
  thisWeek,
  weekComparison,
  yearComparison,
  thisMonth,
  custom,
}

class ReportState {
  final List<Bill> bills;
  final List<Bill> comparisonBills; // For Week-over-Week or Year-over-Year
  final ReportDateFilter filter;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
  final String? error;

  ReportState({
    this.bills = const [],
    this.comparisonBills = const [],
    this.filter = ReportDateFilter.today,
    this.startDate,
    this.endDate,
    this.isLoading = false,
    this.error,
  });

  ReportState copyWith({
    List<Bill>? bills,
    List<Bill>? comparisonBills,
    ReportDateFilter? filter,
    DateTime? startDate,
    DateTime? endDate,
    bool? isLoading,
    String? error,
  }) {
    return ReportState(
      bills: bills ?? this.bills,
      comparisonBills: comparisonBills ?? this.comparisonBills,
      filter: filter ?? this.filter,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  // Aggregations
  double get totalRevenue => bills.fold(0.0, (sum, b) => sum + b.totalAmount);
  double get totalGrossAmount => bills.fold(0.0, (sum, b) => sum + b.subtotal);
  int get totalOrders => bills.length;

  double get cashTotal => bills
      .where((b) => b.paymentMode.toUpperCase() == 'CASH')
      .fold(0.0, (sum, b) => sum + b.totalAmount);
  double get upiTotal => bills
      .where((b) => b.paymentMode.toUpperCase() == 'UPI')
      .fold(0.0, (sum, b) => sum + b.totalAmount);
  double get cardTotal => bills
      .where((b) => b.paymentMode.toUpperCase() == 'CARD')
      .fold(0.0, (sum, b) => sum + b.totalAmount);

  Map<DateTime, double> get salesTrends {
    final Map<DateTime, double> trends = {};
    final isShortTerm =
        filter == ReportDateFilter.today ||
        filter == ReportDateFilter.yesterday;

    for (var bill in bills) {
      if (bill.createdAt == null) continue;

      // Convert to local time (IST) before grouping
      final localCreatedAt = bill.createdAt!.toLocal();

      DateTime key;
      if (isShortTerm) {
        // Group by Hour
        key = DateTime(
          localCreatedAt.year,
          localCreatedAt.month,
          localCreatedAt.day,
          localCreatedAt.hour,
        );
      } else {
        // Group by Day
        key = DateTime(
          localCreatedAt.year,
          localCreatedAt.month,
          localCreatedAt.day,
        );
      }
      trends[key] = (trends[key] ?? 0) + bill.totalAmount;
    }
    return trends;
  }

  Map<DateTime, double> get ordersTrends {
    final Map<DateTime, double> trends = {};
    final isShortTerm =
        filter == ReportDateFilter.today ||
        filter == ReportDateFilter.yesterday;

    for (var bill in bills) {
      if (bill.createdAt == null) continue;
      final localCreatedAt = bill.createdAt!.toLocal();

      DateTime key;
      if (isShortTerm) {
        key = DateTime(
          localCreatedAt.year,
          localCreatedAt.month,
          localCreatedAt.day,
          localCreatedAt.hour,
        );
      } else {
        key = DateTime(
          localCreatedAt.year,
          localCreatedAt.month,
          localCreatedAt.day,
        );
      }
      trends[key] = (trends[key] ?? 0) + 1;
    }
    return trends;
  }

  // Returns Day -> { 'CASH': sum, 'UPI': sum }
  Map<DateTime, Map<String, double>> get paymentModeTrends {
    final Map<DateTime, Map<String, double>> trends = {};
    for (var bill in bills) {
      if (bill.createdAt == null) continue;
      final date = DateTime(
        bill.createdAt!.toLocal().year,
        bill.createdAt!.toLocal().month,
        bill.createdAt!.toLocal().day,
      );

      trends.putIfAbsent(date, () => {'CASH': 0, 'UPI': 0, 'CARD': 0});
      final mode = bill.paymentMode.toUpperCase();
      if (trends[date]!.containsKey(mode)) {
        trends[date]![mode] = trends[date]![mode]! + bill.totalAmount;
      } else {
        trends[date]![mode] = bill.totalAmount;
      }
    }
    return trends;
  }

  Map<DateTime, Map<String, double>> get paymentModeCountTrends {
    final Map<DateTime, Map<String, double>> trends = {};
    for (var bill in bills) {
      if (bill.createdAt == null) continue;
      final date = DateTime(
        bill.createdAt!.toLocal().year,
        bill.createdAt!.toLocal().month,
        bill.createdAt!.toLocal().day,
      );

      trends.putIfAbsent(date, () => {'CASH': 0, 'UPI': 0, 'CARD': 0});
      final mode = bill.paymentMode.toUpperCase();
      if (trends[date]!.containsKey(mode)) {
        trends[date]![mode] = trends[date]![mode]! + 1.0;
      } else {
        trends[date]![mode] = 1.0;
      }
    }
    return trends;
  }

  // Returns a map of Period -> Amount for comparisons
  Map<String, Map<String, double>> get comparisonData {
    if (filter == ReportDateFilter.weekComparison) {
      // Comparison bills are last week
      final currentTotal = bills.fold(0.0, (sum, b) => sum + b.totalAmount);
      final prevTotal = comparisonBills.fold(
        0.0,
        (sum, b) => sum + b.totalAmount,
      );
      return {
        'current': {'Total': currentTotal},
        'previous': {'Total': prevTotal},
      };
    } else if (filter == ReportDateFilter.yearComparison) {
      final currentCash = bills
          .where((b) => b.paymentMode.toUpperCase() == 'CASH')
          .fold(0.0, (sum, b) => sum + b.totalAmount);
      final currentUpi = bills
          .where((b) => b.paymentMode.toUpperCase() == 'UPI')
          .fold(0.0, (sum, b) => sum + b.totalAmount);
      final prevCash = comparisonBills
          .where((b) => b.paymentMode.toUpperCase() == 'CASH')
          .fold(0.0, (sum, b) => sum + b.totalAmount);
      final prevUpi = comparisonBills
          .where((b) => b.paymentMode.toUpperCase() == 'UPI')
          .fold(0.0, (sum, b) => sum + b.totalAmount);

      return {
        'current': {'Cash': currentCash, 'UPI': currentUpi},
        'previous': {'Cash': prevCash, 'UPI': prevUpi},
      };
    }
    return {};
  }

  Map<String, double> get tableSales {
    final Map<String, double> sales = {};
    for (var bill in bills) {
      if (bill.tableName == null || bill.tableName!.isEmpty) continue;
      sales[bill.tableName!] = (sales[bill.tableName!] ?? 0) + bill.totalAmount;
    }
    return sales;
  }
}

final reportProvider =
    StateNotifierProvider.family<ReportNotifier, ReportState, String>((
      ref,
      companyId,
    ) {
      return ReportNotifier(companyId);
    });

class ReportNotifier extends StateNotifier<ReportState> {
  final String companyId;
  ReportNotifier(this.companyId) : super(ReportState()) {
    fetchReport();
  }

  Future<void> setFilter(
    ReportDateFilter filter, {
    DateTime? start,
    DateTime? end,
  }) async {
    state = state.copyWith(filter: filter, startDate: start, endDate: end);
    await fetchReport();
  }

  Future<void> fetchReport() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      DateTime? start;
      DateTime? end = DateTime.now();
      DateTime? compStart;
      DateTime? compEnd;

      switch (state.filter) {
        case ReportDateFilter.today:
          start = DateTime(end.year, end.month, end.day);
          break;
        case ReportDateFilter.yesterday:
          final yesterday = end.subtract(const Duration(days: 1));
          start = DateTime(yesterday.year, yesterday.month, yesterday.day);
          end = DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            23,
            59,
            59,
          );
          break;
        case ReportDateFilter.last7Days:
          start = end.subtract(const Duration(days: 7));
          break;
        case ReportDateFilter.thisWeek:
          // Current Week (Daily split by payment)
          start = end.subtract(const Duration(days: 7));
          break;
        case ReportDateFilter.weekComparison:
          // This week vs Last Week
          start = end.subtract(const Duration(days: 7));
          compEnd = start.subtract(const Duration(seconds: 1));
          compStart = compEnd.subtract(const Duration(days: 7));
          break;
        case ReportDateFilter.yearComparison:
          // This Year vs Last Year
          start = DateTime(end.year, 1, 1);
          compStart = DateTime(end.year - 1, 1, 1);
          compEnd = DateTime(end.year - 1, 12, 31, 23, 59, 59);
          break;
        case ReportDateFilter.thisMonth:
          start = DateTime(end.year, end.month, 1);
          break;
        case ReportDateFilter.custom:
          start = state.startDate;
          end = state.endDate;
          break;
      }

      final res = await SupabaseService.getBills(
        companyId,
        startDate: start,
        endDate: end,
      );
      final bills = res.map((e) => Bill.fromJson(e)).toList();

      List<Bill> comparisonBills = [];
      if (compStart != null && compEnd != null) {
        final compRes = await SupabaseService.getBills(
          companyId,
          startDate: compStart,
          endDate: compEnd,
        );
        comparisonBills = compRes.map((e) => Bill.fromJson(e)).toList();
      }

      state = state.copyWith(
        bills: bills,
        comparisonBills: comparisonBills,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}
