const { Pool } = require('pg');
require('dotenv').config();
const pool = new Pool({
  user: process.env.DB_USER, host: process.env.DB_HOST, database: process.env.DB_NAME, password: process.env.DB_PASSWORD, port: 5432, ssl: { rejectUnauthorized: false }
});
async function fix() {
  try {
    const u = await pool.query("SELECT id FROM users WHERE email = 'nwr@gmail.com'");
    if(u.rows.length) {
      const res = await pool.query("INSERT INTO user_zone_assignments (user_id, zone_name) VALUES ($1, 'North Western Railway (NWR)') ON CONFLICT DO NOTHING", [u.rows[0].id]);
      console.log('Inserted Zone!');
    }
  } catch(e) { console.error(e); }
  pool.end();
}
fix();
