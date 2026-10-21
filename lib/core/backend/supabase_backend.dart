import '../services/supabase_service.dart';
import 'pos_backend.dart';

/// [PosBackend] over the existing, unchanged `SupabaseService`. This is the
/// default backend (`AppConfig.useSupabase == true`) — every call here is a
/// straight pass-through, so Supabase-mode behaviour is byte-for-byte what it
/// was before this facade existed.
class SupabaseBackend implements PosBackend {
  @override
  Future<void> init() => SupabaseService.init();

  // ─── AUTH ──────────────────────────────────────────────
  @override
  Future<Map<String, dynamic>> signInWithUserMaster({
    required String input,
    required String password,
    bool forceLogin = false,
  }) => SupabaseService.signInWithUserMaster(
    input: input,
    password: password,
    forceLogin: forceLogin,
  );

  @override
  Future<void> setLoginStatus(String userId, bool isLogin) =>
      SupabaseService.setLoginStatus(userId, isLogin);

  @override
  Future<Map<String, dynamic>?> getUserSessionStatus(String userId) =>
      SupabaseService.getUserSessionStatus(userId);

  @override
  Future<void> signOut() => SupabaseService.signOut();

  @override
  Future<bool> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) => SupabaseService.changePassword(
    userId: userId,
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  // ─── USERS ─────────────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getUsersForCompany(String companyId) =>
      SupabaseService.getUsersForCompany(companyId);

  @override
  Future<Map<String, dynamic>?> getUserPermissions(String userId) =>
      SupabaseService.getUserPermissions(userId);

  @override
  Future<void> upsertUserWithPermissions({
    required Map<String, dynamic> userData,
    required Map<String, dynamic> permissionData,
    required bool isNew,
  }) => SupabaseService.upsertUserWithPermissions(
    userData: userData,
    permissionData: permissionData,
    isNew: isNew,
  );

  @override
  Future<String> uploadAvatar(String userId, List<int> bytes, String extension) =>
      SupabaseService.uploadAvatar(userId, bytes, extension);

  @override
  Future<void> forceLogoutUser(String userId) =>
      SupabaseService.forceLogoutUser(userId);

  @override
  Future<void> updateOwnProfile({
    required String userId,
    required String userName,
    String? phone,
    String? email,
    String? avatarUrl,
  }) => SupabaseService.updateOwnProfile(
    userId: userId,
    userName: userName,
    phone: phone,
    email: email,
    avatarUrl: avatarUrl,
  );

  // ─── COMPANY ───────────────────────────────────────────
  @override
  Future<Map<String, dynamic>?> getCompany(String companyId) =>
      SupabaseService.getCompany(companyId);

  @override
  Future<void> updateCompany(String companyId, Map<String, dynamic> data) =>
      SupabaseService.updateCompany(companyId, data);

  @override
  Future<List<Map<String, dynamic>>> getCompanyHsns(String companyId) =>
      SupabaseService.getCompanyHsns(companyId);

  // ─── COMPANY SELF-REGISTRATION ─────────────────────────
  @override
  Future<Map<String, dynamic>> requestCompanyRegistration({
    required Map<String, dynamic> company,
    required Map<String, dynamic> owner,
  }) => SupabaseService.requestCompanyRegistration(company: company, owner: owner);

  @override
  Future<Map<String, dynamic>> verifyCompanyRegistrationOtp({
    required String registrationId,
    required String code,
  }) => SupabaseService.verifyCompanyRegistrationOtp(
    registrationId: registrationId,
    code: code,
  );

  @override
  Future<void> registerSuperAdminDevice(String token, {String? label}) =>
      SupabaseService.registerSuperAdminDevice(token, label: label);

  @override
  Future<List<Map<String, dynamic>>> listCompanyRegistrations({int limit = 50}) =>
      SupabaseService.listCompanyRegistrations(limit: limit);

  @override
  Future<Map<String, dynamic>> approveCompanyRegistration(String registrationId) =>
      SupabaseService.approveCompanyRegistration(registrationId);

  // ─── ITEMS ─────────────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getItemGroups(String companyId) =>
      SupabaseService.getItemGroups(companyId);

  @override
  Future<List<Map<String, dynamic>>> getAllItems(String companyId) =>
      SupabaseService.getAllItems(companyId);

  @override
  Future<List<Map<String, dynamic>>> getVariantsByGroup(
    String itemId, {
    bool onlySellable = false,
  }) => SupabaseService.getVariantsByGroup(itemId, onlySellable: onlySellable);

  @override
  Future<void> deleteItemMaster(String id) => SupabaseService.deleteItemMaster(id);

  @override
  Future<void> upsertVariant(Map<String, dynamic> data) =>
      SupabaseService.upsertVariant(data);

  @override
  Future<void> deleteVariant(String variantId) =>
      SupabaseService.deleteVariant(variantId);

  @override
  Future<void> setDefaultVariant({
    required String itemId,
    required String variantId,
  }) => SupabaseService.setDefaultVariant(itemId: itemId, variantId: variantId);

  @override
  Future<String> uploadItemImage(String id, List<int> bytes, String extension) =>
      SupabaseService.uploadItemImage(id, bytes, extension);

  @override
  Future<void> saveItemGroup(Map<String, dynamic> itemData) =>
      SupabaseService.saveItemGroup(itemData);

  @override
  Future<void> setGroupDefaultVariantPointer({
    required String itemId,
    required String variantId,
  }) => SupabaseService.setGroupDefaultVariantPointer(
    itemId: itemId,
    variantId: variantId,
  );

  // ─── TABLES ────────────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getTables(String companyId) =>
      SupabaseService.getTables(companyId);

  @override
  Future<void> createTable({
    required String companyId,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    bool isActive = true,
  }) => SupabaseService.createTable(
    companyId: companyId,
    tableNumber: tableNumber,
    section: section,
    seatingCapacity: seatingCapacity,
    isActive: isActive,
  );

  @override
  Future<void> updateTable({
    required String id,
    required String tableNumber,
    String? section,
    required int seatingCapacity,
    required bool isActive,
  }) => SupabaseService.updateTable(
    id: id,
    tableNumber: tableNumber,
    section: section,
    seatingCapacity: seatingCapacity,
    isActive: isActive,
  );

  @override
  Future<bool> isTableOccupied(String tableId) =>
      SupabaseService.isTableOccupied(tableId);

  // ─── TABLE COVERS ──────────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getCoversForSession(String sessionId) =>
      SupabaseService.getCoversForSession(sessionId);

  @override
  Future<Map<String, double>> getCoverTotals(String sessionId) =>
      SupabaseService.getCoverTotals(sessionId);

  @override
  Future<List<Map<String, dynamic>>> getDetailedItemsForSession(String sessionId) =>
      SupabaseService.getDetailedItemsForSession(sessionId);

  @override
  Future<Map<String, dynamic>> createCover({
    required String sessionId,
    required String companyId,
    required int coverNumber,
    String? label,
    int pax = 1,
  }) => SupabaseService.createCover(
    sessionId: sessionId,
    companyId: companyId,
    coverNumber: coverNumber,
    label: label,
    pax: pax,
  );

  @override
  Future<void> deleteCover(String coverId) => SupabaseService.deleteCover(coverId);

  @override
  Future<void> checkoutCover({
    required String coverId,
    required String sessionId,
    String paymentMode = 'cash',
    double discountPercent = 0,
  }) => SupabaseService.checkoutCover(
    coverId: coverId,
    sessionId: sessionId,
    paymentMode: paymentMode,
    discountPercent: discountPercent,
  );

  // ─── ORDERS (TABLE SESSIONS) ───────────────────────────
  @override
  Future<Map<String, dynamic>> createOrder({
    required String companyId,
    String? tableId,
    String? openedBy,
    String orderType = 'DINING',
  }) => SupabaseService.createOrder(
    companyId: companyId,
    tableId: tableId,
    openedBy: openedBy,
    orderType: orderType,
  );

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
  }) => SupabaseService.createBill(
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

  @override
  Future<List<Map<String, dynamic>>> getBills(
    String companyId, {
    DateTime? startDate,
    DateTime? endDate,
  }) => SupabaseService.getBills(
    companyId,
    startDate: startDate,
    endDate: endDate,
  );

  @override
  Future<void> cancelBill({required String billId, String? reason}) =>
      SupabaseService.cancelBill(billId: billId, reason: reason);

  @override
  Future<void> updateBill({
    required String billId,
    required List<Map<String, dynamic>> items,
    List<String> removedItemIds = const [],
    double discountAmount = 0,
  }) => SupabaseService.updateBill(
    billId: billId,
    items: items,
    removedItemIds: removedItemIds,
    discountAmount: discountAmount,
  );

  // ─── KOT / ORDER-TAKING ────────────────────────────────
  @override
  Future<Map<String, dynamic>?> getOrderSummaryForTable(String tableId) =>
      SupabaseService.getOrderSummaryForTable(tableId);

  @override
  Future<void> checkoutTable({
    required String tableId,
    required String paymentMode,
    double discountPercent = 0,
  }) => SupabaseService.checkoutTable(
    tableId: tableId,
    paymentMode: paymentMode,
    discountPercent: discountPercent,
  );

  @override
  Future<({String sessionId, String coverId})> saveOrderWithKot({
    required String companyId,
    required String tableId,
    required String openedBy,
    required List<dynamic> cart,
    String? coverId,
  }) => SupabaseService.saveOrderWithKot(
    companyId: companyId,
    tableId: tableId,
    openedBy: openedBy,
    cart: cart,
    coverId: coverId,
  );

  @override
  Future<List<Map<String, dynamic>>> getActiveKots(String companyId) =>
      SupabaseService.getActiveKots(companyId);

  @override
  Future<void> updateKotStatus(String kotId, String status) =>
      SupabaseService.updateKotStatus(kotId, status);

  @override
  Future<void> updateKotItemStatus(String kotItemId, String status) =>
      SupabaseService.updateKotItemStatus(kotItemId, status);

  // ─── INVENTORY: RAW MATERIAL ───────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getRawMaterials(String companyId) =>
      SupabaseService.getRawMaterials(companyId);

  @override
  Future<void> upsertRawMaterial(Map<String, dynamic> data) =>
      SupabaseService.upsertRawMaterial(data);

  @override
  Future<void> deleteRawMaterial(String id) =>
      SupabaseService.deleteRawMaterial(id);

  // ─── INVENTORY: RECIPE ─────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getRecipeForVariant(String itemVariantId) =>
      SupabaseService.getRecipeForVariant(itemVariantId);

  @override
  Future<void> upsertRecipeLine(Map<String, dynamic> data) =>
      SupabaseService.upsertRecipeLine(data);

  @override
  Future<void> deleteRecipeLine(String id) => SupabaseService.deleteRecipeLine(id);

  @override
  Future<int> countRecipeLinesUsingMaterial(String rawMaterialId) =>
      SupabaseService.countRecipeLinesUsingMaterial(rawMaterialId);

  // ─── INVENTORY: STOCK ──────────────────────────────────
  @override
  Future<List<Map<String, dynamic>>> getCurrentStock(String companyId) =>
      SupabaseService.getCurrentStock(companyId);

  @override
  Future<List<Map<String, dynamic>>> getStaffConsumption(
    String companyId, {
    DateTime? from,
    DateTime? to,
    String? staffId,
  }) => SupabaseService.getStaffConsumption(
    companyId,
    from: from,
    to: to,
    staffId: staffId,
  );

  @override
  Future<void> submitStockAdjustment({
    required String companyId,
    required String rawMaterialId,
    required double qty,
    String movementType = 'adjustment',
    String? note,
    String? shiftLabel,
    String? staffId,
  }) => SupabaseService.submitStockAdjustment(
    companyId: companyId,
    rawMaterialId: rawMaterialId,
    qty: qty,
    movementType: movementType,
    note: note,
    shiftLabel: shiftLabel,
    staffId: staffId,
  );
}
