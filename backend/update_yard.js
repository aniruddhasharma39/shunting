const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: String(process.env.DB_PASSWORD),
  port: process.env.DB_PORT,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
});

async function updateYard() {
  try {
    await pool.query("UPDATE yards SET zone = 'North Western Railway (NWR)', division = 'Jaipur Division' WHERE yard_name = 'Khatipura Station Yard'");
    console.log('Yard updated successfully.');
  } catch (e) {
    console.error('Error:', e);
  } finally {
    pool.end();
  }
}
updateYard();
