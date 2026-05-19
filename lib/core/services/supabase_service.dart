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
    final tables = await client
        .from('table_master')
        .select()
        .eq('company_id', companyId)
        .order('table_number');

    // Fetch tables that have an open session to determine occupancy
    final openSessions = await client
        .from('table_session')
        .select('table_id')
        .eq('company_id', companyId)
        .eq('status', 'open');

    final occupiedIds = {
      for (final s in openSessions as List) s['table_id'] as String,
    };

    return (tables as List).map((t) {
      final map = Map<String, dynamic>.from(t as Map);
      map['is_occupied'] = occupiedIds.contains(map['id']);
      return map;
    }).toList();
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
    }).eq('id', billId);

    await client.from('table_session').update({
      'status': 'billed',
      'closed_at': now.toIso8601String(),
    }).eq('id', sessionId);
  }

  /// Creates (or reuses) table_session → open bill_master + bill_items → kot_master + kot_items
  static Future<void> saveOrderWithKot({
    required String companyId,
    required String tableId,
    required String openedBy,
    required List<dynamic> cart, // List<CartItem>
  }) async {
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

    // 2. Calculate taxes and build bill_items payload
    double subtotal = 0, totalCgst = 0, totalSgst = 0;
    final billItemsData = (cart as List).map((ci) {
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

    // 3. Reuse existing open bill, or create new one
    final existingBills = await client
        .from('bill_master')
        .select('id, subtotal, cgst_amount, sgst_amount, total_amount')
        .eq('table_session_id', sessionId)
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
          })
          .select()
          .single();
      billId = bill['id'] as String;
    }

    // 4. Insert bill_items and retrieve IDs
    for (final item in billItemsData) {
      item['bill_id'] = billId;
    }
    final insertedItems = await client
        .from('bill_item')
        .insert(billItemsData)
        .select('id, item_id, variant_id');

    // 5. Create kot_master
    final kotNumber = await _generateKotNumber(companyId);
    final kot = await client
        .from('kot_master')
        .insert({
          'company_id': companyId,
          'bill_id': billId,
          'table_session_id': sessionId,
          'kot_number': kotNumber,
          'status': 'pending',
          'created_by': openedBy,
        })
        .select()
        .single();
    final kotId = kot['id'] as String;

    // 6. Create kot_items linked to bill_items
    final cartList = cart as List;
    final kotItems = (insertedItems as List).map((bi) {
      final idx = cartList.indexWhere((ci) {
        final c = ci as dynamic;
        return c.item.id == bi['item_id'] && c.variant?.id == bi['variant_id'];
      });
      final cartItem = idx >= 0 ? cartList[idx] as dynamic : null;
      return {
        'kot_id': kotId,
        'bill_item_id': bi['id'],
        'qty': cartItem != null ? (cartItem.qty as num).toDouble() : 1.0,
        'notes': cartItem != null ? cartItem.notes : null,
        'status': 'pending',
      };
    }).toList();
    await client.from('kot_item').insert(kotItems);
  }

  static Future<List<Map<String, dynamic>>> getActiveKots(
    String companyId,
  ) async {
    final res = await client
        .from('kot_master')
        .select(
          '*, table_session(table_master(table_number)), '
          'kot_item(*, bill_item(item_name_snapshot))',
        )
        .eq('company_id', companyId)
        .not('status', 'in', '(done,cancelled)')
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
}
