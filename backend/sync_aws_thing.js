const db = require('./config/db');

async function addRealAwsThing() {
  const deviceId = 'SHN_RECEIVER_RX-01';
  const deviceName = 'SHN Receiver RX-01';
  const serialNumber = 'SN-SHN-RX-01';
  const productType = 'RECEIVER';
  const deviceType = 'RECEIVER';

  // Make yard_id nullable in devices
  try {
    await db.query('ALTER TABLE devices ALTER COLUMN yard_id DROP NOT NULL;');
  } catch (e) {
    console.log('yard_id nullable update:', e.message);
  }

  // 1. Insert into device_registry
  await db.query(`
    INSERT INTO device_registry (
      device_id, device_name, serial_number, product_type, device_type, hardware_version, firmware_version, health_status, last_reading_timestamp, created_at, updated_at
    ) VALUES ($1, $2, $3, $4, $5, '1.0', '2.0.0', 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (device_id) DO UPDATE SET
      device_name = $2,
      serial_number = $3,
      product_type = $4,
      device_type = $5,
      health_status = 'ONLINE',
      last_reading_timestamp = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP;
  `, [deviceId, deviceName, serialNumber, productType, deviceType]);
  console.log('1. Inserted/Updated device_registry for:', deviceId);

  // Delete existing in devices to prevent duplicates
  await db.query('DELETE FROM devices WHERE device_code = $1', [deviceId]);

  // 2. Insert into devices table
  await db.query(`
    INSERT INTO devices (
      id, device_code, device_name, serial_number, device_type, device_status, online_status, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), $1, $2, $3, $4, 'Available', 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    )
  `, [deviceId, deviceName, serialNumber, deviceType]);
  console.log('2. Inserted devices table for:', deviceId);

  // 3. Insert initial telemetry
  await db.query(`
    INSERT INTO device_telemetry (
      device_id, topic, payload, battery_level, signal_rssi, recorded_at
    ) VALUES ($1, $2, $3, 98, -65, CURRENT_TIMESTAMP)
  `, [deviceId, `devices/${deviceId}/telemetry`, JSON.stringify({ deviceId, battery_pct: 98, gsm_rssi: -65, status: 'ONLINE', timestamp: new Date().toISOString() })]);
  console.log('3. Inserted telemetry for:', deviceId);

  // Verify
  const reg = await db.query('SELECT device_id, device_name, serial_number, product_type, health_status, last_reading_timestamp FROM device_registry');
  console.log('ALL DEVICE REGISTRY ROWS:', reg.rows);
}

addRealAwsThing().catch(console.error).finally(() => process.exit());
