// Inventory / Stock module models.
//
// These map 1:1 to the Supabase tables/views created by the
// `20260620_inventory_module.sql` migration:
//   - raw_material        → RawMaterial
//   - variant_recipe      → VariantRecipe
//   - stock_ledger        → StockLedgerEntry
//   - v_current_stock     → CurrentStockRow   (read-only view)
//   - v_staff_consumption → StaffConsumptionRow (read-only view)
//
// Style mirrors `models.dart`: snake_case JSON keys, doubles parsed via
// `(json[...] as num?)?.toDouble()`, DateTimes via `DateTime.parse`.

/// Allowed units of measure for a raw material. Used to populate unit dropdowns.
const List<String> kUnits = ['ml', 'l', 'g', 'kg', 'unit', 'pinch'];

/// A tracked raw material / ingredient (table: `raw_material`).
class RawMaterial {
  final String id;
  final String companyId;
  final String name;

  /// One of [kUnits]: ml, l, g, kg, unit, pinch.
  final String unit;
  final double openingStock;
  final double reorderLevel;
  final double costPerUnit;
  final bool isActive;

  const RawMaterial({
    required this.id,
    required this.companyId,
    required this.name,
    required this.unit,
    this.openingStock = 0,
    this.reorderLevel = 0,
    this.costPerUnit = 0,
    this.isActive = true,
  });

  factory RawMaterial.fromJson(Map<String, dynamic> json) => RawMaterial(
    id: json['id'] as String,
    companyId: json['company_id'] as String,
    name: json['name'] as String? ?? '',
    unit: json['unit'] as String? ?? 'unit',
    openingStock: (json['opening_stock'] as num?)?.toDouble() ?? 0,
    reorderLevel: (json['reorder_level'] as num?)?.toDouble() ?? 0,
    costPerUnit: (json['cost_per_unit'] as num?)?.toDouble() ?? 0,
    isActive: json['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'name': name,
    'unit': unit,
    'opening_stock': openingStock,
    'reorder_level': reorderLevel,
    'cost_per_unit': costPerUnit,
    'is_active': isActive,
  };

  RawMaterial copyWith({
    String? id,
    String? companyId,
    String? name,
    String? unit,
    double? openingStock,
    double? reorderLevel,
    double? costPerUnit,
    bool? isActive,
  }) => RawMaterial(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    openingStock: openingStock ?? this.openingStock,
    reorderLevel: reorderLevel ?? this.reorderLevel,
    costPerUnit: costPerUnit ?? this.costPerUnit,
    isActive: isActive ?? this.isActive,
  );
}

/// One line of an item variant's recipe / BOM (table: `variant_recipe`).
/// Links an [ItemVariant] to a [RawMaterial] with the qty consumed per unit
/// sold.
class VariantRecipe {
  final String id;
  final String itemVariantId;
  final String rawMaterialId;
  final double qtyPerUnit;

  const VariantRecipe({
    required this.id,
    required this.itemVariantId,
    required this.rawMaterialId,
    this.qtyPerUnit = 0,
  });

  factory VariantRecipe.fromJson(Map<String, dynamic> json) => VariantRecipe(
    id: json['id'] as String,
    itemVariantId: json['item_variant_id'] as String,
    rawMaterialId: json['raw_material_id'] as String,
    qtyPerUnit: (json['qty_per_unit'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_variant_id': itemVariantId,
    'raw_material_id': rawMaterialId,
    'qty_per_unit': qtyPerUnit,
  };
}

/// A single stock movement (table: `stock_ledger`). Negative [qty] reduces
/// stock (consumption / variance loss), positive adds it.
class StockLedgerEntry {
  final String id;
  final String companyId;
  final String rawMaterialId;

  /// e.g. 'consumed', 'adjustment', 'opening', 'purchase'.
  final String movementType;
  final double qty;
  final String? kotItemId;
  final String? staffId;
  final String? note;
  final String? shiftLabel;
  final DateTime createdAt;

  const StockLedgerEntry({
    required this.id,
    required this.companyId,
    required this.rawMaterialId,
    required this.movementType,
    required this.qty,
    required this.createdAt,
    this.kotItemId,
    this.staffId,
    this.note,
    this.shiftLabel,
  });

  factory StockLedgerEntry.fromJson(Map<String, dynamic> json) =>
      StockLedgerEntry(
        id: json['id'] as String,
        companyId: json['company_id'] as String,
        rawMaterialId: json['raw_material_id'] as String,
        movementType: json['movement_type'] as String? ?? 'adjustment',
        qty: (json['qty'] as num?)?.toDouble() ?? 0,
        kotItemId: json['kot_item_id'] as String?,
        staffId: json['staff_id'] as String?,
        note: json['note'] as String?,
        shiftLabel: json['shift_label'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'raw_material_id': rawMaterialId,
    'movement_type': movementType,
    'qty': qty,
    'kot_item_id': kotItemId,
    'staff_id': staffId,
    'note': note,
    'shift_label': shiftLabel,
    'created_at': createdAt.toIso8601String(),
  };
}

/// A row from the read-only `v_current_stock` view: a material plus its
/// computed current stock level and low-stock flag. No `toJson` — read only.
class CurrentStockRow {
  final String id;
  final String companyId;
  final String name;
  final String unit;
  final double openingStock;
  final double currentStock;
  final double reorderLevel;
  final bool isLowStock;

  const CurrentStockRow({
    required this.id,
    required this.companyId,
    required this.name,
    required this.unit,
    required this.openingStock,
    required this.currentStock,
    required this.reorderLevel,
    required this.isLowStock,
  });

  factory CurrentStockRow.fromJson(Map<String, dynamic> json) {
    final current = (json['current_stock'] as num?)?.toDouble() ?? 0;
    final reorder = (json['reorder_level'] as num?)?.toDouble() ?? 0;
    return CurrentStockRow(
      id: json['id'] as String,
      companyId: json['company_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String? ?? 'unit',
      openingStock: (json['opening_stock'] as num?)?.toDouble() ?? 0,
      currentStock: current,
      reorderLevel: reorder,
      // Prefer the view's own flag; fall back to a local computation so the UI
      // still works if the view doesn't expose `is_low_stock`.
      isLowStock: (json['is_low_stock'] as bool?) ?? (current <= reorder),
    );
  }
}

/// A row from the read-only `v_staff_consumption` view (or the date-filtered
/// equivalent aggregated from `stock_ledger`). No `toJson` — read only.
class StaffConsumptionRow {
  final String? staffId;
  final String? staffName;
  final String rawMaterialId;
  final String rawMaterialName;
  final String unit;
  final double totalConsumed;

  const StaffConsumptionRow({
    required this.rawMaterialId,
    required this.rawMaterialName,
    required this.unit,
    required this.totalConsumed,
    this.staffId,
    this.staffName,
  });

  factory StaffConsumptionRow.fromJson(Map<String, dynamic> json) =>
      StaffConsumptionRow(
        staffId: json['staff_id'] as String?,
        staffName: json['staff_name'] as String?,
        rawMaterialId:
            (json['raw_material_id'] ?? json['id']) as String? ?? '',
        rawMaterialName:
            (json['raw_material_name'] ?? json['name']) as String? ?? '',
        unit: json['unit'] as String? ?? 'unit',
        totalConsumed: (json['total_consumed'] as num?)?.toDouble() ?? 0,
      );
}
