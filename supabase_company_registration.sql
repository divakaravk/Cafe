-- ════════════════════════════════════════════════════════════════════════════
--  NEW COMPANY SELF-REGISTRATION  (production onboarding flow)
-- ────────────────────────────────────────────────────────────────────────────
--  Flow:
--    1. A prospect fills the "Register your company" form in the app.
--    2. `request_company_registration` creates the company in an UNVERIFIED /
--       INACTIVE state and a `company_registration` row carrying a 6-digit OTP.
--    3. A Database Webhook on INSERT into `company_registration` invokes the
--       `send-registration-otp` Edge Function, which pushes the OTP via FCM to
--       every device in `super_admin_devices` (the app owner / super-admins).
--    4. The owner relays the OTP to the prospect (this is the approval gate).
--    5. The prospect enters the OTP; `verify_company_registration_otp` flips the
--       company to verified + active.
--    6. The app then creates the first ADMIN user tagged with the new company_id.
--
--  RPCs are SECURITY DEFINER so the anonymous (pre-login) client can call them
--  without broad table-level grants.
-- ════════════════════════════════════════════════════════════════════════════

-- ─── 1. company_master: verification flags ──────────────────────────────────
alter table public.company_master
  add column if not exists is_verified boolean not null default false;

-- New self-registered companies start inactive until the OTP is confirmed.
-- (Existing rows are untouched — they keep is_active = true.)

-- ─── 2. Super-admin devices that receive registration OTP pushes ─────────────
create table if not exists public.super_admin_devices (
  id          uuid primary key default gen_random_uuid(),
  fcm_token   text not null unique,
  label       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ─── 3. Registration requests (one per company onboarding attempt) ───────────
create table if not exists public.company_registration (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid references public.company_master(id) on delete cascade,
  company_name text,
  owner_name   text,
  owner_email  text,
  owner_phone  text,
  otp_code     text not null,
  status       text not null default 'pending',  -- pending | verified | expired
  attempts     int  not null default 0,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '10 minutes')
);

create index if not exists company_registration_status_idx
  on public.company_registration (status);

-- ════════════════════════════════════════════════════════════════════════════
--  RPC: request_company_registration
--  Creates the (unverified) company + a registration row with a fresh OTP.
--  Returns { registration_id, company_id }.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.request_company_registration(
  p_company jsonb,
  p_owner   jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_reg_id     uuid;
  v_otp        text;
begin
  -- 6-digit zero-padded OTP
  v_otp := lpad((floor(random() * 1000000))::int::text, 6, '0');

  insert into public.company_master (
    company_code, company_name, email, phone, address, city, state, country,
    has_gst, gstin, pan_number, has_table_management, has_item_variants,
    show_item_images, is_active, is_verified
  )
  values (
    p_company->>'company_code',
    p_company->>'company_name',
    p_company->>'email',
    p_company->>'phone',
    p_company->>'address',
    p_company->>'city',
    p_company->>'state',
    coalesce(p_company->>'country', 'India'),
    coalesce((p_company->>'has_gst')::boolean, false),
    p_company->>'gstin',
    p_company->>'pan_number',
    coalesce((p_company->>'has_table_management')::boolean, true),
    coalesce((p_company->>'has_item_variants')::boolean, false),
    coalesce((p_company->>'show_item_images')::boolean, true),
    false,   -- is_active  (activated on OTP verify)
    false    -- is_verified
  )
  returning id into v_company_id;

  insert into public.company_registration (
    company_id, company_name, owner_name, owner_email, owner_phone, otp_code
  )
  values (
    v_company_id,
    p_company->>'company_name',
    p_owner->>'owner_name',
    p_owner->>'owner_email',
    p_owner->>'owner_phone',
    v_otp
  )
  returning id into v_reg_id;

  return jsonb_build_object(
    'registration_id', v_reg_id,
    'company_id', v_company_id
  );
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
--  RPC: verify_company_registration_otp
--  Validates the OTP (match + not expired + under attempt limit). On success
--  flips the company to verified + active. Returns { ok, company_id, reason }.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.verify_company_registration_otp(
  p_registration_id uuid,
  p_code            text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reg public.company_registration%rowtype;
begin
  select * into v_reg
  from public.company_registration
  where id = p_registration_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  -- A wrong code must NEVER succeed — even if the row was already verified
  -- (e.g. approved by the owner from the dashboard). Check the code first.
  if v_reg.otp_code <> p_code then
    if v_reg.status = 'pending' then
      update public.company_registration
        set attempts = attempts + 1
        where id = p_registration_id;
      if v_reg.attempts + 1 >= 5 then
        return jsonb_build_object('ok', false, 'reason', 'too_many_attempts');
      end if;
    end if;
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  -- Code matches. Only a still-pending request can expire.
  if v_reg.status = 'pending' and now() > v_reg.expires_at then
    update public.company_registration set status = 'expired'
      where id = p_registration_id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  -- Success (idempotent) — activate the company.
  update public.company_registration
    set status = 'verified'
    where id = p_registration_id;

  update public.company_master
    set is_verified = true, is_active = true
    where id = v_reg.company_id;

  return jsonb_build_object('ok', true, 'company_id', v_reg.company_id);
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
--  RPC: register_super_admin_device
--  Upserts an owner / super-admin FCM token so it receives registration OTPs.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.register_super_admin_device(
  p_token text,
  p_label text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.super_admin_devices (fcm_token, label, updated_at)
  values (p_token, p_label, now())
  on conflict (fcm_token)
  do update set label = excluded.label, updated_at = now();
end;
$$;

-- ─── Grants: allow the pre-login (anon) client to call the RPCs ──────────────
grant execute on function public.request_company_registration(jsonb, jsonb) to anon, authenticated;
grant execute on function public.verify_company_registration_otp(uuid, text)  to anon, authenticated;
grant execute on function public.register_super_admin_device(text, text)      to anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
--  AFTER RUNNING THIS FILE — manual Supabase / Firebase steps (one-time):
--
--   A. Database → Webhooks → create a webhook:
--        Table:  company_registration
--        Events: INSERT
--        Type:   Supabase Edge Function → send-registration-otp
--
--   B. Deploy the Edge Function:  supabase/functions/send-registration-otp
--        supabase functions deploy send-registration-otp
--      Set its secrets (FCM HTTP v1 service account):
--        supabase secrets set FIREBASE_PROJECT_ID=...
--        supabase secrets set FIREBASE_CLIENT_EMAIL=...
--        supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
--
--   C. Firebase console: create the project, add the Android/iOS apps,
--      drop google-services.json into android/app/ (and the iOS plist), and
--      enable Cloud Messaging.  See android setup notes in the Flutter PR.
-- ════════════════════════════════════════════════════════════════════════════
