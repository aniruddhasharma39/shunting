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

async function deleteUsers() {
  try {
    console.log('Deleting jaipur@gmail.com and supervisorkhatipura@gmail.com...');
    await pool.query("DELETE FROM users WHERE email IN ('jaipur@gmail.com', 'supervisorkhatipura@gmail.com')");
    console.log('Successfully deleted the two users.');
  } catch (e) {
    console.error('Error:', e);
  } finally {
    pool.end();
  }
}
deleteUsers();
