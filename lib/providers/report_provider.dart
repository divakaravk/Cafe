import 'dart:async';
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
      // Intentionally not `error ?? this.error`: callers pass `error: null` to
      // clear a previous error on a fresh load/success. With `??` the stale
      // error would stick forever and keep the error banner on screen.
      error: error,
    );
  }

  // Cancelled bills stay in [bills] for the audit ledger, but every revenue
  // aggregation below works off [validBills] so they don't inflate totals.
  List<Bill> get validBills => bills.where((b) => !b.isCancelled).toList();

  // Aggregations
  double get totalRevenue =>
      validBills.fold(0.0, (sum, b) => sum + b.totalAmount);
  double get totalGrossAmount =>
      validBills.fold(0.0, (sum, b) => sum + b.subtotal);
  int get totalOrders => validBills.length;

  double get cashTotal => validBills
      .where((b) => b.paymentMode.toUpperCase() == 'CASH')
      .fold(0.0, (sum, b) => sum + b.totalAmount);
  double get upiTotal => validBills
      .where((b) => b.paymentMode.toUpperCase() == 'UPI')
      .fold(0.0, (sum, b) => sum + b.totalAmount);
  double get cardTotal => validBills
      .where((b) => b.paymentMode.toUpperCase() == 'CARD')
      .fold(0.0, (sum, b) => sum + b.totalAmount);

  Map<DateTime, double> get salesTrends {
    final Map<DateTime, double> trends = {};
    final isShortTerm =
        filter == ReportDateFilter.today ||
        filter == ReportDateFilter.yesterday;

    for (var bill in validBills) {
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

    for (var bill in validBills) {
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
    for (var bill in validBills) {
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
    for (var bill in validBills) {
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
    for (var bill in validBills) {
      if (bill.tableName == null || bill.tableName!.isEmpty) continue;
      sales[bill.tableName!] = (sales[bill.tableName!] ?? 0) + bill.totalAmount;
    }
    return sales;
  }

  /// Per-cover aggregated entries, sorted by revenue descending.
  /// Each entry: tableLabel, coverDisplayName, coverNumber (for color), total, billCount.
  List<Map<String, dynamic>> get coverEntries {
    final Map<String, Map<String, dynamic>> acc = {};
    for (final bill in validBills) {
      if (bill.coverNumber == null) continue;
      final tableLabel =
          bill.tableName != null ? 'Table ${bill.tableName}' : 'Takeaway';
      final coverName = bill.coverDisplayName;
      final key = '${bill.tableName ?? 'takeaway'}_${bill.coverNumber}';
      acc.putIfAbsent(key, () => {
        'tableLabel': tableLabel,
        'coverName': coverName,
        'coverNumber': bill.coverNumber,
        'total': 0.0,
        'billCount': 0,
      });
      acc[key]!['total'] = (acc[key]!['total'] as double) + bill.totalAmount;
      acc[key]!['billCount'] = (acc[key]!['billCount'] as int) + 1;
    }
    return acc.values.toList()
      ..sort(
        (a, b) => (b['total'] as double).compareTo(a['total'] as double),
      );
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

  /// Parses bill rows defensively — a single legacy/odd row (e.g. a null field)
  /// is skipped and logged instead of failing the entire report load.
  List<Bill> _parseBills(List<Map<String, dynamic>> rows) {
    final out = <Bill>[];
    for (final row in rows) {
      try {
        out.add(Bill.fromJson(row));
      } catch (e) {
        // ignore: avoid_print
        print('Skipping unparseable bill row: $e');
      }
    }
    return out;
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
          // Fall back to a sane last-30-days window if the custom range was
          // never fully set, so a half-null range can't break the query.
          start = state.startDate ?? end.subtract(const Duration(days: 30));
          end = state.endDate ?? DateTime.now();
          break;
      }

      final res = await SupabaseService.getBills(
        companyId,
        startDate: start,
        endDate: end,
      ).timeout(const Duration(seconds: 15));
      final bills = _parseBills(res);

      List<Bill> comparisonBills = [];
      if (compStart != null && compEnd != null) {
        final compRes = await SupabaseService.getBills(
          companyId,
          startDate: compStart,
          endDate: compEnd,
        ).timeout(const Duration(seconds: 15));
        comparisonBills = _parseBills(compRes);
      }

      state = state.copyWith(
        bills: bills,
        comparisonBills: comparisonBills,
        isLoading: false,
        error: null,
      );
    } on TimeoutException {
      state = state.copyWith(
        isLoading: false,
        error: 'Request timed out. Check your internet connection and try again.',
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final userMsg = msg.contains('socket') ||
              msg.contains('network') ||
              msg.contains('connection') ||
              msg.contains('unreachable')
          ? 'No internet connection. Pull down to refresh.'
          : msg.contains('server') || msg.contains('500') || msg.contains('503')
          ? 'Server error. Please try again in a moment.'
          : 'Failed to load report: ${e.toString()}';
      state = state.copyWith(isLoading: false, error: userMsg);
    }
  }
}
