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

async function queryYards() {
  try {
    const res = await pool.query("SELECT * FROM yards");
    console.log('Yards in DB:', JSON.stringify(res.rows, null, 2));
  } catch (e) {
    console.error('Error:', e);
  } finally {
    pool.end();
  }
}
queryYards();
