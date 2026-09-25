# RasaBhojan — Node.js + MySQL backend: implementation plan

**Goal:** the same Flutter app runs against **either** Supabase (today) **or** a new Node.js + MySQL API,
chosen by one build flag. Supabase mode must keep working exactly as it does now.

**Status (2026-09-19):** plan + a validated MySQL schema. **No app code has been changed.**
Files here: `PLAN.md` (this), `schema.mysql.sql` (MySQL 8.4 DDL), `verify/` (re-runnable checks).
Companion: `../web-view/PLAN.md` (browser/desktop version of the app) — a *public* web release depends on this backend.

```bash
flutter run                                                        # Supabase — unchanged default
flutter run --dart-define=USE_SUPABASE=false \
            --dart-define=API_BASE_URL=http://10.0.2.2:3000        # Node + MySQL (Android emulator → host PC)
```

---

## 0. Read this first

1. **Do Phase 0 (secrets) before anything else.** Your service-role key is committed and pushed, and the anon key
   that ships in the APK can currently read/modify almost everything (§1.3). Separately, the stock module can't work
   in Supabase mode as deployed (RLS with no policies, §1.3 #13).
2. **The migration is small in data, large in logic.** Live data is tiny (189 bills, 9 users, 12 item groups), but
   the app does all business logic in the client (bill numbers, taxes, multi-step order saves). The Node API has to
   own that logic — that is where the work and the risk are.
3. **The safest design is "same JSON, different transport".** The Node API returns exactly the JSON shapes
   PostgREST returns today (same column names, same nested embeds). The Flutter models and all 26 screens then
   don't change; only one new class (`RestBackend`) is added.
4. **Supabase mode stays byte-for-byte the same code.** `SupabaseService` is not refactored; a thin `Backend` facade
   is placed in front of it (Phase 1), and the only additions to it are 4 small methods that move code out of 3 screens.

| Phase | What | Rough size* |
|---|---|---|
| 0 | Security hygiene (keys, git history, passwords) | 0.5 d |
| 1 | Flutter backend abstraction + `USE_SUPABASE` flag (Supabase path unchanged) | 2 d |
| 2 | Node foundation, MySQL migrations, auth | 4 d |
| 3 | Core POS API: items, tables, covers, KOT, bills, kitchen | 7 d |
| 4 | Admin API: company, users, HSN, inventory, uploads | 4 d |
| 5 | Company registration + owner + FCM push | 2 d |
| 6 | Flutter `RestBackend` (overlaps 3–5) | 5 d |
| 7 | Data migration Supabase → MySQL + verification | 3 d |
| 8 | Hardening: perf, RBAC enforcement, backups, load test | 3 d |
| 9 | Cutover + rollback plan | 2 d |

\* one developer, rough, includes tests. ≈ 6 weeks calendar if sequential, ≈ 5 with Phase 6 overlapped.

---

## 1. What the investigation found

Sources: the app code; the **live** Supabase project `vsbjkytdqhzbtideebwy` (Postgres 17, read-only catalog + `SELECT`
queries only, nothing written); and a throw-away MySQL 8.4.9 used to run the new schema (§9).

### 1.1 How the app talks to the backend today

* All data access goes through `lib/core/services/supabase_service.dart` (1,600 lines, static methods).
  **57 methods** are used by **26 files**; 14 more are dead code (listed in §4.4) and will not be ported.
* Only **3 call sites bypass the service** and use `SupabaseService.client` directly:
  `user_master_screen.dart:373` (force-logout), `item_master_screen.dart:235,252` (save group / set default variant),
  `my_profile_screen.dart:171` (update own profile).
* **Auth is custom, not Supabase Auth.** Login fetches the user row *including the plaintext password* with the anon key
  and compares it in Dart (`supabase_service.dart:44`); the whole row (password included) is then cached in
  `SharedPreferences`. Nothing about a "session" exists server-side.
* **Business logic runs in the client:** GST split, bill/KOT numbering, discount maths, "reuse open session / cover /
  bill", stock consumption aggregation. `saveOrderWithKot` is ~10 sequential requests with no transaction.
* No realtime: kitchen screen polls every 20 s, the session guard every 20 s.

### 1.2 Live data (exact counts, 2026-09-19) — used as ETL baselines

| companies | hsn | users | permissions | tables | sessions | covers | item groups | variants | bills | bill items | KOTs | KOT items | registrations | devices |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 4 | 9 | 6 | 11 | 74 | 60 | 12 | 84 | 189 | 382 | 107 | 176 | 3 | 1 |

`raw_material`, `variant_recipe`, `stock_ledger`, `company_print_config`, `user_preference` are **empty**, so the
inventory tables' precision/keys can be chosen freely. Storage: 43 objects in `items`, 1 in `profiles` (both public buckets).
The inventory tables are empty for a reason, see finding #13 below.

### 1.3 Problems found (ranked) and where each is fixed

| # | Finding | Evidence | Fixed in |
|---|---|---|---|
| 1 | **The anon key (shipped inside the APK) has near-total access.** `anon` can SELECT/UPDATE `user_profiles` (plaintext passwords), DELETE `bill_master`, UPDATE `company_master`, and EXECUTE `approve_company_registration` / `list_company_registrations` (= activate any company, read every OTP). RLS is **off on 15 of 20 tables**; 22 tables/views are anon-readable. Proven read-only: `SET LOCAL ROLE anon; SELECT count(*)` inside a rolled-back transaction returns 9 users and 189 bills. | `has_*_privilege('anon', …)` all `true`; `pg_class.relrowsecurity`; anon-role SELECT | Node API (P2–P5); cannot be fixed in Supabase mode without breaking custom auth |
| 2 | **Secrets in git.** `fix_auth.js` holds a `service_role` JWT (exp 2036) and `api_keys.json` holds all project keys; both in the *first commit* and pushed (`origin/main`, `new_version_1`, `new_version_2`). `api_keys.json` is in `.gitignore` but was already tracked. Seed passwords `Owner@123`, `Admin@123` are in the repo. | `git ls-files`, `git branch -r --contains` | **P0** |
| 3 | **Bill numbers are racy and break at #1000.** Client does `ORDER BY bill_number DESC LIMIT 1` — text sort puts `…/999` above `…/1000`, so the 1000th bill of a financial year regenerates an existing number → duplicate-key error. Two devices can also collide. | code + proven in `verify/schema-check.js`; company COMP001 is at seq 195 | Counter table (P3); optional Supabase fix §8 |
| 4 | **Duplicate KOT numbers already exist** (5 pairs) — no unique constraint, same race. | live query | `UNIQUE(company_id, kot_number)` + counter; ETL renumbers |
| 5 | **58 of 182 finalized bills don't reconcile** (`total ≠ subtotal + tax − discount`). In the bills I inspected (#192–195) `total = subtotal` while CGST/SGST are non-zero, and the most common gaps (−0.76, −1.50, −2.50, −6.00) equal exactly the GST on those bills — consistent with tax being shown but not added. In code, `createBill` takes a caller-supplied total while `saveOrderWithKot` adds tax itself, so the two paths can disagree (inclusive vs exclusive pricing). Header `subtotal` always matches the line items (182/182). | live query + code; I did not trace which path wrote each of the 58 | P3 parity, P8 unification (needs your accounting decision) |
| 6 | **Non-atomic multi-step writes.** A failure mid-`saveOrderWithKot` leaves an orphan session/bill; a timeout + manual retry duplicates the KOT. | code | Transactions + `Idempotency-Key` (P3) |
| 7 | **Wrong uniqueness scope.** `item_code`, `employee_code`, `bill_number` are unique **globally** (two cafes can't both use code `001`); `table_number` has no uniqueness at all. | live constraints | schema `[FIX 2,3,5,8]` |
| 8 | **Two open sessions per table / two open bills per cover are possible** (check-then-insert in the client). | code | schema `[FIX 4,9]`, proven under 30-way concurrency |
| 9 | **Over-indexing:** `item_master` and `item_variant` each carry 12 single-column indexes (mostly on booleans) for ≤ 84 rows. | live `pg_indexes` | schema `[FIX 6]` → 3 + 4 targeted indexes |
| 10 | **Schema drift:** the `supabase_*.sql` files don't match production (`"COMPANY_MASTER"` vs `company_master`, missing `touch_updated_at` triggers, different indexes). | live vs files | this plan uses the **live** schema |
| 11 | **Ambiguous login by email:** two users share `divakaravk11@gmail.com`; the query is `LIMIT 1`. One user has a case-variant duplicate employee code (`DIV01`/`div01`). | live data | login rule §3.4; ETL dedupe |
| 12 | `getActiveKots` never embeds `table_cover`, yet `KotMaster` reads it → cover number is always blank on the kitchen screen. | `models.dart:1195`, service `:1374` | Node API includes it (additive) |
| 13 | **The inventory/stock module cannot work in Supabase mode today.** An `ensure_rls` event trigger auto-enables RLS on every new table; `raw_material`, `variant_recipe`, `stock_ledger` (plus `company_registration`, `super_admin_devices`) have RLS **on with zero policies**, and `anon` does not bypass RLS. Read as `anon`, `company_registration` returns 0 of its 3 rows and `super_admin_devices` 0 of 1. So the app's reads return nothing and, by the same rule, its inserts are rejected — which is why those tables are empty. (The registration flow still works only because it goes through `SECURITY DEFINER` RPCs.) `inventory_module.sql` assumed "no RLS", like the other tables. I verified the read side; I did not attempt an insert. | catalog + anon-role SELECT | Works in Node mode by design; Supabase-mode fix in §8 (not applied) |
| 14 | **Every unpaged Supabase query silently stops at 1,000 rows** (`max_rows: 1000`, read from the live project's PostgREST config). `getBills` (used by all reports and the bills screen) and `getStaffConsumption` have no range, so once a company passes 1,000 bills in the selected period the totals silently under-count. Not hit yet (189 bills in total), but a café doing ~200 bills/day reaches it within a week. | Management-API config read; `supabase_service.dart:959` has no `.range()` | Node API pages server-side (P3); Supabase-mode fix in §8 |

### 1.4 Things I checked that are **not** problems

* `saveItemWithVariants` (delete-all-then-insert variants, which would cascade-delete recipes) is dead code — not ported.
* Bill header vs line items: 0 mismatches on `subtotal` (182/182 reconcile), so historical data is internally consistent
  even where tax handling differs.
* No `UNIQUE` collisions for the new constraints, except 2 data fixes the ETL must make (§6).

---

## 2. Target architecture

```
Flutter screens / providers
        │  Backend.<method>()                     (facade, drop-in for SupabaseService.<method>())
        ▼
 ┌───────────────────────────── USE_SUPABASE (compile-time, default true) ─────────────────────────────┐
 │ true : SupabaseBackend ──► SupabaseService (UNCHANGED) ──► Supabase (PostgREST · Postgres · Storage) │
 │ false: RestBackend ─► ApiClient ──HTTPS/JSON──► Node API (Fastify) ─┬─► MySQL 8.4 (InnoDB)          │
 │                                                                     ├─► Storage adapter (disk | S3)  │
 │                                                                     └─► Firebase Admin (FCM)         │
 └──────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Stack (decisions made for you — say so if you want any changed)

| Concern | Choice | Why |
|---|---|---|
| Runtime | Node 24 LTS (matches your machine, v24.14) + TypeScript | |
| HTTP | **Fastify 5** | fast, schema-first validation/serialization, first-class hooks |
| DB driver | **`mysql2`** (raw SQL, no ORM) | transactions and hand-tuned joins matter here; ORMs would hide the SQL that must match Postgres output |
| Validation | `zod` (request + response) | response schemas also do type coercion (§3.4) |
| Auth | `@fastify/jwt` (HS256, 30-min access) + rotating refresh tokens; **argon2id** via `@node-rs/argon2` (prebuilt binaries, works on Windows) | |
| Money | `decimal.js` for calculations; DB `DECIMAL` | never sum money in JS floats |
| IDs | UUIDv7 (`uuid` v10+) | time-ordered → InnoDB PK locality; generated in Node so no `RETURNING` round-trip |
| Migrations | `umzug` + plain `.sql` files (`0001_init.sql` = `schema.mysql.sql`) | reviewable SQL, no DSL |
| Logging/ops | `pino`, `/healthz`, `/readyz`, request-id, graceful shutdown | |
| Security plugins | `@fastify/helmet`, `cors`, `rate-limit`, `compress` (gzip/br), `multipart` | |
| Push | `firebase-admin` (replaces the Deno Edge Function + DB webhook) | |
| Tests | `vitest` + real MySQL 8.4 (docker-compose service in CI) | mocks would not have caught the issues found in §9 |
| DB | **MySQL 8.4 LTS** (8.0 reached end-of-life April 2026). MariaDB is not targeted (untested: `LATERAL`, generated-column unique indexes) | |

### 2.2 Backend layout

```
backend/
  package.json  tsconfig.json  Dockerfile  docker-compose.yml  .env.example
  db/migrations/0001_init.sql   0002_billing_tax_mode.sql (P8)      db/seeds/dev.sql
  scripts/  migrate.ts  migrate-from-supabase.ts  verify-migration.ts
  src/
    server.ts  app.ts  config.ts                    # env validated by zod, fail-fast
    plugins/  db.ts  auth.ts  rbac.ts  idempotency.ts  errors.ts  rate-limit.ts  storage.ts
    lib/      tx.ts  ids.ts  money.ts  tax.ts  numbering.ts  serialize.ts
    modules/  auth  users  company  items  tables  covers  orders  bills  kitchen  inventory  registration  uploads  push
              └─ each: routes.ts · service.ts · repo.ts (SQL only) · schemas.ts (zod)
  test/       unit · integration (real MySQL) · contract fixtures · load (autocannon)
```

---

## 3. Database

The complete DDL is **`schema.mysql.sql`** (25 tables + 2 views, validated — see §9). Same table and column names as
Supabase so the models, the ETL and your mental model carry over.

### 3.1 Type mapping

| Postgres | MySQL | Notes |
|---|---|---|
| `uuid` | `CHAR(36) ascii_bin` | readable, byte-identical JSON, case-exact; UUIDv7 keeps inserts ordered |
| `timestamptz` | `DATETIME(3)` in **UTC** | `time_zone='+00:00'` on every connection; avoid `TIMESTAMP` (2038 limit, session-tz conversion) |
| `numeric(p,s)` | `DECIMAL(p,s)` | same precision as live; stock tables get more scale (§3.3) |
| `boolean` | `TINYINT(1)` | needs the driver cast in §3.4 |
| `text` | `VARCHAR(n)` if short/indexed, else `TEXT` | sizes chosen from live max lengths with headroom |
| partial unique index | generated `VIRTUAL` column + `UNIQUE` | MySQL has no partial indexes; `UNIQUE` ignores `NULL` |

### 3.2 Corrections applied in the MySQL schema (tagged `[FIX n]` in the DDL)

| Tag | Change vs Supabase | Why | Live data conflict? |
|---|---|---|---|
| 1 | `user_profiles.password` → `password_hash` (argon2id) + `token_version`, `failed_logins`, `locked_until` | plaintext passwords; needed for lockout/revocation | ETL hashes; 1 password is < 8 chars (report it) |
| 2 | `employee_code` unique **per company** (was global) | two cafes can reuse codes | **1 conflict:** `DIV01` vs `div01` (same company) → ETL renames the later one `div01-2` |
| 3 | `table_master`: `UNIQUE(company_id, table_number)` | duplicates were allowed | none |
| 4 | `table_session.open_table_key` generated + `UNIQUE` | at most **one open session per table**, DB-enforced | none (0 today) |
| 5 | `item_master`: `UNIQUE(company_id, item_code)` (was global) | multi-tenant correctness | none |
| 6 | 12+12 single-column indexes → 3 + 4 composites matching real queries | write cost, no read benefit | — |
| 7 | `item_variant.default_key` generated + `UNIQUE` (+ `UNIQUE(item_id, variant_name)`) | exactly one default variant per group | none |
| 8 | `bill_master`: `UNIQUE(company_id, bill_number)` (was global) | | 8 legacy numbers `BL-2026…` are unique already |
| 9 | `bill_master.open_cover_key` generated + `UNIQUE` | one open bill per cover | none |
| 10 | `kot_master`: `UNIQUE(company_id, kot_number)` (had **no** constraint) | duplicates exist | **5 pairs** → ETL suffixes later ones `-D2` |
| 11 | `bill_counter`, `kot_counter` | atomic, **gapless** numbering (rollback burns no number — required for GST invoice series) | seeded from live max (COMP001 / 2026-27 → 195) |
| — | `auth_session`, `idempotency_key`, `audit_log` (new) | refresh tokens/revocation; safe retries; who cancelled/edited what | new |
| — | `item_master.default_variant_id` has **no FK** | Supabase uses a `DEFERRABLE` circular FK, MySQL can't; service validates it and clears it before a group delete (delete cascades cleanly — tested) | — |
| — | `updated_at` via `ON UPDATE CURRENT_TIMESTAMP(3)` | the `touch_updated_at` triggers were never applied in production | — |
| — | `bill_item.kot_status` kept but unused | all 382 rows are `'pending'`; the KDS uses `kot_item.status` | — |

`raw_material` intentionally has **no** `UNIQUE(company_id, name)`: the app soft-deletes (`is_active=false`), so re-creating
a deleted "Milk" would collide.

### 3.3 Precision decisions

`bill_*` amounts `DECIMAL(12,2)`, rates `DECIMAL(10,2)`, qty `DECIMAL(8,3)` — identical to live. Inventory (empty today):
`stock_ledger.qty DECIMAL(16,6)` because recipe qty (4 dp) × sold qty (3 dp) needs 7 dp; verified that `0.03125` survives
exactly.

### 3.4 Driver settings that make MySQL output match PostgREST JSON  *(all verified in `verify/`)*

```ts
// src/plugins/db.ts
const typeCast = (field, next) => {
  const v = next();                                                   // MUST call next() first
  return field.type === 'TINY' && field.length === 1 && v !== null    // TINYINT(1) → boolean
    ? v === 1 || v === '1' : v;
};
export const pool = mysql.createPool({
  host, port, user, password, database,
  connectionLimit: 20, waitForConnections: true, queueLimit: 200,
  timezone: 'Z',            // DATETIME(3) ⇄ JS Date as UTC → JSON "…T…Z"
  decimalNumbers: true,     // DECIMAL → number (Dart does `as num?`); default would be a string
  typeCast,
});
pool.pool.on('connection', c => c.query("SET time_zone='+00:00'"));
```

Gotchas found by running it:

* **Don't use `field.string()` in `typeCast`.** It looks right, but it silently corrupts the *next* column
  (a following `BIGINT` came back as `792633534417207300` under `execute`, `NaN` under `query`). Always `next()` then convert.
* **Booleans from expressions are numbers**, not `TINYINT(1)` (`is_low_stock`, `(s.id IS NOT NULL) AS is_occupied`).
  Coerce them in the response schema, or Dart's `as bool?` throws.
* **Money rounding matches Postgres** with plain numeric binds (13 boundary values incl. `1.005→1.01`, `2.675→2.68`,
  `0.375→0.38`: 0 mismatches for `execute(number)`, `execute(string)` and `query(number)`). No string-binding workaround
  is needed for storage; still *calculate* with `decimal.js` and round once (`ROUND_HALF_UP`).
* `ORDER BY table_number` sorts as text (`T1, T10, T2`) — same as today; kept for parity.
* Login match uses `=` (never `LIKE`), so a typed `%`/`_` can't act as a wildcard (Supabase's `.or('username.ilike.$input…')`
  interpolates raw input into the filter string). Collation is case-insensitive → same result as Postgres `ILIKE`.

### 3.5 Patterns to use (all executed against MySQL 8.4)

```sql
-- Atomic, gapless bill number — call as the LAST write before COMMIT so the counter row is locked briefly.
INSERT INTO bill_counter (company_id, fy, last_seq) VALUES (?, ?, LAST_INSERT_ID(1))
  ON DUPLICATE KEY UPDATE last_seq = LAST_INSERT_ID(last_seq + 1);      -- result.insertId = the number
-- 40 concurrent cold-key + 40 warm-key allocations: unique, gapless, no deadlocks; a rollback burns nothing.
```
```ts
// Race-free "get or create the open session" — relies on uq_session_one_open_per_table
try { await pool.execute('INSERT INTO table_session (id, table_id, opened_by, company_id) VALUES (?,?,?,?)', …); }
catch (e) { if (e.code !== 'ER_DUP_ENTRY') throw e;
            [[s]] = await pool.execute("SELECT id FROM table_session WHERE table_id=? AND status='open'", [tableId]); }
// 30 parallel calls on one table → exactly 1 open row, all callers got the same id.
```
```sql
-- getTables: replaces 5 client round-trips + Dart aggregation with ONE query (uses the unique index)
SELECT t.*, s.id AS active_session_id, s.opened_at, (s.id IS NOT NULL) AS is_occupied,
       COALESCE(b.total,0) AS active_order_total, COALESCE(c.cnt,0) AS active_cover_count
  FROM table_master t
  LEFT JOIN table_session s ON s.open_table_key = t.id
  LEFT JOIN LATERAL (SELECT SUM(total_amount) total FROM bill_master WHERE table_session_id=s.id AND status='open') b ON TRUE
  LEFT JOIN LATERAL (SELECT COUNT(*) cnt FROM table_cover WHERE table_session_id=s.id AND status='active') c ON TRUE
 WHERE t.company_id = ? ORDER BY t.table_number;
```

Also wrap every transaction in a helper that retries `ER_LOCK_DEADLOCK (1213)` and `ER_LOCK_WAIT_TIMEOUT (1205)` up to 3×
with jitter.

---

## 4. API design

### 4.1 Principles

1. **Contract = today's JSON.** Column names, snake_case, nested embeds (`company_hsn`, `item_variant`, `bill_item`,
   `table_session.table_master`, `table_cover`, `kot_item.bill_item`) stay identical. Numbers are numbers, booleans are
   booleans, timestamps ISO-8601 UTC.
2. **Tenant from the token, never from the request.** `company_id` in JWT claims; the Dart calls still pass `companyId`,
   the server ignores/validates it (403 on mismatch, `owner` role excepted where documented). This *is* the RLS replacement.
3. **One request = one transaction** for anything multi-step (order+KOT, checkout, bill edit, default variant).
4. **Prices and totals computed server-side** (P3 parity mode accepts the client's numbers where the client owns them
   today, and records deviations in `audit_log`; P8 decides enforcement).
5. **Idempotent writes** for `POST /orders/kot`, `POST /bills`, checkouts via `Idempotency-Key`.
6. **Errors:** `{ "error": { "code", "message" }, "request_id" }` with 400/401/403/404/409/429/5xx.
7. Polling stays; hot GETs support `ETag`/`If-None-Match` (→ `304`) and gzip. Bills are keyset-paginated server-side while the
   Dart adapter loops pages so callers still get one list.

### 4.2 Endpoint map — every `SupabaseService` method the UI uses → route

*(`§` = notes; all under `/v1`, all require a bearer token unless marked **public**.)*

| Area | Dart method → route | Notes |
|---|---|---|
| **Auth** | `signInWithUserMaster` → `POST /auth/login` **public** | body `{input, password, forceLogin}`; returns `{access_token, refresh_token, expires_in, profile}`; `profile` = today's row **minus password**. Codes map back to the exact strings the login screen matches: `NO_ACCOUNT`, `ACCOUNT_INACTIVE`, `BAD_PASSWORD`, `ALREADY_LOGGED_IN` |
| | `getUserSessionStatus` → `GET /auth/session` | `{user_active,is_login,last_login}` — same 20 s guard |
| | `setLoginStatus(false)` / `signOut` → `POST /auth/logout` | revokes refresh token, `is_login=0` |
| | *(new)* `POST /auth/refresh` | rotating refresh token, single-flight in the client |
| | `changePassword` → `POST /auth/change-password` | verifies current password server-side; bumps `token_version` |
| **Users** | `getUsersForCompany` → `GET /users` · `getUserPermissions` → `GET /users/:id/permissions` | |
| | `upsertUserWithPermissions` → `POST /users` (new) / `PUT /users/:id` | accepts `password`, hashes it, never returns it; column whitelist |
| | *(direct client)* force-logout → `POST /users/:id/force-logout` | sets `user_active=0,is_login=0`, revokes sessions, audit-logged |
| | *(direct client)* own profile → `PATCH /users/me` | only name/phone/email/avatar |
| | `uploadAvatar` → `POST /uploads/avatar` | multipart; returns URL |
| **Company** | `getCompany` → `GET /company` · `updateCompany` → `PATCH /company` | column whitelist; owner may address `/companies/:id` |
| | `getCompanyHsns` → `GET /company/hsn` | |
| **Items** | `getItemGroups` / `getAllItems` → `GET /items?order=display\|name` | groups + `item_variant[]` (+ nested `company_hsn`) — 3 queries assembled in Node (not a row-exploding join); ETag + gzip |
| | `getVariantsByGroup` → `GET /items/:id/variants?sellable=1` | |
| | *(direct client)* save group → `PUT /items/:id` | with `create_default_variant:true` the server creates the "Default" variant and sets `default_variant_id` atomically (replaces 3 client calls) |
| | `deleteItemMaster` → `DELETE /items/:id` | clears `default_variant_id` first, in a tx |
| | `upsertVariant` → `PUT /variants/:id` · `deleteVariant` → `DELETE /variants/:id` | |
| | `setDefaultVariant` → `POST /items/:id/default-variant` | one tx instead of 3 updates |
| | `uploadItemImage` → `POST /uploads/item-image` | content-hash filename ⇒ no stale CDN cache (Supabase reuses one path) |
| **Tables** | `getTables` → `GET /tables` | returns `{server_now, tables[]}`; the Dart adapter re-anchors `occupied_since` to the device clock exactly as today |
| | `createTable` → `POST /tables` · `updateTable` → `PATCH /tables/:id` · `isTableOccupied` → `GET /tables/:id/occupied` | `PATCH` also rejects with 409 if occupied (server-side guard) |
| **Covers** | `getCoversForSession` → `GET /sessions/:id/covers` · `getCoverTotals` → `GET /sessions/:id/cover-totals` · `getDetailedItemsForSession` → `GET /sessions/:id/items` | last one is 3 client queries today → 1 join |
| | `createCover` → `POST /sessions/:id/covers` · `deleteCover` → `DELETE /covers/:id` · `checkoutCover` → `POST /covers/:id/checkout` | checkout = one tx; closes the session when no active cover remains |
| **Orders** | `createOrder` → `POST /sessions` | |
| | `saveOrderWithKot` → `POST /orders/kot` | **idempotent**; the big transaction (§4.3); returns `{sessionId, coverId, kotId, kotNumber, billId}` |
| | `getOrderSummaryForTable` → `GET /tables/:id/order-summary` · `checkoutTable` → `POST /tables/:id/checkout` | |
| **Bills** | `createBill` → `POST /bills` | **idempotent**; server allocates the number (counter) |
| | `getBills` → `GET /bills?from&to&cursor&limit` (and `page&size&sort&q` for the web data table — see `../web-view/PLAN.md` §3.4) | includes `bill_item`, `table_session.table_master`, `table_cover` embeds; the Dart adapter loops cursor pages so callers of the old method still get one full list |
| | `cancelBill` → `POST /bills/:id/cancel` · `updateBill` → `PATCH /bills/:id` | one tx each; both write `audit_log` |
| **Kitchen** | `getActiveKots` → `GET /kots?since=` | now also embeds `table_cover` (fixes #12); ETag for the 20 s poll |
| | `updateKotStatus` → `PATCH /kots/:id` · `updateKotItemStatus` → `PATCH /kot-items/:id` | |
| **Inventory** | `getRawMaterials` `GET /inventory/materials` · `upsertRawMaterial` `PUT …/:id` · `deleteRawMaterial` `DELETE …/:id` (soft) · `countRecipeLinesUsingMaterial` `GET …/:id/recipe-usage` | |
| | `getRecipeForVariant` `GET /inventory/recipes?variant_id=` · `upsertRecipeLine` `PUT …/:id` · `deleteRecipeLine` `DELETE …/:id` | |
| | `getCurrentStock` `GET /inventory/stock` · `submitStockAdjustment` `POST /inventory/adjustments` | |
| | `getStaffConsumption` `GET /inventory/staff-consumption?from&to&staff_id` | real `GROUP BY` in SQL — the Dart code aggregates client-side today |
| **Registration** | `requestCompanyRegistration` → `POST /public/registrations` **public** · `verifyCompanyRegistrationOtp` → `POST /public/registrations/:id/verify` **public** | rate-limited per IP + email; OTP via `crypto.randomInt`; 5 attempts, 10 min |
| | first admin → `upsertUserWithPermissions(isNew)` → `POST /public/registrations/:id/admin` | requires the single-use **registration token** returned by `verify`; `RestBackend` keeps it in memory |
| **Owner** | `listCompanyRegistrations` → `GET /owner/registrations` · `approveCompanyRegistration` → `POST /owner/registrations/:id/approve` · `registerSuperAdminDevice` → `PUT /owner/devices` | **`role=owner` only** (Supabase: anon) |
| **Ops** | — | `GET /healthz`, `GET /readyz`, `GET /time` |

### 4.3 `POST /orders/kot` — the core transaction (replaces ~10 client requests)

```
BEGIN
 1  get-or-create the OPEN session for the table          (INSERT → on dup SELECT; §3.5)
 2  resolve cover: explicit id, else get-or-create "Cover 1"  (UNIQUE session+number)
 3  validate item/variant ids belong to the company and are active; build bill_item rows
    (UUIDv7 generated in Node ⇒ no RETURNING round-trip; GST split identical to the client's today)
 4  get-or-create the OPEN bill for (session, cover)       (uq_bill_one_open_per_cover)
      new  → allocate bill_number (counter) LAST
      old  → SELECT … FOR UPDATE
 5  INSERT bill_items (multi-row)
 6  bill totals := SUM over bill_items  (recomputed in SQL — not "previous + new", so no drift)
 7  allocate kot_number (kot_counter, company-local business date)
 8  INSERT kot_master + kot_items
 9  stock: INSERT INTO stock_ledger … SELECT … FROM kot_item ⨝ bill_item ⨝ variant_recipe   (replaces the Postgres trigger;
    UNIQUE(kot_item_id, raw_material_id) makes a retry harmless)
COMMIT   → response cached under the Idempotency-Key
```

### 4.4 Not ported (dead code in `SupabaseService`)

`addOrderItems`, `closeOrder`, `getOpenOrders` (queries non-existent `orders`/`order_items`), `getCompanyUiSettings`
(non-existent `company_ui_settings`), `getUserUiPreference`, `setUserUiPreference`, `getPrintSettings`, `saveItemWithVariants`,
`getMasterItemsForVariants`, `getDefaultVariant`, `getEffectiveRate`, `deleteItem`, `updateTableStatus`, `getProfile`.
Print-config and preference endpoints are a 30-minute addition if you start using them.

### 4.5 Auth and permissions

* Login: argon2id verify; 5 failed attempts → 15-min lock; `forceLogin` semantics preserved
  (`ALREADY_LOGGED_IN` unless forced). Email login only when it matches **exactly one** user (else "use your username").
* JWT claims `{sub, cid, role, sid, tv}`; `tv` (= `token_version`) is checked through a 10-s in-process cache, so a
  force-logout / password change kills the old token within seconds.
* Refresh tokens: 30-day, rotating, stored as SHA-256 in `auth_session`; reuse of a rotated token revokes the session.
* Permission flags (`can_create_bill`, `can_cancel_bill`, `can_manage_items`, …) are enforced **server-side** by
  `requirePerm()`. It ships in **log-only mode** (P3) and is switched to enforce in P8 after comparing the log against
  the `home_shell` gating — otherwise a flag mismatch would lock a real cashier out at the counter. `admin` bypasses (as the app does).
* Distinct "no account" / "wrong password" messages are kept for UX parity (rate-limited). Say so if you'd rather return one generic message.

---

## 5. Flutter changes (Phase 1 + 6)

```
lib/core/backend/
  app_config.dart          static const useSupabase = bool.fromEnvironment('USE_SUPABASE', defaultValue: true);
                           static const apiBaseUrl  = String.fromEnvironment('API_BASE_URL');
  pos_backend.dart         abstract interface class PosBackend { …57 methods, same signatures as SupabaseService… }
  backend.dart             final facade:  Backend.getTables(companyId) => _i.getTables(companyId)  (static, drop-in)
  supabase_backend.dart    implements PosBackend by delegating 1:1 to SupabaseService            ← Supabase mode
  rest/ api_client.dart · token_store.dart · error_mapper.dart · rest_backend.dart              ← Node mode
```

* **Facade** (`static final PosBackend _i = AppConfig.useSupabase ? SupabaseBackend() : RestBackend();`) lets the 26 call
  sites change by mechanical find-and-replace `SupabaseService.` → `Backend.`. `const` flag ⇒ the unused branch tree-shakes.
* `supabase_service.dart` receives **only additions**: 4 methods (`forceLogoutUser`, `updateOwnProfile`, `saveItemGroup`,
  `setGroupDefaultVariantPointer`) containing the code lifted verbatim from the 3 screens. Supabase behaviour is unchanged.
* `main.dart`: `await Backend.init()` (Supabase → `Supabase.initialize`; REST → load tokens). `PushService` registers via `Backend`.
* **Errors:** `RestBackend` throws `ApiException` (already passed through by `_classify` in `api_helper.dart:56`), with the same
  user-facing messages (`23505` → "Duplicate entry…", 403 → "Permission denied."). Login failures are re-thrown as the *same
  strings* today's login screen matches (`'ALREADY_LOGGED_IN'`, "Incorrect password…").
* **Tokens:** access token in memory, refresh token in `flutter_secure_storage` (only new dependency; `http` is already present).
  Single-flight refresh on 401. `Idempotency-Key` (UUID) attached to order/bill/checkout POSTs and reused on retry.
* `getTables` adapter recomputes `occupied_since` from `server_now` (existing anchoring logic moves into the adapter unchanged).
* Add two launch configs to `.vscode/launch.json` (Supabase / Node).

---

## 6. Data migration (Phase 7)

`backend/scripts/migrate-from-supabase.ts` — idempotent (`INSERT … ON DUPLICATE KEY UPDATE`), batch 500, dependency-ordered:
`company_master → company_hsn → company_print_config → user_profiles → user_permission → user_preference → table_master →
table_session → table_cover → item_master → item_variant → (item_master.default_variant_id) → bill_master → bill_item →
kot_master → kot_item → raw_material → variant_recipe → stock_ledger → company_registration → super_admin_devices → counters`.

| Rule | Detail |
|---|---|
| Source access | `pg` with a **read-only role** (`create role etl_ro …; grant select on all tables in schema public`) — not the token/service key |
| Passwords | hash every plaintext password with argon2id during import; users keep their current password. Report the 1 password < 8 chars. **Rotate the seeded owner password (`Owner@123`) at cutover.** |
| Data fixes | `DIV01`/`div01` → second becomes `div01-2`; 5 duplicate KOT numbers → later ones suffixed `-D2`; every rename is logged to `migration-report.json` |
| Bills | copied **verbatim** — never recompute historical totals (58 don't reconcile; that's history, not a bug to "fix") |
| Counters | `bill_counter` seeded from `MAX(seq)` of canonical numbers per company/FY (COMP001 · 2026-27 → 195); the 8 legacy `BL-2026…` numbers are ignored |
| Timestamps | `timestamptz` → `DATETIME(3)` UTC (µs truncated to ms) |
| Storage | copy 43 + 1 objects preserving `<bucket>/<path>`; rewrite `image_url`/`avatar_url`/`logo_url` by prefix `https://vsbjkytdqhzbtideebwy.supabase.co/storage/v1/object/public/` → `${PUBLIC_ASSET_BASE_URL}/` |
| Verification (`verify-migration.ts`) | row counts vs §1.2; per-company `SUM(total_amount)` by status; `COUNT(DISTINCT bill_number)`; FK orphan queries; field-by-field diff of 20 random bills + all KOTs; a Supabase-vs-Node JSON shape diff for the 12 read endpoints |

---

## 7. Phases in detail

Every phase ends with **exit criteria** that must pass before the next one starts.

### Phase 0 — Security hygiene  *(do first, ~0.5 d — needs you; I did not do any of it)*
1. **Revoke the Supabase access token you pasted in chat** (Dashboard → Account → Access Tokens). I used it only for read-only
   catalog/`SELECT` queries and did not store it, but it is in this session's transcript.
2. **Rotate the leaked keys** (`service_role`, secret key). Note: rotating the legacy JWT secret also changes the **anon** key
   baked into `app_constants.dart` — plan an app release, or migrate to Supabase's new publishable/secret keys.
3. `git rm --cached fix_auth.js api_keys.json`; add both to `.gitignore`; delete or rewrite `fix_auth.js` to read env vars.
4. Purge them from history (`git filter-repo`) + force-push **only after you decide** (rewrites `origin`; teammates must re-clone).
   Check whether the GitHub repo is public (I couldn't — `gh` isn't installed here). If public, treat every key as already stolen.
5. Change seeded passwords (`Owner@123`, `Admin@123`); move the bearer credential hard-coded in the `notify_company_registration()`
   DB function into Supabase Vault.
6. Interim (until cutover), accept that #1 in §1.3 remains open in Supabase mode — closing it needs the Node API.

**Exit:** `git log -S"eyJ" --all` finds no key; old keys return 401.

### Phase 1 — Flutter abstraction, Supabase path unchanged  *(2 d)*
`app_config.dart`, `PosBackend`, `SupabaseBackend`, `Backend` facade; add the 4 methods to `SupabaseService`; codemod the 26
files; `main.dart`; launch configs; a stub `RestBackend` that throws `UnimplementedError`.
**Exit:** `flutter analyze` has no new issues; `git diff supabase_service.dart` is additions only; manual smoke of Supabase mode
(login → tables → KOT → bill → reports → KDS → each admin screen) is identical to before.

### Phase 2 — Node foundation, MySQL, auth  *(4 d)*
Scaffold (§2.2); env validation; pool + migrator; `0001_init.sql`; docker-compose (`mysql:8.4` + api); dev seed; auth module
(login/refresh/logout/session/change-password, lockout, sessions); tenant + `requirePerm` plugins; error envelope; response
mapper (bool coercion); health endpoints; CI (lint, typecheck, tests against a MySQL service container).
**Exit:** curl login → refresh → logout works; tenant-isolation test (company A token can't read B) passes; `schema-check` passes in CI.

### Phase 3 — Core POS API  *(7 d — the risky one)*
Items (ETag/gzip), tables (single query), covers, sessions, `POST /orders/kot`, checkouts, `POST /bills`, bill list/cancel/edit,
KOT list/status, counters, idempotency plugin, stock-deduction step, audit log. **Tax parity first:** each path reproduces its
current arithmetic (`createBill` accepts the client's total; the KOT path computes subtotal+CGST+SGST) — replay the live
bills' line items through the calculator as a golden test that **reports** every bill whose stored total it cannot reproduce
(expect the 58 from #5) rather than asserting all 189 match.
**Exit:** contract fixtures parse through `Item`, `CafeTable`, `Bill`, `KotMaster`, `TableCover` unchanged; concurrency suite
(30 parallel saves → 1 session; 50 parallel bills → 50 gapless numbers; replayed Idempotency-Key → same response) green.

### Phase 4 — Admin API  *(4 d)*
Company + HSN + print config; users/permissions (hash, whitelist, force-logout, audit); table master; item group/variant CRUD
(atomic default variant); inventory (materials, recipes, ledger, stock, staff-consumption `GROUP BY`); uploads behind a
`StorageAdapter` (`local` now, S3-compatible later; 5 MB cap, MIME sniffing, content-hash names).
**Exit:** every admin screen has a passing API test; PII (`aadhaar_no`, `pan_no`) only returned to admins.

### Phase 5 — Registration, owner, push  *(2 d)*
Public registration + OTP + registration token + first-admin endpoint; owner-only list/approve/device endpoints; FCM via
`firebase-admin` (port of the Edge Function incl. pruning dead tokens; sent **after** commit; no-op if Firebase isn't configured,
mirroring `PushService`'s guard). Firebase project + `google-services.json` are still pending on your side (see memory note) —
independent of this migration.
**Exit:** register → OTP → verify → create admin → login works end-to-end; anon can no longer list OTPs or approve.

### Phase 6 — Flutter `RestBackend`  *(5 d, overlaps 3–5)*
`ApiClient`, `TokenStore`, error mapper, one method per `PosBackend` method (§4.2), multipart uploads, table-time anchoring,
paginated bill loop, idempotency keys. Add `verify/` fixtures → Dart tests that parse **Supabase fixtures and Node fixtures
through the same `fromJson` and assert equal objects**.
**Exit:** every screen works with `USE_SUPABASE=false` against the local stack; checklist in §8 fully ticked.

### Phase 7 — Migration  *(3 d)* — see §6. **Exit:** dry-run on a copy: all verification queries green, twice in a row (idempotent).

### Phase 8 — Hardening  *(3 d)*
Switch RBAC to enforce; decide catalog-price enforcement; **billing tax mode** (`0002_billing_tax_mode.sql`: `company_master.prices_include_tax`,
`bill_master.tax_mode`, `round_off`) + one calculator for both paths (**needs your accounting decision**: inclusive or exclusive; §1.3 #5);
slow-query review with `EXPLAIN`; load test (autocannon: 50 devices polling `/kots` + `/auth/session` every 20 s + bursts of
10 bills/s; target p95 < 100 ms locally); helmet/CORS/rate-limit tuning; backups (nightly `mysqldump` + binlog PITR) **and a
restore drill**; log/uptime alerts; `npm audit`; OWASP API Top-10 pass.
**Exit:** load-test and restore-drill reports attached; zero high findings.

### Phase 9 — Cutover  *(2 d)*
1. Announce a ~30-min window; put Supabase in read-only (revoke `anon` writes).
2. Final ETL → verification → smoke on production API.
3. Ship the `USE_SUPABASE=false` build (production `API_BASE_URL`).
4. Keep Supabase intact 30 days. **Rollback = ship the Supabase build**, valid until the first MySQL write; after that,
   going back needs a reverse ETL (not planned — the data is small enough to script in a day if you want the option).
5. Rotate the owner password; pause the Supabase project after the fallback window; delete the leaked keys.

---

## 8. Testing strategy and smoke checklist

* **Unit:** tax/discount calculator (golden: 189 live bills), numbering, money, serializer coercion.
* **Integration (real MySQL 8.4):** every route; tenant isolation matrix; permission matrix; concurrency (sessions, covers,
  bill/KOT counters, idempotency); rollback burns no number; deadlock-retry helper.
* **Contract:** Supabase-vs-Node JSON shape diff (types, nullability, key set) for the 12 read endpoints; Dart `fromJson` parity tests.
* **Load:** as Phase 8.
* **Manual smoke (both modes, before every release):** login/force-login/logout · owner dashboard · register company + OTP ·
  tables (occupied timer) · add items → KOT · second cover · checkout cover/table (cash/UPI/card, discount %) · quick bill ·
  reports incl. cancel + edit bill · KDS status changes · item group/variant CRUD + image · user CRUD/permissions/force-logout ·
  company settings · table master · raw material/recipe/stock/day-end/shift handover.

### Optional fixes for Supabase mode — **not applied** (you asked me not to touch it)
| Fix | Effort |
|---|---|
| Make `_generateBillNumber` compare the numeric suffix (or move numbering to a Postgres sequence) — otherwise the 1000th bill of a FY per company fails | 15 min |
| Strip `password` from the profile JSON before caching it in `SharedPreferences` (`UserProfile.fromJson` never reads it) | 5 min |
| Embed `table_cover(cover_number,label)` in `getActiveKots` so the KDS shows the cover | 5 min |
| Dedupe KOT numbers, then `UNIQUE(company_id, kot_number)` | 20 min |
| Page `getBills` / `getStaffConsumption` in chunks of ≤ 1,000 with `.range()` (or raise `max_rows` in Supabase settings) so reports stop silently truncating (#14) | 30 min |
| Make the stock module work in Supabase mode (#13): add permissive policies on `raw_material`, `variant_recipe`, `stock_ledger` (or `DISABLE ROW LEVEL SECURITY` like the other tables). **Trade-off:** it opens those tables to anyone holding the anon key, exactly like `bill_master` today — so I'd only do it if you need inventory before cutover | 10 min |

---

## 9. What was verified, and what was not

**Verified by running it** (`docs/backend-migration/verify/`, throw-away MySQL **8.4.9**; re-run with `npm i && npm run mysql`, then
`npm run check:schema && npm run check:behaviour && npm run check:driver`):

* DDL executes cleanly: 25 tables, 2 views, generated columns, CHECKs, FKs — **28/28** schema/constraint checks pass
  (per-company uniqueness, one open session/bill, one default variant, CHECK enforcement, cascade delete with a set
  `default_variant_id`, idempotent ledger rows, counters under 40-way concurrency cold *and* warm, rollback gaplessness, driver casts).
* **7/7** behaviour checks: 30 parallel get-or-create → 1 session; single-query `getTables` (correct values, index used, text ordering kept);
  login case-insensitivity and no wildcard.
* Driver: the `typeCast` pitfall (§3.4) and money-rounding parity (13/13 boundary values).

**Not verified — be aware:**
* No Node API, Flutter, or ETL code exists yet; everything in §4–§7 is design. Effort figures are estimates.
* MariaDB compatibility, real-network latency, and MySQL performance under production load were not tested.
* The live data findings are a 2026-09-19 snapshot; re-run the §1.3 queries before the ETL.
* The inclusive-vs-exclusive GST question (#5) is an accounting decision I can't make from the data.

## 10. Decisions I made so you didn't have to answer questions (change any of them)

1. Flag is **compile-time** `USE_SUPABASE`, default `true` → every existing build/run command keeps using Supabase.
2. Node 24 + Fastify + TypeScript; MySQL **8.4** (not MariaDB); raw SQL via `mysql2`.
3. Node returns **PostgREST-identical JSON**; Flutter models untouched.
4. UUID primary keys kept (UUIDv7 generated server-side).
5. Passwords hashed with argon2id at migration; users keep their current password.
6. Historical bills are never recomputed; tax-mode unification is deferred to Phase 8.
7. RBAC starts log-only, enforced in Phase 8. Distinct login error messages kept.
8. Storage on local disk behind an adapter (S3-compatible later); image URLs rewritten during ETL.
9. Polling (20 s) kept with ETag/304; SSE/WebSocket only if the kitchen screen needs sub-second updates.

## Appendix — environment variables (`backend/.env.example`)

```
NODE_ENV=production            PORT=3000               LOG_LEVEL=info
DB_HOST=…  DB_PORT=3306  DB_USER=…  DB_PASSWORD=…  DB_NAME=cafe   DB_POOL_SIZE=20
JWT_ACCESS_SECRET=<32+ random bytes>   ACCESS_TTL=30m   REFRESH_TTL_DAYS=30
CORS_ORIGINS=https://…         RBAC_ENFORCE=false      IDEMPOTENCY_TTL_HOURS=24
STORAGE_DRIVER=local|s3        UPLOAD_DIR=/var/lib/cafe/uploads   PUBLIC_ASSET_BASE_URL=https://cdn.example.com
FIREBASE_PROJECT_ID=…  FIREBASE_CLIENT_EMAIL=…  FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n…"
```
