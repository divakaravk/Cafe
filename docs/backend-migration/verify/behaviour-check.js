const mysql = require('mysql2/promise');
const crypto = require('crypto');
const conn = JSON.parse(require('fs').readFileSync(require('path').join(__dirname, 'conn.json')));
const id = () => crypto.randomUUID();
let pass = 0, fail = 0;
const ok = (n, c, x = '') => { (c ? pass++ : fail++); console.log((c ? 'PASS ' : 'FAIL ') + n + (x ? '  -> ' + x : '')); };
const typeCast = (field, next) => { const v = next(); return (field.type === 'TINY' && field.length === 1 && v !== null) ? (v === 1 || v === '1') : v; };

(async () => {
  const pool = mysql.createPool({ host: '127.0.0.1', port: conn.port, user: 'root', database: 'cafe', timezone: 'Z', decimalNumbers: true, typeCast, connectionLimit: 20 });
  pool.pool.on('connection', c => c.query("SET time_zone='+00:00'"));
  const co = id(), u = id(), t1 = id(), t2 = id(), t3 = id();
  await pool.execute('INSERT INTO company_master (id, company_code, company_name) VALUES (?,?,?)', [co, 'C' + co.slice(0, 6), 'Co']);
  await pool.execute('INSERT INTO user_profiles (id, company_id, employee_code, user_name, username, password_hash, user_role) VALUES (?,?,?,?,?,?,?)', [u, co, 'E1', 'U', 'u' + co.slice(0, 6), 'x', 'waiter']);
  for (const [t, n] of [[t1, 'T1'], [t2, 'T2'], [t3, 'T10']]) await pool.execute('INSERT INTO table_master (id, company_id, table_number) VALUES (?,?,?)', [t, co, n]);

  // ---- race-free get-or-create of the open session (replaces the client's check-then-insert)
  async function openSession(tableId) {
    try {
      const sid = id();
      await pool.execute("INSERT INTO table_session (id, table_id, opened_by, company_id) VALUES (?,?,?,?)", [sid, tableId, u, co]);
      return sid;
    } catch (e) {
      if (e.code !== 'ER_DUP_ENTRY') throw e;
      const [[r]] = await pool.execute("SELECT id FROM table_session WHERE table_id=? AND status='open'", [tableId]);
      return r.id;
    }
  }
  const ids = await Promise.all(Array.from({ length: 30 }, () => openSession(t1)));
  const [[cnt]] = await pool.query("SELECT COUNT(*) n FROM table_session WHERE table_id=? AND status='open'", [t1]);
  ok('30 parallel "save order" calls on one table -> exactly 1 open session, all callers get the same id', new Set(ids).size === 1 && cnt.n === 1, `distinct ids=${new Set(ids).size}, open rows=${cnt.n}`);

  // ---- single-query getTables (replaces 5 client round-trips + Dart aggregation)
  const sid = ids[0];
  const cov = id();
  await pool.execute('INSERT INTO table_cover (id, table_session_id, company_id, cover_number) VALUES (?,?,?,1)', [cov, sid, co]);
  await pool.execute("INSERT INTO bill_master (id, company_id, billed_by, table_session_id, bill_number, status, cover_id, total_amount) VALUES (?,?,?,?,?, 'open', ?, 250.50)", [id(), co, u, sid, 'N/1', cov]);
  const sql = `SELECT t.*, s.id AS active_session_id, s.opened_at,
       (s.id IS NOT NULL) AS is_occupied,
       COALESCE(b.total, 0) AS active_order_total,
       COALESCE(c.cnt, 0)   AS active_cover_count
  FROM table_master t
  LEFT JOIN table_session s ON s.open_table_key = t.id
  LEFT JOIN LATERAL (SELECT SUM(total_amount) AS total FROM bill_master WHERE table_session_id = s.id AND status = 'open') b ON TRUE
  LEFT JOIN LATERAL (SELECT COUNT(*) AS cnt FROM table_cover WHERE table_session_id = s.id AND status = 'active') c ON TRUE
 WHERE t.company_id = ?
 ORDER BY t.table_number`;
  const [rows] = await pool.execute(sql, [co]);
  const r1 = rows.find(r => r.table_number === 'T1'), r2 = rows.find(r => r.table_number === 'T2');
  ok('getTables in ONE query: occupied table has session, total, cover count', r1.active_session_id === sid && r1.active_order_total === 250.5 && r1.active_cover_count === 1, JSON.stringify({ total: r1.active_order_total, covers: r1.active_cover_count }));
  ok('getTables: free table has null session, 0 total, 0 covers', r2.active_session_id === null && r2.active_order_total === 0 && r2.active_cover_count === 0);
  ok('getTables: keeps the app\'s text ordering (T1, T10, T2)', rows.map(r => r.table_number).join() === 'T1,T10,T2', rows.map(r => r.table_number).join());
  ok('getTables: is_occupied is a NUMBER from an expression -> mapper must coerce', typeof r1.is_occupied === 'number', typeof r1.is_occupied);
  const [plan] = await pool.query('EXPLAIN ' + sql.replace('?', "'" + co + "'"));
  console.log('   info  plan:', plan.map(p => `${p.table}:${p.key || 'ALL'}`).join(' | '));

  // ---- login matching semantics
  const [lo] = await pool.execute('SELECT id FROM user_profiles WHERE username = ?', ['U' + co.slice(0, 6).toUpperCase()]);
  ok('login: username match is case-insensitive (parity with Postgres ILIKE)', lo.length === 1);
  const [wild] = await pool.execute('SELECT id FROM user_profiles WHERE username = ?', ['%']);
  ok('login: "=" (not LIKE) means "%" or "_" typed by a user is never a wildcard', wild.length === 0);

  console.log(`\n${pass} passed, ${fail} failed`); await pool.end(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('TEST ERROR', e); process.exit(2); });
