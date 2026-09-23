require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com',
  database: process.env.DB_NAME || 'safeshunt_db',
  password: process.env.DB_PASSWORD || 'pisolve123',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  ssl: { rejectUnauthorized: false }
});

function derivePairedDevice(deviceId) {
  if (deviceId.startsWith('TX-') || deviceId.startsWith('DE-')) {
    const num = deviceId.split('-')[1];
    return `RX-${num}`;
  } else if (deviceId.startsWith('RX-') || deviceId.startsWith('LD-')) {
    const num = deviceId.split('-')[1];
    return `TX-${num}`;
  }
  return deviceId.startsWith('RX') ? 'TX-01' : 'RX-01';
}

async function fixAndSync() {
  console.log('🚀 Step 1: Fixing shunting_sessions table constraints...');

  try {
    await pool.query(`
      ALTER TABLE shunting_sessions ALTER COLUMN yard_id DROP NOT NULL;
      ALTER TABLE shunting_sessions ALTER COLUMN ld_device_id DROP NOT NULL;
      ALTER TABLE shunting_sessions ALTER COLUMN de_device_id DROP NOT NULL;
      ALTER TABLE shunting_sessions ALTER COLUMN session_date DROP NOT NULL;
      ALTER TABLE shunting_sessions ALTER COLUMN session_date SET DEFAULT CURRENT_DATE;
      ALTER TABLE shunting_sessions ALTER COLUMN session_start DROP NOT NULL;
      ALTER TABLE shunting_sessions ALTER COLUMN session_start SET DEFAULT CURRENT_TIMESTAMP;
      ALTER TABLE shunting_sessions ALTER COLUMN session_status SET DEFAULT 'COMPLETED';
    `);
    console.log('✅ Constraints relaxed on shunting_sessions.');
  } catch (e) {
    console.warn('Constraint alteration note:', e.message);
  }

  // Step 2: Ensure default yard exists and sync devices table
  console.log('🚀 Step 2: Syncing all registered devices to devices table...');
  const defaultYardRes = await pool.query('SELECT id FROM yards LIMIT 1');
  const defaultYardId = defaultYardRes.rows[0]?.id;

  const regDevices = await pool.query('SELECT * FROM device_registry');
  for (const reg of regDevices.rows) {
    const devCode = reg.device_id;
    const devType = (reg.product_type?.toUpperCase().includes('TRANSMITTER') || devCode.startsWith('TX')) ? 'Dead-End' : 'Loco Unit';
    const yardId = reg.yard_id || defaultYardId;

    await pool.query(`
      INSERT INTO devices (
        id, device_code, device_type, device_name, serial_number, yard_id, firmware_version, created_at, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
      ON CONFLICT (id) DO UPDATE SET
        device_code = EXCLUDED.device_code,
        device_type = EXCLUDED.device_type,
        yard_id = COALESCE(devices.yard_id, EXCLUDED.yard_id),
        updated_at = CURRENT_TIMESTAMP
    `, [
      reg.id,
      devCode,
      devType,
      reg.device_name || devCode,
      reg.serial_number || devCode,
      yardId,
      reg.firmware_version || '1.0.0'
    ]);
  }
  console.log(`✅ Synced ${regDevices.rows.length} devices to devices table.`);

  // Step 3: Backfill shunting_sessions from device_telemetry
  console.log('🚀 Step 3: Backfilling shunting_sessions from device_telemetry...');

  // Get distinct devices that have telemetry
  const devTel = await pool.query(`
    SELECT DISTINCT device_id FROM device_telemetry WHERE device_id ILIKE 'TX%' OR device_id ILIKE 'RX%'
  `);

  const processedPairs = new Set();

  for (const d of devTel.rows) {
    const devId = d.device_id;
    const paired = derivePairedDevice(devId);
    const rxId = devId.startsWith('RX') ? devId : paired;
    const txId = devId.startsWith('TX') ? devId : paired;
    const pairKey = `${rxId}_${txId}`;

    if (processedPairs.has(pairKey)) continue;
    processedPairs.add(pairKey);

    const telRes = await pool.query(`
      SELECT id, device_id, distance_cm, speed_kmh, battery_level, signal_rssi, recorded_at
      FROM device_telemetry
      WHERE device_id = $1 OR device_id = $2
      ORDER BY recorded_at ASC
    `, [rxId, txId]);

    if (telRes.rows.length === 0) continue;

    // Group packets into sessions (gap > 2 min)
    const sessions = [];
    let cur = [];

    for (let i = 0; i < telRes.rows.length; i++) {
      const pt = telRes.rows[i];
      if (cur.length === 0) {
        cur.push(pt);
      } else {
        const prevT = new Date(cur[cur.length - 1].recorded_at).getTime();
        const currT = new Date(pt.recorded_at).getTime();
        if (currT - prevT > 120000) {
          sessions.push(cur);
          cur = [pt];
        } else {
          cur.push(pt);
        }
      }
    }
    if (cur.length > 0) sessions.push(cur);

    for (const sess of sessions) {
      const startTime = sess[0].recorded_at;
      const endTime = sess[sess.length - 1].recorded_at;
      const startTs = new Date(startTime).getTime();
      const endTs = new Date(endTime).getTime();
      const isLive = (Date.now() - endTs) < 60000;

      let minDistCm = 999999;
      let lastDistCm = 0;
      const trajectory = [];

      for (const pt of sess) {
        if (pt.distance_cm != null) {
          lastDistCm = pt.distance_cm;
          if (pt.distance_cm < minDistCm) minDistCm = pt.distance_cm;
          trajectory.push({
            t: new Date(pt.recorded_at).getTime(),
            d_cm: pt.distance_cm,
            speed_kmh: pt.speed_kmh || 0.0,
            battery: pt.battery_level || 95,
            signal: pt.signal_rssi || -65
          });
        }
      }

      if (minDistCm === 999999) minDistCm = lastDistCm;
      const sessionCode = `SES-${startTs.toString().slice(-6)}-${rxId}`;

      const exist = await pool.query(`
        SELECT id FROM shunting_sessions 
        WHERE (ld_code = $1 OR rx_device_id = $1)
          AND start_time >= ($2::timestamp - INTERVAL '1 MINUTE')
          AND start_time <= ($2::timestamp + INTERVAL '1 MINUTE')
      `, [rxId, startTime]);

      if (exist.rows.length === 0) {
        // Look up device UUIDs if available
        const rxDev = await pool.query('SELECT id, yard_id FROM devices WHERE device_code = $1 LIMIT 1', [rxId]);
        const txDev = await pool.query('SELECT id, yard_id FROM devices WHERE device_code = $1 LIMIT 1', [txId]);
        const yardId = rxDev.rows[0]?.yard_id || txDev.rows[0]?.yard_id || defaultYardId;

        await pool.query(`
          INSERT INTO shunting_sessions (
            session_number, session_code, session_date, yard_id,
            ld_code, rx_device_id, ld_device_id,
            de_code, tx_device_id, de_device_id,
            session_start, start_time, session_end, end_time,
            session_status, status, final_distance_cm, final_placement_distance,
            minimum_distance, distance_trajectory, employee_name, employee_id_number,
            created_at, updated_at
          ) VALUES (
            $1, $1, $2::date, $3,
            $4, $4, $5,
            $6, $6, $7,
            $8::timestamp, $8::timestamp, $9::timestamp, $9::timestamp,
            $10, $10, $11, $12,
            $13, $14::jsonb, 'ian', 'EMP-001',
            $8::timestamp, $9::timestamp
          )
        `, [
          sessionCode,
          new Date(startTime).toISOString().split('T')[0],
          yardId,
          rxId,
          rxDev.rows[0]?.id || null,
          txId,
          txDev.rows[0]?.id || null,
          startTime,
          isLive ? null : endTime,
          isLive ? 'LIVE' : 'COMPLETED',
          lastDistCm,
          lastDistCm / 100.0,
          minDistCm / 100.0,
          JSON.stringify(trajectory)
        ]);
        console.log(`✅ Created session in DB: ${sessionCode} (${rxId} <-> ${txId}) - Points: ${trajectory.length}`);
      }
    }
  }

  console.log('🎉 Full sync completed successfully!');
  await pool.end();
}

fixAndSync();
