const db = require('./config/db');
db.query("SELECT * FROM shunting_sessions WHERE id::text LIKE 'dae6d94d%' OR id::text LIKE '689c5885%' OR id::text LIKE 'eda0d46a%'")
  .then(r => console.log(r.rows))
  .catch(console.error)
  .finally(() => process.exit());
