const { Pool } = require('pg');
require('dotenv').config();
const pool = new Pool({
  user: process.env.DB_USER, host: process.env.DB_HOST, database: process.env.DB_NAME, password: process.env.DB_PASSWORD, port: 5432, ssl: { rejectUnauthorized: false }
});
async function fix() {
  try {
    // Delete the last remaining seeded alert (Buffer Proximity from Sep 15 - fake seed data)
    const res = await pool.query(`DELETE FROM alerts_logs WHERE timestamp < '2026-09-29'`);
    console.log(`Deleted ${res.rowCount} old seeded alerts.`);
    const remaining = await pool.query(`SELECT COUNT(*) FROM alerts_logs`);
    console.log('Total alerts remaining:', remaining.rows[0].count);
  } catch(e) { console.error('Error:', e.message); }
  pool.end();
}
fix();
