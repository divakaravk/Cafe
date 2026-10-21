/// The app's whole data-access surface, as an interface.
///
/// [SupabaseBackend] and [RestBackend] are the two implementations; [Backend]
/// (backend.dart) picks one at compile time via [AppConfig.useSupabase] and
/// exposes it as static methods, so call sites read exactly like the old
/// `SupabaseService.xxx(...)` calls did.
///
/// Signatures are a 1:1 copy of the methods `SupabaseService` already has
/// that the UI actually calls (see docs/backend-migration/PLAN.md §1.1 for the
/// dead ones this deliberately leaves out), plus 4 new methods
/// ([forceLogoutUser], [updateOwnProfile], [saveItemGroup],
/// [setGroupDefaultVariantPointer]) that replace the 3 screens that used to
/// reach past the service and call `SupabaseService.client` directly — those
/// can't survive a backend swap, since a REST API has no Postgrest client.
///
/// Every method keeps returning the same raw `Map<String, dynamic>` /
/// `List<Map<String, dynamic>>` shapes PostgREST returns today, so the
/// existing `fromJson` model constructors don't change either.
abstract interface class PosBackend {
  /// One-time setup; called once from `main()`.
  Future<void> init();

  // ─── AUTH ──────────────────────────────────────────────
  Future<Map<String, dynamic>> signInWithUserMaster({
    required String input,
    required String password,
    bool forceLogin = false,
  });

  Future<void> setLoginStatus(String userId, bool isLogin);

  Future<Map<String, dynamic>?> getUserSessionStatus(String userId);

  Future<void> signOut();

