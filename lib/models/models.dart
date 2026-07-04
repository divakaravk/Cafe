/// Data model for a Company/Café
// 1. COMPANY_MASTER
class Company {
  final String id;
  final String companyCode;
  final String companyName;
  final bool hasGst;
  final bool hasTableManagement;
  final bool hasItemVariants;
  final bool showItemImages;
  final bool isActive;
  final DateTime? createdAt;

  Company({
    required this.id,
    required this.companyCode,
    required this.companyName,
    this.hasGst = false,
    this.hasTableManagement = true,
    this.hasItemVariants = false,
    this.showItemImages = true,
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
    showItemImages: json['show_item_images'] as bool? ?? true,
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
    'show_item_images': showItemImages,
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
  /// Platform/app owner — not tied to any company. Approves new-company
  /// registrations from a dedicated dashboard.
  bool get isOwner => role.toLowerCase() == 'owner';
  bool get isManager => role.toLowerCase() == 'manager';
  bool get isCashier => role.toLowerCase() == 'cashier';
  bool get isWaiter => role.toLowerCase() == 'waiter';
  bool get isKitchen => role.toLowerCase() == 'kitchen';

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    // The app owner has no company, so this can be null in the DB.
    companyId: json['company_id'] as String? ?? '',
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
  final bool canManageStock; // Inventory / Stock module (future-ready)

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
    this.canManageStock = false,
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
    canManageStock: json['can_manage_stock'] as bool? ?? false,
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
    'can_manage_stock': canManageStock,
  };

  /// Full access — used for admins, who bypass per-module gating.
  factory UserPermission.all(String userId) => UserPermission(
    userId: userId,
    canViewDashboard: true,
    canCreateBill: true,
    canEditBill: true,
    canCancelBill: true,
    canApplyDiscount: true,
    canManageItems: true,
    canManageTables: true,
    canViewReports: true,
    canManageUsers: true,
    canManageSettings: true,
    canVoidItems: true,
    canManageStock: true,
  );

  /// Sensible default access for a role, used when no explicit permission row
  /// exists yet. Mirrors how Petpooja seeds module access per staff role.
  factory UserPermission.forRole(String userId, String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return UserPermission.all(userId);
      case 'manager':
        return UserPermission(
          userId: userId,
          canViewDashboard: true,
          canCreateBill: true,
          canEditBill: true,
          canCancelBill: true,
          canApplyDiscount: true,
          canManageItems: true,
          canManageTables: true,
          canViewReports: true,
          canVoidItems: true,
          canManageStock: true,
        );
      case 'cashier':
        return UserPermission(
          userId: userId,
          canCreateBill: true,
          canApplyDiscount: true,
          canManageTables: true,
          canViewReports: true,
        );
      case 'waiter':
        return UserPermission(
          userId: userId,
          canCreateBill: true,
          canManageTables: true,
        );
      case 'kitchen':
        return UserPermission(
          userId: userId,
          canCreateBill: false,
          canManageTables: true,
        );
      default:
        return UserPermission(userId: userId, canCreateBill: true);
    }
  }
}

