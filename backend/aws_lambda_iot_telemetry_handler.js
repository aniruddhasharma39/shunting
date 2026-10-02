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
 *   DB_PASSWORD = ********
 *   DB_PORT = 5432
 */

const { Client } = require('pg');

function derivePairedDevice(deviceId, payload) {
  if (payload.paired_tx_id) return payload.paired_tx_id;
  if (payload.paired_rx_id) return payload.paired_rx_id;
  if (payload.paired_device) return payload.paired_device;

  const readings = payload.readings || {};
  const selectedTargetId = readings.selected_target_id || payload.selected_target_id;
  if (selectedTargetId && selectedTargetId > 0) {
    if (deviceId.startsWith('RX-') || deviceId.startsWith('LD-')) {
      return `TX-${String(selectedTargetId).padStart(2, '0')}`;
    } else {
      return `RX-${String(selectedTargetId).padStart(2, '0')}`;
    }
  }

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

  // Normalize device ID by extracting the base device code (e.g. RX-05, TX-14) from complex AWS IoT Thing names (e.g. SHN-NWR-JP-KWP-RX-05)
  const match = deviceId.match(/(RX-\d+|TX-\d+|DE-\d+|LD-\d+)$/);
  if (match) {
    deviceId = match[1];
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
    password: process.env.DB_PASSWORD,
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
          // Lookup active assignment for this RX device
          const assignmentRes = await client.query(`
            SELECT u.full_name, u.employee_id 
            FROM device_assignments da
            JOIN users u ON da.employee_id = u.id
            JOIN devices d ON d.id = da.device_id
            WHERE (d.device_code = $1 OR d.id::text = $1) AND da.returned_at IS NULL
            ORDER BY da.issued_at DESC LIMIT 1
          `, [rxId]);
          
          let empName = null;
          let empIdNum = null;
          if (assignmentRes.rows.length > 0) {
            empName = assignmentRes.rows[0].full_name;
            empIdNum = assignmentRes.rows[0].employee_id;
          }

          // Only trust explicit pairing fields, NOT selected_target_id (factory default like 11)
          const hasRealPairing = Boolean(event.paired_tx_id || event.paired_rx_id || event.paired_device);
          const isTrustedPairEvent = (eventType === 'PAIR_START');

          if (!hasRealPairing && !isTrustedPairEvent) {
            console.log(`[Lambda] Ignored ghost session: ${rxId} - no real pairing evidence.`);
          } else {
            await client.query(`
              INSERT INTO shunting_sessions (
                session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
                session_start, start_time, session_status, status, distance_trajectory, employee_name, employee_id_number, created_at, updated_at
              ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', '[]'::jsonb, $4, $5, NOW(), NOW())
            `, [sessionCode, rxId, txId, empName, empIdNum]);
            console.log(`[Lambda] Session Started: ${rxId} <--> ${txId} for ${empName || 'Unknown'}`);
          }
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
            final_distance_cm = $1::numeric,
            final_placement_distance = $1::numeric / 100.0,
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

      const readings = event.readings || {};
      const selectedTargetId = readings.selected_target_id ?? event.selected_target_id;

      if (selectedTargetId === 0) {
        await client.query(`
          UPDATE shunting_sessions
          SET 
            session_end = NOW(),
            end_time = NOW(),
            session_status = 'COMPLETED',
            status = 'COMPLETED',
            manual_close_reason = 'Hardware un-paired (target=0)',
            updated_at = NOW()
          WHERE (rx_device_id = $1 OR ld_code = $1) AND (status = 'LIVE' OR session_status = 'LIVE')
        `, [rxId]);
        await client.end();
        return { statusCode: 200, body: JSON.stringify({ success: true, message: 'Unpaired' }) };
      }

      const updateRes = await client.query(`
        UPDATE shunting_sessions
        SET 
          distance_trajectory = COALESCE(distance_trajectory, '[]'::jsonb) || $1::jsonb,
          final_distance_cm = $2::numeric,
          final_placement_distance = $2::numeric / 100.0,
          minimum_distance = LEAST(COALESCE(minimum_distance, $2::numeric / 100.0), $2::numeric / 100.0),
          updated_at = NOW()
        WHERE (tx_device_id = $3 OR de_code = $3 OR rx_device_id = $4 OR ld_code = $4)
          AND (status = 'LIVE' OR session_status = 'LIVE')
      `, [point, distanceCm, txId, rxId]);

      if (updateRes.rowCount === 0) {
        // Only trust explicit pairing fields, NOT selected_target_id (factory default)
        const hasRealPairing = Boolean(event.paired_tx_id || event.paired_rx_id || event.paired_device);
        const isTrustedPairEvent = (event.event === 'PAIR_START');
        
        if (hasRealPairing || isTrustedPairEvent) {
          const sessionCode = `SES-${Date.now().toString().slice(-6)}-${rxId}`;
          const assignmentRes = await client.query(`
            SELECT u.full_name, u.employee_id 
            FROM device_assignments da
            JOIN users u ON da.employee_id = u.id
            JOIN devices d ON d.id = da.device_id
            WHERE (d.device_code = $1 OR d.id::text = $1) AND da.returned_at IS NULL
            ORDER BY da.issued_at DESC LIMIT 1
          `, [rxId]);
          
          let empName = null;
          let empIdNum = null;
          if (assignmentRes.rows.length > 0) {
            empName = assignmentRes.rows[0].full_name;
            empIdNum = assignmentRes.rows[0].employee_id;
          }

          await client.query(`
            INSERT INTO shunting_sessions (
              session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
              session_start, start_time, session_status, status, final_distance_cm, final_placement_distance,
              minimum_distance, distance_trajectory, employee_name, employee_id_number, created_at, updated_at
            ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', $4::numeric, $4::numeric / 100.0, $4::numeric / 100.0, $5::jsonb, $6, $7, NOW(), NOW())
          `, [sessionCode, rxId, txId, distanceCm, JSON.stringify([JSON.parse(point)]), empName, empIdNum]);
          console.log(`[Lambda] Auto-created live session: ${rxId} <--> ${txId} for ${empName || 'Unknown'}`);
        }
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
