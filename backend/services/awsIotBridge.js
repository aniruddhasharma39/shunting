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

  async processSessionAndPersist(deviceId, topic, payload, battery, signal, lat, lng, distanceCm, speedKmh) {
    try {
      const now = new Date();

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

      // 2. Upsert into device_registry
      const productType = deviceId.startsWith('TX') ? 'TRANSMITTER' : (deviceId.startsWith('RX') ? 'RECEIVER' : 'DEVICE');
      await db.query(`
        INSERT INTO device_registry (
          device_id, device_name, serial_number, product_type, hardware_version, firmware_version, health_status, last_reading_timestamp, created_at, updated_at
        ) VALUES (
          $1, $1, $1, $2, '1.0', '1.0.0', 'ONLINE', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        ON CONFLICT (device_id) DO UPDATE SET
          health_status = 'ONLINE',
          last_reading_timestamp = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP
      `, [deviceId, productType]);

      // =========================================================================
      // 3. HARDWARE SESSION & PAIRING STATE MACHINE (devices/RX-XX/status)
      // =========================================================================
      if (topic.includes('/status')) {
        const eventType = payload.event; // 'PAIR_START', 'PAIR_END', 'UNEXPECTED_DISCONNECT'
        const status = payload.status;   // 'PAIRED', 'IDLE', 'OFFLINE'
        const pairedTxId = payload.paired_tx_id;
        const lastDistCm = payload.last_distance_cm ?? distanceCm;
        const finalDistCm = payload.final_distance_cm;

        // A. Pairing Initiated (PAIR_START or PAIRED with paired_tx_id)
        if ((eventType === 'PAIR_START' || status === 'PAIRED') && pairedTxId) {
          const sessionCode = `SES-${Date.now().toString().slice(-6)}-${deviceId}`;
          
          // Check if already active
          const existing = await db.query(
            "SELECT id FROM shunting_sessions WHERE (rx_device_id = $1 OR ld_code = $1) AND (status = 'LIVE' OR session_status = 'LIVE')",
            [deviceId]
          );

          if (existing.rows.length === 0) {
            await db.query(`
              INSERT INTO shunting_sessions (
                session_number, session_code, ld_code, rx_device_id, de_code, tx_device_id,
                session_start, start_time, session_status, status, distance_trajectory, created_at, updated_at
              ) VALUES ($1, $1, $2, $2, $3, $3, NOW(), NOW(), 'LIVE', 'LIVE', '[]'::jsonb, NOW(), NOW())
            `, [sessionCode, deviceId, pairedTxId]);
            console.log(`🚂 [SHUTTLE SESSION START] Hardware Paired: ${deviceId} <--> ${pairedTxId} (Code: ${sessionCode})`);
          } else if (lastDistCm != null) {
            // Append distance point to trajectory
            const point = JSON.stringify({ t: Date.now(), d_cm: lastDistCm });
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

        // B. Pairing Ended (PAIR_END or IDLE)
        else if (eventType === 'PAIR_END' || status === 'IDLE') {
          const finalVal = finalDistCm ?? lastDistCm ?? 0;
          await db.query(`
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
          console.log(`🛑 [SHUTTLE SESSION END] Hardware Unpaired: ${deviceId} (Final Distance: ${finalVal} cm)`);
        }

        // C. Unexpected Disconnect / LWT
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
            WHERE (rx_device_id = $1 OR ld_code = $1) AND (status = 'LIVE' OR session_status = 'LIVE')
          `, [deviceId]);
          console.log(`⚠️ [SHUTTLE SESSION TIMEOUT] LWT Disconnect for: ${deviceId}`);
        }
      }

      // =========================================================================
      // 4. ACTIVE DISTANCE DECAY LOGGING FROM TRANSMITTER (devices/TX-XX/telemetry)
      // =========================================================================
      if (distanceCm !== null && deviceId.startsWith('TX')) {
        const point = JSON.stringify({ t: Date.now(), d_cm: distanceCm });
        await db.query(`
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

    } catch (err) {
      console.error('[DB Persist Error]:', err.message);
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

  subscribeLiveStream(callback) {
    this.subscribers.add(callback);
    return () => this.subscribers.delete(callback);
  }
}

const instance = new AwsIotBridge();
module.exports = instance;
