const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const bcrypt = require('bcrypt');
require('dotenv').config();

// Configuration from environment or defaults
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_USER = process.env.DB_USER || 'postgres';
const DB_PASSWORD = process.env.DB_PASSWORD || 'postgres';
const DB_PORT = parseInt(process.env.DB_PORT, 10) || 5432;
const TARGET_DB = process.argv[2] || process.env.DB_NAME || 'safeshunt_db';
const DB_SSL = process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false;

async function setupDatabase() {
  console.log('====================================================');
  console.log(' SafeShunt Database Setup & Seeding Utility');
  console.log('====================================================');
  console.log(`Host:     ${DB_HOST}:${DB_PORT}`);
  console.log(`User:     ${DB_USER}`);
  console.log(`Target:   ${TARGET_DB}`);
  console.log(`SSL:      ${DB_SSL ? 'Enabled' : 'Disabled'}`);
  console.log('----------------------------------------------------');

  // Step 1: Connect to default administrative database to ensure target DB exists
  const adminDbName = (TARGET_DB === 'postgres') ? 'template1' : 'postgres';
  const adminPool = new Pool({
    host: DB_HOST,
    user: DB_USER,
    password: DB_PASSWORD,
    port: DB_PORT,
    database: adminDbName,
    ssl: DB_SSL,
  });

  try {
    console.log(`[1/4] Checking if database '${TARGET_DB}' exists...`);
    const checkRes = await adminPool.query(
      'SELECT 1 FROM pg_database WHERE datname = $1',
      [TARGET_DB]
    );

    if (checkRes.rows.length === 0) {
      console.log(`      Database '${TARGET_DB}' does not exist. Creating...`);
      // Note: CREATE DATABASE cannot run in a transaction block
      await adminPool.query(`CREATE DATABASE "${TARGET_DB}"`);
      console.log(`      Successfully created database '${TARGET_DB}'.`);
    } else {
      console.log(`      Database '${TARGET_DB}' already exists.`);
    }
  } catch (err) {
    console.warn(`      Note during DB existence check: ${err.message}`);
  } finally {
    await adminPool.end();
  }

  // Step 2: Connect to the target database
  console.log(`[2/4] Connecting to target database '${TARGET_DB}'...`);
  const targetPool = new Pool({
    host: DB_HOST,
    user: DB_USER,
    password: DB_PASSWORD,
    port: DB_PORT,
    database: TARGET_DB,
    ssl: DB_SSL,
  });

  try {
    // Step 3: Run Schema SQL
    console.log('[3/4] Executing complete_schema.sql...');
    const schemaSqlPath = path.join(__dirname, 'complete_schema.sql');
    if (!fs.existsSync(schemaSqlPath)) {
      throw new Error(`Schema file not found at: ${schemaSqlPath}`);
    }
    const schemaSql = fs.readFileSync(schemaSqlPath, 'utf8');
    await targetPool.query(schemaSql);
    console.log('      Schema tables, indexes, and constraints initialized successfully.');

    // Step 4: Seed Data
    console.log('[4/4] Seeding initial data (users, yards, devices, sessions)...');

    // A. Hash Passwords
    const yardAdminHash = await bcrypt.hash('yard123', 10);
    const superAdminHash = await bcrypt.hash('admin123', 10);
    const defaultHash = await bcrypt.hash('password123', 10);

    // B. Insert / Update Users
    const usersToSeed = [
      {
        fullName: 'Yard Administrator',
        empId: 'YD-1010',
        email: 'yd1010@safeshunt.com',
        desig: 'Yard Administrator',
        role: 'yard_admin',
        hash: yardAdminHash,
      },
      {
        fullName: 'Super Administrator',
        empId: 'AN-1010',
        email: 'an1010@safeshunt.com',
        desig: 'Super Administrator',
        role: 'super_admin',
        hash: superAdminHash,
      },
      {
        fullName: 'Yard Manager Demo',
        empId: 'YA-001',
        email: 'ya001@safeshunt.com',
        desig: 'Yard Administrator',
        role: 'yard_admin',
        hash: defaultHash,
      },
      {
        fullName: 'Super Admin Demo',
        empId: 'SA-001',
        email: 'sa001@safeshunt.com',
        desig: 'Super Administrator',
        role: 'super_admin',
        hash: defaultHash,
      },
      {
        fullName: 'Maintenance Tech',
        empId: 'MU-001',
        email: 'tech001@safeshunt.com',
        desig: 'Maintenance User',
        role: 'maintenance_user',
        hash: defaultHash,
      },
      {
        fullName: 'Control Room Viewer',
        empId: 'VW-001',
        email: 'viewer001@safeshunt.com',
        desig: 'Viewer / Control Room User',
        role: 'viewer',
        hash: defaultHash,
      },
    ];

    const userMap = {};
    for (const u of usersToSeed) {
      // Find existing user by employee_id or email
      const existing = await targetPool.query(
        'SELECT id FROM users WHERE employee_id = $1 OR email = $2',
        [u.empId, u.email]
      );

      if (existing.rows.length > 0) {
        const userId = existing.rows[0].id;
        await targetPool.query(
          `UPDATE users 
           SET full_name = $1, employee_id = $2, email = $3, designation = $4, role = $5, password_hash = $6, is_active = true 
           WHERE id = $7`,
          [u.fullName, u.empId, u.email, u.desig, u.role, u.hash, userId]
        );
        userMap[u.empId] = userId;
      } else {
        const userRes = await targetPool.query(
          `INSERT INTO users (full_name, employee_id, email, designation, role, password_hash, is_active)
           VALUES ($1, $2, $3, $4, $5, $6, true)
           RETURNING id`,
          [u.fullName, u.empId, u.email, u.desig, u.role, u.hash]
        );
        userMap[u.empId] = userRes.rows[0].id;
      }
    }
    console.log(`      Users seeded (${usersToSeed.length} accounts configured).`);

    // C. Insert Yards and map by code
    const yardsToSeed = [
      {
        code: 'NY-01',
        name: 'North Yard',
        station: 'Sector A',
        division: 'Div 1',
        zone: 'Zone 1',
        type: 'Freight',
      },
      {
        code: 'SY-01',
        name: 'South Yard',
        station: 'Sector B',
        division: 'Div 1',
        zone: 'Zone 1',
        type: 'Coaching',
      },
    ];

    const yardMap = {};
    for (const y of yardsToSeed) {
      const res = await targetPool.query(
        `INSERT INTO yards (yard_code, yard_name, station, division, zone, yard_type, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'Active')
         ON CONFLICT (yard_code) DO UPDATE 
         SET yard_name = EXCLUDED.yard_name,
             station = EXCLUDED.station,
             division = EXCLUDED.division,
             zone = EXCLUDED.zone,
             yard_type = EXCLUDED.yard_type,
             status = 'Active'
         RETURNING id, yard_code`,
        [y.code, y.name, y.station, y.division, y.zone, y.type]
      );
      yardMap[y.code] = res.rows[0].id;
    }
    console.log('      Yards seeded (North Yard, South Yard).');

    // D. Assign Yards to YD-1010 and YA-001
    const yardAdmins = [userMap['YD-1010'], userMap['YA-001']].filter(Boolean);
    for (const adminId of yardAdmins) {
      for (const yCode of Object.keys(yardMap)) {
        await targetPool.query(
          `INSERT INTO user_yard_assignments (user_id, yard_id)
           VALUES ($1, $2)
           ON CONFLICT (user_id, yard_id) DO NOTHING`,
          [adminId, yardMap[yCode]]
        );
      }
    }
    console.log('      Yard assignments created for Yard Administrators.');

    // E. Insert Yard Lines
    const linesToSeed = [
      {
        yardCode: 'NY-01',
        code: 'LN-101',
        name: 'Pit Line 1',
        deadEnd: 'DE-Stop-101',
        type: 'Pit Line',
      },
      {
        yardCode: 'NY-01',
        code: 'LN-102',
        name: 'Stabling Line 2',
        deadEnd: 'DE-Stop-102',
        type: 'Stabling Line',
      },
      {
        yardCode: 'SY-01',
        code: 'LN-201',
        name: 'Washing Line A',
        deadEnd: 'DE-Stop-201',
        type: 'Washing Line',
      },
      {
        yardCode: 'SY-01',
        code: 'LN-202',
        name: 'Main Shunt Line',
        deadEnd: 'DE-Stop-202',
        type: 'Main Line',
      },
    ];

    const lineMap = {};
    for (const l of linesToSeed) {
      const existingLine = await targetPool.query(
        'SELECT id FROM yard_lines WHERE yard_id = $1 AND (line_number = $2 OR line_name = $3)',
        [yardMap[l.yardCode], l.code, l.name]
      );

      if (existingLine.rows.length > 0) {
        lineMap[l.code] = existingLine.rows[0].id;
      } else {
        const lineRes = await targetPool.query(
          `INSERT INTO yard_lines (yard_id, line_number, line_name, dead_end_name, line_type, warning_distance, slow_distance, stop_distance, status)
           VALUES ($1, $2, $3, $4, $5, 50.0, 20.0, 5.0, 'Active')
           RETURNING id`,
          [yardMap[l.yardCode], l.code, l.name, l.deadEnd, l.type]
        );
        lineMap[l.code] = lineRes.rows[0].id;
      }
    }
    console.log('      Yard lines seeded.');

    // F. Insert Devices
    const devicesToSeed = [
      {
        code: 'DE-042',
        type: 'Dead-End Unit',
        name: 'North Pit Dead-End Device',
        sn: 'SN-DE-042',
        yardCode: 'NY-01',
        online: 'Online',
      },
      {
        code: 'DE-088',
        type: 'Dead-End Unit',
        name: 'North Stabling Dead-End Device',
        sn: 'SN-DE-088',
        yardCode: 'NY-01',
        online: 'Offline',
      },
      {
        code: 'DE-019',
        type: 'Dead-End Unit',
        name: 'South Washing Dead-End Device',
        sn: 'SN-DE-019',
        yardCode: 'SY-01',
        online: 'Online',
      },
      {
        code: 'LD-005',
        type: 'Loco Unit',
        name: 'Loco Unit 5',
        sn: 'SN-LD-005',
        yardCode: 'NY-01',
        online: 'Online',
      },
      {
        code: 'PD-022',
        type: 'Portable',
        name: 'Portable Shunting Device 22',
        sn: 'SN-PD-022',
        yardCode: 'NY-01',
        online: 'Online',
      },
      {
        code: 'CD-014',
        type: 'Coupling',
        name: 'Coupling Sensor 14',
        sn: 'SN-CD-014',
        yardCode: 'SY-01',
        online: 'Online',
      },
      {
        code: 'LD-001',
        type: 'Loco Unit',
        name: 'Loco Unit 1',
        sn: 'SN-LD-001',
        yardCode: 'NY-01',
        online: 'Online',
      },
    ];

    const deviceMap = {};
    for (const d of devicesToSeed) {
      const existingDev = await targetPool.query(
        'SELECT id FROM devices WHERE device_code = $1',
        [d.code]
      );

      if (existingDev.rows.length > 0) {
        const devId = existingDev.rows[0].id;
        await targetPool.query(
          `UPDATE devices 
           SET yard_id = $1, device_name = $2, online_status = $3 
           WHERE id = $4`,
          [yardMap[d.yardCode], d.name, d.online, devId]
        );
        deviceMap[d.code] = devId;
      } else {
        const devRes = await targetPool.query(
          `INSERT INTO devices (device_code, device_type, device_name, serial_number, yard_id, online_status, device_status)
           VALUES ($1, $2, $3, $4, $5, $6, 'Active')
           RETURNING id`,
          [d.code, d.type, d.name, d.sn, yardMap[d.yardCode], d.online]
        );
        deviceMap[d.code] = devRes.rows[0].id;
      }

      // Add SIM record
      const existingSim = await targetPool.query(
        'SELECT id FROM device_sim_details WHERE device_id = $1',
        [deviceMap[d.code]]
      );
      if (existingSim.rows.length === 0) {
        await targetPool.query(
          `INSERT INTO device_sim_details (device_id, sim_available, sim_number, sim_operator, sim_status)
           VALUES ($1, true, $2, 'Airtel IoT', 'Active')`,
          [deviceMap[d.code], `8991${Math.floor(1000000000 + Math.random() * 9000000000)}`]
        );
      }
    }
    console.log('      Devices & SIM details seeded.');

    // G. Assign Dead-End Devices to Lines
    const deAssignments = [
      { devCode: 'DE-042', lineCode: 'LN-101', yardCode: 'NY-01' },
      { devCode: 'DE-088', lineCode: 'LN-102', yardCode: 'NY-01' },
      { devCode: 'DE-019', lineCode: 'LN-201', yardCode: 'SY-01' },
    ];

    for (const a of deAssignments) {
      const devId = deviceMap[a.devCode];
      const lineId = lineMap[a.lineCode];
      const yardId = yardMap[a.yardCode];

      if (devId && lineId && yardId) {
        const existingAssn = await targetPool.query(
          'SELECT id FROM device_line_assignments WHERE device_id = $1 AND line_id = $2',
          [devId, lineId]
        );
        if (existingAssn.rows.length === 0) {
          await targetPool.query(
            `INSERT INTO device_line_assignments (device_id, line_id, yard_id)
             VALUES ($1, $2, $3)`,
            [devId, lineId, yardId]
          );
        }
        await targetPool.query(
          'UPDATE devices SET assigned_line_id = $1 WHERE id = $2',
          [lineId, devId]
        );
      }
    }
    console.log('      Dead-end device line assignments seeded.');

    // G2. Seed Device Assignments (for Dashboard & Sessions)
    if (deviceMap['LD-001'] && userMap['YD-1010']) {
      const existingDa = await targetPool.query('SELECT id FROM device_assignments WHERE device_id = $1', [deviceMap['LD-001']]);
      if (existingDa.rows.length === 0) {
        await targetPool.query(
          `INSERT INTO device_assignments (device_id, employee_id, condition_at_issue, remarks)
           VALUES ($1, $2, 'Good', 'Active Shunting in North Yard')`,
          [deviceMap['LD-001'], userMap['YD-1010']]
        );
      }
    }

    // H. Insert Sample Shunting Session
    const checkSession = await targetPool.query(
      "SELECT id FROM shunting_sessions WHERE session_number = 'SESS-2026-001'"
    );

    if (checkSession.rows.length === 0 && deviceMap['LD-001'] && deviceMap['DE-042']) {
      const sessionRes = await targetPool.query(
        `INSERT INTO shunting_sessions (
           session_number, yard_id, employee_name, employee_id_number,
           ld_device_id, ld_code, de_device_id, de_code, line_id, dead_end_name,
           session_status, minimum_distance, final_placement_distance
         ) VALUES (
           'SESS-2026-001', $1, 'Rajesh Kumar', 'EMP-1102',
           $2, 'LD-001', $3, 'DE-042',
           $4, 'DE-Stop-101', 'Active', 12.4, 15.2
         ) RETURNING id`,
        [yardMap['NY-01'], deviceMap['LD-001'], deviceMap['DE-042'], lineMap['LN-101']]
      );

      if (sessionRes.rows.length > 0) {
        const sessionId = sessionRes.rows[0].id;
        await targetPool.query(
          `INSERT INTO session_events (session_id, event_type, distance, speed, zone, description)
           VALUES 
           ($1, 'CONNECTION_ESTABLISHED', 45.0, 4.5, 'Safe Zone', 'LD-001 connected with DE-042'),
           ($1, 'ZONE_ENTRY', 18.2, 3.1, 'Slow Zone', 'Loco entered slow zone (limit < 20m)'),
           ($1, 'DISTANCE_UPDATE', 12.4, 1.2, 'Slow Zone', 'Approaching buffer target')`,
          [sessionId]
        );
      }
      console.log('      Live Shunting Session and events seeded.');
    }

    // I. Insert Alerts
    const alertsToSeed = [
      {
        type: 'Operational',
        subtype: 'Speed Limit',
        title: 'Speed Warning in North Yard',
        desc: 'Loco Unit LD-001 speed reached 4.5 km/h in slow zone.',
        sev: 'Warning',
        yardCode: 'NY-01',
        devCode: 'LD-001',
      },
      {
        type: 'Device',
        subtype: 'Low Battery',
        title: 'DE-088 Battery Low',
        desc: 'Dead-End Unit DE-088 battery level is below 20%.',
        sev: 'Critical',
        yardCode: 'NY-01',
        devCode: 'DE-088',
      },
      {
        type: 'Administrative',
        subtype: 'Maintenance Due',
        title: 'Routine Inspection Required',
        desc: 'Pit Line 1 DE-042 scheduled maintenance check.',
        sev: 'Info',
        yardCode: 'NY-01',
        devCode: 'DE-042',
      },
    ];

    for (const alt of alertsToSeed) {
      const yId = yardMap[alt.yardCode];
      const dId = deviceMap[alt.devCode];
      const existingAlert = await targetPool.query(
        'SELECT id FROM alerts WHERE title = $1',
        [alt.title]
      );
      if (existingAlert.rows.length === 0) {
        await targetPool.query(
          `INSERT INTO alerts (alert_type, alert_subtype, title, description, severity, yard_id, device_id, alert_status)
           VALUES ($1, $2, $3, $4, $5, $6, $7, 'Open')`,
          [alt.type, alt.subtype, alt.title, alt.desc, alt.sev, yId, dId]
        );
      }

      const existingAlertLog = await targetPool.query(
        'SELECT id FROM alerts_logs WHERE message = $1',
        [alt.desc]
      );
      if (existingAlertLog.rows.length === 0) {
        await targetPool.query(
          `INSERT INTO alerts_logs (alert_type, message, severity, yard_id)
           VALUES ($1, $2, $3, $4)`,
          [alt.subtype, alt.desc, alt.sev.toUpperCase(), yId]
        );
      }
    }
    console.log('      Alerts seeded.');

    console.log('\n====================================================');
    console.log(' DATABASE INITIALIZATION COMPLETE!');
    console.log('====================================================');
    console.log('Available Login Credentials:');
    console.log('  1. Yard Administrator:');
    console.log('     Employee ID: YD-1010');
    console.log('     Password:    yard123');
    console.log('     Role:        yard_admin (North Yard & South Yard)');
    console.log('  2. Super Administrator:');
    console.log('     Employee ID: AN-1010');
    console.log('     Password:    admin123');
    console.log('     Role:        super_admin (All Yards)');
    console.log('====================================================\n');

    process.exit(0);
  } catch (err) {
    console.error('Error during setup:', err);
    process.exit(1);
  } finally {
    await targetPool.end();
  }
}

setupDatabase();
