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
  final bool isLogin;
  final DateTime? lastLogin;
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
    this.isLogin = false,
    this.lastLogin,
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
    role: json['user_role'] as String? ?? 'cashier',
    fullName: json['user_name'] as String? ?? '',
    employeeCode: json['employee_code'] as String? ?? '',
    username: json['username'] as String?,
    phone: json['mob_number'] as String?,
    email: json['user_email'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    isActive: json['user_active'] as bool? ?? true,
    isLogin: json['is_login'] as bool? ?? false,
    lastLogin: json['last_login'] != null
        ? DateTime.parse(json['last_login'] as String)
        : null,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'user_role': role.toLowerCase(),
    'user_name': fullName,
    'employee_code': employeeCode,
    'username': username,
    'mob_number': phone,
    'user_email': email,
    'avatar_url': avatarUrl,
    'user_active': isActive,
    'is_login': isLogin,
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
  final String? hsnCode;
  final double gstRate;
  final double cgstRate;
  final double sgstRate;
  final double igstRate;

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
    this.hsnCode,
    this.gstRate = 0,
    this.cgstRate = 0,
    this.sgstRate = 0,
    this.igstRate = 0,
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
    hsnCode: json['company_hsn'] != null
        ? json['company_hsn']['hsn_code'] as String?
        : null,
    gstRate: json['company_hsn'] != null
        ? (json['company_hsn']['gst_rate'] as num?)?.toDouble() ?? 0
        : 0,
    cgstRate: json['company_hsn'] != null
        ? (json['company_hsn']['cgst_rate'] as num?)?.toDouble() ?? 0
        : 0,
    sgstRate: json['company_hsn'] != null
        ? (json['company_hsn']['sgst_rate'] as num?)?.toDouble() ?? 0
        : 0,
    igstRate: json['company_hsn'] != null
        ? (json['company_hsn']['igst_rate'] as num?)?.toDouble() ?? 0
        : 0,
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
  final String? hsnCode;
  final double gstRate;
  final double cgstRate;
  final double sgstRate;
  final double igstRate;

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
    this.hsnCode,
    this.gstRate = 0,
    this.cgstRate = 0,
    this.sgstRate = 0,
    this.igstRate = 0,
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
    hsnCode: json['company_hsn'] != null
        ? json['company_hsn']['hsn_code'] as String?
        : null,
    gstRate: json['company_hsn'] != null
        ? (json['company_hsn']['gst_rate'] as num?)?.toDouble() ?? 0
        : 0,
    cgstRate: json['company_hsn'] != null
        ? (json['company_hsn']['cgst_rate'] as num?)?.toDouble() ?? 0
        : 0,
    sgstRate: json['company_hsn'] != null
        ? (json['company_hsn']['sgst_rate'] as num?)?.toDouble() ?? 0
        : 0,
    igstRate: json['company_hsn'] != null
        ? (json['company_hsn']['igst_rate'] as num?)?.toDouble() ?? 0
        : 0,
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
  final bool isOccupied;
  final double activeOrderTotal;

  CafeTable({
    required this.id,
    required this.companyId,
    required this.tableNumber,
    this.section,
    this.seatingCapacity = 2,
    this.isActive = true,
    this.isOccupied = false,
    this.activeOrderTotal = 0.0,
    this.activeSessionId,
    this.activeCoverCount = 0,
  });

  String get tableName => tableNumber;
  String get status => isOccupied ? 'OCCUPIED' : 'FREE';
  bool get isFree => !isOccupied;

  final String? activeSessionId;
  final int activeCoverCount;

  factory CafeTable.fromJson(Map<String, dynamic> json) => CafeTable(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    tableNumber: json['table_number'] as String,
    section: json['section'] as String?,
    seatingCapacity: json['seating_capacity'] as int? ?? 2,
    isActive: json['is_active'] as bool? ?? true,
    isOccupied: json['is_occupied'] as bool? ?? false,
    activeOrderTotal: (json['active_order_total'] as num?)?.toDouble() ?? 0.0,
    activeSessionId: json['active_session_id'] as String?,
    activeCoverCount: json['active_cover_count'] as int? ?? 0,
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
  final String? billNumber;
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  final double totalAmount;
  final String paymentMode;
  final bool isVoided;
  final String? tableName;
  final int? coverNumber;
  final String? coverLabel;
  final List<BillItem> items;
  final DateTime? createdAt;

  Bill({
    required this.id,
    required this.companyId,
    this.orderId,
    this.billNumber,
    this.tableName,
    this.coverNumber,
    this.coverLabel,
    required this.subtotal,
    this.taxAmount = 0,
    this.discountAmount = 0,
    required this.totalAmount,
    this.paymentMode = 'CASH',
    this.isVoided = false,
    this.items = const [],
    this.createdAt,
  });

  String get coverDisplayName {
    if (coverNumber == null) return '';
    if (coverLabel != null && coverLabel!.isNotEmpty) return coverLabel!;
    return 'Cover $coverNumber';
  }

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    orderId: json['order_id'] as String?,
    billNumber: json['bill_number']?.toString(),
    subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
    discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
    totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
    paymentMode: json['payment_mode'] as String? ?? 'CASH',
    tableName:
        json['table_session'] != null &&
                json['table_session']['table_master'] != null
            ? json['table_session']['table_master']['table_number']
                ?.toString()
            : null,
    coverNumber: json['table_cover'] != null
        ? json['table_cover']['cover_number'] as int?
        : null,
    coverLabel: json['table_cover'] != null
        ? json['table_cover']['label'] as String?
        : null,
    isVoided: json['is_voided'] as bool? ?? false,
    items:
        (json['bill_item'] as List<dynamic>?)
            ?.map((e) => BillItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    createdAt: json['bill_date'] != null
        ? DateTime.parse(json['bill_date'] as String)
        : null,
  );
}

/// Bill line item (snapshot of item at time of billing)
class BillItem {
  final String id;
  final String billId;
  final String itemId;
  final String? itemName;
  final double qty;
  final double rate;
  final double taxPercentage;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;

  BillItem({
    required this.id,
    required this.billId,
    required this.itemId,
    this.itemName,
    required this.qty,
    required this.rate,
    this.taxPercentage = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
  });

  double get total => rate * qty;
  double get taxAmount => total * (taxPercentage / 100);

  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
    id: json['id'] as String,
    billId: json['bill_id'] as String,
    itemId: json['item_id'] as String,
    itemName: json['item_name_snapshot'] as String?,
    qty: (json['qty'] as num?)?.toDouble() ?? 1.0,
    rate: (json['rate_snapshot'] as num?)?.toDouble() ?? 0,
    taxPercentage: (json['gst_rate_snapshot'] as num?)?.toDouble() ?? 0,
    cgstAmount: (json['cgst_amount'] as num?)?.toDouble() ?? 0,
    sgstAmount: (json['sgst_amount'] as num?)?.toDouble() ?? 0,
    igstAmount: (json['igst_amount'] as num?)?.toDouble() ?? 0,
  );
}