/// Item Group model (table: item_master).
///
/// In the enterprise model an Item Group (e.g. "Dosa", "Rice") is never sold
/// directly — only its [variants] (the actual selling items) can be billed.
/// The group carries a [baseRate] which variants inherit when they do not
/// override it. See [effectiveRateFor] for the single source of pricing truth.
// 4. ITEM_MASTER  (= ITEM GROUP)
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
  final String? defaultVariantId;
  final DateTime? createdAt;
  final List<ItemVariant> variants;
  final String? hsnCode;
  final double gstRate;
  final double cgstRate;
  final double sgstRate;
  final double igstRate;

  // ─── Future-ready columns (mapped, not yet surfaced in UI) ─────────────
  final String? shortName;
  final String? localName;
  final String? searchKeywords;
  final String? printName;
  final String? kitchenName;
  final String? badge;
  final bool isFeatured;
  final bool isRecommended;
  final int? preparationTime;
  final String? barcode;
  final String? sku;
  final bool stockEnabled;
  final bool unlimitedStock;
  final double packingCharge;
  final double serviceCharge;
  final bool onlineVisible;
  final bool qrVisible;
  final bool selfOrderVisible;
  final bool dineInAvailable;
  final bool takeawayAvailable;
  final bool deliveryAvailable;
  final DateTime? updatedAt;
  final String? updatedBy;
  final int syncVersion;

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
    this.defaultVariantId,
    this.createdAt,
    this.variants = const [],
    this.hsnCode,
    this.gstRate = 0,
    this.cgstRate = 0,
    this.sgstRate = 0,
    this.igstRate = 0,
    this.shortName,
    this.localName,
    this.searchKeywords,
    this.printName,
    this.kitchenName,
    this.badge,
    this.isFeatured = false,
    this.isRecommended = false,
    this.preparationTime,
    this.barcode,
    this.sku,
    this.stockEnabled = false,
    this.unlimitedStock = true,
    this.packingCharge = 0,
    this.serviceCharge = 0,
    this.onlineVisible = true,
    this.qrVisible = true,
    this.selfOrderVisible = true,
    this.dineInAvailable = true,
    this.takeawayAvailable = true,
    this.deliveryAvailable = true,
    this.updatedAt,
    this.updatedBy,
    this.syncVersion = 0,
  });

  // Compatibility getters
  double get rate => baseRate;
  bool get taxable => isTaxable;
  bool get isAvailable => isActive;

  /// Selling items belonging to this group that are sellable in the POS:
  /// active AND available, sorted by display order then name.
  List<ItemVariant> get sellableVariants {
    final list = variants.where((v) => v.isActive && v.isAvailable).toList()
      ..sort((a, b) {
        final byOrder = a.displayOrder.compareTo(b.displayOrder);
        return byOrder != 0
            ? byOrder
            : a.variantName.toLowerCase().compareTo(b.variantName.toLowerCase());
      });
    return list;
  }

  /// The default selling item for this group (explicit flag → group pointer →
  /// first sellable variant → first variant). Never returns null when the
  /// group has at least one variant.
  ItemVariant? get defaultVariant {
    if (variants.isEmpty) return null;
    for (final v in variants) {
      if (v.isDefault) return v;
    }
    if (defaultVariantId != null) {
      for (final v in variants) {
        if (v.id == defaultVariantId) return v;
      }
    }
    final sellable = sellableVariants;
    return sellable.isNotEmpty ? sellable.first : variants.first;
  }

  /// SINGLE SOURCE OF PRICING TRUTH.
  /// A variant inherits the group [baseRate] when it has no override
  /// (override rate is null or 0); otherwise the variant rate wins.
  double effectiveRateFor(ItemVariant? variant) {
    if (variant == null) return baseRate;
    return variant.hasPriceOverride ? variant.baseRate : baseRate;
  }

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
    defaultVariantId: json['default_variant_id'] as String?,
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
    shortName: json['short_name'] as String?,
    localName: json['local_name'] as String?,
    searchKeywords: json['search_keywords'] as String?,
    printName: json['print_name'] as String?,
    kitchenName: json['kitchen_name'] as String?,
    badge: json['badge'] as String?,
    isFeatured: json['is_featured'] as bool? ?? false,
    isRecommended: json['is_recommended'] as bool? ?? false,
    preparationTime: json['preparation_time'] as int?,
    barcode: json['barcode'] as String?,
    sku: json['sku'] as String?,
    stockEnabled: json['stock_enabled'] as bool? ?? false,
    unlimitedStock: json['unlimited_stock'] as bool? ?? true,
    packingCharge: (json['packing_charge'] as num?)?.toDouble() ?? 0,
    serviceCharge: (json['service_charge'] as num?)?.toDouble() ?? 0,
    onlineVisible: json['online_visible'] as bool? ?? true,
    qrVisible: json['qr_visible'] as bool? ?? true,
    selfOrderVisible: json['self_order_visible'] as bool? ?? true,
    dineInAvailable: json['dine_in_available'] as bool? ?? true,
    takeawayAvailable: json['takeaway_available'] as bool? ?? true,
    deliveryAvailable: json['delivery_available'] as bool? ?? true,
    updatedAt: json['updated_at'] != null
        ? DateTime.tryParse(json['updated_at'] as String)
        : null,
    updatedBy: json['updated_by'] as String?,
    syncVersion: json['sync_version'] as int? ?? 0,
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
    'default_variant_id': defaultVariantId,
  };

  Item copyWith({
    String? id,
    String? companyId,
    String? hsnId,
    String? itemCode,
    String? itemName,
    String? description,
    String? unitOfMeasure,
    double? baseRate,
    bool? hasVariants,
    bool? isTaxable,
    bool? isActive,
    String? imageUrl,
    int? displayOrder,
    double? inclusiveRate,
    bool? isRateInclusive,
    String? sectionLabel,
    String? colorTag,
    String? foodType,
    String? defaultVariantId,
    DateTime? createdAt,
    List<ItemVariant>? variants,
    String? hsnCode,
    double? gstRate,
    double? cgstRate,
    double? sgstRate,
    double? igstRate,
  }) => Item(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    hsnId: hsnId ?? this.hsnId,
    itemCode: itemCode ?? this.itemCode,
    itemName: itemName ?? this.itemName,
    description: description ?? this.description,
    unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
    baseRate: baseRate ?? this.baseRate,
    hasVariants: hasVariants ?? this.hasVariants,
    isTaxable: isTaxable ?? this.isTaxable,
    isActive: isActive ?? this.isActive,
    imageUrl: imageUrl ?? this.imageUrl,
    displayOrder: displayOrder ?? this.displayOrder,
    inclusiveRate: inclusiveRate ?? this.inclusiveRate,
    isRateInclusive: isRateInclusive ?? this.isRateInclusive,
    sectionLabel: sectionLabel ?? this.sectionLabel,
    colorTag: colorTag ?? this.colorTag,
    foodType: foodType ?? this.foodType,
    defaultVariantId: defaultVariantId ?? this.defaultVariantId,
    createdAt: createdAt ?? this.createdAt,
    variants: variants ?? this.variants,
    hsnCode: hsnCode ?? this.hsnCode,
    gstRate: gstRate ?? this.gstRate,
    cgstRate: cgstRate ?? this.cgstRate,
    sgstRate: sgstRate ?? this.sgstRate,
    igstRate: igstRate ?? this.igstRate,
    shortName: shortName,
    localName: localName,
    searchKeywords: searchKeywords,
    printName: printName,
    kitchenName: kitchenName,
    badge: badge,
    isFeatured: isFeatured,
    isRecommended: isRecommended,
    preparationTime: preparationTime,
    barcode: barcode,
    sku: sku,
    stockEnabled: stockEnabled,
    unlimitedStock: unlimitedStock,
    packingCharge: packingCharge,
    serviceCharge: serviceCharge,
    onlineVisible: onlineVisible,
    qrVisible: qrVisible,
    selfOrderVisible: selfOrderVisible,
    dineInAvailable: dineInAvailable,
    takeawayAvailable: takeawayAvailable,
    deliveryAvailable: deliveryAvailable,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
    syncVersion: syncVersion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Item &&
          other.id == id &&
          other.itemName == itemName &&
          other.baseRate == baseRate &&
          other.isActive == isActive &&
          other.displayOrder == displayOrder &&
          other.updatedAt == updatedAt &&
          other.syncVersion == syncVersion &&
          other.variants.length == variants.length);

  @override
  int get hashCode => Object.hash(id, itemName, baseRate, isActive,
      displayOrder, updatedAt, syncVersion, variants.length);
}

