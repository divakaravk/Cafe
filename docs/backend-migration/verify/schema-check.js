const mysql = require('mysql2/promise');
const fs = require('fs');
const crypto = require('crypto');
const conn = JSON.parse(fs.readFileSync(require('path').join(__dirname, 'conn.json')));
const ddl = fs.readFileSync(require('path').join(__dirname, '..', 'schema.mysql.sql'), 'utf8');
const id = () => crypto.randomUUID();
let pass = 0, fail = 0;
const ok = (name, cond, extra = '') => { (cond ? pass++ : fail++); console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  -> ' + extra : '')); };
const rejects = async (name, p, code) => {
  try { await p; ok(name, false, 'expected error, got success'); }
  catch (e) { ok(name, !code || e.code === code, e.code + ' ' + (e.sqlMessage || '').slice(0, 70)); }
};

// Same driver settings the Node API will use.
const typeCast = (field, next) => { const v = next(); return (field.type === 'TINY' && field.length === 1 && v !== null) ? (v === 1 || v === '1') : v; };

(async () => {
  const base = { host: '127.0.0.1', port: conn.port, user: 'root' };
  const admin = await mysql.createConnection({ ...base, database: 'cafe', multipleStatements: true });
  console.log('server:', JSON.stringify((await admin.query('select version() v, @@sql_mode m'))[0][0]));
  await admin.query('DROP DATABASE cafe; CREATE DATABASE cafe CHARACTER SET utf8mb4; USE cafe;');
  try { await admin.query(ddl); ok('DDL executes on MySQL 8.4 (tables, generated cols, CHECKs, views)', true); }
  catch (e) { ok('DDL executes', false, e.sqlMessage); console.log(e); process.exit(1); }
  const [t] = await admin.query("select count(*) n from information_schema.tables where table_schema='cafe' and table_type='BASE TABLE'");
  const [v] = await admin.query("select count(*) n from information_schema.tables where table_schema='cafe' and table_type='VIEW'");
  ok('tables/views created', v[0].n === 2, `${t[0].n} tables, ${v[0].n} views`);
  await admin.end();

  const pool = mysql.createPool({ ...base, database: 'cafe', timezone: 'Z', decimalNumbers: true, typeCast, connectionLimit: 20 });
  pool.pool.on('connection', c => c.query("SET time_zone='+00:00'"));
  const q = (s, p) => pool.execute(s, p);

  // ---- seed
  const co = id(), co2 = id(), u = id(), tbl = id();
  for (const [c, code] of [[co, 'COMP001'], [co2, 'COMP002']]) await q('INSERT INTO company_master (id, company_code, company_name) VALUES (?,?,?)', [c, code, code]);
  const user = (cid, code, uname) => q('INSERT INTO user_profiles (id, company_id, employee_code, user_name, username, password_hash, user_role) VALUES (?,?,?,?,?,?,?)', [cid === co && code === 'DIV01' && uname === 'divakar' ? u : id(), cid, code, 'A', uname, 'x', 'waiter']);
  await user(co, 'DIV01', 'divakar');
  await q('INSERT INTO table_master (id, company_id, table_number) VALUES (?,?,?)', [tbl, co, 'T1']);

  // ---- FIX 2
  await rejects('FIX2 employee_code DIV01 vs div01 in one company rejected (ETL must dedupe the 1 live case)', user(co, 'div01', 'other'), 'ER_DUP_ENTRY');
  await user(co2, 'DIV01', 'third');
  ok('FIX2 same employee_code allowed in a DIFFERENT company', true);

  // ---- FIX 4: one open session per table
  const s1 = id();
  const sess = (sid, status = 'open') => q('INSERT INTO table_session (id, table_id, opened_by, company_id, status) VALUES (?,?,?,?,?)', [sid, tbl, u, co, status]);
  await sess(s1);
  await rejects('FIX4 second OPEN session on the same table rejected', sess(id()), 'ER_DUP_ENTRY');
  await q("UPDATE table_session SET status='billed', closed_at=NOW(3) WHERE id=?", [s1]);
  await sess(id());
  await sess(id(), 'billed'); await sess(id(), 'billed');
  ok('FIX4 after billing, table reopens; many billed sessions coexist', true);
  const [exAll] = await pool.query('EXPLAIN SELECT t.id, s.id FROM table_master t LEFT JOIN table_session s ON s.open_table_key = t.id WHERE t.company_id = ?', [co]);
  ok('occupancy join uses the generated-column unique index', exAll.some(r => r.key === 'uq_session_one_open_per_table'), exAll.map(r => r.table + ':' + r.key).join(', '));

  // ---- FIX 5 + FIX 7
  const g = id(), g2 = id();
  const grp = (gid, cid, code) => q('INSERT INTO item_master (id, company_id, item_code, item_name) VALUES (?,?,?,?)', [gid, cid, code, 'Dosa']);
  await grp(g, co, '001'); await grp(g2, co2, '001');
  ok('FIX5 same item_code allowed in different companies', true);
  await rejects('FIX5 duplicate item_code inside one company rejected', grp(id(), co, '001'), 'ER_DUP_ENTRY');
  const v1 = id(), v2 = id();
  const variant = (vid, name, def) => q('INSERT INTO item_variant (id, item_id, variant_name, is_default) VALUES (?,?,?,?)', [vid, g, name, def]);
  await variant(v1, 'Plain', 1);
  await rejects('FIX7 second default variant in the same group rejected', variant(v2, 'Ghee', 1), 'ER_DUP_ENTRY');
  await variant(v2, 'Ghee', 0); await variant(id(), 'Masala', 0);
  ok('FIX7 many non-default variants coexist', true);
  await q('UPDATE item_master SET default_variant_id=? WHERE id=?', [v1, g]);
  await q('DELETE FROM item_master WHERE id=?', [g]);
  const [[left]] = await pool.query('SELECT COUNT(*) n FROM item_variant WHERE item_id=?', [g]);
  ok('deleting a group whose default_variant_id is set cascades cleanly (no circular-FK error)', left.n === 0);

  // ---- FIX 8 + 9
  const s2 = id(), cov = id();
  await sess(s2, 'billed');
  await q('INSERT INTO table_cover (id, table_session_id, company_id, cover_number) VALUES (?,?,?,1)', [cov, s2, co]);
  const bill = (num, status, cover) => q('INSERT INTO bill_master (id, company_id, billed_by, bill_number, status, cover_id) VALUES (?,?,?,?,?,?)', [id(), co, u, num, status, cover]);
  await bill('B/1', 'open', cov);
  await rejects('FIX9 second OPEN bill on the same cover rejected', bill('B/2', 'open', cov), 'ER_DUP_ENTRY');
  await bill('B/3', 'paid', cov); await bill('B/4', 'open', null); await bill('B/5', 'open', null);
  ok('FIX9 paid bills + legacy open bills without a cover coexist', true);
  await rejects('FIX8 duplicate bill_number inside one company rejected', bill('B/3', 'paid', null), 'ER_DUP_ENTRY');
  await rejects('CHECK constraint enforced (bill status)', bill('B/9', 'weird', null), 'ER_CHECK_CONSTRAINT_VIOLATED');

  // ---- FIX 11: gapless counter
  const ALLOC = 'INSERT INTO bill_counter (company_id, fy, last_seq) VALUES (?,?,LAST_INSERT_ID(1)) ON DUPLICATE KEY UPDATE last_seq = LAST_INSERT_ID(last_seq + 1)';
  const alloc = async (company, fy, hold = 5) => {
    const c = await pool.getConnection();
    try {
      await c.beginTransaction();
      const [r] = await c.execute(ALLOC, [company, fy]);
      await new Promise(res => setTimeout(res, hold));
      await c.commit();
      return r.insertId;
    } catch (e) { await c.rollback(); throw e; } finally { c.release(); }
  };
  const settle = await Promise.allSettled(Array.from({ length: 40 }, () => alloc(co, '2026-27')));
  const got = settle.filter(s => s.status === 'fulfilled').map(s => s.value).sort((a, b) => a - b);
  const errs = settle.filter(s => s.status === 'rejected').map(s => s.reason.code);
  ok('counter: 40 concurrent allocations on a COLD key -> unique gapless 1..40', got.length === 40 && got.every((n, i) => n === i + 1), errs.length ? 'errors: ' + [...new Set(errs)].join(',') + ' (' + got.length + ' ok)' : 'no errors');
  const warmStart = (await pool.query('SELECT last_seq FROM bill_counter WHERE company_id=?', [co]))[0][0].last_seq;
  const warm = (await Promise.all(Array.from({ length: 40 }, () => alloc(co, '2026-27')))).sort((a, b) => a - b);
  ok('counter: 40 concurrent allocations on a WARM key -> next 40, unique, gapless', warm.every((n, i) => n === warmStart + 1 + i), `${warm[0]}..${warm[39]}`);
  const c1 = await pool.getConnection(); await c1.beginTransaction();
  const [r1] = await c1.execute(ALLOC, [co, '2026-27']);
  await c1.rollback(); c1.release();
  const next = await alloc(co, '2026-27', 0);
  ok('counter: rolled-back allocation burns no number (GST-gapless)', next === r1.insertId, `rolled back ${r1.insertId}, next got ${next}`);
  ok('text ordering bug is real: ORDER BY bill_number DESC puts .../999 above .../1000', ['X/999', 'X/1000'].sort().reverse()[0] === 'X/999');

  // ---- driver type parity with PostgREST JSON
  const [[row]] = await pool.execute('SELECT is_active, has_gst, created_at FROM company_master WHERE id=?', [co]);
  ok('typeCast: TINYINT(1) -> real booleans (Dart `as bool?` needs this)', row.is_active === true && row.has_gst === false, JSON.stringify({ a: row.is_active, g: row.has_gst }));
  ok('timestamps serialize as ISO-8601 UTC "...Z" (Dart DateTime.parse ok)', /Z"?$/.test(JSON.stringify(row.created_at)), JSON.stringify(row.created_at));
  await q("INSERT INTO bill_item (id, bill_id, item_name_snapshot, rate_snapshot, qty) SELECT ?, id, 'Tea', 15.00, 2.5 FROM bill_master WHERE bill_number='B/1'", [id()]);
  const [[bi]] = await pool.execute('SELECT rate_snapshot, qty FROM bill_item LIMIT 1');
  ok('decimalNumbers: DECIMAL -> JS number (Dart `as num?` needs this)', typeof bi.rate_snapshot === 'number' && typeof bi.qty === 'number', JSON.stringify(bi));
  const rm = id();
  await q('INSERT INTO raw_material (id, company_id, name, opening_stock, reorder_level) VALUES (?,?,?,?,?)', [rm, co, 'Milk', 1, 5]);
  const [[cs]] = await pool.execute('SELECT current_stock, is_low_stock FROM v_current_stock WHERE id=?', [rm]);
  ok('view boolean is a number, not TINYINT(1) -> API mapper must coerce', typeof cs.is_low_stock === 'number' && cs.is_low_stock === 1, `typeof=${typeof cs.is_low_stock} value=${cs.is_low_stock}`);

  // ---- money rounding parity (Postgres rounds 1.005 -> 1.01 and 0.375 -> 0.38)
  const cast = async (bind, mode) => { const [r] = await pool[mode]('SELECT CAST(? AS DECIMAL(12,2)) AS v', [bind]); return r[0].v; };
  const dbl = await cast(1.005, 'execute'), str = await cast('1.005', 'execute'), txt = await cast(1.005, 'query'), half = await cast('0.375', 'execute');
  console.log(`   info  CAST(1.005 AS DECIMAL(12,2)): execute(number)=${dbl}  execute('1.005')=${str}  query(number)=${txt}   0.375 -> ${half}`);
  ok('money: binding decimals as STRINGS reproduces Postgres half-up rounding', str === 1.01 && half === 0.38);

  // ---- stock ledger idempotency
  const ins = (ki, note) => q('INSERT INTO stock_ledger (id, company_id, raw_material_id, movement_type, qty, kot_item_id, note) VALUES (?,?,?,?,?,?,?)', [id(), co, rm, 'consumed', -0.03125, ki, note]);
  await ins(null, 'manual1'); await ins(null, 'manual2');
  ok('ledger: multiple manual rows (kot_item_id NULL) allowed', true);
  await q("INSERT INTO kot_master (id, bill_id, company_id, kot_number, created_by) SELECT ?, id, ?, 'KOT/1', ? FROM bill_master WHERE bill_number='B/1'", [id(), co, u]);
  const kot = (await pool.query('SELECT id FROM kot_master LIMIT 1'))[0][0].id;
  const kotItem = id(); const biId = (await pool.query('SELECT id FROM bill_item LIMIT 1'))[0][0].id;
  await q('INSERT INTO kot_item (id, kot_id, bill_item_id, qty) VALUES (?,?,?,1)', [kotItem, kot, biId]);
  await ins(kotItem, 'auto');
  await rejects('ledger: same KOT item deducted twice for one material rejected (retry-safe)', ins(kotItem, 'auto-retry'), 'ER_DUP_ENTRY');
  const [[sc]] = await pool.execute('SELECT current_stock FROM v_current_stock WHERE id=?', [rm]);
  ok('ledger: DECIMAL(16,6) keeps 0.03125 exact (3 rows)', Math.abs(sc.current_stock - (1 - 0.09375)) < 1e-9, String(sc.current_stock));

  console.log(`\n${pass} passed, ${fail} failed`);
  await pool.end(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('TEST ERROR', e); process.exit(2); });
