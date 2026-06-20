-- ============================================================
-- CafePOS Migration V3 — Item Group & Item Variant (Enterprise)
-- ------------------------------------------------------------
-- Model:
--   item_master  ->  ITEM GROUP   (e.g. "Dosa", "Rice", "Chinese")
--   item_variant ->  SELLING ITEM (e.g. "Plain Dosa", "Ghee Dosa")
--
-- Only VARIANTS are sold. A group is never sold directly.
-- Pricing: if a variant's base_rate is NULL/0 it INHERITS the group base_rate.
--
-- This script is ADDITIVE and IDEMPOTENT — it never drops or recreates
-- tables and preserves all existing data. Safe to re-run.
-- Run in the Supabase SQL editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. ITEM_MASTER  (= ITEM GROUP) — add future-ready columns
-- ------------------------------------------------------------
ALTER TABLE item_master
  -- Business columns already exposed in UI (guard for older DBs)
  ADD COLUMN IF NOT EXISTS section_label          TEXT,
  ADD COLUMN IF NOT EXISTS color_tag              TEXT,
  ADD COLUMN IF NOT EXISTS food_type              TEXT    DEFAULT 'veg',
  -- Naming / search
  ADD COLUMN IF NOT EXISTS short_name             TEXT,
  ADD COLUMN IF NOT EXISTS local_name             TEXT,
  ADD COLUMN IF NOT EXISTS search_keywords        TEXT,
  ADD COLUMN IF NOT EXISTS print_name             TEXT,
  ADD COLUMN IF NOT EXISTS kitchen_name           TEXT,
  -- Merchandising
  ADD COLUMN IF NOT EXISTS badge                  TEXT,
  ADD COLUMN IF NOT EXISTS is_featured            BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_recommended         BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS preparation_time       INTEGER,
  ADD COLUMN IF NOT EXISTS default_variant_id     UUID,
  -- Inventory / codes
  ADD COLUMN IF NOT EXISTS barcode                TEXT,
  ADD COLUMN IF NOT EXISTS sku                    TEXT,
  ADD COLUMN IF NOT EXISTS stock_enabled          BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS unlimited_stock        BOOLEAN DEFAULT true,
  -- Charges
  ADD COLUMN IF NOT EXISTS packing_charge         DECIMAL(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS service_charge         DECIMAL(10,2) DEFAULT 0,
  -- Channel visibility
  ADD COLUMN IF NOT EXISTS online_visible         BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS qr_visible             BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS self_order_visible     BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS dine_in_available      BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS takeaway_available     BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS delivery_available     BOOLEAN DEFAULT true,
  -- Audit / sync
  ADD COLUMN IF NOT EXISTS updated_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_by             UUID,
  ADD COLUMN IF NOT EXISTS sync_version           INTEGER DEFAULT 0;

-- default_variant_id points at the group's default selling item
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'item_master_default_variant_fk'
  ) THEN
    ALTER TABLE item_master
      ADD CONSTRAINT item_master_default_variant_fk
      FOREIGN KEY (default_variant_id) REFERENCES item_variant(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ------------------------------------------------------------
-- 2. ITEM_VARIANT  (= SELLING ITEM) — add future-ready columns
-- ------------------------------------------------------------
ALTER TABLE item_variant
  -- Pricing override (NULL/0 => inherit group base_rate, enforced in app layer)
  ADD COLUMN IF NOT EXISTS base_rate              DECIMAL(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS inclusive_rate         DECIMAL(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_rate_inclusive      BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS hsn_id                 UUID,
  ADD COLUMN IF NOT EXISTS description            TEXT,
  ADD COLUMN IF NOT EXISTS image_url              TEXT,
  ADD COLUMN IF NOT EXISTS display_order          INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_available           BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_default             BOOLEAN DEFAULT false,
  -- Veg / Egg / Non-veg lives on the SELLING ITEM, not the group, because a
  -- single group (e.g. "Biryani") can have both veg and non-veg items.
  ADD COLUMN IF NOT EXISTS food_type              TEXT    DEFAULT 'veg',
  -- Naming / search
  ADD COLUMN IF NOT EXISTS short_name             TEXT,
  ADD COLUMN IF NOT EXISTS local_name             TEXT,
  ADD COLUMN IF NOT EXISTS search_keywords        TEXT,
  ADD COLUMN IF NOT EXISTS print_name             TEXT,
  ADD COLUMN IF NOT EXISTS kitchen_name           TEXT,
  -- Merchandising
  ADD COLUMN IF NOT EXISTS badge                  TEXT,
  ADD COLUMN IF NOT EXISTS is_featured            BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_recommended         BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS preparation_time       INTEGER,
  -- Inventory / codes
  ADD COLUMN IF NOT EXISTS barcode                TEXT,
  ADD COLUMN IF NOT EXISTS sku                    TEXT,
  ADD COLUMN IF NOT EXISTS stock_enabled          BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS unlimited_stock        BOOLEAN DEFAULT true,
  -- Charges
  ADD COLUMN IF NOT EXISTS packing_charge         DECIMAL(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS service_charge         DECIMAL(10,2) DEFAULT 0,
  -- Channel visibility
  ADD COLUMN IF NOT EXISTS online_visible         BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS qr_visible             BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS self_order_visible     BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS dine_in_available      BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS takeaway_available     BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS delivery_available     BOOLEAN DEFAULT true,
  -- Audit / sync
  ADD COLUMN IF NOT EXISTS updated_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_by             UUID,
  ADD COLUMN IF NOT EXISTS sync_version           INTEGER DEFAULT 0;

-- hsn_id references the company HSN/GST table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'item_variant_hsn_fk'
  ) THEN
    ALTER TABLE item_variant
      ADD CONSTRAINT item_variant_hsn_fk
      FOREIGN KEY (hsn_id) REFERENCES company_hsn(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ------------------------------------------------------------
-- 3. CONSTRAINTS — defensive data integrity (optimised for menus)
-- ------------------------------------------------------------
-- Non-negative pricing on the group
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'item_master_base_rate_nonneg') THEN
    ALTER TABLE item_master ADD CONSTRAINT item_master_base_rate_nonneg CHECK (base_rate >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'item_master_display_order_nonneg') THEN
    ALTER TABLE item_master ADD CONSTRAINT item_master_display_order_nonneg CHECK (display_order >= 0);
  END IF;
  -- Non-negative override + display order on the variant
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'item_variant_base_rate_nonneg') THEN
    ALTER TABLE item_variant ADD CONSTRAINT item_variant_base_rate_nonneg CHECK (base_rate >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'item_variant_display_order_nonneg') THEN
    ALTER TABLE item_variant ADD CONSTRAINT item_variant_display_order_nonneg CHECK (display_order >= 0);
  END IF;
END $$;

-- Unique item_code per company (only where a code is present)
CREATE UNIQUE INDEX IF NOT EXISTS uq_item_master_company_code
  ON item_master (company_id, item_code)
  WHERE item_code IS NOT NULL AND item_code <> '';

-- ------------------------------------------------------------
-- 4. INDEXES — fast group listing + variant lazy-loading
-- ------------------------------------------------------------
-- Group listing (sorted by display_order) per company
CREATE INDEX IF NOT EXISTS idx_item_master_company_order
  ON item_master (company_id, display_order);

-- Active-group filter (POS only shows active groups)
CREATE INDEX IF NOT EXISTS idx_item_master_company_active
  ON item_master (company_id, is_active);

-- Section/category chip filtering
CREATE INDEX IF NOT EXISTS idx_item_master_company_section
  ON item_master (company_id, section_label);

-- Variant lazy-load by group, already in display order
CREATE INDEX IF NOT EXISTS idx_item_variant_item_order
  ON item_variant (item_id, display_order);

-- POS variant filter: only active + available items per group
CREATE INDEX IF NOT EXISTS idx_item_variant_item_active_avail
  ON item_variant (item_id, is_active, is_available);

-- One default variant per group (partial unique index)
CREATE UNIQUE INDEX IF NOT EXISTS uq_item_variant_one_default
  ON item_variant (item_id)
  WHERE is_default = true;

-- ------------------------------------------------------------
-- 5. BACKFILL — keep existing rows consistent with the new model
-- ------------------------------------------------------------
-- Treat every existing item as a group; ensure visibility defaults.
UPDATE item_master
   SET food_type = COALESCE(food_type, 'veg'),
       online_visible = COALESCE(online_visible, true),
       dine_in_available = COALESCE(dine_in_available, true),
       updated_at = COALESCE(updated_at, NOW())
 WHERE food_type IS NULL OR online_visible IS NULL;

-- Mark the first variant of each group (by display order) as default
-- where the group currently has no default flagged.
WITH ranked AS (
  SELECT id,
         item_id,
         ROW_NUMBER() OVER (
           PARTITION BY item_id
           ORDER BY display_order ASC, variant_name ASC
         ) AS rn
    FROM item_variant
)
UPDATE item_variant v
   SET is_default = true
  FROM ranked r
 WHERE v.id = r.id
   AND r.rn = 1
   AND NOT EXISTS (
     SELECT 1 FROM item_variant d
      WHERE d.item_id = v.item_id AND d.is_default = true
   );

-- Sync each group's default_variant_id with its flagged default variant.
UPDATE item_master m
   SET default_variant_id = v.id
  FROM item_variant v
 WHERE v.item_id = m.id
   AND v.is_default = true
   AND (m.default_variant_id IS NULL OR m.default_variant_id <> v.id);

-- ------------------------------------------------------------
-- 6. updated_at auto-touch trigger (audit-friendly)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_item_master_touch ON item_master;
CREATE TRIGGER trg_item_master_touch
  BEFORE UPDATE ON item_master
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_item_variant_touch ON item_variant;
CREATE TRIGGER trg_item_variant_touch
  BEFORE UPDATE ON item_variant
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ============================================================
-- END MIGRATION V3
-- ============================================================
