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

async function run() {
  console.log('🔄 Backfilling past telemetry into shunting_sessions...');

  try {
    // Group telemetry into sessions per device cluster
    const devRes = await pool.query(`
      SELECT DISTINCT device_id FROM device_telemetry WHERE device_id ILIKE 'TX%' OR device_id ILIKE 'RX%'
    `);

    for (const dev of devRes.rows) {
      const devId = dev.device_id;
      const paired = derivePairedDevice(devId);
      const rxId = devId.startsWith('RX') ? devId : paired;
      const txId = devId.startsWith('TX') ? devId : paired;

      // Fetch all telemetry for this device
      const telRes = await pool.query(`
        SELECT id, distance_cm, speed_kmh, battery_level, signal_rssi, recorded_at
        FROM device_telemetry
        WHERE device_id = $1 OR device_id = $2
        ORDER BY recorded_at ASC
      `, [devId, paired]);

      if (telRes.rows.length === 0) continue;

      // Group packets into sessions (split if gap > 3 minutes)
      let currentSession = [];
      const sessions = [];

      for (let i = 0; i < telRes.rows.length; i++) {
        const row = telRes.rows[i];
        if (currentSession.length === 0) {
          currentSession.push(row);
        } else {
          const prevTime = new Date(currentSession[currentSession.length - 1].recorded_at).getTime();
          const currTime = new Date(row.recorded_at).getTime();
          if (currTime - prevTime > 180000) { // > 3 min gap
            sessions.push(currentSession);
            currentSession = [row];
          } else {
            currentSession.push(row);
          }
        }
      }
      if (currentSession.length > 0) {
        sessions.push(currentSession);
      }

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

        // Check if session already exists for this time range
        const exist = await pool.query(`
          SELECT id FROM shunting_sessions 
          WHERE (ld_code = $1 OR rx_device_id = $1)
            AND start_time >= ($2::timestamp - INTERVAL '1 MINUTE')
            AND start_time <= ($2::timestamp + INTERVAL '1 MINUTE')
        `, [rxId, startTime]);

        if (exist.rows.length === 0) {
          await pool.query(`
            INSERT INTO shunting_sessions (
              session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
              session_start, start_time, session_end, end_time,
              session_status, status, final_distance_cm, final_placement_distance,
              minimum_distance, distance_trajectory, created_at, updated_at
            ) VALUES (
              $1, $1, $2, $2, $3, $3,
              $4::timestamp, $4::timestamp, $5::timestamp, $5::timestamp,
              $6, $6, $7::int, $8::numeric,
              $9::numeric, $10::jsonb, $4::timestamp, $5::timestamp
            )
          `, [
            sessionCode,
            rxId,
            txId,
            startTime,
            isLive ? null : endTime,
            isLive ? 'LIVE' : 'COMPLETED',
            lastDistCm,
            lastDistCm / 100.0,
            minDistCm / 100.0,
            JSON.stringify(trajectory)
          ]);
          console.log(`✅ Backfilled session: ${sessionCode} (${rxId} <-> ${txId}) with ${trajectory.length} trajectory points`);
        }
      }
    }

    console.log('🎉 Done backfilling telemetry to shunting_sessions!');
  } catch (err) {
    console.error('Error during backfill:', err);
  } finally {
    await pool.end();
  }
}

run();
