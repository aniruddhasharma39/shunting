const { Pool } = require('pg');
require('dotenv').config();
const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: 5432,
  ssl: { rejectUnauthorized: false }
});
async function fix() {
  try {
    const res = await pool.query("UPDATE users SET role = 'zone_admin' WHERE email = 'nwr@gmail.com' RETURNING *");
    console.log("Updated:", res.rows);
  } catch (err) {
    console.error(err);
  } finally {
    pool.end();
  }
}
fix();
