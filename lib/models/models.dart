/// Data model for a Company/Café
// 1. COMPANY_MASTER
class Company {
  final String id;
  final String companyCode;
  final String companyName;
  final bool hasGst;
  final bool hasTableManagement;
  final bool isActive;
  final DateTime? createdAt;

  Company({
    required this.id,
    required this.companyCode,
    required this.companyName,
    this.hasGst = false,
    this.hasTableManagement = true,
    this.isActive = true,
    this.createdAt,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
    id: json['id'] as String,
    companyCode: json['company_code'] as String,
    companyName: json['company_name'] as String,
    hasGst: json['has_gst'] as bool? ?? false,
    hasTableManagement: json['has_table_management'] as bool? ?? true,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'company_code': companyCode,
    'company_name': companyName,
    'has_gst': hasGst,
    'has_table_management': hasTableManagement,
    'is_active': isActive,
  };
}

/// User profile linked to Supabase Auth
// 2. USER_MASTER
class UserProfile {
  final String id;
  final String companyId;
  final String role;
  final String fullName;
  final String? username;
  final String? phone;
  final bool isActive;
  final DateTime? createdAt;

  UserProfile({
    required this.id,
    required this.companyId,
    required this.role,
    required this.fullName,
    this.username,
    this.phone,
    this.isActive = true,
    this.createdAt,
  });

  bool get isAdmin => role.toUpperCase() == 'ADMIN';
  bool get isManager => role.toUpperCase() == 'MANAGER';
  bool get isCashier => role.toUpperCase() == 'CASHIER';
  bool get isWaiter => role.toUpperCase() == 'WAITER';
  bool get isKitchen => role.toUpperCase() == 'KITCHEN';

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    role: json['role'] as String? ?? 'CASHIER',
    fullName: json['full_name'] as String? ?? '',
    username: json['username'] as String?,
    phone: json['phone'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );
}

/// Item group model
class ItemGroup {
  final String id;
  final String companyId;
  final String groupName;
  final String displayType; // DIRECT or GROUPED
  final bool showSeparateItems;
  final List<Item> items;

  ItemGroup({
    required this.id,
    required this.companyId,
    required this.groupName,
    this.displayType = 'DIRECT',
    this.showSeparateItems = false,
    this.items = const [],
  });

  bool get isDirect => displayType == 'DIRECT';
  bool get isGrouped => displayType == 'GROUPED';

  factory ItemGroup.fromJson(Map<String, dynamic> json) => ItemGroup(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    groupName: json['group_name'] as String,
    displayType: json['display_type'] as String? ?? 'DIRECT',
    showSeparateItems: json['show_separate_items'] as bool? ?? false,
    items: (json['items'] as List<dynamic>?)
        ?.map((e) => Item.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'company_id': companyId,
    'group_name': groupName,
    'display_type': displayType,
    'show_separate_items': showSeparateItems,
  };
}

/// Menu item model
// 3. ITEM_MASTER
class Item {
  final String id;
  final String companyId;
  final String? itemGroupId;
  final String itemName;
  final double baseRate;
  final bool isTaxable;
  final String? hsnId;
  final bool isActive;
  final DateTime? createdAt;

  Item({
    required this.id,
    required this.companyId,
    this.itemGroupId,
    required this.itemName,
    required this.baseRate,
    this.isTaxable = false,
    this.hsnId,
    this.isActive = true,
    this.createdAt,
  });

  // Compatibility getters
  double get rate => baseRate;
  bool get taxable => isTaxable;
  bool get isAvailable => isActive;

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    itemGroupId: json['item_group_id'] as String?,
    itemName: json['item_name'] as String,
    baseRate: (json['base_rate'] as num).toDouble(),
    isTaxable: json['is_taxable'] as bool? ?? false,
    hsnId: json['hsn_id'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'company_id': companyId,
    'item_group_id': itemGroupId,
    'item_name': itemName,
    'base_rate': baseRate,
    'is_taxable': isTaxable,
    'hsn_id': hsnId,
    'is_active': isActive,
  };
}

/// Cafe table model
// 4. TABLE_MASTER
class CafeTable {
  final String id;
  final String companyId;
  final String tableNumber;
  final String? section;
  final int seatingCapacity;
  final bool isActive;

  CafeTable({
    required this.id,
    required this.companyId,
    required this.tableNumber,
    this.section,
    this.seatingCapacity = 2,
    this.isActive = true,
  });

