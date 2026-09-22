const bcrypt = require('bcrypt');
const db = require('./config/db');

async function seedCredentials() {
  try {
    console.log('--- Seeding Credentials ---');

    // 1. Credentials definition
    const creds = [
      {
        fullName: 'Yard Administrator',
        employeeId: 'YD-1010',
        email: 'yd1010@safeshunt.com',
        designation: 'Yard Administrator',
        role: 'yard_admin',
        plainPassword: 'yard123'
      },
      {
        fullName: 'Admin User',
        employeeId: 'AN-1010',
        email: 'an1010@safeshunt.com',
        designation: 'Super Administrator',
        role: 'super_admin',
        plainPassword: 'admin123'
      }
    ];

    for (const c of creds) {
      const passwordHash = await bcrypt.hash(c.plainPassword, 10);

      // Check if user already exists
      const existing = await db.query('SELECT id FROM users WHERE employee_id = $1', [c.employeeId]);

      let userId;
      if (existing.rows.length > 0) {
        userId = existing.rows[0].id;
        await db.query(
          `UPDATE users 
           SET full_name = $1, email = $2, designation = $3, role = $4, password_hash = $5, is_active = true 
           WHERE id = $6`,
          [c.fullName, c.email, c.designation, c.role, passwordHash, userId]
        );
        console.log(`[UPDATED] User ${c.employeeId} (Password: ${c.plainPassword})`);
      } else {
        const inserted = await db.query(
          `INSERT INTO users (full_name, employee_id, email, designation, role, password_hash, is_active)
           VALUES ($1, $2, $3, $4, $5, $6, true)
           RETURNING id`,
          [c.fullName, c.employeeId, c.email, c.designation, c.role, passwordHash]
        );
        userId = inserted.rows[0].id;
        console.log(`[CREATED] User ${c.employeeId} (Password: ${c.plainPassword}) with ID: ${userId}`);
      }

      // If Yard Admin, assign to existing active yards so dashboard shows data
      if (c.role === 'yard_admin') {
        const yardsRes = await db.query("SELECT id, yard_name FROM yards WHERE status = 'Active'");
        for (const yard of yardsRes.rows) {
          await db.query(
            `INSERT INTO user_yard_assignments (user_id, yard_id)
             VALUES ($1, $2)
             ON CONFLICT (user_id, yard_id) DO NOTHING`,
            [userId, yard.id]
          );
          console.log(`   Assigned ${c.employeeId} to yard: ${yard.yard_name}`);
        }
      }
    }

    console.log('--- Successfully configured users YD-1010 and AN-1010! ---');
    process.exit(0);
  } catch (err) {
    console.error('Error seeding credentials:', err);
    process.exit(1);
  }
}

seedCredentials();
