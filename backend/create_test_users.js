const bcrypt = require('bcrypt');
const db = require('./config/db');

async function createUsers() {
  const passwordHash = await bcrypt.hash('password123', 10);
  const users = [
    { name: 'Super Admin', empId: 'SA-001', email: 'super@safeshunt.com', desig: 'Super Administrator', role: 'super_admin' },
    { name: 'Yard Admin', empId: 'YA-001', email: 'yard@safeshunt.com', desig: 'Yard Administrator', role: 'yard_admin' },
    { name: 'Maintenance User', empId: 'MU-001', email: 'maintenance@safeshunt.com', desig: 'Maintenance User', role: 'maintenance_user' },
    { name: 'Viewer', empId: 'VW-001', email: 'viewer@safeshunt.com', desig: 'Viewer / Control Room User', role: 'viewer' }
  ];

  for (const u of users) {
    try {
      await db.query(
        'INSERT INTO users (full_name, employee_id, email, designation, password_hash, role) VALUES ($1, $2, $3, $4, $5, $6)',
        [u.name, u.empId, u.email, u.desig, passwordHash, u.role]
      );
      console.log(`Created ${u.role}: ${u.email}`);
    } catch (e) {
      if (e.code === '23505') console.log(`User ${u.email} already exists.`);
      else console.error(e);
    }
  }
  process.exit();
}

createUsers();
