-- ============================================================
-- RasaBhojan — Inventory / Stock module migration
-- Adapted to the live schema:
--   • kot_item has NO item_variant_id → variant resolved via
--     kot_item.bill_item_id → bill_item.variant_id
--   • staff + company resolved via kot_item.kot_id → kot_master
--   • user display name column is user_profiles.user_name
--   • existing tables run with RLS DISABLED (anon key + custom auth),
--     so these tables follow the same convention (no RLS).
-- Idempotent: safe to re-run.
-- ============================================================

create extension if not exists pgcrypto;

-- ─── RAW MATERIAL ───────────────────────────────────────────
create table if not exists raw_material (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references company_master(id) on delete cascade,
  name          text not null,
  unit          text not null default 'unit',
  opening_stock numeric not null default 0,
  reorder_level numeric not null default 0,
  cost_per_unit numeric not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
create index if not exists idx_raw_material_company on raw_material(company_id);

-- ─── VARIANT RECIPE (BOM) ───────────────────────────────────
create table if not exists variant_recipe (
  id              uuid primary key default gen_random_uuid(),
  item_variant_id uuid not null references item_variant(id) on delete cascade,
  raw_material_id uuid not null references raw_material(id) on delete cascade,
  qty_per_unit    numeric not null default 0,
  unique (item_variant_id, raw_material_id)
);
create index if not exists idx_variant_recipe_variant on variant_recipe(item_variant_id);
create index if not exists idx_variant_recipe_material on variant_recipe(raw_material_id);

-- ─── STOCK LEDGER ───────────────────────────────────────────
create table if not exists stock_ledger (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references company_master(id) on delete cascade,
  raw_material_id uuid not null references raw_material(id) on delete cascade,
  movement_type   text not null default 'adjustment',
  qty             numeric not null,
  kot_item_id     uuid references kot_item(id) on delete set null,
  staff_id        uuid references user_profiles(id) on delete set null,
  note            text,
  shift_label     text,
  created_at      timestamptz not null default now()
);
create index if not exists idx_stock_ledger_company on stock_ledger(company_id);
create index if not exists idx_stock_ledger_material on stock_ledger(raw_material_id);
create index if not exists idx_stock_ledger_staff on stock_ledger(staff_id);
create index if not exists idx_stock_ledger_created on stock_ledger(created_at);

-- ─── AUTO-DEDUCT TRIGGER ────────────────────────────────────
-- On every new kot_item, deduct each recipe ingredient of the sold variant.
create or replace function deduct_stock_on_kot()
returns trigger
language plpgsql
security definer
as $$
declare
  v_variant_id uuid;
  v_company_id uuid;
  v_staff_id   uuid;
begin
  -- Resolve the sold variant from the linked bill_item.
  select bi.variant_id into v_variant_id
  from bill_item bi where bi.id = NEW.bill_item_id;

  -- Resolve company + staff from the parent KOT.
  select km.company_id, km.created_by into v_company_id, v_staff_id
  from kot_master km where km.id = NEW.kot_id;

  if v_variant_id is null or v_company_id is null then
    return NEW;
  end if;

  insert into stock_ledger (
    company_id, raw_material_id, movement_type, qty, kot_item_id, staff_id, note
  )
  select
    v_company_id,
    vr.raw_material_id,
    'consumed',
    -(vr.qty_per_unit * coalesce(NEW.qty, 0)),
    NEW.id,
    v_staff_id,
    'auto KOT deduction'
  from variant_recipe vr
  where vr.item_variant_id = v_variant_id;

  return NEW;
end;
$$;

drop trigger if exists trg_deduct_stock on kot_item;
create trigger trg_deduct_stock
  after insert on kot_item
  for each row execute function deduct_stock_on_kot();

-- ─── VIEW: CURRENT STOCK ────────────────────────────────────
create or replace view v_current_stock as
select
  rm.id,
  rm.company_id,
  rm.name,
  rm.unit,
  rm.opening_stock,
  rm.reorder_level,
  rm.opening_stock + coalesce((
    select sum(sl.qty) from stock_ledger sl where sl.raw_material_id = rm.id
  ), 0) as current_stock,
  (rm.opening_stock + coalesce((
    select sum(sl.qty) from stock_ledger sl where sl.raw_material_id = rm.id
  ), 0)) <= rm.reorder_level as is_low_stock
from raw_material rm
where rm.is_active = true;

-- ─── VIEW: STAFF CONSUMPTION (all-time aggregate) ───────────
create or replace view v_staff_consumption as
select
  sl.staff_id,
  up.user_name as staff_name,
  rm.id        as raw_material_id,
  rm.name      as raw_material_name,
  rm.unit,
  rm.company_id,
  sum(-sl.qty) as total_consumed
from stock_ledger sl
join raw_material rm on rm.id = sl.raw_material_id
left join user_profiles up on up.id = sl.staff_id
where sl.movement_type = 'consumed'
group by sl.staff_id, up.user_name, rm.id, rm.name, rm.unit, rm.company_id;