// ─── KOT ─────────────────────────────────────────────────

class KotStatus {
  static const String pending   = 'pending';
  static const String inProgress = 'in_progress';
  static const String done      = 'done';
  static const String cancelled = 'cancelled';
}

class KotItemStatus {
  static const String pending    = 'pending';
  static const String inProgress = 'in_progress';
  static const String done       = 'done';
  static const String voided     = 'void';
}

class KotMaster {
  final String id;
  final String companyId;
  final String billId;
  final String? tableSessionId;
  final String? tableName;
  final String? coverId;
  final int? coverNumber;
  final String kotNumber;
  String status;
  final String createdBy;
  final bool isPrinted;
  final List<KotItem> items;
  final DateTime? createdAt;

  KotMaster({
    required this.id,
    required this.companyId,
    required this.billId,
    this.tableSessionId,
    this.tableName,
    this.coverId,
    this.coverNumber,
    required this.kotNumber,
    this.status = KotStatus.pending,
    required this.createdBy,
    this.isPrinted = false,
    this.items = const [],
    this.createdAt,
  });

  bool get allDone =>
      items.isNotEmpty &&
      items.every((i) => i.status == KotItemStatus.done || i.status == KotItemStatus.voided);

  factory KotMaster.fromJson(Map<String, dynamic> json) => KotMaster(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    billId: json['bill_id'] as String,
    tableSessionId: json['table_session_id'] as String?,
    tableName: json['table_session'] != null &&
            json['table_session']['table_master'] != null
        ? json['table_session']['table_master']['table_number'] as String?
        : null,
    coverId: json['cover_id'] as String?,
    coverNumber: json['table_cover'] != null
        ? json['table_cover']['cover_number'] as int?
        : null,
    kotNumber: json['kot_number'] as String? ?? '',
    status: json['status'] as String? ?? KotStatus.pending,
    createdBy: json['created_by'] as String? ?? '',
    isPrinted: json['is_printed'] as bool? ?? false,
    items: (json['kot_item'] as List<dynamic>?)
            ?.map((e) => KotItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );
}

class KotItem {
  final String id;
  final String kotId;
  final String billItemId;
  final String itemNameSnapshot; // from bill_item join
  final int qty;
  final String? notes;
  String status;

