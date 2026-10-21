import 'package:uuid/uuid.dart';
import '../../utils/api_helper.dart';
import '../pos_backend.dart';
import 'api_client.dart';
import 'token_store.dart';

List<Map<String, dynamic>> _list(dynamic res) =>
    (res as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

Map<String, dynamic>? _map(dynamic res) => res == null ? null : Map<String, dynamic>.from(res as Map);

/// The Node + MySQL backend (docs/backend-migration/PLAN.md Phase 6). Every
/// method mirrors the exact endpoint it was designed against in that plan and
/// verified against in `backend/scripts/smoke.mjs` (auth, tenant isolation,
/// the order/KOT transaction, idempotency replay, etc. — 85/85 there as of
/// writing). Returns the same JSON shapes PostgREST did, so the existing
/// `fromJson` model constructors are untouched.
class RestBackend implements PosBackend {
  final _api = ApiClient.instance;
  final _uuid = const Uuid();

  /// Registration id + token received from [verifyCompanyRegistrationOtp],
  /// keyed by company id — [upsertUserWithPermissions] needs both to create
  /// the first admin (that call happens before any login exists, and
  /// `RegisterAdminScreen` is only ever given a `companyId`, never the
  /// registration id — see register_admin_screen.dart's constructor). See
  /// docs/backend-migration/PLAN.md §4.2's endpoint map: "requires the
  /// single-use registration token ... RestBackend keeps it in memory."
  final Map<String, ({String registrationId, String token})> _registrations = {};

  // ─── AUTH ──────────────────────────────────────────────
  @override
  Future<void> init() async {
    // No network call here on purpose: ApiClient transparently refreshes on
    // the first 401 it hits, so a cold start with a stored refresh token
    // "just works" the moment the app makes its first authenticated request
    // (e.g. AuthNotifier's post-frame `validateSession()` call).
  }

  @override
  Future<Map<String, dynamic>> signInWithUserMaster({
    required String input,
    required String password,
    bool forceLogin = false,
  }) async {
    try {
      final res = await _api.post(
        '/auth/login',
        auth: false,
        body: {'input': input, 'password': password, 'forceLogin': forceLogin},
      );
      final body = Map<String, dynamic>.from(res as Map);
      TokenStore.instance.setAccessToken(body['access_token'] as String);
      // Absent on web — the backend hands it back as an httpOnly cookie
      // instead (see api_client.dart's X-Client-Platform header).
      final refreshToken = body['refresh_token'] as String?;
      if (refreshToken != null) await TokenStore.instance.saveRefreshToken(refreshToken);
      return Map<String, dynamic>.from(body['profile'] as Map);
    } on ApiException catch (e) {
      // Exact parity with SupabaseService.signInWithUserMaster: it `throw`s a
      // raw String, and AuthNotifier.signIn stores `e.toString()` as the
      // AsyncError — login_screen.dart's `err == 'ALREADY_LOGGED_IN'` equality
      // check only works if that raw string round-trips exactly like this.
      if (e.code == 'ALREADY_LOGGED_IN') throw 'ALREADY_LOGGED_IN';
      throw e.message;
    }
  }

  @override
  Future<void> setLoginStatus(String userId, bool isLogin) async {
    await _api.post('/auth/login-status', body: {'is_login': isLogin});
  }

  @override
  Future<Map<String, dynamic>?> getUserSessionStatus(String userId) async {
    return _map(await _api.get('/auth/session'));
  }

  @override
  Future<void> signOut() async {
    final refreshToken = await TokenStore.instance.readRefreshToken();
    try {
      // On web there's nothing stored (the cookie itself carries it); on
      // native, omit the key entirely when null rather than send it as JSON
      // `null`.
      await _api.post('/auth/logout', auth: false, body: {if (refreshToken != null) 'refresh_token': refreshToken});
    } catch (_) {
      // best-effort — the local sign-out below must always proceed
    }
    await TokenStore.instance.clear();
  }

  @override
  Future<bool> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _api.post('/auth/change-password', body: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
    return (res as Map)['ok'] == true;
  }

  // ─── USERS ─────────────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getUsersForCompany(String companyId) async {
    return _list(await _api.get('/users', query: {'company_id': companyId}));
  }

  @override
  Future<Map<String, dynamic>?> getUserPermissions(String userId) async {
    return _map(await _api.get('/users/$userId/permissions'));
  }

  @override
  Future<void> upsertUserWithPermissions({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> permissionData,
    required bool isNew,
  }) async {
    final companyId = userData['company_id'] as String?;
    final pending = isNew && companyId != null ? _registrations[companyId] : null;

    if (pending != null) {
      // First admin of a just-verified registration — no session exists yet.
      await _api.post(
        '/public/registrations/${pending.registrationId}/admin',
        auth: false,
        body: {
          'registration_token': pending.token,
          'user': {
            'user_name': userData['user_name'],
            'employee_code': userData['employee_code'],
            'username': userData['username'],
            'password': userData['password'],
            'mob_number': userData['mob_number'],
            'user_email': userData['user_email'],
          },
        },
      );
      _registrations.remove(companyId);
      return;
    }

    final body = {'user': userData, 'permissions': permissionData};
    if (isNew) {
      await _api.post('/users', body: body);
    } else {
      await _api.put('/users/${userData['id']}', body: body);
    }
  }

  @override
  Future<String> uploadAvatar(String userId, List<int> bytes, String extension) async {
    final res = await _api.uploadFile('/uploads/avatar', bytes: bytes, filename: 'avatar.$extension');
    return (res as Map)['url'] as String;
  }

  @override
  Future<void> forceLogoutUser(String userId) async {
    await _api.post('/users/$userId/force-logout');
  }

  @override
  Future<void> updateOwnProfile({
    required String userId,
    required String userName,
    String? phone,
    String? email,
    String? avatarUrl,
  }) async {
    await _api.patch('/users/me', body: {
      'user_name': userName,
      'mob_number': phone,
      'user_email': email,
      'avatar_url': avatarUrl,
    });
  }

  // ─── COMPANY ───────────────────────────────────────────
  @override
  Future<Map<String, dynamic>?> getCompany(String companyId) async {
    return _map(await _api.get('/company'));
  }

  @override
  Future<void> updateCompany(String companyId, Map<String, dynamic> data) async {
    await _api.patch('/company', body: data);
  }

  @override
  Future<List<Map<String, dynamic>>> getCompanyHsns(String companyId) async {
    return _list(await _api.get('/company/hsn'));
  }

  // ─── COMPANY SELF-REGISTRATION ─────────────────────────
  @override
  Future<Map<String, dynamic>> requestCompanyRegistration({
    required Map<String, dynamic> company,
    required Map<String, dynamic> owner,
  }) async {
    final res = await _api.post('/public/registrations', auth: false, body: {'company': company, 'owner': owner});
    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<Map<String, dynamic>> verifyCompanyRegistrationOtp({
    required String registrationId,
    required String code,
  }) async {
    final res = await _api.post('/public/registrations/$registrationId/verify', auth: false, body: {'code': code});
    final body = Map<String, dynamic>.from(res as Map);
    if (body['ok'] == true && body['registration_token'] != null && body['company_id'] != null) {
      _registrations[body['company_id'] as String] =
          (registrationId: registrationId, token: body['registration_token'] as String);
    }
    return body;
  }

  @override
  Future<void> registerSuperAdminDevice(String token, {String? label}) async {
    await _api.put('/owner/devices', body: {'token': token, 'label': label});
  }

  @override
  Future<List<Map<String, dynamic>>> listCompanyRegistrations({int limit = 50}) async {
    return _list(await _api.get('/owner/registrations', query: {'limit': '$limit'}));
  }

  @override
  Future<Map<String, dynamic>> approveCompanyRegistration(String registrationId) async {
    final res = await _api.post('/owner/registrations/$registrationId/approve');
    return Map<String, dynamic>.from(res as Map);
  }

  // ─── ITEMS ─────────────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getItemGroups(String companyId) async {
    return _list(await _api.get('/items', query: {'order': 'display'}));
  }

  @override
  Future<List<Map<String, dynamic>>> getAllItems(String companyId) async {
    return _list(await _api.get('/items', query: {'order': 'name'}));
  }

  @override
  Future<List<Map<String, dynamic>>> getVariantsByGroup(String itemId, {bool onlySellable = false}) async {
    return _list(await _api.get('/items/$itemId/variants', query: {'sellable': '$onlySellable'}));
  }

  @override
  Future<void> deleteItemMaster(String id) async {
    await _api.delete('/items/$id');
  }

  @override
  Future<void> upsertVariant(Map<String, dynamic> data) async {
    await _api.put('/variants/${data['id']}', body: data);
  }

  @override
  Future<void> deleteVariant(String variantId) async {
    await _api.delete('/variants/$variantId');
  }

  @override
  Future<void> setDefaultVariant({required String itemId, required String variantId}) async {
    await _api.post('/items/$itemId/default-variant', body: {'variant_id': variantId});
  }

  @override
  Future<String> uploadItemImage(String id, List<int> bytes, String extension) async {
    final res = await _api.uploadFile('/uploads/item-image', bytes: bytes, filename: 'item.$extension', query: {'id': id});
    return (res as Map)['url'] as String;
  }

  @override
  Future<void> saveItemGroup(Map<String, dynamic> itemData) async {
    await _api.put('/items/${itemData['id']}', body: {'data': itemData});
  }

  @override
  Future<void> setGroupDefaultVariantPointer({required String itemId, required String variantId}) async {
    await _api.post('/items/$itemId/default-variant-pointer', body: {'variant_id': variantId});
  }

  // ─── TABLES ────────────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getTables(String companyId) async {
    return _list(await _api.get('/tables'));
  }

  @override
  Future<void> createTable({
    required String companyId,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    bool isActive = true,
  }) async {
    await _api.post('/tables', body: {
      'table_number': tableNumber,
      'section': section,
      'seating_capacity': seatingCapacity,
      'is_active': isActive,
    });
  }

  @override
  Future<void> updateTable({
    required String id,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    required bool isActive,
  }) async {
    await _api.patch('/tables/$id', body: {
      'table_number': tableNumber,
      'section': section,
      'seating_capacity': seatingCapacity,
      'is_active': isActive,
    });
  }

  @override
  Future<bool> isTableOccupied(String tableId) async {
    final res = await _api.get('/tables/$tableId/occupied');
    return (res as Map)['occupied'] == true;
  }

  // ─── TABLE COVERS ──────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getCoversForSession(String sessionId) async {
    return _list(await _api.get('/sessions/$sessionId/covers'));
  }

  @override
  Future<Map<String, double>> getCoverTotals(String sessionId) async {
    final res = Map<String, dynamic>.from(await _api.get('/sessions/$sessionId/cover-totals') as Map);
    return res.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  @override
  Future<List<Map<String, dynamic>>> getDetailedItemsForSession(String sessionId) async {
    return _list(await _api.get('/sessions/$sessionId/items'));
  }

  @override
  Future<Map<String, dynamic>> createCover({
    required String sessionId,
    required String companyId,
    required int coverNumber,
    String? label,
    int pax = 1,
  }) async {
    final res = await _api.post('/sessions/$sessionId/covers', body: {
      'cover_number': coverNumber,
      'label': label,
      'pax': pax,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<void> deleteCover(String coverId) async {
    await _api.delete('/covers/$coverId');
  }

  @override
  Future<void> checkoutCover({
    required String coverId,
    required String sessionId,
    String paymentMode = 'cash',
    double discountPercent = 0,
  }) async {
    await _api.post('/covers/$coverId/checkout', body: {
      'session_id': sessionId,
      'payment_mode': paymentMode,
      'discount_percent': discountPercent,
    });
  }

  // ─── ORDERS (TABLE SESSIONS) ───────────────────────────
  @override
  Future<Map<String, dynamic>> createOrder({
    required String companyId,
    String? tableId,
    String? openedBy,
    String orderType = 'DINING',
  }) async {
    final res = await _api.post('/sessions', body: {'table_id': tableId, 'order_type': orderType});
    return Map<String, dynamic>.from(res as Map);
  }

  // ─── BILLS ─────────────────────────────────────────────
  @override
  Future<Map<String, dynamic>> createBill({
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
    final res = await _api.post(
      '/bills',
      idempotencyKey: _uuid.v4(),
      body: {
        'table_session_id': tableSessionId,
        'subtotal': subtotal,
        'discount_amount': discountAmount,
        'discount_type': discountType,
        'total_amount': totalAmount,
        'payment_mode': paymentMode,
        'bill_type': billType,
        'bill_items': billItems,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> getBills(String companyId, {DateTime? startDate, DateTime? endDate}) async {
    return _list(await _api.get('/bills', query: {
      if (startDate != null) 'from': startDate.toUtc().toIso8601String(),
      if (endDate != null) 'to': endDate.toUtc().toIso8601String(),
    }));
  }

  @override
  Future<void> cancelBill({required String billId, String? reason}) async {
    await _api.post('/bills/$billId/cancel', body: {'reason': reason});
  }

  @override
  Future<void> updateBill({
    required String billId,
    required List<Map<String, dynamic>> items,
    List<String> removedItemIds = const [],
    double discountAmount = 0,
  }) async {
    await _api.patch('/bills/$billId', body: {
      'items': items,
      'removed_item_ids': removedItemIds,
      'discount_amount': discountAmount,
    });
  }

  // ─── KOT / ORDER-TAKING ────────────────────────────────
  @override
  Future<Map<String, dynamic>?> getOrderSummaryForTable(String tableId) async {
    return _map(await _api.get('/tables/$tableId/order-summary'));
  }

  @override
  Future<void> checkoutTable({
    required String tableId,
    required String paymentMode,
    double discountPercent = 0,
  }) async {
    await _api.post(
      '/tables/$tableId/checkout',
      idempotencyKey: _uuid.v4(),
      body: {'payment_mode': paymentMode, 'discount_percent': discountPercent},
    );
  }

  @override
  Future<({String sessionId, String coverId})> saveOrderWithKot({
    required String companyId,
    required String tableId,
    required String openedBy,
    required List<dynamic> cart,
    String? coverId,
  }) async {
    final cartJson = cart.map((ci) {
      final c = ci as dynamic;
      final qty = (c.qty as num).toDouble();
      final rate = c.rate as double;
      final gstRate = (c.variant?.gstRate ?? c.item.gstRate) as double;
      final isTaxable = c.item.isTaxable as bool;
      final hsnCode = (c.variant?.hsnCode ?? c.item.hsnCode) as String?;
      return {
        'item_id': c.item.id as String,
        'variant_id': c.variant?.id as String?,
        'item_name': c.itemName as String,
        'rate': rate,
        'qty': qty,
        'gst_rate': gstRate,
        'is_taxable': isTaxable,
        'hsn_code': hsnCode,
        'notes': c.notes as String?,
      };
    }).toList();

    final res = await _api.post(
      '/orders/kot',
      idempotencyKey: _uuid.v4(),
      body: {'table_id': tableId, 'cover_id': coverId, 'cart': cartJson},
    );
    final body = Map<String, dynamic>.from(res as Map);
    return (sessionId: body['sessionId'] as String, coverId: body['coverId'] as String);
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveKots(String companyId) async {
    return _list(await _api.get('/kots'));
  }

  @override
  Future<void> updateKotStatus(String kotId, String status) async {
    await _api.patch('/kots/$kotId', body: {'status': status});
  }

  @override
  Future<void> updateKotItemStatus(String kotItemId, String status) async {
    await _api.patch('/kot-items/$kotItemId', body: {'status': status});
  }

  // ─── INVENTORY: RAW MATERIAL ───────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getRawMaterials(String companyId) async {
    return _list(await _api.get('/inventory/materials'));
  }

  @override
  Future<void> upsertRawMaterial(Map<String, dynamic> data) async {
    final id = data['id'] ?? _uuid.v4();
    await _api.put('/inventory/materials/$id', body: data);
  }

  @override
  Future<void> deleteRawMaterial(String id) async {
    await _api.delete('/inventory/materials/$id');
  }

  // ─── INVENTORY: RECIPE ─────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getRecipeForVariant(String itemVariantId) async {
    return _list(await _api.get('/inventory/recipes', query: {'variant_id': itemVariantId}));
  }

  @override
  Future<void> upsertRecipeLine(Map<String, dynamic> data) async {
    final id = data['id'] ?? _uuid.v4();
    await _api.put('/inventory/recipes/$id', body: data);
  }

  @override
  Future<void> deleteRecipeLine(String id) async {
    await _api.delete('/inventory/recipes/$id');
  }

  @override
  Future<int> countRecipeLinesUsingMaterial(String rawMaterialId) async {
    final res = await _api.get('/inventory/materials/$rawMaterialId/recipe-usage');
    return ((res as Map)['count'] as num).toInt();
  }

  // ─── INVENTORY: STOCK ──────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getCurrentStock(String companyId) async {
    return _list(await _api.get('/inventory/stock'));
  }

  @override
  Future<List<Map<String, dynamic>>> getStaffConsumption(
    String companyId, {
    DateTime? from,
    DateTime? to,
    String? staffId,
  }) async {
    return _list(await _api.get('/inventory/staff-consumption', query: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (staffId != null) 'staff_id': staffId,
    }));
  }

  @override
  Future<void> submitStockAdjustment({
    required String companyId,
    required String rawMaterialId,
    required double qty,
    String movementType = 'adjustment',
    String? note,
    String? shiftLabel,
    String? staffId,
  }) async {
    await _api.post('/inventory/adjustments', body: {
      'raw_material_id': rawMaterialId,
      'qty': qty,
      'movement_type': movementType,
      'note': note,
      'shift_label': shiftLabel,
      'staff_id': staffId,
    });
  }
}
