/// Data model for a Company/Café
// 1. COMPANY_MASTER
class Company {
  final String id;
  final String companyCode;
  final String companyName;
  final bool hasGst;
  final bool hasTableManagement;
  final bool hasItemVariants;
  final bool isActive;
  final DateTime? createdAt;

  Company({
    required this.id,
    required this.companyCode,
    required this.companyName,
    this.hasGst = false,
    this.hasTableManagement = true,
    this.hasItemVariants = false,
    this.isActive = true,
    this.createdAt,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
    id: json['id'] as String,
    companyCode: json['company_code'] as String,
    companyName: json['company_name'] as String,
    hasGst: json['has_gst'] as bool? ?? false,
    hasTableManagement: json['has_table_management'] as bool? ?? true,
    hasItemVariants: json['has_item_variants'] as bool? ?? false,
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
    'has_item_variants': hasItemVariants,
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
  final String employeeCode;
  final String? username;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final bool isActive;
  final DateTime? createdAt;

  UserProfile({
    required this.id,
    required this.companyId,
    required this.role,
    required this.fullName,
    required this.employeeCode,
    this.username,
    this.phone,
    this.email,
    this.avatarUrl,
    this.isActive = true,
    this.createdAt,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isManager => role.toLowerCase() == 'manager';
  bool get isCashier => role.toLowerCase() == 'cashier';
  bool get isWaiter => role.toLowerCase() == 'waiter';
  bool get isKitchen => role.toLowerCase() == 'kitchen';

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    role: json['role'] as String? ?? 'cashier',
    fullName: json['full_name'] as String? ?? '',
    employeeCode: json['employee_code'] as String? ?? '',
    username: json['username'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'role': role.toLowerCase(),
    'full_name': fullName,
    'employee_code': employeeCode,
    'username': username,
    'phone': phone,
    'email': email,
    'avatar_url': avatarUrl,
    'is_active': isActive,
  };
}

/// Permissions for a User
// 2b. USER_PERMISSION
class UserPermission {
  final String userId;
  final bool canViewDashboard;
  final bool canCreateBill;
  final bool canEditBill;
  final bool canCancelBill;
  final bool canApplyDiscount;
  final bool canManageItems;
  final bool canManageTables;
  final bool canViewReports;
  final bool canManageUsers;
  final bool canManageSettings;
  final bool canVoidItems;

  UserPermission({
    required this.userId,
    this.canViewDashboard = false,
    this.canCreateBill = true,
    this.canEditBill = false,
    this.canCancelBill = false,
    this.canApplyDiscount = false,
    this.canManageItems = false,
    this.canManageTables = false,
    this.canViewReports = false,
    this.canManageUsers = false,
    this.canManageSettings = false,
    this.canVoidItems = false,
  });

  factory UserPermission.fromJson(Map<String, dynamic> json) => UserPermission(
    userId: json['user_id'] as String,
    canViewDashboard: json['can_view_dashboard'] as bool? ?? false,
    canCreateBill: json['can_create_bill'] as bool? ?? true,
    canEditBill: json['can_edit_bill'] as bool? ?? false,
    canCancelBill: json['can_cancel_bill'] as bool? ?? false,
    canApplyDiscount: json['can_apply_discount'] as bool? ?? false,
    canManageItems: json['can_manage_items'] as bool? ?? false,
    canManageTables: json['can_manage_tables'] as bool? ?? false,
    canViewReports: json['can_view_reports'] as bool? ?? false,
    canManageUsers: json['can_manage_users'] as bool? ?? false,
    canManageSettings: json['can_manage_settings'] as bool? ?? false,
    canVoidItems: json['can_void_items'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'can_view_dashboard': canViewDashboard,
    'can_create_bill': canCreateBill,
    'can_edit_bill': canEditBill,
    'can_cancel_bill': canCancelBill,
    'can_apply_discount': canApplyDiscount,
    'can_manage_items': canManageItems,
    'can_manage_tables': canManageTables,
    'can_view_reports': canViewReports,
    'can_manage_users': canManageUsers,
    'can_manage_settings': canManageSettings,
    'can_void_items': canVoidItems,
  };
}

/// Menu item model
// 4. ITEM_MASTER
class Item {
  final String id;
  final String companyId;
  final String? hsnId;
  final String itemCode;
  final String itemName;
  final String? description;
  final String unitOfMeasure;
  final double baseRate;
  final bool hasVariants;
  final bool isTaxable;
  final bool isActive;
  final String? imageUrl;
  final int displayOrder;
  final double inclusiveRate;
  final bool isRateInclusive;
  final String? sectionLabel;
  final String? colorTag;
  final String foodType; // 'veg', 'egg', 'non-veg'
  final DateTime? createdAt;
  final List<ItemVariant> variants;

  Item({
    required this.id,
    required this.companyId,
    this.hsnId,
    required this.itemCode,
    required this.itemName,
    this.description,
    this.unitOfMeasure = 'PCS',
    required this.baseRate,
    this.hasVariants = false,
    this.isTaxable = true,
    this.isActive = true,
    this.imageUrl,
    this.displayOrder = 0,
    this.inclusiveRate = 0,
    this.isRateInclusive = false,
    this.sectionLabel,
    this.colorTag,
    this.foodType = 'veg',
    this.createdAt,
    this.variants = const [],
  });

  // Compatibility getters
  double get rate => baseRate;
  bool get taxable => isTaxable;
  bool get isAvailable => isActive;

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    hsnId: json['hsn_id'] as String?,
    itemCode: json['item_code'] as String? ?? '',
    itemName: json['item_name'] as String,
    description: json['description'] as String?,
    unitOfMeasure: json['unit_of_measure'] as String? ?? 'PCS',
    baseRate: (json['base_rate'] as num?)?.toDouble() ?? 0,
    hasVariants: json['has_variants'] as bool? ?? false,
    isTaxable: json['is_taxable'] as bool? ?? true,
    isActive: json['is_active'] as bool? ?? true,
    imageUrl: json['image_url'] as String?,
    displayOrder: json['display_order'] as int? ?? 0,
    inclusiveRate: (json['inclusive_rate'] as num?)?.toDouble() ?? 0,
    isRateInclusive: json['is_rate_inclusive'] as bool? ?? false,
    sectionLabel: json['section_label'] as String?,
    colorTag: json['color_tag'] as String?,
    foodType: json['food_type'] as String? ?? 'veg',
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
    variants:
        (json['item_variant'] as List<dynamic>?)
            ?.map((e) => ItemVariant.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'hsn_id': hsnId,
    'item_code': itemCode,
    'item_name': itemName,
    'description': description,
    'unit_of_measure': unitOfMeasure,
    'base_rate': baseRate,
    'has_variants': hasVariants,
    'is_taxable': isTaxable,
    'is_active': isActive,
    'image_url': imageUrl,
    'display_order': displayOrder,
    'inclusive_rate': inclusiveRate,
    'is_rate_inclusive': isRateInclusive,
    'section_label': sectionLabel,
    'color_tag': colorTag,
    'food_type': foodType,
  };
}

/// Item variant model
class ItemVariant {
  final String id;
  final String itemId;
  final String variantName;
  final double baseRate;
  final bool isActive;
  final String? imageUrl;
  final String? hsnId;
  final double inclusiveRate;
  final bool isRateInclusive;
  final String? description;
  final int displayOrder;
  final bool isAvailable;

  ItemVariant({
    required this.id,
    required this.itemId,
    required this.variantName,
    required this.baseRate,
    this.isActive = true,
    this.imageUrl,
    this.hsnId,
    this.inclusiveRate = 0,
    this.isRateInclusive = false,
    this.description,
    this.displayOrder = 0,
    this.isAvailable = true,
  });

  double get rate => baseRate;

  factory ItemVariant.fromJson(Map<String, dynamic> json) => ItemVariant(
    id: json['id'] as String,
    itemId: json['item_id'] as String,
    variantName: json['variant_name'] as String,
    baseRate: (json['base_rate'] as num?)?.toDouble() ?? 0,
    isActive: json['is_active'] as bool? ?? true,
    imageUrl: json['image_url'] as String?,
    hsnId: json['hsn_id'] as String?,
    inclusiveRate: (json['inclusive_rate'] as num?)?.toDouble() ?? 0,
    isRateInclusive: json['is_rate_inclusive'] as bool? ?? false,
    description: json['description'] as String?,
    displayOrder: json['display_order'] as int? ?? 0,
    isAvailable: json['is_available'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_id': itemId,
    'variant_name': variantName,
    'base_rate': baseRate,
    'is_active': isActive,
    'image_url': imageUrl,
    'hsn_id': hsnId,
    'inclusive_rate': inclusiveRate,
    'is_rate_inclusive': isRateInclusive,
    'description': description,
    'display_order': displayOrder,
    'is_available': isAvailable,
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
  String get status =>
      'FREE'; // Placeholder: V2 uses TABLE_SESSION to determine this
  bool get isFree => true; // Placeholder
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
    items:
        (json['order_items'] as List<dynamic>?)
            ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
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
    itemName:
        json['item_name'] ??
        (json['items'] != null ? json['items']['item_name'] : '') as String,
    rate:
        (json['rate'] ??
                (json['items'] != null ? json['items']['rate'] : 0) as num)
            .toDouble(),
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
    items:
        (json['bill_items'] as List<dynamic>?)
            ?.map((e) => BillItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
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
    itemName:
        json['item_name'] ??
        (json['items'] != null ? json['items']['item_name'] : null) as String?,
    qty: json['qty'] as int,
    rate: (json['rate'] as num).toDouble(),
    taxPercentage: (json['tax_percentage'] as num?)?.toDouble() ?? 0,
  );
}

/// Cart item for the POS (local state before billing)
class CartItem {
  final Item item;
  final ItemVariant? variant;
  int qty;
  String? notes;

  CartItem({required this.item, this.variant, this.qty = 1, this.notes});

  double get total => rate * qty;
  String get itemName => variant != null ? variant!.variantName : item.itemName;
  double get rate => variant?.baseRate ?? item.baseRate;
}
