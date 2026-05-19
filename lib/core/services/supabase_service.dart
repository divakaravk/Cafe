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
  }) async {
    // Search by username or email (case-insensitive)
    final res = await client
        .from('user_profiles')
        .select()
        .or('username.ilike.$input,user_email.ilike.$input')
        .eq('password', password)
        .eq('user_active', true)
        .maybeSingle();

    if (res == null) {
      throw 'Invalid username/email or password';
    }

    return res;
  }

  static Future<void> signOut() async {
    // Since we are bypassing Supabase Auth,
    // actual signOut only affects the Supabase client state,
    // but the local session should be cleared in the provider.
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
    if (isNew) {
      // 1. Insert User
      await client.from('user_profiles').insert(userData);

      // 2. Insert Permissions
      permissionData['user_id'] = userData['id'];
      await client.from('user_permission').insert(permissionData);
    } else {
      // 1. Update User
      await client
          .from('user_profiles')
          .update(userData)
          .eq('id', userData['id']);

      // 2. Upsert Permissions (easier to upsert permissions since they might not exist yet)
      permissionData['user_id'] = userData['id'];
      await client.from('user_permission').upsert(permissionData);
    }
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

  // ─── ITEMS ─────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getItemGroups(
    String companyId,
  ) async {
    final res = await client
        .from('item_master')
        .select('*, company_hsn(*), item_variant(*, company_hsn(*))')
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

  static Future<List<Map<String, dynamic>>> getAllItems(
    String companyId,
  ) async {
    final res = await client
        .from('item_master')
        .select('*, company_hsn(*), item_variant(*, company_hsn(*))')
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
      final variantsToSave = variants.map((v) {
        final map = {...v, 'item_id': itemData['id']};
        map.remove('food_type'); // Safeguard against schema mismatch
        return map;
      }).toList();
      await client.from('item_variant').insert(variantsToSave);
    }
  }

  static Future<void> upsertVariant(Map<String, dynamic> data) async {
    final cleanData = {...data};
    cleanData.remove('food_type'); // Safeguard against schema mismatch
    await client.from('item_variant').upsert(cleanData);
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

  // ─── TABLES ────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTables(String companyId) async {
    final res = await client
        .from('table_master')
        .select()
        .eq('company_id', companyId)
        .order('table_number');
    return List<Map<String, dynamic>>.from(res);
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

    // Financial Year Calculation (April to March)
    String fy;
    if (now.month >= 4) {
      fy = "${now.year}-${(now.year + 1) % 100}";
    } else {
      fy = "${now.year - 1}-${(now.year) % 100}";
    }

    try {
      // Fetch company code (prefix)
      final companyRes = await client
          .from('company_master')
          .select('company_code')
          .eq('id', companyId)
          .maybeSingle();

      String prefix = companyRes?['company_code'] ?? 'POS';
      if (prefix.isEmpty) prefix = 'POS';

      // Find the latest bill number for this company and FY
      // We order by bill_date to get the most recent one, which should have the highest sequence
      final latestBillRes = await client
          .from('bill_master')
          .select('bill_number')
          .eq('company_id', companyId)
          .ilike('bill_number', '$prefix/$fy/%')
          .order('bill_date', ascending: false)
          .limit(1);

      int sequence = 1;
      if (latestBillRes != null && (latestBillRes as List).isNotEmpty) {
        final latestBillNumber = latestBillRes[0]['bill_number'] as String;
        final parts = latestBillNumber.split('/');
        if (parts.length == 3) {
          final lastPart = parts[2];
          // Try to parse the sequence, default to current bills count if parsing fails
          sequence = (int.tryParse(lastPart) ?? 0) + 1;
        }
      }

      return '$prefix/$fy/${sequence.toString().padLeft(3, '0')}';
    } catch (e) {
      // Fallback in case of any database errors
      return 'BILL/${now.year}${now.month}${now.day}/${now.millisecondsSinceEpoch.toString().substring(now.millisecondsSinceEpoch.toString().length - 4)}';
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
        })
        .select()
        .single();

    // Insert bill items
    final billId = bill['id'];
    for (var item in itemsToInsert) {
      item['bill_id'] = billId;
    }

    await client.from('bill_item').insert(itemsToInsert);

    // If table session exists, update it
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
        .select('*, bill_item(*), table_session(table_master(table_number))')
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
}
