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
        .from('user_master')
        .select()
        .or('username.ilike.$input,email.ilike.$input')
        .eq('password_hash', password)
        .eq('is_active', true)
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
        .from('user_master')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return res;
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

  // ─── ITEMS ─────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getItemGroups(
    String companyId,
  ) async {
    final res = await client
        .from('item_group')
        .select('*, item_master(*)')
        .eq('company_id', companyId)
        .order('group_name');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> getAllItems(
    String companyId,
  ) async {
    final res = await client
        .from('item_master')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('item_name');
    return List<Map<String, dynamic>>.from(res);
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
    String orderType = 'DINING',
  }) async {
    final res = await client
        .from('table_session')
        .insert({
          'company_id': companyId,
          'table_id': tableId,
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

  // ─── BILLS (BILL_MASTER) ─────────────────────────────
  static Future<Map<String, dynamic>> createBill({
    required String companyId,
    String? tableSessionId,
    required double subtotal,
    double taxAmount = 0,
    double discountAmount = 0,
    required double totalAmount,
    String paymentMode = 'cash',
    required List<Map<String, dynamic>> billItems,
  }) async {
    // Create bill
    final bill = await client
        .from('bill_master')
        .insert({
          'company_id': companyId,
          'table_session_id': tableSessionId,
          'subtotal': subtotal,
          'taxable_amount': subtotal,
          'discount_amount': discountAmount,
          'total_amount': totalAmount,
          'payment_mode': paymentMode,
          'bill_type': 'dine_in',
          'bill_number': 'AUTO', // Should be generated
        })
        .select()
        .single();

    // Insert bill items
    final billId = bill['id'];
    final items = billItems
        .map(
          (bi) => {
            'bill_id': billId,
            'item_id': bi['item_id'],
            'qty': bi['qty'],
            'rate_snapshot': bi['rate'],
            'item_name_snapshot': bi['item_name'] ?? '',
            'gross_amount': bi['rate'] * bi['qty'],
            'net_amount': bi['rate'] * bi['qty'],
          },
        )
        .toList();
    await client.from('bill_item').insert(items);

    return bill;
  }

  static Future<List<Map<String, dynamic>>> getBills(String companyId) async {
    final res = await client
        .from('bills')
        .select('*, bill_items(*, items(item_name))')
        .eq('company_id', companyId)
        .order('created_at', ascending: false);
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
    await client.from('"USER_PREFERENCE"').upsert({
      'user_id': userId,
      'ui_theme_type': theme,
    });
  }

  // ─── PRINT SETTINGS ───────────────────────────────────
  static Future<Map<String, dynamic>?> getPrintSettings(
    String companyId,
  ) async {
    return await client
        .from('"COMPANY_PRINT_CONFIG"')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
  }
}