  // Compatibility getters
  String get tableName => tableNumber;
  String get status => 'FREE'; // Placeholder: V2 uses TABLE_SESSION to determine this
  bool get isFree => true;     // Placeholder
  bool get isOccupied => false; // Placeholder

  factory CafeTable.fromJson(Map<String, dynamic> json) => CafeTable(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    tableNumber: json['table_number'] as String,
    section: json['section'] as String?,
    seatingCapacity: json['seating_capacity'] as int? ?? 2,
    isActive: json['is_active'] as bool? ?? true,
  );
}

/// Order model
class Order {
  final String id;
  final String companyId;
  final String? tableId;
  final String orderType;
  final String status;
  final List<OrderItem> items;
  final DateTime? createdAt;

  Order({
    required this.id,
    required this.companyId,
    this.tableId,
    this.orderType = 'DINE_IN',
    this.status = 'OPEN',
    this.items = const [],
    this.createdAt,
  });

  double get subtotal => items.fold(0, (sum, oi) => sum + (oi.rate * oi.qty));

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    tableId: json['table_id'] as String?,
    orderType: json['order_type'] as String? ?? 'DINE_IN',
    status: json['status'] as String? ?? 'OPEN',
    items: (json['order_items'] as List<dynamic>?)
        ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );
}

/// Order item (line item inside an order)
class OrderItem {
  final String id;
  final String orderId;
  final String itemId;
  final String itemName;
  final double rate;
  int qty;
  final String? notes;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.itemId,
    required this.itemName,
    required this.rate,
    this.qty = 1,
    this.notes,
  });

  double get total => rate * qty;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: json['id'] as String,
    orderId: json['order_id'] as String,
    itemId: json['item_id'] as String,
    itemName: json['item_name'] ?? (json['items'] != null ? json['items']['item_name'] : '') as String,
    rate: (json['rate'] ?? (json['items'] != null ? json['items']['rate'] : 0) as num).toDouble(),
    qty: json['qty'] as int? ?? 1,
    notes: json['notes'] as String?,
  );
}

/// Bill model (immutable after finalization)
class Bill {
  final String id;
  final String companyId;
  final String? orderId;
  final int? billNumber;
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  final double totalAmount;
  final String paymentMode;
  final bool isVoided;
  final List<BillItem> items;
  final DateTime? createdAt;

  Bill({
    required this.id,
    required this.companyId,
    this.orderId,
    this.billNumber,
    required this.subtotal,
    this.taxAmount = 0,
    this.discountAmount = 0,
    required this.totalAmount,
    this.paymentMode = 'CASH',
    this.isVoided = false,
    this.items = const [],
    this.createdAt,
  });

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    orderId: json['order_id'] as String?,
    billNumber: json['bill_number'] as int?,
    subtotal: (json['subtotal'] as num).toDouble(),
    taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
    discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
    totalAmount: (json['total_amount'] as num).toDouble(),
    paymentMode: json['payment_mode'] as String? ?? 'CASH',
    isVoided: json['is_voided'] as bool? ?? false,
    items: (json['bill_items'] as List<dynamic>?)
        ?.map((e) => BillItem.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );
}

/// Bill line item (snapshot of item at time of billing)
class BillItem {
  final String id;
  final String billId;
  final String itemId;
  final String? itemName;
  final int qty;
  final double rate;
  final double taxPercentage;

  BillItem({
    required this.id,
    required this.billId,
    required this.itemId,
    this.itemName,
    required this.qty,
    required this.rate,
    this.taxPercentage = 0,
  });

  double get total => rate * qty;
  double get taxAmount => total * (taxPercentage / 100);

  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
    id: json['id'] as String,
    billId: json['bill_id'] as String,
    itemId: json['item_id'] as String,
    itemName: json['item_name'] ?? (json['items'] != null ? json['items']['item_name'] : null) as String?,
    qty: json['qty'] as int,
    rate: (json['rate'] as num).toDouble(),
    taxPercentage: (json['tax_percentage'] as num?)?.toDouble() ?? 0,
  );
}

/// Cart item for the POS (local state before billing)
class CartItem {
  final Item item;
  int qty;
  String? notes;

  CartItem({
    required this.item,
    this.qty = 1,
    this.notes,
  });

  double get total => item.baseRate * qty;
  String get itemName => item.itemName;
  double get rate => item.baseRate;
}
