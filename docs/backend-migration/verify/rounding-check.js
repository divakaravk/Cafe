// Does INSERTing a JS number into DECIMAL(12,2) round like Postgres (half-up on the decimal text)?
const mysql = require('mysql2/promise');
const conn = JSON.parse(require('fs').readFileSync(require('path').join(__dirname, 'conn.json')));
(async () => {
  const pool = mysql.createPool({ host: '127.0.0.1', port: conn.port, user: 'root', database: 'cafe', decimalNumbers: true });
  await pool.query('DROP TABLE IF EXISTS r; CREATE TABLE r (k VARCHAR(20), v DECIMAL(12,2))').catch(async () => {
    await pool.query('DROP TABLE IF EXISTS r'); await pool.query('CREATE TABLE r (k VARCHAR(20), v DECIMAL(12,2))');
  });
  // Values a POS actually produces: qty*rate*gst/2 style tax splits and .xx5 boundaries.
  const vals = [1.005, 2.675, 1.115, 0.285, 8.345, 0.375, 1.255, 4.075, 19.995, 0.125 * 3, 15 * 0.05 / 2, 33.33 * 0.18 / 2, 7 * 12.5 * 0.05 / 2];
  const half = s => { // exact half-up on the shortest decimal text (what Postgres does with JSON text "2.675")
    const [i, f = ''] = String(s).split('.'); const d = (f + '000').slice(0, 3); let n = BigInt(i + d.slice(0, 2)); if (d[2] >= '5') n += 1n;
    const str = n.toString().padStart(3, '0'); return Number(str.slice(0, -2) + '.' + str.slice(-2));
  };
  let badNum = 0, badStr = 0, badQuery = 0;
  for (const x of vals) {
    await pool.execute('TRUNCATE r');
    await pool.execute('INSERT INTO r VALUES (?,?)', ['num', x]);
    await pool.execute('INSERT INTO r VALUES (?,?)', ['str', String(x)]);
    await pool.query('INSERT INTO r VALUES (?,?)', ['qry', x]);
    const [rows] = await pool.query('SELECT k, v FROM r'); const m = Object.fromEntries(rows.map(r => [r.k, r.v]));
    const want = half(x);
    if (m.num !== want) badNum++; if (m.str !== want) badStr++; if (m.qry !== want) badQuery++;
    console.log(String(x).padEnd(22), 'postgres-style=' + want, ' execute(number)=' + m.num + (m.num !== want ? ' X' : ''), ' execute(string)=' + m.str + (m.str !== want ? ' X' : ''), ' query(number)=' + m.qry + (m.qry !== want ? ' X' : ''));
  }
  console.log(`\nmismatches vs Postgres half-up:  execute(number)=${badNum}  execute(string)=${badStr}  query(number)=${badQuery}   of ${vals.length}`);
  await pool.query('DROP TABLE r'); await pool.end();
})();
