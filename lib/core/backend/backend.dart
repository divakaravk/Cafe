import 'app_config.dart';
import 'pos_backend.dart';
import 'rest/rest_backend.dart';
import 'supabase_backend.dart';

/// Drop-in replacement for `SupabaseService.xxx(...)` calls: same method
/// names, same signatures, same return shapes — just `Backend.` instead of
/// `SupabaseService.`. Which implementation actually runs is decided once, at
/// compile time, by [AppConfig.useSupabase]; screens never see the switch.
class Backend {
  Backend._();

  static final PosBackend _i = AppConfig.useSupabase
      ? SupabaseBackend()
      : RestBackend();

  // ─── AUTH ──────────────────────────────────────────────
  static Future<void> init() => _i.init();

  static Future<Map<String, dynamic>> signInWithUserMaster({
    required String input,
    required String password,
    bool forceLogin = false,
  }) => _i.signInWithUserMaster(
    input: input,
    password: password,
    forceLogin: forceLogin,
  );

  static Future<void> setLoginStatus(String userId, bool isLogin) =>
      _i.setLoginStatus(userId, isLogin);

  static Future<Map<String, dynamic>?> getUserSessionStatus(String userId) =>
      _i.getUserSessionStatus(userId);

  static Future<void> signOut() => _i.signOut();

