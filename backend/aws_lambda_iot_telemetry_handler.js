/**
 * AWS LAMBDA FUNCTION: IoT Telemetry to PostgreSQL RDS Ingestion Handler
 * Runtime: Node.js 18.x or 20.x
 * 
 * AWS IoT Rule SQL:
 *   SELECT *, topic() as topic, timestamp() as msg_timestamp FROM 'devices/+/telemetry'
 *   (or SELECT * FROM 'devices/#' to capture status & telemetry)
 * 
 * Environment Variables in AWS Lambda:
 *   DB_HOST = safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com
 *   DB_NAME = safeshunt_db
 *   DB_USER = postgres
 *   DB_PASSWORD = pisolve123
 *   DB_PORT = 5432
 */

const { Client } = require('pg');

function derivePairedDevice(deviceId, payload) {
  if (payload.paired_tx_id) return payload.paired_tx_id;
  if (payload.paired_rx_id) return payload.paired_rx_id;
  if (payload.paired_device) return payload.paired_device;

  if (deviceId.startsWith('TX-') || deviceId.startsWith('DE-')) {
    const num = deviceId.split('-')[1];
    return `RX-${num}`;
  } else if (deviceId.startsWith('RX-') || deviceId.startsWith('LD-')) {
    const num = deviceId.split('-')[1];
    return `TX-${num}`;
  } else if (deviceId.startsWith('TX')) {
    return deviceId.replace('TX', 'RX');
  } else if (deviceId.startsWith('RX')) {
    return deviceId.replace('RX', 'TX');
  }
  return deviceId.startsWith('RX') ? 'TX-01' : 'RX-01';
}

