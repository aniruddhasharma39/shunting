const { Pool } = require('pg');
const bcrypt = require('bcrypt');
require('dotenv').config();

const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'safeshunt_db',
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT || 5432,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

async function run() {
  const client = await pool.connect();
  try {
    console.log('Clearing foreign keys to prevent constraint violations...');
    const fkTables = [
      { table: 'user_zone_assignments', col: 'assigned_by' },
      { table: 'user_division_assignments', col: 'assigned_by' },
      { table: 'user_yard_assignments', col: 'assigned_by' },
      { table: 'device_assignments', col: 'issued_by' },
      { table: 'device_assignments', col: 'received_by' },
      { table: 'shunting_sessions', col: 'closed_by' },
      { table: 'alerts', col: 'acknowledged_by' },
      { table: 'alerts', col: 'resolved_by' },
      { table: 'system_logs', col: 'user_id' },
      { table: 'reports', col: 'generated_by' },
      { table: 'ota_campaigns', col: 'created_by' }
    ];

    for (const fk of fkTables) {
      try {
        await client.query(`UPDATE ${fk.table} SET ${fk.col} = NULL`);
      } catch (e) {
        // Table or column might not exist, ignore
      }
    }

    console.log('Deleting ALL existing users from the database...');
    const deleteRes = await client.query('DELETE FROM users');
    console.log(`Deleted ${deleteRes.rowCount} users.`);

    console.log('Creating new Super Admin user...');
    const email = 'pisolve704@gmail.com';
    const employeeId = 'SA-0001';
    const rawPassword = 'admin123';
    const designation = 'Super Administrator';
    const role = 'super_admin';
    const fullName = 'Super Admin';
    const isActive = true;

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(rawPassword, salt);

    await client.query(
      'INSERT INTO users (full_name, employee_id, email, designation, password_hash, role, is_active) VALUES ($1, $2, $3, $4, $5, $6, $7)',
      [fullName, employeeId, email, designation, passwordHash, role, isActive]
    );

    console.log(`\nSuccessfully recreated the users table!`);
    console.log(`Only ONE user remains:`);
    console.log(`Email: ${email}`);
    console.log(`Password: ${rawPassword}`);
    console.log(`Employee ID: ${employeeId}`);
    
  } catch (err) {
    console.error('Error occurred:', err);
  } finally {
    client.release();
    pool.end();
  }
}

run();