  Future<bool> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  });

  // ─── USERS ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getUsersForCompany(String companyId);

  Future<Map<String, dynamic>?> getUserPermissions(String userId);

  Future<void> upsertUserWithPermissions({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> permissionData,
    required bool isNew,
  });

  Future<String> uploadAvatar(String userId, List<int> bytes, String extension);

  /// Deactivates + force-logs-out a user. Lifted from the direct
  /// `SupabaseService.client` call in user_master_screen.dart.
  Future<void> forceLogoutUser(String userId);

  /// Updates the signed-in user's own name/phone/email/avatar. Lifted from
  /// the direct `SupabaseService.client` call in my_profile_screen.dart.
  Future<void> updateOwnProfile({
    required String userId,
    required String userName,
    String? phone,
    String? email,
    String? avatarUrl,
  });

  // ─── COMPANY ───────────────────────────────────────────
  Future<Map<String, dynamic>?> getCompany(String companyId);

  Future<void> updateCompany(String companyId, Map<String, dynamic> data);

  Future<List<Map<String, dynamic>>> getCompanyHsns(String companyId);

  // ─── COMPANY SELF-REGISTRATION ─────────────────────────
  Future<Map<String, dynamic>> requestCompanyRegistration({
    required Map<String, dynamic> company,
    required Map<String, dynamic> owner,
  });

  Future<Map<String, dynamic>> verifyCompanyRegistrationOtp({
    required String registrationId,
    required String code,
  });

  Future<void> registerSuperAdminDevice(String token, {String? label});

  Future<List<Map<String, dynamic>>> listCompanyRegistrations({int limit = 50});

  Future<Map<String, dynamic>> approveCompanyRegistration(String registrationId);

  // ─── ITEMS ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getItemGroups(String companyId);

  Future<List<Map<String, dynamic>>> getAllItems(String companyId);

  Future<List<Map<String, dynamic>>> getVariantsByGroup(
    String itemId, {
    bool onlySellable = false,
  });

  Future<void> deleteItemMaster(String id);

  Future<void> upsertVariant(Map<String, dynamic> data);

  Future<void> deleteVariant(String variantId);

  Future<void> setDefaultVariant({
    required String itemId,
    required String variantId,
  });

  Future<String> uploadItemImage(String id, List<int> bytes, String extension);

  /// Upserts an item group row. Lifted from the direct `SupabaseService.client`
  /// call in item_master_screen.dart (its `_save`).
  Future<void> saveItemGroup(Map<String, dynamic> itemData);

  /// Points a group's `default_variant_id` at [variantId]. Only used right
  /// after creating a brand-new group's auto-generated "Default" variant —
  /// [setDefaultVariant] is the general-purpose version used everywhere else.
  Future<void> setGroupDefaultVariantPointer({
    required String itemId,
    required String variantId,
  });

  // ─── TABLES ────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getTables(String companyId);

  Future<void> createTable({
    required String companyId,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    bool isActive = true,
  });

  Future<void> updateTable({
    required String id,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    required bool isActive,
  });

  Future<bool> isTableOccupied(String tableId);

  // ─── TABLE COVERS ──────────────────────────────────────
  Future<List<Map<String, dynamic>>> getCoversForSession(String sessionId);

  Future<Map<String, double>> getCoverTotals(String sessionId);

  Future<List<Map<String, dynamic>>> getDetailedItemsForSession(String sessionId);

  Future<Map<String, dynamic>> createCover({
    required String sessionId,
    required String companyId,
    required int coverNumber,
    String? label,
    int pax = 1,
  });

  Future<void> deleteCover(String coverId);

  Future<void> checkoutCover({
    required String coverId,
    required String sessionId,
    String paymentMode = 'cash',
    double discountPercent = 0,
  });

  // ─── ORDERS (TABLE SESSIONS) ───────────────────────────
  Future<Map<String, dynamic>> createOrder({
    required String companyId,
    String? tableId,
    String? openedBy,
    String orderType = 'DINING',
  });

  // ─── BILLS ─────────────────────────────────────────────
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
  });

  Future<List<Map<String, dynamic>>> getBills(
    String companyId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  Future<void> cancelBill({required String billId, String? reason});

  Future<void> updateBill({
    required String billId,
    required List<Map<String, dynamic>> items,
    List<String> removedItemIds = const [],
    double discountAmount = 0,
  });

  // ─── KOT / ORDER-TAKING ────────────────────────────────
  Future<Map<String, dynamic>?> getOrderSummaryForTable(String tableId);

  Future<void> checkoutTable({
    required String tableId,
    required String paymentMode,
    double discountPercent = 0,
  });

  /// [cart] is `List<CartItem>` in practice; kept as `dynamic` here — same as
  /// `SupabaseService` — so this file doesn't depend on `models.dart`.
  Future<({String sessionId, String coverId})> saveOrderWithKot({
    required String companyId,
    required String tableId,
    required String openedBy,
    required List<dynamic> cart,
    String? coverId,
  });

  Future<List<Map<String, dynamic>>> getActiveKots(String companyId);

  Future<void> updateKotStatus(String kotId, String status);

  Future<void> updateKotItemStatus(String kotItemId, String status);

  // ─── INVENTORY: RAW MATERIAL ───────────────────────────
  Future<List<Map<String, dynamic>>> getRawMaterials(String companyId);

  Future<void> upsertRawMaterial(Map<String, dynamic> data);

  Future<void> deleteRawMaterial(String id);

  // ─── INVENTORY: RECIPE ─────────────────────────────────
  Future<List<Map<String, dynamic>>> getRecipeForVariant(String itemVariantId);

  Future<void> upsertRecipeLine(Map<String, dynamic> data);

  Future<void> deleteRecipeLine(String id);

  Future<int> countRecipeLinesUsingMaterial(String rawMaterialId);

  // ─── INVENTORY: STOCK ──────────────────────────────────
  Future<List<Map<String, dynamic>>> getCurrentStock(String companyId);

  Future<List<Map<String, dynamic>>> getStaffConsumption(
    String companyId, {
    DateTime? from,
    DateTime? to,
    String? staffId,
  });

  Future<void> submitStockAdjustment({
    required String companyId,
    required String rawMaterialId,
    required double qty,
    String movementType = 'adjustment',
    String? note,
    String? shiftLabel,
    String? staffId,
  });
}
