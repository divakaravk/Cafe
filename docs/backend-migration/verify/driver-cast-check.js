// Which typeCast pattern is safe under BOTH pool.execute (binary protocol) and pool.query (text protocol)?
const mysql = require('mysql2/promise');
const conn = JSON.parse(require('fs').readFileSync(require('path').join(__dirname, 'conn.json')));

const A = (f, next) => (f.type === 'TINY' && f.length === 1) ? (f.string() === null ? null : f.string() === '1') : next();   // what test.js used
const B = (f, next) => { const v = next(); return (f.type === 'TINY' && f.length === 1 && v !== null) ? v === 1 || v === '1' : v; }; // convert AFTER next()

(async () => {
  for (const [name, typeCast] of [['A field.string()', A], ['B next()+convert', B]]) {
    const pool = mysql.createPool({ host: '127.0.0.1', port: conn.port, user: 'root', database: 'cafe', timezone: 'Z', decimalNumbers: true, typeCast });
    const sql = 'SELECT t.*, (t.is_active IS NOT NULL) AS flag, NOW(3) AS ts, 12.5 AS dec_lit FROM table_master t LIMIT 3';
    for (const mode of ['execute', 'query']) {
      try {
        const [rows] = await pool[mode](sql);
        const r = rows[0];
        console.log(`${name.padEnd(20)} ${mode.padEnd(8)} OK   is_active=${JSON.stringify(r.is_active)} (${typeof r.is_active})  flag=${r.flag}(${typeof r.flag})  section=${r.section}  qr_code=${r.qr_code}`);
      } catch (e) { console.log(`${name.padEnd(20)} ${mode.padEnd(8)} FAIL ${e.message.slice(0, 80)}`); }
    }
    await pool.end();
  }
})();