/// Selling item belonging to an [Item] group (table: item_variant).
///
/// This is the only sellable entity. [baseRate] is an OPTIONAL override of the
/// group rate — a value of 0 means "inherit the group base rate" (resolved by
/// [Item.effectiveRateFor]).
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
  final bool isDefault;
  final String foodType; // 'veg', 'egg', 'non-veg' — per selling item
  final String? hsnCode;
  final double gstRate;
  final double cgstRate;
  final double sgstRate;
  final double igstRate;

  // ─── Future-ready columns (mapped, not yet surfaced in UI) ─────────────
  final String? shortName;
  final String? localName;
  final String? searchKeywords;
  final String? printName;
  final String? kitchenName;
  final String? badge;
  final bool isFeatured;
  final bool isRecommended;
  final int? preparationTime;
  final String? barcode;
  final String? sku;
  final bool stockEnabled;
  final bool unlimitedStock;
  final double packingCharge;
  final double serviceCharge;
  final bool onlineVisible;
  final bool qrVisible;
  final bool selfOrderVisible;
  final bool dineInAvailable;
  final bool takeawayAvailable;
  final bool deliveryAvailable;
  final DateTime? updatedAt;
  final String? updatedBy;
  final int syncVersion;

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
    this.isDefault = false,
    this.foodType = 'veg',
    this.hsnCode,
    this.gstRate = 0,
    this.cgstRate = 0,
    this.sgstRate = 0,
    this.igstRate = 0,
    this.shortName,
    this.localName,
    this.searchKeywords,
    this.printName,
    this.kitchenName,
    this.badge,
    this.isFeatured = false,
    this.isRecommended = false,
    this.preparationTime,
    this.barcode,
    this.sku,
    this.stockEnabled = false,
    this.unlimitedStock = true,
    this.packingCharge = 0,
    this.serviceCharge = 0,
    this.onlineVisible = true,
    this.qrVisible = true,
    this.selfOrderVisible = true,
    this.dineInAvailable = true,
    this.takeawayAvailable = true,
    this.deliveryAvailable = true,
    this.updatedAt,
    this.updatedBy,
    this.syncVersion = 0,
  });

  double get rate => baseRate;

  /// True when this variant defines its own price (overrides the group rate).
  /// A null/0 stored value means "inherit the group base rate".
  bool get hasPriceOverride => baseRate > 0;

  /// Whether the variant name is the implicit single "Default" selling item,
  /// which the POS renders using the group name instead of the variant name.
  bool get isDefaultName => variantName.trim().toLowerCase() == 'default';

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
    isDefault: json['is_default'] as bool? ?? false,
    foodType: json['food_type'] as String? ?? 'veg',
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
    shortName: json['short_name'] as String?,
    localName: json['local_name'] as String?,
    searchKeywords: json['search_keywords'] as String?,
    printName: json['print_name'] as String?,
    kitchenName: json['kitchen_name'] as String?,
    badge: json['badge'] as String?,
    isFeatured: json['is_featured'] as bool? ?? false,
    isRecommended: json['is_recommended'] as bool? ?? false,
    preparationTime: json['preparation_time'] as int?,
    barcode: json['barcode'] as String?,
    sku: json['sku'] as String?,
    stockEnabled: json['stock_enabled'] as bool? ?? false,
    unlimitedStock: json['unlimited_stock'] as bool? ?? true,
    packingCharge: (json['packing_charge'] as num?)?.toDouble() ?? 0,
    serviceCharge: (json['service_charge'] as num?)?.toDouble() ?? 0,
    onlineVisible: json['online_visible'] as bool? ?? true,
    qrVisible: json['qr_visible'] as bool? ?? true,
    selfOrderVisible: json['self_order_visible'] as bool? ?? true,
    dineInAvailable: json['dine_in_available'] as bool? ?? true,
    takeawayAvailable: json['takeaway_available'] as bool? ?? true,
    deliveryAvailable: json['delivery_available'] as bool? ?? true,
    updatedAt: json['updated_at'] != null
        ? DateTime.tryParse(json['updated_at'] as String)
        : null,
    updatedBy: json['updated_by'] as String?,
    syncVersion: json['sync_version'] as int? ?? 0,
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
    'is_default': isDefault,
    'food_type': foodType,
  };

  ItemVariant copyWith({
    String? id,
    String? itemId,
    String? variantName,
    double? baseRate,
    bool? isActive,
    String? imageUrl,
    String? hsnId,
    double? inclusiveRate,
    bool? isRateInclusive,
    String? description,
    int? displayOrder,
    bool? isAvailable,
    bool? isDefault,
    String? foodType,
    String? hsnCode,
    double? gstRate,
    double? cgstRate,
    double? sgstRate,
    double? igstRate,
  }) => ItemVariant(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    variantName: variantName ?? this.variantName,
    baseRate: baseRate ?? this.baseRate,
    isActive: isActive ?? this.isActive,
    imageUrl: imageUrl ?? this.imageUrl,
    hsnId: hsnId ?? this.hsnId,
    inclusiveRate: inclusiveRate ?? this.inclusiveRate,
    isRateInclusive: isRateInclusive ?? this.isRateInclusive,
    description: description ?? this.description,
    displayOrder: displayOrder ?? this.displayOrder,
    isAvailable: isAvailable ?? this.isAvailable,
    isDefault: isDefault ?? this.isDefault,
    foodType: foodType ?? this.foodType,
    hsnCode: hsnCode ?? this.hsnCode,
    gstRate: gstRate ?? this.gstRate,
    cgstRate: cgstRate ?? this.cgstRate,
    sgstRate: sgstRate ?? this.sgstRate,
    igstRate: igstRate ?? this.igstRate,
    shortName: shortName,
    localName: localName,
    searchKeywords: searchKeywords,
    printName: printName,
    kitchenName: kitchenName,
    badge: badge,
    isFeatured: isFeatured,
    isRecommended: isRecommended,
    preparationTime: preparationTime,
    barcode: barcode,
    sku: sku,
    stockEnabled: stockEnabled,
    unlimitedStock: unlimitedStock,
    packingCharge: packingCharge,
    serviceCharge: serviceCharge,
    onlineVisible: onlineVisible,
    qrVisible: qrVisible,
    selfOrderVisible: selfOrderVisible,
    dineInAvailable: dineInAvailable,
    takeawayAvailable: takeawayAvailable,
    deliveryAvailable: deliveryAvailable,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
    syncVersion: syncVersion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemVariant &&
          other.id == id &&
          other.variantName == variantName &&
          other.baseRate == baseRate &&
          other.isActive == isActive &&
          other.isAvailable == isAvailable &&
          other.isDefault == isDefault &&
          other.displayOrder == displayOrder &&
          other.updatedAt == updatedAt &&
          other.syncVersion == syncVersion);

  @override
  int get hashCode => Object.hash(id, variantName, baseRate, isActive,
      isAvailable, isDefault, displayOrder, updatedAt, syncVersion);
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
    this.occupiedSince,
  });

  String get tableName => tableNumber;
  String get status => isOccupied ? 'OCCUPIED' : 'FREE';
  bool get isFree => !isOccupied;

  final String? activeSessionId;
  final int activeCoverCount;

  /// When the active session was opened (used to sort/show how long the table
  /// has been occupied). Null when the table is free.
  final DateTime? occupiedSince;

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
    occupiedSince: json['occupied_since'] != null
        ? DateTime.tryParse(json['occupied_since'] as String)
        : null,
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
  final String status;
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
    this.status = 'paid',
    this.items = const [],
    this.createdAt,
  });

  /// True when the bill has been cancelled/voided. Such bills stay in the
  /// ledger for audit but are excluded from revenue totals.
  bool get isCancelled {
    final s = status.toLowerCase();
    return isVoided || s == 'cancelled' || s == 'void' || s == 'cancel';
  }

  String get coverDisplayName {
    if (coverNumber == null) return '';
    if (coverLabel != null && coverLabel!.isNotEmpty) return coverLabel!;
    return 'Cover $coverNumber';
  }

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
    id: json['id'] as String? ?? '',
    companyId: json['company_id'] as String? ?? '',
    orderId: json['order_id'] as String?,
    billNumber: json['bill_number']?.toString(),
    subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
    discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
    totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
    paymentMode: json['payment_mode'] as String? ?? 'CASH',
    status: json['status'] as String? ?? 'paid',
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
    id: json['id'] as String? ?? '',
    billId: json['bill_id'] as String? ?? '',
    // item_id can be null for bills whose menu item was later deleted.
    itemId: json['item_id'] as String? ?? '',
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
      (variant != null && !variant!.isDefaultName)
      ? variant!.variantName
      : item.itemName;

  /// Effective selling rate — delegates to the group so the variant's
  /// price-inheritance rule (override vs. group base rate) is applied in
  /// exactly one place.
  double get rate => item.effectiveRateFor(variant);
}
