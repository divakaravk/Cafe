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
  // The last_login this device recorded at sign-in. If the server's last_login
  // later differs, someone signed in elsewhere and this device is stale.
  static const _lastLoginKey = 'session_last_login';

  @override
  AsyncValue<UserProfile?> build() {
    // Attempt to load current user on start
    _loadInitialSession();
    return const AsyncValue.loading();
  }

  /// Resolves and caches the signed-in user's module permissions. Admins get
  /// full access without a DB round-trip; everyone else uses their stored
  /// permission row, falling back to role defaults when none exists.
  Future<void> _syncPermissions(UserProfile profile) async {
    UserPermission perms;
    if (profile.isAdmin) {
      perms = UserPermission.all(profile.id);
    } else {
      try {
        final json = await SupabaseService.getUserPermissions(profile.id);
        perms = json != null
            ? UserPermission.fromJson(json)
            : UserPermission.forRole(profile.id, profile.role);
      } catch (_) {
        perms = UserPermission.forRole(profile.id, profile.role);
      }
    }
    await ref.read(permissionsProvider.notifier).set(perms);
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

  Future<void> signIn(String input, String password, {bool force = false}) async {
    state = const AsyncValue.loading();
    try {
      final profileJson = await SupabaseService.signInWithUserMaster(
        input: input,
        password: password,
        forceLogin: force,
      );

      final profile = UserProfile.fromJson(profileJson);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(profileJson));
      await prefs.setString(
        _lastLoginKey,
        profileJson['last_login']?.toString() ?? '',
      );

      await _syncPermissions(profile);
      state = AsyncValue.data(profile);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }

  Future<void> loadCurrentUser() async {
    // This is now handled by _loadInitialSession, but we can re-sync if needed
    await _loadInitialSession();
  }

  /// Signs the user out. [clearRemote] clears the DB is_login flag; pass false
  /// when another device has taken over the session (it now owns is_login, so
  /// we must not reset it and log that device out too).
  Future<void> signOut({bool clearRemote = true}) async {
    final currentUser = state.value;
    if (clearRemote && currentUser != null) {
      try {
        await SupabaseService.setLoginStatus(currentUser.id, false);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_lastLoginKey);
    await ref.read(permissionsProvider.notifier).clear();
    try {
      await SupabaseService.signOut();
    } catch (_) {}
    state = const AsyncValue.data(null);
  }

  /// Verifies the live session against the server. If the account was
  /// deactivated, force-logged-out, or signed in on another device, this signs
  /// out locally and publishes a reason via [sessionKickProvider] so the login
  /// screen can show a toast. Network errors are ignored (no false kicks).
  Future<void> validateSession() async {
    final user = state.value;
    if (user == null) return;

    Map<String, dynamic>? status;
    try {
      status = await SupabaseService.getUserSessionStatus(user.id);
    } catch (_) {
      return; // offline / transient — don't kick the user out
    }
    if (status == null) return;

    final active = status['user_active'] as bool? ?? true;
    final isLogin = status['is_login'] as bool? ?? true;
    final serverLast = status['last_login']?.toString();

    final prefs = await SharedPreferences.getInstance();
    final localLast = prefs.getString(_lastLoginKey);

    String? reason;
    bool clearRemote = true;
    if (!active) {
      reason = 'Your account is inactive. Contact your administrator.';
    } else if (serverLast != null &&
        localLast != null &&
        localLast.isNotEmpty &&
        !_sameInstant(serverLast, localLast)) {
      // A newer login exists elsewhere — that device owns the session now.
      // Compare as instants, not raw strings: this device records Dart's ISO
      // form ("…Z") at sign-in while the server re-reads PostgREST's form
      // ("…+00:00"), which represent the same moment in different text.
      reason = 'You have been logged in on another device.';
      clearRemote = false;
    } else if (!isLogin) {
      reason = 'Your session has ended. Please sign in again.';
    }

    if (reason != null) {
      await signOut(clearRemote: clearRemote);
      ref.read(sessionKickProvider.notifier).set(reason);
    }
  }

  /// True when two timestamp strings refer to the same moment, tolerating
  /// representation differences (e.g. "…Z" vs "…+00:00", trimmed fractional
  /// zeros). Falls back to exact string equality if either fails to parse.
  static bool _sameInstant(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return a == b;
    return da.toUtc().isAtSameMomentAs(db.toUtc());
  }
}

// ─── SESSION KICK MESSAGE ────────────────────────────────
// Set when the session guard logs the user out (inactive / another device).
// The login screen shows it as a toast then clears it.
final sessionKickProvider =
    NotifierProvider<SessionKickNotifier, String?>(SessionKickNotifier.new);

class SessionKickNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? message) => state = message;
  void clear() => state = null;
}

// ─── CURRENT USER PERMISSIONS ────────────────────────────
// The signed-in user's module access, cached to SharedPreferences so screen
// gating is instant and works offline (no per-screen network call). Populated
// at sign-in by [AuthNotifier]; restored from cache on app start.
final permissionsProvider =
    NotifierProvider<PermissionsNotifier, UserPermission?>(
      PermissionsNotifier.new,
    );

class PermissionsNotifier extends Notifier<UserPermission?> {
  static const _key = 'user_permissions';

  @override
  UserPermission? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final j = prefs.getString(_key);
    if (j != null) {
      try {
        state = UserPermission.fromJson(
          jsonDecode(j) as Map<String, dynamic>,
        );
      } catch (_) {
        state = null;
      }
    }
  }

  Future<void> set(UserPermission perms) async {
    state = perms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(perms.toJson()));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
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

// ─── SELECTED POS ITEM GROUP (session memory) ────────────
// Remembers which Item Group is selected in the POS for the session so the
// grid does not reset when the widget rebuilds.
final selectedPosGroupProvider =
    NotifierProvider<SelectedPosGroupNotifier, String?>(
      SelectedPosGroupNotifier.new,
    );

class SelectedPosGroupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? groupId) => state = groupId;
}

// ─── VARIANTS BY GROUP (lazy, POS-sellable only) ─────────
// Lazy-loads the active+available selling items for a single group. Groups
// already embed their variants via [itemGroupsProvider]; this is the
// pagination-ready entry point for very large menus where embedding is
// undesirable.
final variantsByGroupProvider =
    FutureProvider.family<List<ItemVariant>, String>((ref, itemId) async {
  final res = await SupabaseService.getVariantsByGroup(
    itemId,
    onlySellable: true,
  );
  return res.map((e) => ItemVariant.fromJson(e)).toList();
});

// ─── TABLES ──────────────────────────────────────────────
final tablesProvider = FutureProvider.family<List<CafeTable>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getTables(companyId);
  return res.map((e) => CafeTable.fromJson(e)).toList();
});

// ─── COMPANY USERS ───────────────────────────────────────
// Staff of a company, used by the Stock module (staff filters, shift handover).
final companyUsersProvider = FutureProvider.family<List<UserProfile>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getUsersForCompany(companyId);
  return res.map((e) => UserProfile.fromJson(e)).toList();
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
