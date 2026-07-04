-- ════════════════════════════════════════════════════════════════════════════
--  APP OWNER  (platform super-admin, not tied to any company)
-- ────────────────────────────────────────────────────────────────────────────
--  The owner logs in on the normal login screen and is routed to a dedicated
--  "Company Registrations" dashboard (no POS / company UI). They receive an FCM
--  push for every new-company registration and can approve requests there.
--
--  Run this AFTER supabase_company_registration.sql.
-- ════════════════════════════════════════════════════════════════════════════

-- ─── 1. Allow a company-less user (the owner) ───────────────────────────────
alter table public.user_profiles
  alter column company_id drop not null;

-- The role CHECK constraint (user_master_role_check) excludes 'owner' by
-- default — widen it to allow the platform owner role.
alter table public.user_profiles
  drop constraint if exists user_master_role_check;
alter table public.user_profiles
  add constraint user_master_role_check
  check (user_role = any (array['owner','admin','manager','cashier','waiter','kitchen']));

-- ─── 2. Seed the owner account ──────────────────────────────────────────────
--  Login with username 'owner' (or the email) + the password below.
--  CHANGE THE PASSWORD after first login.
insert into public.user_profiles (
  id, company_id, user_name, employee_code, username,
  user_role, user_email, password, user_active
)
values (
  gen_random_uuid(),
  null,                       -- owner belongs to no company
  'App Owner',
  'OWNER',
  'owner',
  'owner',
  'divakaravk11@gmail.com',
  'Owner@123',                -- TODO: change after first login
  true
)
on conflict do nothing;

-- ════════════════════════════════════════════════════════════════════════════
--  RPC: list_company_registrations  — recent requests for the owner dashboard
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.list_company_registrations(
  p_limit int default 50
)
returns setof public.company_registration
language sql
security definer
set search_path = public
as $$
  select *
  from public.company_registration
  order by created_at desc
  limit p_limit;
$$;

-- ════════════════════════════════════════════════════════════════════════════
--  RPC: approve_company_registration — owner override (activates the company)
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.approve_company_registration(
  p_registration_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  update public.company_registration
    set status = 'verified'
    where id = p_registration_id
    returning company_id into v_company_id;

  if v_company_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  update public.company_master
    set is_verified = true, is_active = true
    where id = v_company_id;

  return jsonb_build_object('ok', true, 'company_id', v_company_id);
end;
$$;

grant execute on function public.list_company_registrations(int)        to anon, authenticated;
grant execute on function public.approve_company_registration(uuid)     to anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
--  SECURITY NOTE
--  This app uses custom auth (anon key, no Supabase Auth session), so these
--  RPCs — like the rest of the app's data access — are reachable by anyone
--  holding the anon key. That matches the existing trust-the-client model.
--  The proper hardening (Supabase Auth + RLS that restricts these RPCs to the
--  owner) is a separate, larger migration.
-- ════════════════════════════════════════════════════════════════════════════
