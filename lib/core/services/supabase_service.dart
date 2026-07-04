import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';

/// Central service to interact with Supabase
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Initialize Supabase (call in main)
  static Future<void> init() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  }

  // ─── AUTH ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> signInWithUserMaster({
    required String input,
    required String password,
    bool forceLogin = false,
  }) async {
    final trimmed = input.trim();

    // Step 1 — find user by username OR email (no password in query to get
    // a precise error message when only the password is wrong)
    final List<dynamic> rows = await client
        .from('user_profiles')
        .select()
        .or('username.ilike.$trimmed,user_email.ilike.$trimmed')
        .limit(1);

    if (rows.isEmpty) {
      throw 'No account found for "$trimmed". Check your username or email.';
    }

    final userRow = Map<String, dynamic>.from(rows.first as Map);

    // Step 2 — active check
    if (!(userRow['user_active'] as bool? ?? true)) {
      throw 'This account is deactivated. Contact your administrator.';
    }

    // Step 3 — password check (plain-text comparison, same as before)
    final stored = userRow['password'] as String? ?? '';
    if (stored != password) {
      throw 'Incorrect password. Please try again.';
    }

    // Step 4 — concurrent session check
    if ((userRow['is_login'] as bool? ?? false) && !forceLogin) {
      throw 'ALREADY_LOGGED_IN';
    }

    // Step 5 — stamp is_login + last_login (best-effort; never blocks login)
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await client
          .from('user_profiles')
          .update({'is_login': true, 'last_login': now})
          .eq('id', userRow['id'] as String);
      return {...userRow, 'is_login': true, 'last_login': now};
    } catch (_) {
      // Update failed (RLS / trigger issue) — login still succeeds
      return userRow;
    }
  }

  static Future<void> setLoginStatus(String userId, bool isLogin) async {
    await client
        .from('user_profiles')
        .update({'is_login': isLogin})
        .eq('id', userId);
  }

  /// Live session status for the signed-in user — used by the app's session
  /// guard to detect deactivation, admin force-logout, or a login from another
  /// device (a newer last_login than the one this device recorded).
  static Future<Map<String, dynamic>?> getUserSessionStatus(
    String userId,
  ) async {
    return await client
        .from('user_profiles')
        .select('user_active, is_login, last_login')
        .eq('id', userId)
        .maybeSingle();
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static User? get currentUser => client.auth.currentUser;
  static String? get currentUserId => currentUser?.id;

  // ─── PROFILE ───────────────────────────────────────────
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    final res = await client
        .from('user_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return res;
  }

  static Future<List<Map<String, dynamic>>> getUsersForCompany(
    String companyId,
  ) async {
    final res = await client
        .from('user_profiles')
        .select()
        .eq('company_id', companyId)
        .order('user_name');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>?> getUserPermissions(String userId) async {
    final res = await client
        .from('user_permission')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return res;
  }

  static Future<void> upsertUserWithPermissions({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> permissionData,
    required bool isNew,
  }) async {
    permissionData['user_id'] = userData['id'];
    if (isNew) {
      // 1. Insert User
      await client.from('user_profiles').insert(userData);
    } else {
      // 1. Update User
      await client
          .from('user_profiles')
          .update(userData)
          .eq('id', userData['id']);
    }

    // 2. Upsert Permissions — idempotent on user_id so it works whether the
    // row was just created, already seeded by a DB trigger, or left over from a
    // previous partial save. A plain insert here throws a duplicate-key error
    // when a permission row for this user already exists.
    await client
        .from('user_permission')
        .upsert(permissionData, onConflict: 'user_id');
  }

  static Future<String> uploadAvatar(
    String userId,
    List<int> bytes,
    String extension,
  ) async {
    final path = 'avatars/$userId.$extension';
    final contentType = 'image/$extension' == 'image/jpg'
        ? 'image/jpeg'
        : 'image/$extension';

    await client.storage
        .from('profiles')
        .uploadBinary(
          path,
          bytes as Uint8List,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );

    return client.storage.from('profiles').getPublicUrl(path);
  }

  // ─── COMPANY ───────────────────────────────────────────
  static Future<Map<String, dynamic>?> getCompany(String companyId) async {
    final res = await client
        .from('company_master')
        .select()
        .eq('id', companyId)
        .maybeSingle();
    return res;
  }

  static Future<void> updateCompany(
    String companyId,
    Map<String, dynamic> data,
  ) async {
    await client.from('company_master').update(data).eq('id', companyId);
  }

  // ─── COMPANY SELF-REGISTRATION ─────────────────────────
  /// Creates an unverified/inactive company + a registration request carrying a
  /// fresh OTP. A DB webhook pushes that OTP to super-admin devices via FCM.
  /// Returns { registration_id, company_id }.
  static Future<Map<String, dynamic>> requestCompanyRegistration({
    required Map<String, dynamic> company,
    required Map<String, dynamic> owner,
  }) async {
    final res = await client.rpc(
      'request_company_registration',
      params: {'p_company': company, 'p_owner': owner},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Verifies the OTP for a registration. On success the company is flipped to
  /// verified + active. Returns { ok, company_id?, reason? }.
  static Future<Map<String, dynamic>> verifyCompanyRegistrationOtp({
    required String registrationId,
    required String code,
  }) async {
    final res = await client.rpc(
      'verify_company_registration_otp',
      params: {'p_registration_id': registrationId, 'p_code': code},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Registers this device's FCM token as an owner/super-admin recipient for
  /// new-company registration OTPs.
  static Future<void> registerSuperAdminDevice(String token, {String? label}) async {
    await client.rpc(
      'register_super_admin_device',
      params: {'p_token': token, 'p_label': label},
    );
  }

  /// App-owner dashboard: recent company-registration requests.
  static Future<List<Map<String, dynamic>>> listCompanyRegistrations({
    int limit = 50,
  }) async {
    final res = await client.rpc(
      'list_company_registrations',
      params: {'p_limit': limit},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// App-owner override: approve a registration without the OTP step (activates
  /// the company directly). Returns { ok, company_id? }.
  static Future<Map<String, dynamic>> approveCompanyRegistration(
    String registrationId,
  ) async {
    final res = await client.rpc(
      'approve_company_registration',
      params: {'p_registration_id': registrationId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Changes a user's password, but only if [currentPassword] matches the stored
  /// one (enforced in the WHERE clause). Returns true on success, false when the
  /// current password is wrong.
  static Future<bool> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final rows = await client
        .from('user_profiles')
        .update({'password': newPassword})
        .eq('id', userId)
        .eq('password', currentPassword)
        .select('id');
    return (rows as List).isNotEmpty;
  }

  // ─── ITEMS ─────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getItemGroups(
    String companyId,
  ) async {
    final res = await client
        .from('item_master')
        .select(
          '*, company_hsn(*), item_variant!item_variant_item_id_fkey(*, company_hsn(*))',
        )
        .eq('company_id', companyId)
        .order('display_order');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> getMasterItemsForVariants(
    String companyId,
  ) async {
    final res = await client
        .from('item_master')
        .select()
        .eq('company_id', companyId)
        .eq('has_variants', true)
        .order('item_name');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> getCompanyHsns(
    String companyId,
  ) async {
    final res = await client
        .from('company_hsn')
        .select()
        .eq('company_id', companyId)
        .order('hsn_code');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> deleteItemMaster(String id) async {
    await client.from('item_master').delete().eq('id', id);
  }

  /// Returns the selling items (variants) for a single group, sorted by
  /// display_order then name. Pass [onlySellable] for the POS (active +
  /// available only). Lazy-load entry point — used when variants are not
  /// already embedded in the group payload.
  static Future<List<Map<String, dynamic>>> getVariantsByGroup(
    String itemId, {
    bool onlySellable = false,
  }) async {
    var query = client
        .from('item_variant')
        .select('*, company_hsn(*)')
        .eq('item_id', itemId);
    if (onlySellable) {
      query = query.eq('is_active', true).eq('is_available', true);
    }
    final res = await query
        .order('display_order', ascending: true)
        .order('variant_name', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Returns the default selling item for a group, or null if none.
  static Future<Map<String, dynamic>?> getDefaultVariant(String itemId) async {
    final flagged = await client
        .from('item_variant')
        .select('*, company_hsn(*)')
        .eq('item_id', itemId)
        .eq('is_default', true)
        .limit(1);
    if ((flagged as List).isNotEmpty) {
      return Map<String, dynamic>.from(flagged.first as Map);
    }
    final first = await client
        .from('item_variant')
        .select('*, company_hsn(*)')
        .eq('item_id', itemId)
        .order('display_order', ascending: true)
        .order('variant_name', ascending: true)
        .limit(1);
    return (first as List).isNotEmpty
        ? Map<String, dynamic>.from(first.first as Map)
        : null;
  }

  /// Pricing rule, server-friendly form: a variant's override rate
  /// (null/0) inherits the group base rate; otherwise it overrides.
  /// UI must call this (or [Item.effectiveRateFor]) — never recompute.
  static double getEffectiveRate({
    required double groupBaseRate,
    double? variantOverrideRate,
  }) {
    final override = variantOverrideRate ?? 0;
    return override > 0 ? override : groupBaseRate;
  }

  /// Marks [variantId] as the single default selling item for its group and
  /// syncs the group's default_variant_id pointer. Atomic-ish: clears the
  /// flag on siblings first.
  static Future<void> setDefaultVariant({
    required String itemId,
    required String variantId,
  }) async {
    await client
        .from('item_variant')
        .update({'is_default': false})
        .eq('item_id', itemId);
    await client
        .from('item_variant')
        .update({'is_default': true})
        .eq('id', variantId);
    await client
        .from('item_master')
        .update({'default_variant_id': variantId})
        .eq('id', itemId);
  }

  static Future<List<Map<String, dynamic>>> getAllItems(
    String companyId,
  ) async {
    final res = await client
        .from('item_master')
        .select(
          '*, company_hsn(*), item_variant!item_variant_item_id_fkey(*, company_hsn(*))',
        )
        .eq('company_id', companyId)
        .order('item_name');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> saveItemWithVariants({
    required Map<String, dynamic> itemData,
    required List<Map<String, dynamic>> variants,
  }) async {
    // 1. Save Item Master
    await client.from('item_master').upsert(itemData);

    // 2. Clear old variants and save new ones
    await client.from('item_variant').delete().eq('item_id', itemData['id']);

    if (variants.isNotEmpty) {
      final variantsToSave = variants
          .map((v) => {...v, 'item_id': itemData['id']})
          .toList();
      await client.from('item_variant').insert(variantsToSave);
    }
  }

  static Future<void> upsertVariant(Map<String, dynamic> data) async {
    await client.from('item_variant').upsert(data);
  }

  static Future<void> deleteVariant(String variantId) async {
    await client.from('item_variant').delete().eq('id', variantId);
  }

  static Future<void> deleteItem(String itemId) async {
    await client.from('item_master').delete().eq('id', itemId);
  }

  static Future<String> uploadItemImage(
    String id,
    List<int> bytes,
    String extension,
  ) async {
    final path = 'items/$id.$extension';
    final contentType = 'image/$extension' == 'image/jpg'
        ? 'image/jpeg'
        : 'image/$extension';

    await client.storage
        .from('items')
        .uploadBinary(
          path,
          bytes as Uint8List,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from('items').getPublicUrl(path);
  }

  /// Current time from the database (UTC). Used to anchor elapsed-time displays
  /// to the server clock so a wrong device/emulator clock can't skew them.
  static Future<DateTime?> getServerNow() async {
    try {
      final res = await client.rpc('server_now');
      if (res == null) return null;
      return DateTime.parse(res as String).toUtc();
    } catch (_) {
      return null;
    }
  }

  // ─── TABLES ────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTables(String companyId) async {
    final tables = await client
        .from('table_master')
        .select()
        .eq('company_id', companyId)
        .order('table_number');

    // Fetch open sessions to determine occupancy and map tableId -> sessionId
    final openSessions = await client
        .from('table_session')
        .select('table_id, id, opened_at')
        .eq('company_id', companyId)
        .eq('status', 'open');

    final sessionMap = <String, String>{};
    final sessionOpenedMap = <String, String>{};
    for (final s in openSessions as List) {
      final tid = s['table_id'] as String;
      sessionMap[tid] = s['id'] as String;
      if (s['opened_at'] != null) {
        sessionOpenedMap[tid] = s['opened_at'] as String;
      }
    }

    // Server clock, fetched once, so occupancy elapsed-time is anchored to the
    // database — not the (possibly wrong) device/emulator clock.
    final serverNow = sessionMap.isNotEmpty ? await getServerNow() : null;

    // Fetch open bill totals + cover counts for all occupied sessions in parallel
    final Map<String, double> sessionTotals = {};
    final Map<String, int> coverCounts = {};
    if (sessionMap.isNotEmpty) {
      final sessionIds = sessionMap.values.toList();
      final results = await Future.wait([
        client
            .from('bill_master')
            .select('table_session_id, total_amount, subtotal, cgst_amount, sgst_amount')
            .inFilter('table_session_id', sessionIds)
            .eq('status', 'open'),
        client
            .from('table_cover')
            .select('table_session_id')
            .inFilter('table_session_id', sessionIds)
            .eq('status', 'active'),
      ]);
      for (final bill in results[0] as List) {
        final sid = bill['table_session_id'] as String;
        final total = (bill['total_amount'] as num?)?.toDouble() ??
            ((bill['subtotal'] as num?)?.toDouble() ?? 0.0) +
                ((bill['cgst_amount'] as num?)?.toDouble() ?? 0.0) +
                ((bill['sgst_amount'] as num?)?.toDouble() ?? 0.0);
        sessionTotals[sid] = (sessionTotals[sid] ?? 0.0) + total;
      }
      for (final cover in results[1] as List) {
        final sid = cover['table_session_id'] as String;
        coverCounts[sid] = (coverCounts[sid] ?? 0) + 1;
      }
    }

    return (tables as List).map((t) {
      final map = Map<String, dynamic>.from(t as Map);
      final tableId = map['id'] as String;
      final sessionId = sessionMap[tableId];
      map['is_occupied'] = sessionId != null;
      map['active_session_id'] = sessionId;
      // Re-anchor opened_at into the device's clock frame using the measured
      // server elapsed, so the elapsed chip stays correct even when the device
      // clock is off. Falls back to the raw timestamp if server time is absent.
      final openedStr = sessionOpenedMap[tableId];
      if (openedStr != null && serverNow != null) {
        final opened = DateTime.tryParse(openedStr)?.toUtc();
        if (opened != null) {
          final elapsed = serverNow.difference(opened);
          map['occupied_since'] = DateTime.now()
              .toUtc()
              .subtract(elapsed.isNegative ? Duration.zero : elapsed)
              .toIso8601String();
        } else {
          map['occupied_since'] = openedStr;
        }
      } else {
        map['occupied_since'] = openedStr;
      }
      map['active_order_total'] = sessionId != null ? (sessionTotals[sessionId] ?? 0.0) : 0.0;
      map['active_cover_count'] = sessionId != null ? (coverCounts[sessionId] ?? 0) : 0;
      return map;
    }).toList();
  }

  // ─── TABLE MASTER (CRUD) ───────────────────────────────
  /// Creates a new dining table. [tableNumber] should be unique per company.
  static Future<void> createTable({
    required String companyId,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    bool isActive = true,
  }) async {
    await client.from('table_master').insert({
      'company_id': companyId,
      'table_number': tableNumber,
      'section': (section == null || section.trim().isEmpty)
          ? 'Main'
          : section.trim(),
      'seating_capacity': seatingCapacity,
      'is_active': isActive,
    });
  }

  /// Updates an existing dining table's layout fields.
  static Future<void> updateTable({
    required String id,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    required bool isActive,
  }) async {
    await client
        .from('table_master')
        .update({
          'table_number': tableNumber,
          'section': (section == null || section.trim().isEmpty)
              ? 'Main'
              : section.trim(),
          'seating_capacity': seatingCapacity,
          'is_active': isActive,
        })
        .eq('id', id);
  }

  /// Whether a table currently has an open session (is occupied right now).
  /// Used to block edits on tables that are mid-service.
  static Future<bool> isTableOccupied(String tableId) async {
    final res = await client
        .from('table_session')
        .select('id')
        .eq('table_id', tableId)
        .eq('status', 'open')
        .limit(1);
    return (res as List).isNotEmpty;
  }

  // ─── TABLE COVERS ──────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getCoversForSession(
    String sessionId,
  ) async {
    final res = await client
        .from('table_cover')
        .select()
        .eq('table_session_id', sessionId)
        .order('cover_number');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Returns a `Map<coverId, total>` for all open bills under a session
  static Future<Map<String, double>> getCoverTotals(String sessionId) async {
    final bills = await client
        .from('bill_master')
        .select('cover_id, total_amount, subtotal, cgst_amount, sgst_amount')
        .eq('table_session_id', sessionId)
        .eq('status', 'open');
    final Map<String, double> totals = {};
    for (final b in bills as List) {
      final cid = b['cover_id'] as String?;
      if (cid == null) continue;
      final total = (b['total_amount'] as num?)?.toDouble() ??
          ((b['subtotal'] as num?)?.toDouble() ?? 0.0) +
              ((b['cgst_amount'] as num?)?.toDouble() ?? 0.0) +
              ((b['sgst_amount'] as num?)?.toDouble() ?? 0.0);
      totals[cid] = (totals[cid] ?? 0.0) + total;
    }
    return totals;
  }

  /// Returns all bill items for a session, each tagged with cover_number/cover_label.
  static Future<List<Map<String, dynamic>>> getDetailedItemsForSession(
      String sessionId) async {
    final bills = await client
        .from('bill_master')
        .select('id, cover_id')
        .eq('table_session_id', sessionId);
    if ((bills as List).isEmpty) return [];

    final billIds = bills.map<String>((b) => b['id'] as String).toList();
    final coverIdByBill = <String, String?>{
      for (final b in bills) b['id'] as String: b['cover_id'] as String?,
    };

    final itemRows = await client
        .from('bill_item')
        .select('item_name_snapshot, qty, rate_snapshot, bill_id')
        .inFilter('bill_id', billIds);

    final coverIds =
        coverIdByBill.values.whereType<String>().toSet().toList();
    final coverDetails = <String, Map<String, dynamic>>{};
    if (coverIds.isNotEmpty) {
      final covers = await client
          .from('table_cover')
          .select('id, cover_number, label')
          .inFilter('id', coverIds);
      for (final c in covers as List) {
        coverDetails[c['id'] as String] = c as Map<String, dynamic>;
      }
    }

    return (itemRows as List<dynamic>).map<Map<String, dynamic>>((raw) {
      final item = raw as Map<String, dynamic>;
      final billId = item['bill_id'] as String?;
      final coverId = billId != null ? coverIdByBill[billId] : null;
      final cover = coverId != null ? coverDetails[coverId] : null;
      return {
        'item_name': (item['item_name_snapshot'] as String?) ?? '—',
        'qty': (item['qty'] as num?)?.toInt() ?? 1,
        'rate': (item['rate_snapshot'] as num?)?.toDouble() ?? 0.0,
        'cover_id': coverId,
        'cover_number': cover?['cover_number'] as int?,
        'cover_label': cover?['label'] as String?,
      };
    }).toList();
  }

  static Future<Map<String, dynamic>> createCover({
    required String sessionId,
    required String companyId,
    required int coverNumber,
    String? label,
    int pax = 1,
  }) async {
    final res = await client
        .from('table_cover')
        .insert({
          'table_session_id': sessionId,
          'company_id': companyId,
          'cover_number': coverNumber,
          'label': label,
          'pax': pax,
          'status': 'active',
        })
        .select()
        .single();
    return res;
  }

  static Future<void> updateCoverStatus(String coverId, String status) async {
    await client
        .from('table_cover')
        .update({'status': status})
        .eq('id', coverId);
  }

  static Future<void> deleteCover(String coverId) async {
    await client.from('table_cover').delete().eq('id', coverId);
  }

  /// Pays a specific cover's bill and closes the session if all covers are done
  static Future<void> checkoutCover({
    required String coverId,
    required String sessionId,
    String paymentMode = 'cash',
    double discountPercent = 0,
  }) async {
    final bills = await client
        .from('bill_master')
        .select('id, total_amount')
        .eq('cover_id', coverId)
        .eq('status', 'open')
        .limit(1);
    if ((bills as List).isEmpty) throw Exception('No open bill for this cover');

    final billId = bills[0]['id'] as String;
    final rawTotal = (bills[0]['total_amount'] as num?)?.toDouble() ?? 0.0;
    final discountAmount = rawTotal * (discountPercent / 100);
    final finalTotal = rawTotal - discountAmount;
    final now = DateTime.now();

    await Future.wait([
      client.from('bill_master').update({
        'status': 'paid',
        'payment_mode': paymentMode.toLowerCase(),
        'discount_amount': discountAmount,
        'total_amount': finalTotal,
        'bill_date': now.toIso8601String(),
      }).eq('id', billId),
      updateCoverStatus(coverId, 'billed'),
    ]);

    // Close session if no more active covers remain
    final activeCovers = await client
        .from('table_cover')
        .select('id')
        .eq('table_session_id', sessionId)
        .eq('status', 'active');
    if ((activeCovers as List).isEmpty) {
      await client.from('table_session').update({
        'status': 'billed',
        'closed_at': now.toIso8601String(),
      }).eq('id', sessionId);
    }
  }

  static Future<void> updateTableStatus(String tableId, String status) async {
    // In V2 status is typically handled via table_session,
    // but for compatibility we might update a session or just log.
    // Fixed table status update logic for V2 would go here.
  }

  // ─── ORDERS (TABLE SESSIONS) ──────────────────────────
  static Future<Map<String, dynamic>> createOrder({
    required String companyId,
    String? tableId,
    String? openedBy,
    String orderType = 'DINING',
  }) async {
    final res = await client
        .from('table_session')
        .insert({
          'company_id': companyId,
          'table_id': tableId,
          'opened_by': openedBy,
          'status': 'open',
        })
        .select()
        .single();
    return res;
  }

  static Future<void> addOrderItems(
    String sessionId,
    List<Map<String, dynamic>> items,
  ) async {
    // Note: In V2, items are added to bill_item linked via bill_master
    // which references table_session.
    // This part requires more refactoring of the internal logic.
  }

  static Future<List<Map<String, dynamic>>> getOpenOrders(
    String companyId,
  ) async {
    final res = await client
        .from('orders')
        .select('*, order_items(*, items(item_name, rate))')
        .eq('company_id', companyId)
        .eq('status', 'OPEN')
        .order('created_at');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> closeOrder(String orderId) async {
    await client.from('orders').update({'status': 'CLOSED'}).eq('id', orderId);
  }

  static Future<String> _generateBillNumber(String companyId) async {
    final now = DateTime.now();
    final fy = now.month >= 4
        ? "${now.year}-${(now.year + 1) % 100}"
        : "${now.year - 1}-${now.year % 100}";

    try {
      final companyRes = await client
          .from('company_master')
          .select('company_code')
          .eq('id', companyId)
          .maybeSingle();

      String prefix = (companyRes?['company_code'] as String?) ?? 'POS';
      if (prefix.isEmpty) prefix = 'POS';

      // Find the highest existing sequence by matching the bill_number pattern
      // for this FY — NOT by bill_date. Legacy bills can have a null bill_date,
      // and ordering by it would miss them and regenerate an already-used number
      // (a duplicate-key error on save). bill_number itself is always present.
      final latestBills = await client
          .from('bill_master')
          .select('bill_number')
          .eq('company_id', companyId)
          .ilike('bill_number', '$prefix/$fy/%')
          .order('bill_number', ascending: false)
          .limit(1);

      int sequence = 1;
      if ((latestBills as List).isNotEmpty) {
        final parts = (latestBills[0]['bill_number'] as String).split('/');
        if (parts.length == 3) sequence = (int.tryParse(parts[2]) ?? 0) + 1;
      }

      return '$prefix/$fy/${sequence.toString().padLeft(3, '0')}';
    } catch (_) {
      final ts = now.millisecondsSinceEpoch.toString();
      return 'BILL/${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}/${ts.substring(ts.length - 4)}';
    }
  }

  // ─── BILLS (BILL_MASTER) ─────────────────────────────
  static Future<Map<String, dynamic>> createBill({
    required String companyId,
    required String billedBy,
    String? tableSessionId,
    required double subtotal,
    double taxAmount = 0,
    double discountAmount = 0,
    String? discountType,
    required double totalAmount,
    String paymentMode = 'cash',
    String billType = 'dine_in',
    required List<Map<String, dynamic>> billItems,
  }) async {
    // Generate GST compliant bill number
    final billNumber = await _generateBillNumber(companyId);
    final now = DateTime.now();

    double totalCgst = 0;
    double totalSgst = 0;
    double totalIgst = 0;

    // Prepare bill items and calculate taxes
    final itemsToInsert = billItems.map((bi) {
      final qty = (bi['qty'] as num).toDouble();
      final rate = (bi['rate'] as num).toDouble();
      final gstRate = (bi['gst_rate'] as num?)?.toDouble() ?? 0;
      final isTaxable = bi['is_taxable'] as bool? ?? true;

      double cgst = 0;
      double sgst = 0;
      double igst = 0;

      if (isTaxable && gstRate > 0) {
        // Simple calculation: GST is split 50/50 between CGST and SGST for local sales
        // IGST would be the full amount for inter-state (not handled specifically here, default to CGST/SGST)
        final itemTax = (qty * rate) * (gstRate / 100);
        cgst = itemTax / 2;
        sgst = itemTax / 2;

        totalCgst += cgst;
        totalSgst += sgst;
      }

      return {
        'item_id': bi['item_id'],
        'variant_id': bi['variant_id'],
        'item_name_snapshot': bi['item_name'] ?? '',
        'rate_snapshot': rate,
        'qty': qty,
        'gross_amount': qty * rate,
        'discount_amount': bi['discount_item'] ?? 0,
        'hsn_code_snapshot': bi['hsn_code'],
        'gst_rate_snapshot': gstRate,
        'cgst_amount': cgst,
        'sgst_amount': sgst,
        'igst_amount': igst,
        'net_amount': (qty * rate) + cgst + sgst + igst,
        'notes': bi['notes'],
      };
    }).toList();

    // Create bill master
    final bill = await client
        .from('bill_master')
        .insert({
          'company_id': companyId,
          'billed_by': billedBy,
          'table_session_id': tableSessionId,
          'bill_number': billNumber,
          'bill_type': billType,
          'subtotal': subtotal,
          'discount_amount': discountAmount,
          'discount_type': discountType,
          'taxable_amount': subtotal,
          'cgst_amount': totalCgst,
          'sgst_amount': totalSgst,
          'igst_amount': totalIgst,
          'total_amount': totalAmount,
          'payment_mode': paymentMode.toLowerCase(),
          'status': 'paid', // Defaulting to paid for POS checkout
          // Stamp the billing date explicitly — reports filter/sort on
          // bill_date, so a null here hides the bill from every report.
          'bill_date': now.toIso8601String(),
        })
        .select()
        .single();

    // Insert bill items
    final billId = bill['id'];
    for (var item in itemsToInsert) {
      item['bill_id'] = billId;
    }

    await client.from('bill_item').insert(itemsToInsert);

    // Close table session and free the table
    if (tableSessionId != null) {
      await client
          .from('table_session')
          .update({'status': 'billed', 'closed_at': now.toIso8601String()})
          .eq('id', tableSessionId);
    }
    return bill;
  }

  static Future<List<Map<String, dynamic>>> getBills(
    String companyId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    var query = client
        .from('bill_master')
        .select('*, bill_item(*), table_session(table_master(table_number)), table_cover(cover_number, label)')
        .eq('company_id', companyId);

    if (startDate != null) {
      query = query.gte('bill_date', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('bill_date', endDate.toIso8601String());
    }

    final res = await query.order('bill_date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Cancels (voids) a finalized bill. The row is kept for audit — it is
  /// marked cancelled/voided rather than deleted, so reports can still show it
  /// while excluding it from revenue totals.
  static Future<void> cancelBill({
    required String billId,
    String? reason,
  }) async {
    // Only the `status` column is touched — it definitely exists and is already
    // written across the codebase. Optional [reason] is appended to `notes`.
    final data = <String, dynamic>{'status': 'cancelled'};
    if (reason != null && reason.isNotEmpty) {
      data['notes'] = 'Cancelled: $reason';
    }
    await client.from('bill_master').update(data).eq('id', billId);
  }

  /// Edits a finalized bill's line items: deletes [removedItemIds], updates the
  /// quantities of [items], then recomputes and writes back the bill totals.
  /// Each entry in [items] must contain: id, qty, rate, gst_rate.
  static Future<void> updateBill({
    required String billId,
    required List<Map<String, dynamic>> items,
    List<String> removedItemIds = const [],
    double discountAmount = 0,
  }) async {
    if (removedItemIds.isNotEmpty) {
      await client.from('bill_item').delete().inFilter('id', removedItemIds);
    }

    double subtotal = 0;
    double totalCgst = 0;
    double totalSgst = 0;

    for (final it in items) {
      final qty = (it['qty'] as num).toDouble();
      final rate = (it['rate'] as num).toDouble();
      final gstRate = (it['gst_rate'] as num?)?.toDouble() ?? 0;
      final line = qty * rate;
      final tax = line * (gstRate / 100);
      final cgst = tax / 2;
      final sgst = tax / 2;

      subtotal += line;
      totalCgst += cgst;
      totalSgst += sgst;

      await client
          .from('bill_item')
          .update({
            'qty': qty,
            'gross_amount': line,
            'cgst_amount': cgst,
            'sgst_amount': sgst,
            'net_amount': line + tax,
          })
          .eq('id', it['id']);
    }

    final total = subtotal + totalCgst + totalSgst - discountAmount;
    await client
        .from('bill_master')
        .update({
          'subtotal': subtotal,
          'taxable_amount': subtotal,
          'cgst_amount': totalCgst,
          'sgst_amount': totalSgst,
          'discount_amount': discountAmount,
          'total_amount': total < 0 ? 0 : total,
        })
        .eq('id', billId);
  }

  // ─── KOT ────────────────────────────────────────────────
  static Future<String> _generateKotNumber(String companyId) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final latest = await client
        .from('kot_master')
        .select('kot_number')
        .eq('company_id', companyId)
        .ilike('kot_number', 'KOT/$dateStr/%')
        .order('created_at', ascending: false)
        .limit(1);
    int seq = 1;
    if ((latest as List).isNotEmpty) {
      final parts = (latest[0]['kot_number'] as String).split('/');
      if (parts.length == 3) seq = (int.tryParse(parts[2]) ?? 0) + 1;
    }
    return 'KOT/$dateStr/${seq.toString().padLeft(3, '0')}';
  }

  /// Returns open bill info for a table (session_id, bill_id, total_amount, subtotal)
  static Future<Map<String, dynamic>?> getOpenBillForTable(String tableId) async {
    final sessions = await client
        .from('table_session')
        .select('id')
        .eq('table_id', tableId)
        .eq('status', 'open')
        .limit(1);
    if ((sessions as List).isEmpty) return null;
    final sessionId = sessions[0]['id'] as String;

    final bills = await client
        .from('bill_master')
        .select('id, subtotal, total_amount, cgst_amount, sgst_amount')
        .eq('table_session_id', sessionId)
        .eq('status', 'open')
        .limit(1);
    if ((bills as List).isEmpty) return {'session_id': sessionId, 'total_amount': 0.0};
    final bill = Map<String, dynamic>.from(bills[0]);
    bill['session_id'] = sessionId;
    return bill;
  }

  /// Returns full order summary with ordered items list for the active-order checkout panel
  static Future<Map<String, dynamic>?> getOrderSummaryForTable(String tableId) async {
    final sessions = await client
        .from('table_session')
        .select('id')
        .eq('table_id', tableId)
        .eq('status', 'open')
        .limit(1);
    if ((sessions as List).isEmpty) return null;
    final sessionId = sessions[0]['id'] as String;

    final bills = await client
        .from('bill_master')
        .select('id, subtotal, total_amount, cgst_amount, sgst_amount')
        .eq('table_session_id', sessionId)
        .eq('status', 'open')
        .limit(1);
    if ((bills as List).isEmpty) {
      return {'session_id': sessionId, 'ordered_items': <Map<String, dynamic>>[]};
    }
    final bill = Map<String, dynamic>.from(bills[0] as Map);
    bill['session_id'] = sessionId;

    final items = await client
        .from('bill_item')
        .select('item_name_snapshot, qty, rate_snapshot')
        .eq('bill_id', bill['id'] as String);
    bill['ordered_items'] = List<Map<String, dynamic>>.from(items as List);
    return bill;
  }

  /// Finalizes an open bill and closes the session (checkout)
  static Future<void> checkoutTable({
    required String tableId,
    required String paymentMode,
    double discountPercent = 0,
  }) async {
    final billData = await getOpenBillForTable(tableId);
    if (billData == null) throw Exception('No open order found for this table');
    final sessionId = billData['session_id'] as String;
    final billId = billData['id'] as String?;
    if (billId == null) throw Exception('No open bill found for this table');

    final rawTotal = (billData['total_amount'] as num?)?.toDouble() ?? 0.0;
    final discountAmount = rawTotal * (discountPercent / 100);
    final finalTotal = rawTotal - discountAmount;
    final now = DateTime.now();

    await client.from('bill_master').update({
      'status': 'paid',
      'payment_mode': paymentMode.toLowerCase(),
      'discount_amount': discountAmount,
      'total_amount': finalTotal,
      'bill_date': now.toIso8601String(),
    }).eq('id', billId);

    await client.from('table_session').update({
      'status': 'billed',
      'closed_at': now.toIso8601String(),
    }).eq('id', sessionId);
  }

  /// Creates (or reuses) table_session → cover → open bill_master + bill_items → kot_master + kot_items.
  /// If [coverId] is null the order is placed under Cover 1 (created if it doesn't exist yet).
  /// Returns the session ID and the cover ID actually used.
  static Future<({String sessionId, String coverId})> saveOrderWithKot({
    required String companyId,
    required String tableId,
    required String openedBy,
    required List<dynamic> cart, // List<CartItem>
    String? coverId,
  }) async {
    // Kick off the KOT-number lookup immediately (only needs companyId) so it
    // resolves in the background while we build the session/cover/bill chain,
    // keeping it off the critical path.
    final kotNumberFuture = _generateKotNumber(companyId);

    // 1. Reuse existing open session, or create a new one
    final existingSessions = await client
        .from('table_session')
        .select('id')
        .eq('company_id', companyId)
        .eq('table_id', tableId)
        .eq('status', 'open')
        .limit(1);

    String sessionId;
    if ((existingSessions as List).isNotEmpty) {
      sessionId = existingSessions[0]['id'] as String;
    } else {
      final session = await client
          .from('table_session')
          .insert({
            'company_id': companyId,
            'table_id': tableId,
            'opened_by': openedBy,
            'status': 'open',
          })
          .select()
          .single();
      sessionId = session['id'] as String;
    }

    // 1b. Resolve cover — always use an explicit cover so overview works correctly.
    //     If none supplied, create (or reuse) Cover 1 for this session.
    String effectiveCoverId;
    if (coverId != null) {
      effectiveCoverId = coverId;
    } else {
      final existing = await client
          .from('table_cover')
          .select('id')
          .eq('table_session_id', sessionId)
          .eq('cover_number', 1)
          .eq('status', 'active')
          .limit(1);
      if ((existing as List).isNotEmpty) {
        effectiveCoverId = existing[0]['id'] as String;
      } else {
        final cover = await client
            .from('table_cover')
            .insert({
              'table_session_id': sessionId,
              'company_id': companyId,
              'cover_number': 1,
              'status': 'active',
            })
            .select()
            .single();
        effectiveCoverId = cover['id'] as String;
      }
    }

    // 2. Calculate taxes and build bill_items payload
    double subtotal = 0, totalCgst = 0, totalSgst = 0;
    final billItemsData = cart.map((ci) {
      final cartItem = ci as dynamic;
      final qty = (cartItem.qty as int).toDouble();
      final rate = (cartItem.rate as double);
      final gstRate = (cartItem.variant?.gstRate ?? cartItem.item.gstRate) as double;
      final isTaxable = cartItem.item.isTaxable as bool;
      double cgst = 0, sgst = 0;
      if (isTaxable && gstRate > 0) {
        final tax = qty * rate * (gstRate / 100);
        cgst = tax / 2;
        sgst = tax / 2;
        totalCgst += cgst;
        totalSgst += sgst;
      }
      subtotal += qty * rate;
      return {
        'item_id': cartItem.item.id as String,
        'variant_id': cartItem.variant?.id as String?,
        'item_name_snapshot': cartItem.itemName as String,
        'rate_snapshot': rate,
        'qty': qty,
        'gross_amount': qty * rate,
        'discount_amount': 0.0,
        'hsn_code_snapshot': (cartItem.variant?.hsnCode ?? cartItem.item.hsnCode) as String?,
        'gst_rate_snapshot': gstRate,
        'cgst_amount': cgst,
        'sgst_amount': sgst,
        'igst_amount': 0.0,
        'net_amount': qty * rate + cgst + sgst,
        'notes': cartItem.notes as String?,
      };
    }).toList();

    // 3. Reuse existing open bill for this cover, or create new one
    final existingBills = await client
        .from('bill_master')
        .select('id, subtotal, cgst_amount, sgst_amount, total_amount')
        .eq('table_session_id', sessionId)
        .eq('cover_id', effectiveCoverId)
        .eq('status', 'open')
        .limit(1);

    String billId;
    if ((existingBills as List).isNotEmpty) {
      billId = existingBills[0]['id'] as String;
      final prevSubtotal = (existingBills[0]['subtotal'] as num).toDouble();
      final prevCgst = (existingBills[0]['cgst_amount'] as num).toDouble();
      final prevSgst = (existingBills[0]['sgst_amount'] as num).toDouble();
      await client.from('bill_master').update({
        'subtotal': prevSubtotal + subtotal,
        'taxable_amount': prevSubtotal + subtotal,
        'cgst_amount': prevCgst + totalCgst,
        'sgst_amount': prevSgst + totalSgst,
        'total_amount': prevSubtotal + subtotal + prevCgst + totalCgst + prevSgst + totalSgst,
      }).eq('id', billId);
    } else {
      final billNumber = await _generateBillNumber(companyId);
      final bill = await client
          .from('bill_master')
          .insert({
            'company_id': companyId,
            'billed_by': openedBy,
            'table_session_id': sessionId,
            'cover_id': effectiveCoverId,
            'bill_number': billNumber,
            'bill_type': 'dine_in',
            'subtotal': subtotal,
            'discount_amount': 0,
            'taxable_amount': subtotal,
            'cgst_amount': totalCgst,
            'sgst_amount': totalSgst,
            'igst_amount': 0,
            'total_amount': subtotal + totalCgst + totalSgst,
            'payment_mode': 'cash',
            'status': 'open',
            // Stamp at creation so the bill is never invisible to reports
            // (which filter/sort on bill_date); refined to the payment time
            // on checkout below.
            'bill_date': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      billId = bill['id'] as String;
    }

    // 4 + 5. The bill_items and the kot_master only depend on billId, so insert
    // them in parallel instead of sequentially (the KOT number is already
    // resolving from the start of the method).
    for (final item in billItemsData) {
      item['bill_id'] = billId;
    }
    final kotNumber = await kotNumberFuture;
    final step45 = await Future.wait<dynamic>([
      client
          .from('bill_item')
          .insert(billItemsData)
          .select('id, item_id, variant_id'),
      client
          .from('kot_master')
          .insert({
            'company_id': companyId,
            'bill_id': billId,
            'table_session_id': sessionId,
            'cover_id': effectiveCoverId,
            'kot_number': kotNumber,
            'status': 'pending',
            'created_by': openedBy,
          })
          .select('id')
          .single(),
    ]);
    final insertedItems = step45[0] as List;
    final kotId = (step45[1] as Map)['id'] as String;

    // 6. Create kot_items linked to bill_items
    final cartList = cart;
    final kotItems = insertedItems.map((bi) {
      final idx = cartList.indexWhere((ci) {
        final c = ci as dynamic;
        return c.item.id == bi['item_id'] && c.variant?.id == bi['variant_id'];
      });
      final cartItem = idx >= 0 ? cartList[idx] as dynamic : null;
      return {
        'kot_id': kotId,
        'bill_item_id': bi['id'],
        'qty': cartItem != null ? (cartItem.qty as num).toDouble() : 1.0,
        'notes': cartItem?.notes,
        'status': 'pending',
      };
    }).toList();
    await client.from('kot_item').insert(kotItems);

    return (sessionId: sessionId, coverId: effectiveCoverId);
  }

  static Future<List<Map<String, dynamic>>> getActiveKots(
    String companyId,
  ) async {
    // Show pending/in_progress always; include done KOTs from today only
    final todayStart = DateTime.now().toUtc().copyWith(
      hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0,
    );
    final res = await client
        .from('kot_master')
        .select(
          '*, table_session(table_master(table_number)), '
          'kot_item(*, bill_item(item_name_snapshot))',
        )
        .eq('company_id', companyId)
        .neq('status', 'cancelled')
        .gte('created_at', todayStart.toIso8601String())
        .order('created_at');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> updateKotStatus(String kotId, String status) async {
    await client.from('kot_master').update({'status': status}).eq('id', kotId);
  }

  static Future<void> updateKotItemStatus(
    String kotItemId,
    String status,
  ) async {
    await client.from('kot_item').update({'status': status}).eq('id', kotItemId);
  }

  // ─── UI SETTINGS ───────────────────────────────────────
  static Future<Map<String, dynamic>?> getCompanyUiSettings(
    String companyId,
  ) async {
    return await client
        .from('company_ui_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
  }

  static Future<Map<String, dynamic>?> getUserUiPreference(
    String userId,
  ) async {
    return await client
        .from('user_preference')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
  }

  static Future<void> setUserUiPreference(String userId, String theme) async {
    await client.from('user_preference').upsert({
      'user_id': userId,
      'ui_theme_type': theme,
    });
  }

  // ─── PRINT SETTINGS ───────────────────────────────────
  static Future<Map<String, dynamic>?> getPrintSettings(
    String companyId,
  ) async {
    return await client
        .from('company_print_config')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
  }

  // ─── INVENTORY: RAW MATERIAL ───────────────────────────
  /// Active raw materials for a company, ordered by name. Returns raw rows;
  /// callers map to [RawMaterial].
  static Future<List<Map<String, dynamic>>> getRawMaterials(
    String companyId,
  ) async {
    final res = await client
        .from('raw_material')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> upsertRawMaterial(Map<String, dynamic> data) async {
    await client.from('raw_material').upsert(data, onConflict: 'id');
  }

  /// Soft delete — keeps the row (and any recipe history) but hides it from
  /// the active list.
  static Future<void> deleteRawMaterial(String id) async {
    await client.from('raw_material').update({'is_active': false}).eq('id', id);
  }

  // ─── INVENTORY: RECIPE ─────────────────────────────────
  static Future<List<Map<String, dynamic>>> getRecipeForVariant(
    String itemVariantId,
  ) async {
    final res = await client
        .from('variant_recipe')
        .select()
        .eq('item_variant_id', itemVariantId);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> upsertRecipeLine(Map<String, dynamic> data) async {
    await client.from('variant_recipe').upsert(data, onConflict: 'id');
  }

  static Future<void> deleteRecipeLine(String id) async {
    await client.from('variant_recipe').delete().eq('id', id);
  }

  /// Count how many recipe lines reference a raw material — used to warn before
  /// deactivating a material that is still part of recipes.
  static Future<int> countRecipeLinesUsingMaterial(String rawMaterialId) async {
    final res = await client
        .from('variant_recipe')
        .select('id')
        .eq('raw_material_id', rawMaterialId);
    return List<Map<String, dynamic>>.from(res).length;
  }

  // ─── INVENTORY: STOCK VIEWS ────────────────────────────
  static Future<List<Map<String, dynamic>>> getCurrentStock(
    String companyId,
  ) async {
    final res = await client
        .from('v_current_stock')
        .select()
        .eq('company_id', companyId)
        .order('name');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Per-staff, per-material consumption.
  ///
  /// Without a date range we read the all-time `v_staff_consumption` view
  /// directly. With a range we aggregate `stock_ledger` consumed rows in Dart
  /// (the Supabase client can't GROUP BY), resolving material + staff names
  /// from lookup maps so we don't depend on view/FK names. Returns rows shaped
  /// for [StaffConsumptionRow].
  static Future<List<Map<String, dynamic>>> getStaffConsumption(
    String companyId, {
    DateTime? from,
    DateTime? to,
    String? staffId,
  }) async {
    if (from == null && to == null) {
      final base = client
          .from('v_staff_consumption')
          .select()
          .eq('company_id', companyId);
      final res = await (staffId != null
          ? base.eq('staff_id', staffId)
          : base);
      return List<Map<String, dynamic>>.from(res);
    }

    // Date-filtered: pull consumed ledger rows in range.
    var query = client
        .from('stock_ledger')
        .select('staff_id, raw_material_id, qty')
        .eq('company_id', companyId)
        .eq('movement_type', 'consumed');
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lte('created_at', to.toUtc().toIso8601String());
    }
    if (staffId != null) {
      query = query.eq('staff_id', staffId);
    }
    final rows = List<Map<String, dynamic>>.from(await query);

    // Lookups for labelling (names + units).
    final materials = await client
        .from('raw_material')
        .select('id, name, unit')
        .eq('company_id', companyId);
    final matById = {
      for (final m in List<Map<String, dynamic>>.from(materials))
        m['id'] as String: m,
    };
    final users = await client
        .from('user_profiles')
        .select('id, user_name')
        .eq('company_id', companyId);
    final userById = {
      for (final u in List<Map<String, dynamic>>.from(users))
        u['id'] as String: u['user_name'] as String?,
    };

    // Aggregate by (staff, material). Consumed qty is stored negative, so the
    // consumed total is the negated sum.
    final grouped = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final sId = r['staff_id'] as String?;
      final mId = r['raw_material_id'] as String? ?? '';
      final key = '${sId ?? 'unknown'}|$mId';
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      final mat = matById[mId];
      final agg = grouped.putIfAbsent(
        key,
        () => {
          'staff_id': sId,
          'staff_name': userById[sId],
          'raw_material_id': mId,
          'raw_material_name': mat?['name'] ?? '',
          'unit': mat?['unit'] ?? 'unit',
          'total_consumed': 0.0,
        },
      );
      agg['total_consumed'] = (agg['total_consumed'] as double) - qty;
    }
    return grouped.values.toList();
  }

  // ─── INVENTORY: STOCK ADJUSTMENT ───────────────────────
  /// Inserts a manual stock movement (day-end count, shift handover, etc.).
  /// Positive [qty] adds stock; negative records consumption / variance loss.
  static Future<void> submitStockAdjustment({
    required String companyId,
    required String rawMaterialId,
    required double qty,
    String movementType = 'adjustment',
    String? note,
    String? shiftLabel,
    String? staffId,
  }) async {
    await client.from('stock_ledger').insert({
      'company_id': companyId,
      'raw_material_id': rawMaterialId,
      'movement_type': movementType,
      'qty': qty,
      'note': note,
      'shift_label': shiftLabel,
      'staff_id': staffId,
    });
  }
}
