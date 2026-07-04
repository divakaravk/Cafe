import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/inventory_models.dart';
import '../core/services/supabase_service.dart';

/// Riverpod providers for the Inventory / Stock module. Follows the same
/// `FutureProvider.family` + service-returns-raw-rows / provider-maps-models
/// pattern as `tablesProvider` and friends in `providers.dart`.

// ─── RAW MATERIALS (by company) ──────────────────────────
final rawMaterialsProvider = FutureProvider.family<List<RawMaterial>, String>((
  ref,
  companyId,
) async {
  final res = await SupabaseService.getRawMaterials(companyId);
  return res.map((e) => RawMaterial.fromJson(e)).toList();
});

// ─── VARIANT RECIPE (by item variant) ────────────────────
final variantRecipeProvider =
    FutureProvider.family<List<VariantRecipe>, String>((
      ref,
      itemVariantId,
    ) async {
      final res = await SupabaseService.getRecipeForVariant(itemVariantId);
      return res.map((e) => VariantRecipe.fromJson(e)).toList();
    });

// ─── CURRENT STOCK (by company) ──────────────────────────
final currentStockProvider =
    FutureProvider.family<List<CurrentStockRow>, String>((ref, companyId) async {
      final res = await SupabaseService.getCurrentStock(companyId);
      return res.map((e) => CurrentStockRow.fromJson(e)).toList();
    });

// ─── LOW STOCK ALERTS (derived from current stock) ───────
final lowStockAlertsProvider =
    FutureProvider.family<List<CurrentStockRow>, String>((ref, companyId) async {
      final all = await ref.watch(currentStockProvider(companyId).future);
      return all.where((r) => r.isLowStock).toList();
    });

// ─── STAFF CONSUMPTION (by company + optional date range / staff) ─
/// Family key for [staffConsumptionProvider]. A record so the provider is
/// cached per (company, range, staff) combination.
typedef StaffConsumptionArgs = ({
  String companyId,
  DateTime? from,
  DateTime? to,
  String? staffId,
});

final staffConsumptionProvider =
    FutureProvider.family<List<StaffConsumptionRow>, StaffConsumptionArgs>((
      ref,
      args,
    ) async {
      final res = await SupabaseService.getStaffConsumption(
        args.companyId,
        from: args.from,
        to: args.to,
        staffId: args.staffId,
      );
      return res.map((e) => StaffConsumptionRow.fromJson(e)).toList();
    });