exports.handler = async (event, context) => {
  console.log('Incoming AWS IoT Telemetry Event:', JSON.stringify(event, null, 2));

  // Extract Device ID
  let deviceId = event.deviceId || event.device_id || event.deviceCode || event.SerialNumber;
  const topic = event.topic || (deviceId ? `devices/${deviceId}/telemetry` : 'devices/unknown/telemetry');

  if (!deviceId && event.topic) {
    const parts = event.topic.split('/');
    if (parts.length >= 2 && parts[0] === 'devices') {
      deviceId = parts[1];
    }
  }

  if (!deviceId) {
    console.error('ERROR: No deviceId found in event or topic.');
    return { statusCode: 400, body: 'Missing deviceId' };
  }

  // Extract metrics
  const diagnostics = event.diagnostics || {};
  const readings = event.readings || {};

  const battery = diagnostics.battery_pct ?? event.battery_level ?? event.battery ?? null;
  const signal = diagnostics.gsm_rssi ?? event.signal_rssi ?? event.gsm_rssi ?? event.signal ?? null;
  const lat = event.latitude ?? event.lat ?? null;
  const lng = event.longitude ?? event.lng ?? null;

  let distanceCm = readings.distance_cm ?? event.distance_cm;
  if (distanceCm == null && event.distance != null) {
    try {
      distanceCm = Math.round(Number(event.distance) * 100);
    } catch (_) {
      distanceCm = null;
    }
  }

  const speedKmh = event.speed_kmh ?? event.speed ?? null;
  const productType = event.productType || event.product_type || (deviceId.startsWith('TX') ? 'TRANSMITTER' : 'RECEIVER');

  const client = new Client({
    host: process.env.DB_HOST || 'safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'pisolve123',
    database: process.env.DB_NAME || 'safeshunt_db',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();

    // 1. Insert Polling Log into device_telemetry
    const telemetryInsertSql = `
      INSERT INTO device_telemetry (
        device_id, topic, payload, battery_level, signal_rssi, latitude, longitude, distance_cm, speed_kmh, recorded_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP)
      RETURNING id, device_id, recorded_at;
    `;
    const res = await client.query(telemetryInsertSql, [
      deviceId,
      topic,
      JSON.stringify(event),
      battery,
      signal,
      lat,
      lng,
      distanceCm,
      speedKmh
    ]);

    console.log('Saved to device_telemetry with ID:', res.rows[0].id);

    // 2. Ensure device exists in device_registry and update last reading timestamp
    const registryUpsertSql = `
      INSERT INTO device_registry (
        device_id, device_name, serial_number, product_type, hardware_version, firmware_version, health_status, last_reading_timestamp, updated_at
      ) VALUES (
        $1, $1, $1, $2, '1.0', '1.0.0', 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
      ON CONFLICT (device_id) DO UPDATE SET
        health_status = 'ONLINE',
        last_reading_timestamp = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP;
    `;
    await client.query(registryUpsertSql, [deviceId, productType]);

    // 3. HARDWARE SESSION & PAIRING STATE MACHINE
    const eventType = event.event;
    const status = event.status;
    const pairedDevice = derivePairedDevice(deviceId, event);
    const rxId = (deviceId.startsWith('RX') || deviceId.startsWith('LD')) ? deviceId : pairedDevice;
    const txId = (deviceId.startsWith('TX') || deviceId.startsWith('DE')) ? deviceId : pairedDevice;

    if (topic.includes('/status') || ['PAIR_START', 'PAIR_END', 'UNEXPECTED_DISCONNECT'].includes(eventType)) {
      if (eventType === 'PAIR_START' || status === 'PAIRED') {
        const sessionCode = `SES-${Date.now().toString().slice(-6)}-${rxId}`;
        const existing = await client.query(
          "SELECT id FROM shunting_sessions WHERE (rx_device_id = $1 OR ld_code = $1) AND (status = 'LIVE' OR session_status = 'LIVE')",
          [rxId]
        );

        if (existing.rows.length === 0) {
          await client.query(`
            INSERT INTO shunting_sessions (
              session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
              session_start, start_time, session_status, status, distance_trajectory, created_at, updated_at
            ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', '[]'::jsonb, NOW(), NOW())
          `, [sessionCode, rxId, txId]);
          console.log(`[Lambda] Session Started: ${rxId} <--> ${txId}`);
        }
      } else if (eventType === 'PAIR_END' || status === 'IDLE') {
        const finalVal = event.final_distance_cm ?? distanceCm ?? 0;
        await client.query(`
          UPDATE shunting_sessions
          SET 
            session_end = NOW(),
            end_time = NOW(),
            session_status = 'COMPLETED',
            status = 'COMPLETED',
            final_distance_cm = $1,
            final_placement_distance = $1 / 100.0,
            updated_at = NOW()
          WHERE (rx_device_id = $2 OR ld_code = $2 OR tx_device_id = $3 OR de_code = $3) AND (status = 'LIVE' OR session_status = 'LIVE')
        `, [finalVal, rxId, txId]);
        console.log(`[Lambda] Session Ended: ${rxId} / ${txId}`);
      } else if (eventType === 'UNEXPECTED_DISCONNECT' || status === 'OFFLINE') {
        await client.query(`
          UPDATE shunting_sessions
          SET 
            session_end = NOW(),
            end_time = NOW(),
            session_status = 'TIMED_OUT',
            status = 'TIMED_OUT',
            manual_close_reason = 'Hardware Unexpected Disconnect / LWT',
            updated_at = NOW()
          WHERE (rx_device_id = $1 OR ld_code = $1 OR tx_device_id = $2 OR de_code = $2) AND (status = 'LIVE' OR session_status = 'LIVE')
        `, [rxId, txId]);
        console.log(`[Lambda] Session Timed Out: ${rxId} / ${txId}`);
      }
    }

    // 4. Distance Telemetry Point from TX or RX
    if (distanceCm !== null && distanceCm !== undefined) {
      const point = JSON.stringify({
        t: event.cloud_timestamp || Date.now(),
        d_cm: distanceCm,
        speed_kmh: speedKmh || 0.0,
        battery: battery,
        signal: signal
      });

      const updateRes = await client.query(`
        UPDATE shunting_sessions
        SET 
          distance_trajectory = COALESCE(distance_trajectory, '[]'::jsonb) || $1::jsonb,
          final_distance_cm = $2,
          final_placement_distance = $2 / 100.0,
          minimum_distance = LEAST(COALESCE(minimum_distance, $2 / 100.0), $2 / 100.0),
          updated_at = NOW()
        WHERE (tx_device_id = $3 OR de_code = $3 OR rx_device_id = $4 OR ld_code = $4)
          AND (status = 'LIVE' OR session_status = 'LIVE')
      `, [point, distanceCm, txId, rxId]);

      if (updateRes.rowCount === 0) {
        const sessionCode = `SES-${Date.now().toString().slice(-6)}-${rxId}`;
        await client.query(`
          INSERT INTO shunting_sessions (
            session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
            session_start, start_time, session_status, status, final_distance_cm, final_placement_distance,
            minimum_distance, distance_trajectory, created_at, updated_at
          ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', $4, $4 / 100.0, $4 / 100.0, $5::jsonb, NOW(), NOW())
        `, [sessionCode, rxId, txId, distanceCm, JSON.stringify([JSON.parse(point)])]);
        console.log(`[Lambda] Auto-created live session: ${rxId} <--> ${txId}`);
      }
    }

    // 5. Insert into legacy telemetry_data for compatibility
    try {
      await client.query(
        'INSERT INTO telemetry_data (device_id, payload, recorded_at) VALUES ($1, $2, CURRENT_TIMESTAMP)',
        [deviceId, JSON.stringify(event)]
      );
    } catch (_) {}

    await client.end();
    return { statusCode: 200, body: JSON.stringify({ success: true, id: res.rows[0].id }) };
  } catch (err) {
    console.error('Database Error in Lambda:', err);
    try { await client.end(); } catch (_) {}
    return { statusCode: 500, body: err.message };
  }
};
