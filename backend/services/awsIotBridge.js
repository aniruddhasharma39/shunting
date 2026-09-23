const crypto = require('crypto');
const mqtt = require('mqtt');
const db = require('../config/db');

class AwsIotBridge {
  constructor() {
    this.client = null;
    this.isConnected = false;
    this.subscribers = new Set(); // Active SSE / listener callbacks
    this.recentPackets = []; // In-memory ring buffer for sub-second latency
    this.maxBufferSize = 100;
  }

  getSignatureKey(key, dateStamp, regionName, serviceName) {
    const kDate = crypto.createHmac('sha256', 'AWS4' + key).update(dateStamp).digest();
    const kRegion = crypto.createHmac('sha256', kDate).update(regionName).digest();
    const kService = crypto.createHmac('sha256', kRegion).update(serviceName).digest();
    const kSigning = crypto.createHmac('sha256', kService).update('aws4_request').digest();
    return kSigning;
  }

  getSignedWebSocketUrl() {
    const endpoint = process.env.AWS_IOT_ENDPOINT;
    const region = process.env.AWS_REGION || 'ap-south-1';
    const accessKeyId = process.env.AWS_ACCESS_KEY_ID;
    const secretAccessKey = process.env.AWS_SECRET_ACCESS_KEY;

    if (!endpoint || !accessKeyId || !secretAccessKey) {
      return null;
    }

    const date = new Date();
    const amzDate = date.toISOString().replace(/[:-]|\.\d{3}/g, '');
    const dateStamp = amzDate.substr(0, 8);
    const service = 'iotdevicegateway';

    const algorithm = 'AWS4-HMAC-SHA256';
    const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;

    const canonicalQuerystring = [
      `X-Amz-Algorithm=${algorithm}`,
      `X-Amz-Credential=${encodeURIComponent(`${accessKeyId}/${credentialScope}`)}`,
      `X-Amz-Date=${amzDate}`,
      `X-Amz-SignedHeaders=host`
    ].join('&');

    const canonicalHeaders = `host:${endpoint}\n`;
    const signedHeaders = 'host';
    const payloadHash = crypto.createHash('sha256').update('').digest('hex');

    const canonicalRequest = [
      'GET',
      '/mqtt',
      canonicalQuerystring,
      canonicalHeaders,
      signedHeaders,
      payloadHash
    ].join('\n');

    const stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      crypto.createHash('sha256').update(canonicalRequest).digest('hex')
    ].join('\n');

    const signingKey = this.getSignatureKey(secretAccessKey, dateStamp, region, service);
    const signature = crypto.createHmac('sha256', signingKey).update(stringToSign).digest('hex');

