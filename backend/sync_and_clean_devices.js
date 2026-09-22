const db = require('./config/db');

async function syncAndClean() {
  try {
    console.log('--- Starting Device Registry & Devices Sync and Cleanup ---');

    // 1. Add assigned_line_id and yard_id to device_registry if not exists
    await db.query(`
      ALTER TABLE device_registry 
      ADD COLUMN IF NOT EXISTS assigned_line_id UUID REFERENCES yard_lines(id) ON DELETE SET NULL;
      
      ALTER TABLE device_registry 
      ADD COLUMN IF NOT EXISTS yard_id UUID REFERENCES yards(id) ON DELETE SET NULL;

      ALTER TABLE device_registry 
      ADD COLUMN IF NOT EXISTS device_type VARCHAR(50);
    `);
    console.log('Columns verified on device_registry table.');

    // 2. Remove fake mock alerts from alerts_logs and alerts
    try {
      await db.query(`
        DELETE FROM alerts_logs WHERE alert_type ILIKE '%MOCK%' OR message ILIKE '%Simulated%';
      `);
    } catch (_) {}
    try {
      await db.query(`
        DELETE FROM alerts WHERE alert_type ILIKE '%MOCK%' OR message ILIKE '%Simulated%';
      `);
    } catch (_) {}
    console.log('Cleaned mock alerts.');

    // 3. Remove hardcoded dummy devices from devices and all referencing tables
    const existingRegistry = await db.query('SELECT * FROM device_registry');
    const validDeviceIds = existingRegistry.rows.map(r => r.device_id);

    console.log('Real devices in device_registry:', validDeviceIds);

    const fakeDevicesSubquery = `
      SELECT id FROM devices WHERE device_code NOT IN (SELECT device_id FROM device_registry)
    `;

    const dependentTables = [
      'device_assignments',
      'device_line_assignments',
      'device_issue_returns',
      'device_heartbeats',
      'device_health_status',
      'shunting_sessions',
      'alerts',
      'maintenance_records',
      'device_sim_details',
      'telemetry_data'
    ];

    for (const table of dependentTables) {
      try {
        if (table === 'shunting_sessions') {
          await db.query(`DELETE FROM shunting_sessions WHERE ld_device_id IN (${fakeDevicesSubquery}) OR de_device_id IN (${fakeDevicesSubquery})`);
        } else if (table === 'telemetry_data') {
          await db.query(`DELETE FROM telemetry_data WHERE device_id NOT IN (SELECT device_id FROM device_registry) AND device_id NOT IN (SELECT id::text FROM device_registry)`);
        } else {
          await db.query(`DELETE FROM ${table} WHERE device_id IN (${fakeDevicesSubquery})`);
        }
      } catch (err) {
        // Table might not exist in some setups
      }
    }

    await db.query(`DELETE FROM devices WHERE device_code NOT IN (SELECT device_id FROM device_registry)`);
    console.log('Cleaned mock devices.');

    // 4. Clean devices table to prevent UUID / serial_number mismatch and resync directly from device_registry
    await db.query('DELETE FROM devices');

    for (const reg of existingRegistry.rows) {
      // Determine device_type mapping
      let devType = reg.device_type;
      if (!devType) {
        if (reg.product_type === 'RECEIVER' || reg.device_id.startsWith('RX') || reg.device_id.startsWith('LD') || reg.device_id.includes('RECEIVER')) {
          devType = 'Loco Unit';
        } else if (reg.product_type === 'TRANSMITTER' || reg.device_id.startsWith('TX') || reg.device_id.startsWith('DE') || reg.device_id.includes('TRANSMITTER')) {
          devType = 'Dead-End';
        } else if (reg.product_type === 'REPEATER') {
          devType = 'Portable';
        } else {
          devType = reg.product_type || 'Loco Unit';
        }
      }

      // Update device_registry device_type
      await db.query(
        'UPDATE device_registry SET device_type = $1 WHERE id = $2',
        [devType, reg.id]
      );

      // Get first active yard for yard_id requirement if yard_id is null
      let yardId = reg.yard_id;
      if (!yardId) {
        const yardRes = await db.query('SELECT id FROM yards LIMIT 1');
        yardId = yardRes.rows[0]?.id;
      }

      if (yardId) {
        await db.query(`
          INSERT INTO devices (
            id, device_code, device_type, device_name, serial_number, yard_id, firmware_version, assigned_line_id, created_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP)
        `, [
          reg.id,
          reg.device_id,
          devType,
          reg.device_name || reg.device_id,
          reg.serial_number || `SN-${reg.device_id}`,
          yardId,
          reg.firmware_version || '1.0.0',
          reg.assigned_line_id || null,
          reg.created_at || new Date()
        ]);
      }
    }

    console.log('Synced all device_registry records to devices table.');

    // 5. Verify results
    const devicesAfter = await db.query('SELECT id, device_code, device_type FROM devices');
    console.log('Current devices in database:', devicesAfter.rows);

    process.exit(0);
  } catch (err) {
    console.error('Error in syncAndClean:', err);
    process.exit(1);
  }
}

syncAndClean();
