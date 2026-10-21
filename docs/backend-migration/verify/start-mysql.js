// Starts an embedded MySQL 8.4, prints connection info, stays alive until killed.
const { createDB } = require('mysql-memory-server');
(async () => {
  console.log('starting (first run downloads MySQL binaries)...');
  const db = await createDB({ version: '8.4.x', dbName: 'cafe', username: 'root', logLevel: 'ERROR', downloadBinaryOnce: true, ignoreUnsupportedSystemVersion: true });
  require('fs').writeFileSync(require('path').join(__dirname, 'conn.json'), JSON.stringify({ port: db.port, socket: db.socket, user: db.username, db: db.dbName }));
  console.log('READY port=' + db.port);
  setInterval(() => {}, 1 << 30);
})().catch(e => { console.error('FAILED:', e && (e.stack || e)); process.exit(1); });
