/**
 * AWS LAMBDA FUNCTION: IoT Telemetry to PostgreSQL RDS Ingestion Handler
 * Runtime: Node.js 18.x or 20.x
 * 
 * AWS IoT Rule SQL:
 *   SELECT *, topic() as topic, timestamp() as msg_timestamp FROM 'devices/+/telemetry'
 * 
 * Environment Variables in AWS Lambda:
 *   DB_HOST = safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com
 *   DB_NAME = safeshunt_db
 *   DB_USER = postgres
 *   DB_PASSWORD = pisolve123
 *   DB_PORT = 5432
 */

const { Client } = require('pg');

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

  // Extract metrics from nested STM32 telemetry or flat fields
  const battery = event.diagnostics?.battery_pct ?? event.battery_level ?? event.battery ?? null;
  const signal = event.diagnostics?.gsm_rssi ?? event.signal_rssi ?? event.gsm_rssi ?? event.signal ?? null;
  const lat = event.latitude ?? event.lat ?? null;
  const lng = event.longitude ?? event.lng ?? null;
  const distanceCm = event.readings?.distance_cm ?? event.distance_cm ?? (event.distance ? Math.round(Number(event.distance) * 100) : null);
  const speedKmh = event.speed_kmh ?? event.speed ?? null;
  const productType = event.productType || event.product_type || 'RECEIVER';

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

    // 3. HARDWARE SESSION & PAIRING STATE MACHINE (devices/RX-XX/status)
    const eventType = event.event;
    const status = event.status;
    const pairedTxId = event.paired_tx_id;
    const lastDistCm = event.last_distance_cm ?? distanceCm;
    const finalDistCm = event.final_distance_cm;

    if (topic.includes('/status')) {
      if ((eventType === 'PAIR_START' || status === 'PAIRED') && pairedTxId) {
        const sessionCode = `SES-${Date.now().toString().slice(-6)}-${deviceId}`;
        const existing = await client.query(
          "SELECT id FROM shunting_sessions WHERE (rx_device_id = $1 OR ld_code = $1) AND (status = 'LIVE' OR session_status = 'LIVE')",
          [deviceId]
        );

        if (existing.rows.length === 0) {
          await client.query(`
            INSERT INTO shunting_sessions (
              session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
              session_start, start_time, session_status, status, distance_trajectory, created_at, updated_at
            ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', '[]'::jsonb, NOW(), NOW())
          `, [sessionCode, deviceId, pairedTxId]);
          console.log(`[Lambda] Session Started: ${deviceId} <--> ${pairedTxId}`);
        } else if (lastDistCm != null) {
          const point = JSON.stringify({ t: event.cloud_timestamp || Date.now(), d_cm: lastDistCm });
          await client.query(`
            UPDATE shunting_sessions
            SET 
              distance_trajectory = COALESCE(distance_trajectory, '[]'::jsonb) || $1::jsonb,
              final_distance_cm = $2,
              final_placement_distance = $2 / 100.0,
              updated_at = NOW()
            WHERE id = $3
          `, [point, lastDistCm, existing.rows[0].id]);
        }
      } else if (eventType === 'PAIR_END' || status === 'IDLE') {
        const finalVal = finalDistCm ?? lastDistCm ?? 0;
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
          WHERE (rx_device_id = $2 OR ld_code = $2) AND (status = 'LIVE' OR session_status = 'LIVE')
        `, [finalVal, deviceId]);
        console.log(`[Lambda] Session Ended: ${deviceId}`);
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
          WHERE (rx_device_id = $1 OR ld_code = $1) AND (status = 'LIVE' OR session_status = 'LIVE')
        `, [deviceId]);
        console.log(`[Lambda] Session Timed Out (LWT): ${deviceId}`);
      }
    }

    // 4. Distance Telemetry Point from TX
    if (distanceCm !== null && deviceId.startsWith('TX')) {
      const point = JSON.stringify({ t: event.cloud_timestamp || Date.now(), d_cm: distanceCm });
      await client.query(`
        UPDATE shunting_sessions
        SET 
          distance_trajectory = COALESCE(distance_trajectory, '[]'::jsonb) || $1::jsonb,
          final_distance_cm = $2,
          final_placement_distance = $2 / 100.0,
          minimum_distance = LEAST(COALESCE(minimum_distance, $2 / 100.0), $2 / 100.0),
          updated_at = NOW()
        WHERE (tx_device_id = $3 OR de_code = $3) AND (status = 'LIVE' OR session_status = 'LIVE')
      `, [point, distanceCm, deviceId]);
    }

    await client.end();
    return { statusCode: 200, body: JSON.stringify({ success: true, id: res.rows[0].id }) };
  } catch (err) {
    console.error('Database Error in Lambda:', err);
    try { await client.end(); } catch (_) {}
    return { statusCode: 500, body: err.message };
  }
};
