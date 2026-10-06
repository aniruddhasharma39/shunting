const { Pool } = require('pg');
require('dotenv').config();
const pool = new Pool({
  user: process.env.DB_USER, host: process.env.DB_HOST, database: process.env.DB_NAME, password: process.env.DB_PASSWORD, port: 5432, ssl: { rejectUnauthorized: false }
});
async function check() {
  try {
    const u = await pool.query("SELECT id FROM users WHERE email = 'nwr@gmail.com'");
    if(u.rows.length) {
      const res = await pool.query("SELECT * FROM user_zone_assignments WHERE user_id = $1", [u.rows[0].id]);
      console.log('Assignments:', res.rows);
    }
  } catch(e) { console.error(e); }
  pool.end();
}
check();
