require('dotenv').config();
const { Pool } = require('pg');
const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
});

async function run() {
  try {
    await pool.query('BEGIN');
    
    const res = await pool.query("SELECT id, yard_name FROM yards WHERE yard_name IN ('North Yard', 'South Yard')");
    const yardIds = res.rows.map(r => r.id);
    
    if (yardIds.length === 0) {
      console.log('No dummy yards found in DB.');
      await pool.query('ROLLBACK');
      return;
    }

    console.log('Deleting yards with IDs:', yardIds);

    await pool.query('DELETE FROM device_telemetry WHERE device_id IN (SELECT id::text FROM devices WHERE yard_id = ANY($1::uuid[]))', [yardIds]);
    await pool.query('DELETE FROM session_events WHERE session_id IN (SELECT id FROM shunting_sessions WHERE ld_device_id IN (SELECT id FROM devices WHERE yard_id = ANY($1::uuid[])) OR de_device_id IN (SELECT id FROM devices WHERE yard_id = ANY($1::uuid[])))', [yardIds]);
    await pool.query('DELETE FROM shunting_sessions WHERE ld_device_id IN (SELECT id FROM devices WHERE yard_id = ANY($1::uuid[])) OR de_device_id IN (SELECT id FROM devices WHERE yard_id = ANY($1::uuid[]))', [yardIds]);
    await pool.query('DELETE FROM device_assignments WHERE device_id IN (SELECT id FROM devices WHERE yard_id = ANY($1::uuid[]))', [yardIds]);
    await pool.query('DELETE FROM alerts WHERE device_id IN (SELECT id FROM devices WHERE yard_id = ANY($1::uuid[]))', [yardIds]);
    await pool.query('DELETE FROM device_line_assignments WHERE device_id IN (SELECT id FROM devices WHERE yard_id = ANY($1::uuid[]))', [yardIds]);
    await pool.query('DELETE FROM devices WHERE yard_id = ANY($1::uuid[])', [yardIds]);
    await pool.query('DELETE FROM device_registry WHERE yard_id = ANY($1::uuid[])', [yardIds]);
    await pool.query('DELETE FROM user_yard_assignments WHERE yard_id = ANY($1::uuid[])', [yardIds]);
    await pool.query('DELETE FROM yard_lines WHERE yard_id = ANY($1::uuid[])', [yardIds]);
    await pool.query('DELETE FROM yards WHERE id = ANY($1::uuid[])', [yardIds]);
    
    await pool.query('COMMIT');
    console.log('Successfully deleted North Yard and South Yard and all related data from the database.');
  } catch (error) {
    await pool.query('ROLLBACK');
    console.error('Error:', error);
  } finally {
    await pool.end();
  }
}
run();
