import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../core/services/supabase_service.dart';
import '../core/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ─── AUTH STATE ──────────────────────────────────────────
final authStateProvider =
    NotifierProvider<AuthNotifier, AsyncValue<UserProfile?>>(AuthNotifier.new);

class AuthNotifier extends Notifier<AsyncValue<UserProfile?>> {
  static const _sessionKey = 'user_session';

  @override
  AsyncValue<UserProfile?> build() {
    // Attempt to load current user on start
    _loadInitialSession();
    return const AsyncValue.loading();
  }

  Future<void> _loadInitialSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionJson = prefs.getString(_sessionKey);
      if (sessionJson != null) {
        state = AsyncValue.data(UserProfile.fromJson(jsonDecode(sessionJson)));
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signIn(String input, String password) async {
    state = const AsyncValue.loading();
    try {
      final profileJson = await SupabaseService.signInWithUserMaster(
        input: input,
        password: password,
      );

      final profile = UserProfile.fromJson(profileJson);

      // Save session locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(profileJson));

      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }

  Future<void> loadCurrentUser() async {
    // This is now handled by _loadInitialSession, but we can re-sync if needed
    await _loadInitialSession();
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await SupabaseService.signOut();
    state = const AsyncValue.data(null);
  }
}

// ─── COMPANY ─────────────────────────────────────────────
final companyProvider = FutureProvider.family<Company?, String>((
  ref,
  companyId,
) async {
  final json = await SupabaseService.getCompany(companyId);
  return json != null ? Company.fromJson(json) : null;
});

// ─── ITEM GROUPS ─────────────────────────────────────────
final itemGroupsProvider = FutureProvider.family<List<Item>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getItemGroups(companyId);
  return res.map((e) => Item.fromJson(e)).toList();
});

// ─── ALL ITEMS ───────────────────────────────────────────
final allItemsProvider = FutureProvider.family<List<Item>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getAllItems(companyId);
  return res.map((e) => Item.fromJson(e)).toList();
});

// ─── TABLES ──────────────────────────────────────────────
final tablesProvider = FutureProvider.family<List<CafeTable>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getTables(companyId);
  return res.map((e) => CafeTable.fromJson(e)).toList();
});

// ─── CART ────────────────────────────────────────────────
final cartProvider =
    NotifierProvider.family<CartNotifier, List<CartItem>, String?>(
      CartNotifier.new,
    );

class CartNotifier extends Notifier<List<CartItem>> {
  final String? tableId;
  CartNotifier(this.tableId);

  @override
  List<CartItem> build() => [];

  void addItem(Item item, [ItemVariant? variant]) {
    final existingIndex = state.indexWhere(
      (ci) => ci.item.id == item.id && ci.variant?.id == variant?.id,
    );
    if (existingIndex >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == existingIndex)
            CartItem(
              item: state[i].item,
              variant: state[i].variant,
              qty: state[i].qty + 1,
              notes: state[i].notes,
            )
          else
            state[i],
      ];
    } else {
      state = [...state, CartItem(item: item, variant: variant)];
    }
  }

  void removeItem(String itemId, [String? variantId]) {
    state = state
        .where((ci) => !(ci.item.id == itemId && ci.variant?.id == variantId))
        .toList();
  }

  void updateQty(String itemId, int qty, [String? variantId]) {
    if (qty <= 0) {
      removeItem(itemId, variantId);
      return;
    }
    state = [
      for (final ci in state)
        if (ci.item.id == itemId && ci.variant?.id == variantId)
          CartItem(
            item: ci.item,
            variant: ci.variant,
            qty: qty,
            notes: ci.notes,
          )
        else
          ci,
    ];
  }

  void incrementQty(String itemId, [String? variantId]) {
    state = [
      for (final ci in state)
        if (ci.item.id == itemId && ci.variant?.id == variantId)
          CartItem(
            item: ci.item,
            variant: ci.variant,
            qty: ci.qty + 1,
            notes: ci.notes,
          )
        else
          ci,
    ];
  }

  void decrementQty(String itemId, [String? variantId]) {
    final ci = state.firstWhere(
      (c) => c.item.id == itemId && c.variant?.id == variantId,
    );
    if (ci.qty <= 1) {
      removeItem(itemId, variantId);
    } else {
      updateQty(itemId, ci.qty - 1, variantId);
    }
  }

  void clear() {
    state = [];
  }

  double get subtotal => state.fold(0, (sum, ci) => sum + ci.total);
}

// ─── SELECTED UI THEME ───────────────────────────────────
final selectedUiThemeProvider =
    NotifierProvider<SelectedUiThemeNotifier, String>(
      SelectedUiThemeNotifier.new,
    );

class SelectedUiThemeNotifier extends Notifier<String> {
  @override
  String build() => AppConstants.uiModern;

  void setTheme(String theme) => state = theme;
}

// ─── DARK MODE TOGGLE ────────────────────────────────────
final isDarkModeProvider = NotifierProvider<IsDarkModeNotifier, bool>(
  IsDarkModeNotifier.new,
);

class IsDarkModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void set(bool value) => state = value;
}

// ─── DISCOUNT ────────────────────────────────────────────
final discountProvider = NotifierProvider<DiscountNotifier, double>(
  DiscountNotifier.new,
);

class DiscountNotifier extends Notifier<double> {
  @override
  double build() => 0;

  void setDiscount(double value) => state = value;
  void reset() => state = 0;
}

// ─── SELECTED TABLE ──────────────────────────────────────
final selectedTableProvider =
    NotifierProvider<SelectedTableNotifier, CafeTable?>(
      SelectedTableNotifier.new,
    );

class SelectedTableNotifier extends Notifier<CafeTable?> {
  @override
  CafeTable? build() => null;

  void select(CafeTable? table) => state = table;
}

// ─── ACTIVE KOTS ─────────────────────────────────────────
final activeKotsProvider = FutureProvider.family<List<KotMaster>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getActiveKots(companyId);
  return res.map((e) => KotMaster.fromJson(e)).toList();
});

// ─── BILLS ───────────────────────────────────────────────
final billsProvider = FutureProvider.family<List<Bill>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getBills(companyId);
  return res.map((e) => Bill.fromJson(e)).toList();
});
