# Cutover runbook (Phase 9)

**Status: not executed.** This is a checklist to follow when you've chosen a
production host for the Node API and a production MySQL instance — neither
exists yet. Nothing here can run until those two things do.

## Prerequisites (blocking — do these first)

- [ ] **Phase 0 security items done**: leaked `service_role` key rotated, git
      history purged of `fix_auth.js`/`api_keys.json`, seeded passwords
      (`Owner@123`, `Admin@123`) changed. See `PLAN.md` §1.3 findings #1–#2.
- [ ] A production MySQL 8.4 instance provisioned, reachable from where the
      Node API will run, with a dedicated (non-root) app user.
- [ ] A production host for the Node API (a VM, container platform, or PaaS)
      with a real domain + TLS certificate. `backend/.env.example` lists every
      variable that needs a real value there — in particular
      `JWT_ACCESS_SECRET` (32+ random bytes, `openssl rand -base64 48`),
      `CORS_ORIGINS`, `PUBLIC_ASSET_BASE_URL`, and the Firebase secrets if push
      is wanted.
- [ ] A read-only Postgres role on the Supabase project for the ETL
      (`migrate-from-supabase.ts`'s header comment has the exact `CREATE ROLE`
      statement).
- [ ] Phase 8 hardening re-run against the **production** MySQL/host once
      they exist — the checks in `verify/` and `scripts/` here were run
      against a local/embedded MySQL, which proves the logic but not
      production network latency, TLS, or firewall behaviour.

## Window

Pick a low-traffic ~30–60 minute window. Tell staff in advance: the app will
show connection errors for a few minutes during the cutover.

## Steps

1. **Freeze writes on Supabase.** In the Supabase dashboard, revoke `anon`'s
   INSERT/UPDATE/DELETE grants (or simplest: temporarily rotate the anon key
   so the app can't reach it) so no new data is written after the ETL reads.
   Confirm via the app: an active POS screen should start failing writes.

2. **Run the ETL.**
   ```bash
   cd backend
   SUPABASE_DB_URL=postgres://etl_ro:...@db.<ref>.supabase.co:5432/postgres \
     npm run migrate:from-supabase -- --dry-run     # read the summary first
   SUPABASE_DB_URL=... npm run migrate:from-supabase # then apply
   ```
   Read the fixup log it prints (renamed duplicate codes/numbers — expect the
   ones already identified in `PLAN.md` §3.2/§6: one `DIV01`/`div01` employee
   code, five duplicate KOT numbers). It's idempotent — safe to re-run if
   something looks wrong before you proceed.

3. **Verify the migration.** Run `verify-migration.ts` (row counts per table,
   `SUM(total_amount)` per company/status, orphan-FK scan) and manually spot
   check: log into the new API as an existing user, pull up a known bill,
   compare totals against what's in Supabase right now.

4. **Smoke-test the new API** against production data: login, tables, one
   test order + KOT + checkout (on a test company, not a real one), reports.
   Use `backend/scripts/smoke.mjs` as a template — point `BASE` at the
   production URL and re-run the read-only portions.

5. **Ship the app build.**
   ```bash
   flutter build apk --dart-define=USE_SUPABASE=false --dart-define=API_BASE_URL=https://api.yourdomain.com
   ```
   Roll out through your normal release channel. Until every device has
   updated, **do not** decommission Supabase (see rollback below).

6. **Keep Supabase read-only, not deleted, for 30 days.** It's your rollback
   path (§ below) and a reference for spot-checking historical bills.

7. **After 30 days with no issues:** rotate/revoke the owner password seeded
   during ETL, pause the Supabase project, and delete the leaked keys from
   §1.3 for good (they should already be rotated per the prerequisite above —
   this step retires the *project*, not just the keys).

## Rollback

**Valid until the first write happens against the new MySQL database.** After
that, going back means either:
- Accepting the small window of new-MySQL-only data is lost (usually fine —
  it's typically a handful of orders in the first hour), or
- Manually replaying those specific rows back into Supabase (a short one-off
  script; not written, since the data to replay depends entirely on what
  happened during that specific cutover).

To roll back before any new-database write:
1. Restore Supabase's `anon` write grants (undo step 1).
2. Ship a build with `--dart-define=USE_SUPABASE=true` (or just don't
   distribute the new build yet, if it hasn't gone out).
3. Investigate, fix, and re-attempt the cutover another day.

## Post-cutover monitoring (first 48 hours)

- Watch the Node API's logs for 5xx rates and slow queries.
- Watch MySQL's error log and slow query log.
- Confirm scheduled backups are actually running against the *new* production
  MySQL (a fresh instance has no backup history yet — don't assume `PLAN.md`
  §8's backup script is wired to cron until you've checked).
- Ask a couple of staff at the pilot café whether anything feels different
  (slower, KOTs missing, totals wrong) — they'll notice things a dashboard
  won't.