  static Future<bool> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) => _i.changePassword(
    userId: userId,
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  // ─── USERS ─────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getUsersForCompany(String companyId) =>
      _i.getUsersForCompany(companyId);

  static Future<Map<String, dynamic>?> getUserPermissions(String userId) =>
      _i.getUserPermissions(userId);

  static Future<void> upsertUserWithPermissions({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> permissionData,
    required bool isNew,
  }) => _i.upsertUserWithPermissions(
    userData: userData,
    permissionData: permissionData,
    isNew: isNew,
  );

  static Future<String> uploadAvatar(String userId, List<int> bytes, String extension) =>
      _i.uploadAvatar(userId, bytes, extension);

  static Future<void> forceLogoutUser(String userId) => _i.forceLogoutUser(userId);

  static Future<void> updateOwnProfile({
    required String userId,
    required String userName,
    String? phone,
    String? email,
    String? avatarUrl,
  }) => _i.updateOwnProfile(
    userId: userId,
    userName: userName,
    phone: phone,
    email: email,
    avatarUrl: avatarUrl,
  );

  // ─── COMPANY ───────────────────────────────────────────
  static Future<Map<String, dynamic>?> getCompany(String companyId) =>
      _i.getCompany(companyId);

  static Future<void> updateCompany(String companyId, Map<String, dynamic> data) =>
      _i.updateCompany(companyId, data);

  static Future<List<Map<String, dynamic>>> getCompanyHsns(String companyId) =>
      _i.getCompanyHsns(companyId);

  // ─── COMPANY SELF-REGISTRATION ─────────────────────────
  static Future<Map<String, dynamic>> requestCompanyRegistration({
    required Map<String, dynamic> company,
    required Map<String, dynamic> owner,
  }) => _i.requestCompanyRegistration(company: company, owner: owner);

  static Future<Map<String, dynamic>> verifyCompanyRegistrationOtp({
    required String registrationId,
    required String code,
  }) => _i.verifyCompanyRegistrationOtp(registrationId: registrationId, code: code);

  static Future<void> registerSuperAdminDevice(String token, {String? label}) =>
      _i.registerSuperAdminDevice(token, label: label);

  static Future<List<Map<String, dynamic>>> listCompanyRegistrations({int limit = 50}) =>
      _i.listCompanyRegistrations(limit: limit);

  static Future<Map<String, dynamic>> approveCompanyRegistration(String registrationId) =>
      _i.approveCompanyRegistration(registrationId);

  // ─── ITEMS ─────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getItemGroups(String companyId) =>
      _i.getItemGroups(companyId);

  static Future<List<Map<String, dynamic>>> getAllItems(String companyId) =>
      _i.getAllItems(companyId);

  static Future<List<Map<String, dynamic>>> getVariantsByGroup(
    String itemId, {
    bool onlySellable = false,
  }) => _i.getVariantsByGroup(itemId, onlySellable: onlySellable);

  static Future<void> deleteItemMaster(String id) => _i.deleteItemMaster(id);

  static Future<void> upsertVariant(Map<String, dynamic> data) => _i.upsertVariant(data);

  static Future<void> deleteVariant(String variantId) => _i.deleteVariant(variantId);

  static Future<void> setDefaultVariant({
    required String itemId,
    required String variantId,
  }) => _i.setDefaultVariant(itemId: itemId, variantId: variantId);

  static Future<String> uploadItemImage(String id, List<int> bytes, String extension) =>
      _i.uploadItemImage(id, bytes, extension);

  static Future<void> saveItemGroup(Map<String, dynamic> itemData) =>
      _i.saveItemGroup(itemData);

  static Future<void> setGroupDefaultVariantPointer({
    required String itemId,
    required String variantId,
  }) => _i.setGroupDefaultVariantPointer(itemId: itemId, variantId: variantId);

  // ─── TABLES ────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTables(String companyId) =>
      _i.getTables(companyId);

  static Future<void> createTable({
    required String companyId,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    bool isActive = true,
  }) => _i.createTable(
    companyId: companyId,
    tableNumber: tableNumber,
    section: section,
    seatingCapacity: seatingCapacity,
    isActive: isActive,
  );

  static Future<void> updateTable({
    required String id,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    required bool isActive,
  }) => _i.updateTable(
    id: id,
    tableNumber: tableNumber,
    section: section,
    seatingCapacity: seatingCapacity,
    isActive: isActive,
  );

  static Future<bool> isTableOccupied(String tableId) => _i.isTableOccupied(tableId);

  // ─── TABLE COVERS ──────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getCoversForSession(String sessionId) =>
      _i.getCoversForSession(sessionId);

  static Future<Map<String, double>> getCoverTotals(String sessionId) =>
      _i.getCoverTotals(sessionId);

  static Future<List<Map<String, dynamic>>> getDetailedItemsForSession(String sessionId) =>
      _i.getDetailedItemsForSession(sessionId);

  static Future<Map<String, dynamic>> createCover({
    required String sessionId,
    required String companyId,
    required int coverNumber,
    String? label,
    int pax = 1,
  }) => _i.createCover(
    sessionId: sessionId,
    companyId: companyId,
    coverNumber: coverNumber,
    label: label,
    pax: pax,
  );

  static Future<void> deleteCover(String coverId) => _i.deleteCover(coverId);

  static Future<void> checkoutCover({
    required String coverId,
    required String sessionId,
    String paymentMode = 'cash',
    double discountPercent = 0,
  }) => _i.checkoutCover(
    coverId: coverId,
    sessionId: sessionId,
    paymentMode: paymentMode,
    discountPercent: discountPercent,
  );

  // ─── ORDERS (TABLE SESSIONS) ───────────────────────────
  static Future<Map<String, dynamic>> createOrder({
    required String companyId,
    String? tableId,
    String? openedBy,
    String orderType = 'DINING',
  }) => _i.createOrder(
    companyId: companyId,
    tableId: tableId,
    openedBy: openedBy,
    orderType: orderType,
  );

  // ─── BILLS ─────────────────────────────────────────────
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
  }) => _i.createBill(
    companyId: companyId,
    billedBy: billedBy,
    tableSessionId: tableSessionId,
    subtotal: subtotal,
    taxAmount: taxAmount,
    discountAmount: discountAmount,
    discountType: discountType,
    totalAmount: totalAmount,
    paymentMode: paymentMode,
    billType: billType,
    billItems: billItems,
  );

  static Future<List<Map<String, dynamic>>> getBills(
    String companyId, {
    DateTime? startDate,
    DateTime? endDate,
  }) => _i.getBills(companyId, startDate: startDate, endDate: endDate);

  static Future<void> cancelBill({required String billId, String? reason}) =>
      _i.cancelBill(billId: billId, reason: reason);

  static Future<void> updateBill({
    required String billId,
    required List<Map<String, dynamic>> items,
    List<String> removedItemIds = const [],
    double discountAmount = 0,
  }) => _i.updateBill(
    billId: billId,
    items: items,
    removedItemIds: removedItemIds,
    discountAmount: discountAmount,
  );

  // ─── KOT / ORDER-TAKING ────────────────────────────────
  static Future<Map<String, dynamic>?> getOrderSummaryForTable(String tableId) =>
      _i.getOrderSummaryForTable(tableId);

  static Future<void> checkoutTable({
    required String tableId,
    required String paymentMode,
    double discountPercent = 0,
  }) => _i.checkoutTable(
    tableId: tableId,
    paymentMode: paymentMode,
    discountPercent: discountPercent,
  );

  static Future<({String sessionId, String coverId})> saveOrderWithKot({
    required String companyId,
    required String tableId,
    required String openedBy,
    required List<dynamic> cart,
    String? coverId,
  }) => _i.saveOrderWithKot(
    companyId: companyId,
    tableId: tableId,
    openedBy: openedBy,
    cart: cart,
    coverId: coverId,
  );

  static Future<List<Map<String, dynamic>>> getActiveKots(String companyId) =>
      _i.getActiveKots(companyId);

  static Future<void> updateKotStatus(String kotId, String status) =>
      _i.updateKotStatus(kotId, status);

  static Future<void> updateKotItemStatus(String kotItemId, String status) =>
      _i.updateKotItemStatus(kotItemId, status);

  // ─── INVENTORY: RAW MATERIAL ───────────────────────────
  static Future<List<Map<String, dynamic>>> getRawMaterials(String companyId) =>
      _i.getRawMaterials(companyId);

  static Future<void> upsertRawMaterial(Map<String, dynamic> data) =>
      _i.upsertRawMaterial(data);

  static Future<void> deleteRawMaterial(String id) => _i.deleteRawMaterial(id);

  // ─── INVENTORY: RECIPE ─────────────────────────────────
  static Future<List<Map<String, dynamic>>> getRecipeForVariant(String itemVariantId) =>
      _i.getRecipeForVariant(itemVariantId);

  static Future<void> upsertRecipeLine(Map<String, dynamic> data) =>
      _i.upsertRecipeLine(data);

  static Future<void> deleteRecipeLine(String id) => _i.deleteRecipeLine(id);

  static Future<int> countRecipeLinesUsingMaterial(String rawMaterialId) =>
      _i.countRecipeLinesUsingMaterial(rawMaterialId);

  // ─── INVENTORY: STOCK ──────────────────────────────────
  static Future<List<Map<String, dynamic>>> getCurrentStock(String companyId) =>
      _i.getCurrentStock(companyId);

  static Future<List<Map<String, dynamic>>> getStaffConsumption(
    String companyId, {
    DateTime? from,
    DateTime? to,
    String? staffId,
  }) => _i.getStaffConsumption(companyId, from: from, to: to, staffId: staffId);

  static Future<void> submitStockAdjustment({
    required String companyId,
    required String rawMaterialId,
    required double qty,
    String movementType = 'adjustment',
    String? note,
    String? shiftLabel,
    String? staffId,
  }) => _i.submitStockAdjustment(
    companyId: companyId,
    rawMaterialId: rawMaterialId,
    qty: qty,
    movementType: movementType,
    note: note,
    shiftLabel: shiftLabel,
    staffId: staffId,
  );
}