  KotItem({
    required this.id,
    required this.kotId,
    required this.billItemId,
    required this.itemNameSnapshot,
    this.qty = 1,
    this.notes,
    this.status = KotItemStatus.pending,
  });

  factory KotItem.fromJson(Map<String, dynamic> json) => KotItem(
    id: json['id'] as String,
    kotId: json['kot_id'] as String,
    billItemId: json['bill_item_id'] as String,
    itemNameSnapshot: json['bill_item'] != null
        ? (json['bill_item']['item_name_snapshot'] as String? ?? '')
        : '',
    qty: (json['qty'] as num?)?.toInt() ?? 1,
    notes: json['notes'] as String?,
    status: json['status'] as String? ?? KotItemStatus.pending,
  );
}

/// Represents one customer group at a table (a "cover")
class TableCover {
  final String id;
  final String tableSessionId;
  final String companyId;
  final int coverNumber;
  final String? label;
  final int pax;
  final String status; // 'active' | 'billed' | 'merged'
  final DateTime? createdAt;

  TableCover({
    required this.id,
    required this.tableSessionId,
    required this.companyId,
    required this.coverNumber,
    this.label,
    this.pax = 1,
    this.status = 'active',
    this.createdAt,
  });

  String get displayName =>
      (label != null && label!.isNotEmpty) ? label! : 'Cover $coverNumber';
  bool get isActive => status == 'active';
  bool get isBilled => status == 'billed';

  factory TableCover.fromJson(Map<String, dynamic> json) => TableCover(
    id: json['id'] as String,
    tableSessionId: json['table_session_id'] as String,
    companyId: json['company_id'] as String,
    coverNumber: json['cover_number'] as int,
    label: json['label'] as String?,
    pax: json['pax'] as int? ?? 1,
    status: json['status'] as String? ?? 'active',
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'table_session_id': tableSessionId,
    'company_id': companyId,
    'cover_number': coverNumber,
    'label': label,
    'pax': pax,
    'status': status,
  };
}

/// Cart item for the POS (local state before billing)
class CartItem {
  final Item item;
  final ItemVariant? variant;
  int qty;
  String? notes;

  CartItem({required this.item, this.variant, this.qty = 1, this.notes});

  double get total => rate * qty;
  String get itemName =>
      (variant != null && variant!.variantName.toLowerCase() != 'default')
      ? variant!.variantName
      : item.itemName;
  double get rate => variant?.baseRate ?? item.baseRate;
}
