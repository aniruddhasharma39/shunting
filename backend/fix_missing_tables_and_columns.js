const db = require('./config/db');

async function fixSchema() {
  try {
    console.log('--- Applying Schema Fixes for Dashboard, Sessions, and Devices ---');

    // 1. Add missing columns to devices table
    console.log('1. Adding missing columns to devices...');
    await db.query(`
      ALTER TABLE devices 
        ADD COLUMN IF NOT EXISTS assigned_line_id UUID REFERENCES yard_lines(id) ON DELETE SET NULL,
        ADD COLUMN IF NOT EXISTS network_status VARCHAR(50) DEFAULT 'Online',
        ADD COLUMN IF NOT EXISTS battery_level VARCHAR(20) DEFAULT '92%',
        ADD COLUMN IF NOT EXISTS condition_status VARCHAR(50) DEFAULT 'Good',
        ADD COLUMN IF NOT EXISTS sim_status VARCHAR(50) DEFAULT 'Active';
    `);
    // Sync network_status with online_status if online_status has values
    await db.query(`
      UPDATE devices 
      SET network_status = COALESCE(online_status, 'Online') 
      WHERE network_status IS NULL;
    `);
    console.log('   OK');

    // 2. Create device_assignments table
    console.log('2. Creating device_assignments table...');
    await db.query(`
      CREATE TABLE IF NOT EXISTS device_assignments (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        returned_at TIMESTAMP,
        condition_at_issue VARCHAR(50) DEFAULT 'Good',
        condition_at_return VARCHAR(50),
        fault_reported VARCHAR(50),
        remarks TEXT
      );
    `);
    console.log('   OK');

    // 3. Create alerts_logs table
    console.log('3. Creating alerts_logs table...');
    await db.query(`
      CREATE TABLE IF NOT EXISTS alerts_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        alert_type VARCHAR(50) NOT NULL,
        message TEXT NOT NULL,
        severity VARCHAR(50) NOT NULL,
        yard_id UUID REFERENCES yards(id) ON DELETE CASCADE,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    console.log('   OK');

    // 4. Create telemetry_data table
    console.log('4. Creating telemetry_data table...');
    await db.query(`
      CREATE TABLE IF NOT EXISTS telemetry_data (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        payload JSONB NOT NULL,
        recorded_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX IF NOT EXISTS idx_telemetry_device_time ON telemetry_data(device_id, recorded_at DESC);
    `);
    console.log('   OK');

    // 5. Connect devices to yard lines via assigned_line_id
    console.log('5. Mapping devices to lines in devices.assigned_line_id...');
    const lines = await db.query('SELECT id, line_number, line_name, yard_id FROM yard_lines LIMIT 5');
    const pitLine = lines.rows.find(l => l.line_number === 'LN-101' || l.line_name.includes('Pit')) || lines.rows[0];
    const stablingLine = lines.rows.find(l => l.line_number === 'LN-102' || l.line_name.includes('Stabling')) || lines.rows[1];

    if (pitLine) {
      await db.query(
        "UPDATE devices SET assigned_line_id = $1 WHERE device_code = 'DE-042'",
        [pitLine.id]
      );
    }
    if (stablingLine) {
      await db.query(
        "UPDATE devices SET assigned_line_id = $1 WHERE device_code = 'DE-088'",
        [stablingLine.id]
      );
    }
    console.log('   OK');

    // 6. Seed sample device assignments (for active and past sessions)
    console.log('6. Seeding device assignments...');
    const users = await db.query("SELECT id FROM users WHERE employee_id IN ('YD-1010', 'AN-1010', 'SA-001') LIMIT 2");
    const testUser = users.rows[0] || (await db.query('SELECT id FROM users LIMIT 1')).rows[0];

    const ldDev = (await db.query("SELECT id FROM devices WHERE device_code = 'LD-001' LIMIT 1")).rows[0] ||
                  (await db.query("SELECT id FROM devices WHERE device_type LIKE '%Loco%' LIMIT 1")).rows[0] ||
                  (await db.query("SELECT id FROM devices LIMIT 1")).rows[0];

    const pdDev = (await db.query("SELECT id FROM devices WHERE device_code = 'PD-011' OR device_code = 'PD-022' LIMIT 1")).rows[0] ||
                  (await db.query("SELECT id FROM devices LIMIT 1")).rows[0];

    if (testUser && ldDev) {
      // Check if assignment already exists
      const existing = await db.query('SELECT id FROM device_assignments WHERE device_id = $1', [ldDev.id]);
      if (existing.rows.length === 0) {
        // Active session
        const activeAssn = await db.query(
          `INSERT INTO device_assignments (device_id, employee_id, condition_at_issue, remarks)
           VALUES ($1, $2, 'Good', 'Active Shunting in North Yard')
           RETURNING id`,
          [ldDev.id, testUser.id]
        );

        // Also add telemetry for this device
        await db.query(
          `INSERT INTO telemetry_data (device_id, payload, recorded_at)
           VALUES ($1, $2, CURRENT_TIMESTAMP)`,
          [
            ldDev.id,
            JSON.stringify({
              distance: 14.5,
              distance_show: '14.5m',
              battery: 88,
              speed: 2.3,
              location: 'North Yard',
              pit_lane: pitLine ? pitLine.line_name : 'Pit Line 1'
            })
          ]
        );
      }

      if (pdDev) {
        const existingPd = await db.query('SELECT id FROM device_assignments WHERE device_id = $1', [pdDev.id]);
        if (existingPd.rows.length === 0) {
          // Completed session
          await db.query(
            `INSERT INTO device_assignments (device_id, employee_id, condition_at_issue, condition_at_return, returned_at, remarks)
             VALUES ($1, $2, 'Good', 'Good', CURRENT_TIMESTAMP - INTERVAL '2 HOURS', 'Completed Shunting Session')`,
            [pdDev.id, testUser.id]
          );
        }
      }
    }
    console.log('   OK');

    // 7. Seed sample alerts in alerts_logs
    console.log('7. Seeding sample alerts into alerts_logs...');
    const yard = (await db.query("SELECT id FROM yards LIMIT 1")).rows[0];
    const yardId = yard ? yard.id : null;

    const existingAlerts = await db.query('SELECT COUNT(*) FROM alerts_logs');
    if (parseInt(existingAlerts.rows[0].count, 10) === 0) {
      await db.query(
        `INSERT INTO alerts_logs (alert_type, message, severity, yard_id)
         VALUES 
         ('Speed Violation', 'Loco Unit LD-001 exceeded safe shunting speed (4.8 km/h).', 'CRITICAL', $1),
         ('Buffer Proximity', 'Distance to dead-end buffer below warning threshold (14.5m).', 'WARNING', $1),
         ('Routine Heartbeat', 'DE-042 dead-end unit heartbeat received successfully.', 'INFO', $1)`,
        [yardId]
      );
    }
    console.log('   OK');

    console.log('\n--- ALL DASHBOARD & SESSION PREREQUISITES RESOLVED SUCCESSFULLY! ---');
    process.exit(0);
  } catch (err) {
    console.error('Error fixing schema:', err);
    process.exit(1);
  }
}

fixSchema();