    return `wss://${endpoint}:443/mqtt?${canonicalQuerystring}&X-Amz-Signature=${signature}`;
  }

  initialize() {
    const signedUrl = this.getSignedWebSocketUrl();
    if (!signedUrl) {
      console.log('⚠️ AWS IoT credentials not fully configured in .env. AWS IoT Bridge skipped.');
      return;
    }

    const clientId = `safeshunt_backend_bridge_${Math.random().toString(16).substring(2, 10)}`;
    console.log(`[AWS IoT] Connecting to ${process.env.AWS_IOT_ENDPOINT} as ${clientId}...`);

    try {
      this.client = mqtt.connect(signedUrl, {
        clientId,
        protocol: 'wss',
        port: 443,
        clean: true,
        reconnectPeriod: 5000,
        connectTimeout: 10000,
      });

      this.client.on('connect', () => {
        this.isConnected = true;
        console.log('✅ [AWS IoT] Connected directly to AWS IoT Core MQTT Broker (SigV4)!');

        const topics = ['devices/+/telemetry', 'devices/#'];
        this.client.subscribe(topics, (err, granted) => {
          if (err) {
            console.error('❌ [AWS IoT] Subscription error:', err);
          } else {
            console.log('📡 [AWS IoT] Active Subscriptions:');
            granted.forEach(g => console.log(`   ✓ ${g.topic}`));
          }
        });
      });

      this.client.on('message', (topic, message) => {
        this.handleIncomingMqttMessage(topic, message);
      });

      this.client.on('error', (err) => {
        console.error('❌ [AWS IoT] Client error:', err.message || err);
      });

      this.client.on('close', () => {
        this.isConnected = false;
      });

    } catch (err) {
      console.error('❌ [AWS IoT] Failed to initialize MQTT client:', err);
    }
  }

  async handleIncomingMqttMessage(topic, messageBuffer) {
    const rawStr = messageBuffer.toString();
    const timeIST = new Date().toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata' });
    const dateIST = new Date().toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata' });

    let payloadObj = null;
    try {
      payloadObj = JSON.parse(rawStr);
    } catch (_) {
      payloadObj = { raw: rawStr };
    }

    // Extract device ID from topic or payload
    let deviceId = payloadObj.deviceId || payloadObj.device_id || payloadObj.deviceCode;
    if (!deviceId && topic) {
      const parts = topic.split('/');
      if (parts.length >= 2 && parts[0] === 'devices') {
        deviceId = parts[1];
      }
    }
    deviceId = deviceId || 'UNKNOWN';

    // Extract common metrics
    const battery = payloadObj.battery_pct ?? payloadObj.battery_level ?? payloadObj.battery ?? null;
    const signal = payloadObj.gsm_rssi ?? payloadObj.signal_rssi ?? payloadObj.signal ?? null;
    const lat = payloadObj.latitude ?? payloadObj.lat ?? null;
    const lng = payloadObj.longitude ?? payloadObj.lng ?? null;
    const distanceCm = payloadObj.distance_cm ?? (payloadObj.distance ? Math.round(Number(payloadObj.distance) * 100) : null);
    const speedKmh = payloadObj.speed_kmh ?? payloadObj.speed ?? null;

    // Display in Console with rich formatting
    console.log(`\n================== [ LIVE AWS IoT MQTT PACKET ] ==================`);
    console.log(`🕒 Timestamp : ${dateIST} ${timeIST} IST`);
    console.log(`🏷️ Topic     : ${topic}`);
    console.log(`📟 Device ID : ${deviceId}`);
    if (battery !== null) console.log(`🔋 Battery   : ${battery}%`);
    if (signal !== null) console.log(`📶 Signal    : ${signal} dBm`);
    if (distanceCm !== null) console.log(`📏 Distance  : ${distanceCm} cm`);
    if (lat !== null && lng !== null) console.log(`📍 GPS       : ${lat}, ${lng}`);
    console.log(`📦 Payload:`);
    console.log(JSON.stringify(payloadObj, null, 2));
    console.log(`==================================================================\n`);

    const packetRecord = {
      id: `live_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
      device_id: deviceId,
      device_name: `Device ${deviceId}`,
      product_type: deviceId.startsWith('TX') ? 'TRANSMITTER' : (deviceId.startsWith('RX') ? 'RECEIVER' : 'DEVICE'),
      topic,
      payload: payloadObj,
      battery_level: battery,
      signal_rssi: signal,
      latitude: lat,
      longitude: lng,
      distance_cm: distanceCm,
      speed_kmh: speedKmh,
      recorded_at: new Date().toISOString(),
      live_status: 'ONLINE',
      seconds_ago: 0
    };

    // 1. Add to in-memory ring buffer
    this.recentPackets.unshift(packetRecord);
    if (this.recentPackets.length > this.maxBufferSize) {
      this.recentPackets.pop();
    }

    // 2. Broadcast to live SSE subscribers
    this.subscribers.forEach(callback => {
      try {
        callback(packetRecord);
      } catch (_) {}
    });

    // 3. Asynchronously persist to database & manage session lifecycle in background
    this.processSessionAndPersist(deviceId, topic, payloadObj, battery, signal, lat, lng, distanceCm, speedKmh).catch(err => {
      console.error('[AWS IoT Process error]:', err.message);
    });
  }

  derivePairedDevice(deviceId, payload) {
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

  async processSessionAndPersist(deviceId, topic, payload, battery, signal, lat, lng, distanceCm, speedKmh) {
    try {
      // 1. Insert into device_telemetry
      await db.query(`
        INSERT INTO device_telemetry (
          device_id, topic, payload, battery_level, signal_rssi, latitude, longitude, distance_cm, speed_kmh, recorded_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP)
      `, [
        deviceId,
        topic,
        JSON.stringify(payload),
        battery,
        signal,
        lat,
        lng,
        distanceCm,
        speedKmh
      ]);

      // 2. Upsert into device_registry and capture hardware/firmware specs and sensor configuration
      const productType = deviceId.startsWith('TX') ? 'TRANSMITTER' : (deviceId.startsWith('RX') ? 'RECEIVER' : 'DEVICE');
      const hwVer = payload.hardware_version || payload.hw_version || payload.deviceConfig?.hw_version || '1.0';
      const fwVer = payload.firmware_version || payload.fw_version || payload.deviceConfig?.fw_version || '2.0.0';
      const sensorsConfig = payload.sensors_config || payload.sensors || payload.deviceConfig?.sensors || null;

      if (sensorsConfig && Array.isArray(sensorsConfig) && sensorsConfig.length > 0) {
        await db.query(`
          INSERT INTO device_registry (
            device_id, device_name, serial_number, product_type, hardware_version, firmware_version, sensors_config, health_status, last_reading_timestamp, created_at, updated_at
          ) VALUES (
            $1, $1, $1, $2, $3, $4, $5::jsonb, 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          )
          ON CONFLICT (device_id) DO UPDATE SET
            health_status = 'ONLINE',
            hardware_version = COALESCE(NULLIF($3, '1.0'), device_registry.hardware_version),
            firmware_version = COALESCE(NULLIF($4, '1.0.0'), device_registry.firmware_version),
            sensors_config = $5::jsonb,
            last_reading_timestamp = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        `, [deviceId, productType, hwVer, fwVer, JSON.stringify(sensorsConfig)]);
      } else {
        await db.query(`
          INSERT INTO device_registry (
            device_id, device_name, serial_number, product_type, hardware_version, firmware_version, health_status, last_reading_timestamp, created_at, updated_at
          ) VALUES (
            $1, $1, $1, $2, $3, $4, 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          )
          ON CONFLICT (device_id) DO UPDATE SET
            health_status = 'ONLINE',
            hardware_version = COALESCE(NULLIF($3, '1.0'), device_registry.hardware_version),
            firmware_version = COALESCE(NULLIF($4, '1.0.0'), device_registry.firmware_version),
            last_reading_timestamp = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        `, [deviceId, productType, hwVer, fwVer]);
      }

      // =========================================================================
      // 3. HARDWARE SESSION & PAIRING STATE MACHINE
      // =========================================================================
      const pairedDevice = this.derivePairedDevice(deviceId, payload);
      const rxId = (deviceId.startsWith('RX') || deviceId.startsWith('LD')) ? deviceId : pairedDevice;
      const txId = (deviceId.startsWith('TX') || deviceId.startsWith('DE')) ? deviceId : pairedDevice;

      if (topic.includes('/status') || ['PAIR_START', 'PAIR_END', 'UNEXPECTED_DISCONNECT'].includes(payload.event)) {
        const eventType = payload.event;
        const status = payload.status;
        const lastDistCm = payload.last_distance_cm ?? distanceCm;
        const finalDistCm = payload.final_distance_cm;

        if (eventType === 'PAIR_START' || status === 'PAIRED') {
          const sessionCode = `SES-${Date.now().toString().slice(-6)}-${rxId}`;
          
          const existing = await db.query(
            "SELECT id FROM shunting_sessions WHERE (rx_device_id = $1 OR ld_code = $1) AND (status = 'LIVE' OR session_status = 'LIVE')",
            [rxId]
          );

          if (existing.rows.length === 0) {
            await db.query(`
              INSERT INTO shunting_sessions (
                session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
                session_start, start_time, session_status, status, distance_trajectory, created_at, updated_at
              ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', '[]'::jsonb, NOW(), NOW())
            `, [sessionCode, rxId, txId]);
            console.log(`🚂 [SHUTTLE SESSION START] Hardware Paired: ${rxId} <--> ${txId} (Code: ${sessionCode})`);
          } else if (lastDistCm != null) {
            const point = JSON.stringify({ t: Date.now(), d_cm: lastDistCm, speed_kmh: speedKmh || 0.0, battery, signal });
            await db.query(`
              UPDATE shunting_sessions
              SET 
                distance_trajectory = COALESCE(distance_trajectory, '[]'::jsonb) || $1::jsonb,
                final_distance_cm = $2,
                final_placement_distance = $2 / 100.0,
                updated_at = NOW()
              WHERE id = $3
            `, [point, lastDistCm, existing.rows[0].id]);
          }
        }

        else if (eventType === 'PAIR_END' || status === 'IDLE') {
          const finalVal = parseInt(finalDistCm ?? lastDistCm ?? 0, 10);
          const finalMeters = finalVal / 100.0;
          await db.query(`
            UPDATE shunting_sessions
            SET 
              session_end = NOW(),
              end_time = NOW(),
              session_status = 'COMPLETED',
              status = 'COMPLETED',
              final_distance_cm = $1,
              final_placement_distance = $2,
              updated_at = NOW()
            WHERE (rx_device_id = $3 OR ld_code = $3 OR tx_device_id = $4 OR de_code = $4) AND (status = 'LIVE' OR session_status = 'LIVE')
          `, [finalVal, finalMeters, rxId, txId]);

          try {
            await db.query(`
              UPDATE device_assignments
              SET returned_at = NOW()
              WHERE device_id IN (SELECT id FROM devices WHERE device_code = $1 OR device_code = $2) AND returned_at IS NULL
            `, [rxId, txId]);
          } catch (_) {}

          console.log(`🛑 [SHUTTLE SESSION END] Hardware Unpaired: ${rxId} / ${txId} (Final Distance: ${finalVal} cm)`);
        }

        else if (eventType === 'UNEXPECTED_DISCONNECT' || status === 'OFFLINE') {
          await db.query(`
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

          try {
            await db.query(`
              UPDATE device_assignments
              SET returned_at = NOW()
              WHERE device_id IN (SELECT id FROM devices WHERE device_code = $1 OR device_code = $2) AND returned_at IS NULL
            `, [rxId, txId]);
          } catch (_) {}

          console.log(`⚠️ [SHUTTLE SESSION TIMEOUT] LWT Disconnect for: ${rxId} / ${txId}`);
        }
      }

      // =========================================================================
      // 4. ACTIVE DISTANCE TELEMETRY LOGGING FROM TRANSMITTER OR RECEIVER
      // =========================================================================
      if (distanceCm !== null && distanceCm !== undefined) {
        const point = JSON.stringify({
          t: Date.now(),
          d_cm: distanceCm,
          speed_kmh: speedKmh || 0.0,
          battery: battery,
          signal: signal
        });
        
        // Update existing live session if active
        const updateRes = await db.query(`
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

        // If no active shunting session exists yet, auto-create one when distance streaming begins
        if (updateRes.rowCount === 0) {
          const sessionCode = `SES-${Date.now().toString().slice(-6)}-${rxId}`;
          await db.query(`
            INSERT INTO shunting_sessions (
              session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
              session_start, start_time, session_status, status, final_distance_cm, final_placement_distance,
              minimum_distance, distance_trajectory, created_at, updated_at
            ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', $4, $4 / 100.0, $4 / 100.0, $5::jsonb, NOW(), NOW())
          `, [sessionCode, rxId, txId, distanceCm, JSON.stringify([JSON.parse(point)])]);
          console.log(`🚂 [SHUTTLE SESSION AUTO-START] Streaming from ${rxId} <--> ${txId}`);
        }
      }

    } catch (err) {
      console.error('[DB Persist Error]:', err.message);
    }
  }

  // Periodic sweep to automatically mark stale live sessions as completed
  async sweepStaleSessions() {
    try {
      const staleThresholdSeconds = 45;
      const res = await db.query(`
        UPDATE shunting_sessions
        SET 
          session_end = updated_at,
          end_time = updated_at,
          session_status = 'COMPLETED',
          status = 'COMPLETED',
          manual_close_reason = 'Hardware disconnected (no telemetry for > 45s)',
          updated_at = NOW()
        WHERE (status = 'LIVE' OR session_status = 'LIVE')
          AND updated_at < (NOW() - INTERVAL '45 SECONDS')
        RETURNING id, session_code, ld_code, tx_device_id;
      `);

      if (res.rows.length > 0) {
        for (const s of res.rows) {
          console.log(`⏱️ [AUTO-SESSION CLOSE] Session ${s.session_code} (${s.ld_code} <-> ${s.tx_device_id}) marked COMPLETED after disconnect.`);
        }
      }
    } catch (err) {
      // Non-fatal background error
    }
  }

  getLivePackets(topicFilter, deviceId) {
    return this.recentPackets.filter(p => {
      if (deviceId && deviceId !== 'ALL' && p.device_id !== deviceId) {
        return false;
      }
      if (topicFilter && topicFilter !== 'devices/#' && topicFilter !== '#') {
        if (topicFilter.includes('+') || topicFilter.includes('#')) {
          const regex = new RegExp('^' + topicFilter.replace(/\+/g, '[^/]+').replace(/#/g, '.*') + '$');
          return regex.test(p.topic);
        } else {
          return p.topic === topicFilter;
        }
      }
      return true;
    });
  }

  // Fast in-memory lookup for zero-latency mobile telemetry
  getLatestTelemetryForDevices(deviceIds) {
    if (!deviceIds || !deviceIds.length) return null;
    for (const pkt of this.recentPackets) {
      if (deviceIds.includes(pkt.device_id)) {
        return pkt;
      }
    }
    return null;
  }

  subscribeLiveStream(callback) {
    this.subscribers.add(callback);
    return () => this.subscribers.delete(callback);
  }
}

const instance = new AwsIotBridge();

// Run stale session sweep every 15 seconds
setInterval(() => {
  instance.sweepStaleSessions();
}, 15000);

module.exports = instance;
