const db = require('../config/db');
const awsIotBridge = require('../services/awsIotBridge');

// Helper to derive standard application device_type from product_type or device_id
function normalizeDeviceType(productType, deviceId) {
  const p = (productType || '').toUpperCase();
  const d = (deviceId || '').toUpperCase();
  if (p.includes('RECEIVER') || p.includes('LOCO') || d.includes('RECEIVER') || d.startsWith('RX') || d.startsWith('LD')) {
    return 'Loco Unit';
  }
  if (p.includes('TRANSMITTER') || p.includes('DEAD-END') || d.includes('TRANSMITTER') || d.startsWith('TX') || d.startsWith('DE')) {
    return 'Dead-End';
  }
  if (p.includes('REPEATER') || p.includes('PORTABLE') || d.startsWith('PD') || d.startsWith('RP')) {
    return 'Portable';
  }
  if (p.includes('COUPLING') || d.startsWith('CD')) {
    return 'Coupling';
  }
  return productType || 'Loco Unit';
}

// @desc    Get all registered IoT devices with search and filters + dynamic 30-sec status summary
// @route   GET /api/device-registry
// @access  Hardware Engineer / Super Admin / Yard Admin / Viewer
const getRegistryDevices = async (req, res) => {
  try {
    const { search, product_type, health_status } = req.query;

    // Join latest telemetry timestamp from device_telemetry and line/yard info
    let query = `
      SELECT 
        dr.*,
        COALESCE(dr.device_type, 
          CASE 
            WHEN dr.product_type ILIKE '%RECEIVER%' OR dr.device_id ILIKE '%RECEIVER%' OR dr.device_id ILIKE 'RX%' OR dr.device_id ILIKE 'LD%' THEN 'Loco Unit'
            WHEN dr.product_type ILIKE '%TRANSMITTER%' OR dr.device_id ILIKE '%TRANSMITTER%' OR dr.device_id ILIKE 'TX%' OR dr.device_id ILIKE 'DE%' THEN 'Dead-End'
            WHEN dr.product_type ILIKE '%REPEATER%' OR dr.device_id ILIKE 'RP%' OR dr.device_id ILIKE 'PD%' THEN 'Portable'
            WHEN dr.product_type ILIKE '%COUPLING%' OR dr.device_id ILIKE 'CD%' THEN 'Coupling'
            ELSE dr.product_type
          END
        ) AS device_type,
        dt.latest_telemetry_time,
        GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) AS effective_last_reading,
        CASE 
          WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) >= (NOW() - INTERVAL '30 SECONDS') THEN 'ONLINE'
          ELSE 'OFFLINE'
        END AS computed_status,
        ROUND(EXTRACT(EPOCH FROM (NOW() - GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time)))) AS seconds_since_last_reading,
        yl.line_name,
        yl.line_number,
        y.yard_name,
        y.yard_code
      FROM device_registry dr
      LEFT JOIN (
        SELECT device_id, MAX(recorded_at) AS latest_telemetry_time
        FROM device_telemetry
        GROUP BY device_id
      ) dt ON dr.device_id = dt.device_id
      LEFT JOIN yard_lines yl ON dr.assigned_line_id = yl.id
      LEFT JOIN yards y ON COALESCE(dr.yard_id, yl.yard_id) = y.id
      WHERE 1=1
    `;
    const params = [];

    if (search && search.trim() !== '') {
      params.push(`%${search.trim()}%`);
      const pIdx = params.length;
      query += ` AND (
        dr.device_id ILIKE $${pIdx} OR 
        dr.device_name ILIKE $${pIdx} OR 
        dr.serial_number ILIKE $${pIdx} OR 
        dr.product_type ILIKE $${pIdx} OR
        dr.hardware_version ILIKE $${pIdx} OR
        dr.firmware_version ILIKE $${pIdx} OR
        dr.sensors_config::text ILIKE $${pIdx}
      )`;
    }

    if (product_type && product_type !== 'ALL') {
      params.push(product_type);
      const pIdx = params.length;
      // Allow matching either exact product_type or mapped type (e.g. Loco Unit / RECEIVER)
      if (product_type.toUpperCase() === 'RECEIVER' || product_type === 'Loco Unit') {
        query += ` AND (dr.product_type ILIKE '%RECEIVER%' OR dr.product_type ILIKE '%Loco%' OR dr.device_id ILIKE 'RX%' OR dr.device_id ILIKE 'LD%')`;
      } else if (product_type.toUpperCase() === 'TRANSMITTER' || product_type === 'Dead-End') {
        query += ` AND (dr.product_type ILIKE '%TRANSMITTER%' OR dr.product_type ILIKE '%Dead%' OR dr.device_id ILIKE 'TX%' OR dr.device_id ILIKE 'DE%')`;
      } else if (product_type.toUpperCase() === 'REPEATER' || product_type === 'Portable') {
        query += ` AND (dr.product_type ILIKE '%REPEATER%' OR dr.product_type ILIKE '%Portable%' OR dr.device_id ILIKE 'RP%' OR dr.device_id ILIKE 'PD%')`;
      } else {
        query += ` AND (dr.product_type = $${pIdx} OR dr.device_type = $${pIdx})`;
      }
    }

    query += ' ORDER BY effective_last_reading DESC NULLS LAST, dr.created_at DESC';

    const result = await db.query(query, params);

    // Filter by health_status if requested (using computed 30s status)
    let devices = result.rows.map(dev => ({
      ...dev,
      last_reading_timestamp: dev.effective_last_reading || dev.last_reading_timestamp,
      health_status: dev.computed_status // Real-time computed status based on 30s rule
    }));

    if (health_status && health_status !== 'ALL') {
      devices = devices.filter(d => d.computed_status === health_status);
    }

    // Compute stats summary across all devices using the 30-second rule
    const statsResult = await db.query(`
      SELECT 
        COUNT(*)::int AS total_devices,
        COUNT(CASE WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) >= (NOW() - INTERVAL '30 SECONDS') THEN 1 END)::int AS online_count,
        COUNT(CASE WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) < (NOW() - INTERVAL '30 SECONDS') OR (dr.last_reading_timestamp IS NULL AND dt.latest_telemetry_time IS NULL) THEN 1 END)::int AS offline_count
      FROM device_registry dr
      LEFT JOIN (
        SELECT device_id, MAX(recorded_at) AS latest_telemetry_time
        FROM device_telemetry
        GROUP BY device_id
      ) dt ON dr.device_id = dt.device_id
    `);

    // Calculate total sensors configured across all devices
    let totalSensors = 0;
    for (const dev of devices) {
      if (Array.isArray(dev.sensors_config)) {
        totalSensors += dev.sensors_config.length;
      }
    }

    const summary = {
      totalDevices: statsResult.rows[0]?.total_devices || devices.length,
      onlineCount: statsResult.rows[0]?.online_count || 0,
      offlineCount: statsResult.rows[0]?.offline_count || 0,
      totalSensors: totalSensors
    };

    res.json({
      success: true,
      summary,
      count: devices.length,
      devices
    });
  } catch (error) {
    console.error('Error in getRegistryDevices:', error);
    res.status(500).json({ success: false, message: 'Server error fetching device registry' });
  }
};

// @desc    Get single device registry detail
// @route   GET /api/device-registry/:deviceId
// @access  Hardware Engineer / Super Admin / Yard Admin / Viewer
const getRegistryDeviceById = async (req, res) => {
  try {
    const { deviceId } = req.params;

    const result = await db.query(
      `SELECT 
        dr.*,
        COALESCE(dr.device_type, 
          CASE 
            WHEN dr.product_type ILIKE '%RECEIVER%' OR dr.device_id ILIKE 'RX%' OR dr.device_id ILIKE 'LD%' THEN 'Loco Unit'
            WHEN dr.product_type ILIKE '%TRANSMITTER%' OR dr.device_id ILIKE 'TX%' OR dr.device_id ILIKE 'DE%' THEN 'Dead-End'
            WHEN dr.product_type ILIKE '%REPEATER%' OR dr.device_id ILIKE 'RP%' OR dr.device_id ILIKE 'PD%' THEN 'Portable'
            WHEN dr.product_type ILIKE '%COUPLING%' OR dr.device_id ILIKE 'CD%' THEN 'Coupling'
            ELSE dr.product_type
          END
        ) AS device_type,
        dt.latest_telemetry_time,
        GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) AS effective_last_reading,
        CASE 
          WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) >= (NOW() - INTERVAL '30 SECONDS') THEN 'ONLINE'
          ELSE 'OFFLINE'
        END AS computed_status,
        ROUND(EXTRACT(EPOCH FROM (NOW() - GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time)))) AS seconds_since_last_reading,
        yl.line_name,
        yl.line_number,
        y.yard_name
      FROM device_registry dr
      LEFT JOIN (
        SELECT device_id, MAX(recorded_at) AS latest_telemetry_time
        FROM device_telemetry
        GROUP BY device_id
      ) dt ON dr.device_id = dt.device_id
      LEFT JOIN yard_lines yl ON dr.assigned_line_id = yl.id
      LEFT JOIN yards y ON COALESCE(dr.yard_id, yl.yard_id) = y.id
      WHERE dr.device_id = $1 OR dr.id::text = $1`,
      [deviceId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Device not found in registry' });
    }

    const device = {
      ...result.rows[0],
      last_reading_timestamp: result.rows[0].effective_last_reading || result.rows[0].last_reading_timestamp,
      health_status: result.rows[0].computed_status
    };

    // Also fetch recent telemetry logs if any
    const telemetryResult = await db.query(
      'SELECT * FROM device_telemetry WHERE device_id = $1 ORDER BY recorded_at DESC LIMIT 20',
      [device.device_id]
    );

    res.json({
      success: true,
      device,
      recentTelemetry: telemetryResult.rows
    });
  } catch (error) {
    console.error('Error in getRegistryDeviceById:', error);
    res.status(500).json({ success: false, message: 'Server error fetching device details' });
  }
};

// @desc    Get live telemetry stream for all or specific devices (AWS MQTT Test Client level)
// @route   GET /api/device-registry/telemetry/live
// @access  Hardware Engineer / Super Admin / Viewer
const getLiveTelemetry = async (req, res) => {
  try {
    const { device_id, topic, limit = 50 } = req.query;

    let query = `
      SELECT 
        dt.id,
        dt.device_id,
        COALESCE(dt.topic, 'devices/' || dt.device_id || '/telemetry') AS topic,
        dt.recorded_at,
        dt.payload,
        dt.battery_level,
        dt.signal_rssi,
        dt.latitude,
        dt.longitude,
        COALESCE(dr.device_name, 'Device ' || dt.device_id) AS device_name,
        COALESCE(dr.product_type, 'DEVICE') AS product_type,
        dr.hardware_version,
        dr.firmware_version,
        CASE 
          WHEN dt.recorded_at >= (NOW() - INTERVAL '30 SECONDS') THEN 'ONLINE'
          ELSE 'OFFLINE'
        END AS live_status,
        ROUND(EXTRACT(EPOCH FROM (NOW() - dt.recorded_at))) AS seconds_ago
      FROM device_telemetry dt
      LEFT JOIN device_registry dr ON dt.device_id = dr.device_id
      WHERE 1=1
    `;
    const params = [];

    if (device_id && device_id.trim() !== '' && device_id !== 'ALL') {
      params.push(device_id.trim());
      query += ` AND dt.device_id = $${params.length}`;
    }

    if (topic && topic.trim() !== '' && topic !== '#' && topic !== 'devices/#') {
      const cleanTopic = topic.trim();
      if (cleanTopic.includes('+') || cleanTopic.includes('#')) {
        // Support MQTT wildcards (e.g. devices/+/telemetry or devices/TX-02/+)
        const regexPattern = '^' + cleanTopic.replace(/\+/g, '[^/]+').replace(/#/g, '.*') + '$';
        params.push(regexPattern);
        query += ` AND COALESCE(dt.topic, 'devices/' || dt.device_id || '/telemetry') ~ $${params.length}`;
      } else {
        // Exact topic match
        params.push(cleanTopic);
        query += ` AND COALESCE(dt.topic, 'devices/' || dt.device_id || '/telemetry') = $${params.length}`;
      }
    }

    params.push(Math.min(parseInt(limit, 10) || 50, 200));
    query += ` ORDER BY dt.recorded_at DESC LIMIT $${params.length}`;

    const result = await db.query(query, params);

    // Get all distinct device IDs from both registry and telemetry for dropdown filter
    const devicesListResult = await db.query(`
      SELECT 
        COALESCE(dr.device_id, dt.device_id) AS device_id, 
        COALESCE(dr.device_name, 'Device ' || COALESCE(dr.device_id, dt.device_id)) AS device_name, 
        COALESCE(dr.product_type, 'DEVICE') AS product_type,
        dt.max_rec,
        CASE 
          WHEN dt.max_rec >= (NOW() - INTERVAL '30 SECONDS') THEN 'ONLINE'
          ELSE 'OFFLINE'
        END AS status
      FROM (
        SELECT device_id, MAX(recorded_at) AS max_rec
        FROM device_telemetry
        GROUP BY device_id
      ) dt
      FULL OUTER JOIN device_registry dr ON dt.device_id = dr.device_id
      ORDER BY device_id ASC
    `);

    // Live count in last 30 seconds
    const liveCountResult = await db.query(`
      SELECT COUNT(DISTINCT device_id)::int AS active_devices
      FROM device_telemetry
      WHERE recorded_at >= (NOW() - INTERVAL '30 SECONDS')
    `);

    // Merge in-memory sub-second packets from direct AWS IoT MQTT stream
    const liveMemoryPackets = awsIotBridge.getLivePackets(topic, device_id);
    const combinedTelemetry = [...liveMemoryPackets, ...result.rows.filter(r => !liveMemoryPackets.some(lp => lp.topic === r.topic && lp.recorded_at === r.recorded_at))].slice(0, parseInt(limit, 10) || 50);

    res.json({
      success: true,
      count: combinedTelemetry.length,
      activeDevicesCount: Math.max(liveCountResult.rows[0]?.active_devices || 0, liveMemoryPackets.length > 0 ? 1 : 0),
      devicesList: devicesListResult.rows,
      telemetry: combinedTelemetry
    });
  } catch (error) {
    console.error('Error in getLiveTelemetry:', error);
    res.status(500).json({ success: false, message: 'Server error fetching live telemetry' });
  }
};

// @desc    Ingest telemetry record (via AWS Lambda IoT MQTT Hook or Direct API)
// @route   POST /api/device-registry/telemetry
// @access  Protected / Public (for AWS Lambda / IoT Hook)
const ingestDeviceTelemetry = async (req, res) => {
  try {
    const body = req.body || {};
    
    // Extract device ID from multiple possible formats
    let deviceId = body.device_id || body.deviceId || body.deviceCode || body.SerialNumber;
    const mqttTopic = body.topic || (deviceId ? `devices/${deviceId}/telemetry` : null);

    if (!deviceId && mqttTopic) {
      const parts = mqttTopic.split('/');
      if (parts.length >= 2 && parts[0] === 'devices') {
        deviceId = parts[1];
      }
    }

    if (!deviceId) {
      return res.status(400).json({ success: false, message: 'device_id or topic is required' });
    }

    const timestamp = body.recorded_at ? new Date(body.recorded_at) : (body.msg_timestamp ? new Date(body.msg_timestamp) : new Date());
    const rawPayload = body.payload !== undefined ? body.payload : body;

    // Extract metrics from flat or nested STM32 telemetry structures
    const battery = body.battery_level ?? body.battery ?? body.diagnostics?.battery_pct ?? rawPayload?.diagnostics?.battery_pct ?? null;
    const signal = body.signal_rssi ?? body.signal ?? body.gsm_rssi ?? body.diagnostics?.gsm_rssi ?? rawPayload?.diagnostics?.gsm_rssi ?? null;
    const lat = body.latitude ?? body.lat ?? rawPayload?.latitude ?? rawPayload?.lat ?? null;
    const lng = body.longitude ?? body.lng ?? rawPayload?.longitude ?? rawPayload?.lng ?? null;
    const distanceCm = body.distance_cm ?? body.readings?.distance_cm ?? rawPayload?.readings?.distance_cm ?? (body.distance ? Math.round(Number(body.distance) * 100) : null);
    const speedKmh = body.speed_kmh ?? body.speed ?? rawPayload?.speed_kmh ?? null;
    const productType = body.product_type || body.productType || rawPayload?.productType || 'RECEIVER';
    const deviceType = normalizeDeviceType(productType, deviceId);

    // 1. Ensure device exists in device_registry and update last reading timestamp
    let registryRow;
    try {
      const regUpsert = await db.query(`
        INSERT INTO device_registry (
          device_id, device_name, serial_number, product_type, device_type, hardware_version, firmware_version, health_status, last_reading_timestamp, updated_at
        ) VALUES (
          $1, $1, $1, $2, $3, '1.0', '1.0.0', 'ONLINE', $4, CURRENT_TIMESTAMP
        )
        ON CONFLICT (device_id) DO UPDATE SET
          health_status = 'ONLINE',
          last_reading_timestamp = $4,
          updated_at = CURRENT_TIMESTAMP
        RETURNING *
      `, [deviceId, productType, deviceType, timestamp]);
      registryRow = regUpsert.rows[0];
    } catch (regErr) {
      console.warn('Could not auto-upsert into device_registry:', regErr.message);
    }

    // 2. Insert into device_telemetry (Primary persistent telemetry store)
    const telemetryInsert = await db.query(`
      INSERT INTO device_telemetry (
        device_id, topic, payload, battery_level, signal_rssi, latitude, longitude, distance_cm, speed_kmh, recorded_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `, [
      deviceId,
      mqttTopic || `devices/${deviceId}/telemetry`,
      typeof rawPayload === 'object' ? JSON.stringify(rawPayload) : (rawPayload || '{}'),
      battery,
      signal,
      lat,
      lng,
      distanceCm,
      speedKmh,
      timestamp
    ]);

    // 3. Keep devices table in sync for foreign key references
    try {
      const defaultYard = await db.query('SELECT id FROM yards LIMIT 1');
      const yardId = registryRow?.yard_id || defaultYard.rows[0]?.id;
      if (yardId && registryRow) {
        await db.query(`
          INSERT INTO devices (
            id, device_code, device_type, device_name, serial_number, yard_id, firmware_version, last_heartbeat, battery_level, created_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          ON CONFLICT (id) DO UPDATE SET
            device_code = EXCLUDED.device_code,
            device_type = EXCLUDED.device_type,
            last_heartbeat = EXCLUDED.last_heartbeat,
            battery_level = EXCLUDED.battery_level,
            updated_at = CURRENT_TIMESTAMP
        `, [
          registryRow.id,
          deviceId,
          deviceType,
          registryRow.device_name || deviceId,
          registryRow.serial_number || deviceId,
          yardId,
          registryRow.firmware_version || '1.0.0',
          timestamp,
          battery ? `${battery}%` : null
        ]);
      }
    } catch (syncErr) {
      console.warn('Sync to devices table skipped:', syncErr.message);
    }

    // 4. Also insert into legacy telemetry_data for backwards compatibility
    try {
      await db.query(
        'INSERT INTO telemetry_data (device_id, payload, recorded_at) VALUES ($1, $2, $3)',
        [deviceId, typeof rawPayload === 'object' ? JSON.stringify(rawPayload) : (rawPayload || '{}'), timestamp]
      );
    } catch (_) {}

    res.status(201).json({
      success: true,
      message: 'Telemetry polling successfully stored in device_telemetry',
      data: telemetryInsert.rows[0]
    });
  } catch (error) {
    console.error('Error in ingestDeviceTelemetry:', error);
    res.status(500).json({ success: false, message: 'Server error ingesting telemetry', error: error.message });
  }
};

// @desc    Upsert / Register device (AWS Lambda IoT hook or Device Inventory)
// @route   POST /api/device-registry
// @access  Hardware Engineer / Super Admin / Yard Admin
const upsertRegistryDevice = async (req, res) => {
  try {
    const {
      device_id,
      device_name,
      serial_number,
      product_type,
      device_type,
      hardware_version,
      firmware_version,
      manufacturing_date,
      sensors_config,
      health_status,
      last_error_code,
      assigned_line_id,
      yard_id
    } = req.body;

    if (!device_id || !serial_number || !product_type) {
      return res.status(400).json({
        success: false,
        message: 'device_id, serial_number, and product_type are required'
      });
    }

    const resolvedDeviceType = device_type || normalizeDeviceType(product_type, device_id);

    // Get a default yard if not specified
    let targetYardId = yard_id;
    if (!targetYardId) {
      const defaultYard = await db.query('SELECT id FROM yards LIMIT 1');
      targetYardId = defaultYard.rows[0]?.id;
    }

    const result = await db.query(`
      INSERT INTO device_registry (
        device_id, device_name, serial_number, product_type, device_type,
        hardware_version, firmware_version, manufacturing_date,
        sensors_config, health_status, last_error_code, assigned_line_id, yard_id, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, CURRENT_TIMESTAMP)
      ON CONFLICT (device_id) DO UPDATE SET
        device_name = COALESCE(EXCLUDED.device_name, device_registry.device_name),
        serial_number = COALESCE(EXCLUDED.serial_number, device_registry.serial_number),
        product_type = COALESCE(EXCLUDED.product_type, device_registry.product_type),
        device_type = COALESCE(EXCLUDED.device_type, device_registry.device_type),
        hardware_version = COALESCE(EXCLUDED.hardware_version, device_registry.hardware_version),
        firmware_version = COALESCE(EXCLUDED.firmware_version, device_registry.firmware_version),
        manufacturing_date = COALESCE(EXCLUDED.manufacturing_date, device_registry.manufacturing_date),
        sensors_config = COALESCE(EXCLUDED.sensors_config, device_registry.sensors_config),
        health_status = COALESCE(EXCLUDED.health_status, device_registry.health_status),
        last_error_code = EXCLUDED.last_error_code,
        assigned_line_id = COALESCE(EXCLUDED.assigned_line_id, device_registry.assigned_line_id),
        yard_id = COALESCE(EXCLUDED.yard_id, device_registry.yard_id),
        updated_at = CURRENT_TIMESTAMP
      RETURNING *
    `, [
      device_id,
      device_name || device_id,
      serial_number,
      product_type,
      resolvedDeviceType,
      hardware_version || '1.0',
      firmware_version || '1.0.0',
      manufacturing_date || new Date().toISOString().split('T')[0],
      JSON.stringify(sensors_config || []),
      health_status || 'ONLINE',
      last_error_code || null,
      assigned_line_id || null,
      targetYardId || null
    ]);

    const registered = result.rows[0];

    // Maintain devices table sync
    if (targetYardId && registered) {
      await db.query(`
        INSERT INTO devices (
          id, device_code, device_type, device_name, serial_number, yard_id, firmware_version, assigned_line_id, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (id) DO UPDATE SET
          device_code = EXCLUDED.device_code,
          device_type = EXCLUDED.device_type,
          device_name = EXCLUDED.device_name,
          serial_number = EXCLUDED.serial_number,
          firmware_version = EXCLUDED.firmware_version,
          assigned_line_id = EXCLUDED.assigned_line_id,
          updated_at = CURRENT_TIMESTAMP
      `, [
        registered.id,
        registered.device_id,
        resolvedDeviceType,
        registered.device_name,
        registered.serial_number,
        targetYardId,
        registered.firmware_version,
        registered.assigned_line_id
      ]);
    }

    res.status(201).json({
      success: true,
      message: 'Device registered / updated successfully',
      device: registered
    });
  } catch (error) {
    console.error('Error in upsertRegistryDevice:', error);
    res.status(500).json({ success: false, message: 'Server error registering device' });
  }
};

// @desc    Delete a device and all its recorded telemetry
// @route   DELETE /api/device-registry/:deviceId
// @access  Super Admin / Hardware Engineer / Yard Admin
const deleteRegistryDevice = async (req, res) => {
  try {
    const { deviceId } = req.params;

    if (!deviceId) {
      return res.status(400).json({ success: false, message: 'Device ID is required' });
    }

    // Find the device in registry first
    const findRes = await db.query(
      'SELECT id, device_id FROM device_registry WHERE device_id = $1 OR id::text = $1',
      [deviceId]
    );

    if (findRes.rows.length === 0) {
      // Check if it exists in devices table alone
      const devRes = await db.query(
        'SELECT id, device_code FROM devices WHERE device_code = $1 OR id::text = $1',
        [deviceId]
      );
      if (devRes.rows.length === 0) {
        return res.status(404).json({ success: false, message: 'Device not found' });
      }
    }

    const matchedDevId = findRes.rows[0]?.device_id || deviceId;
    const matchedUuid = findRes.rows[0]?.id;

    // 1. Delete from device_telemetry (primary AWS IoT telemetry table)
    await db.query('DELETE FROM device_telemetry WHERE device_id = $1', [matchedDevId]);

    // 2. Delete from legacy telemetry_data
    try {
      await db.query(
        'DELETE FROM telemetry_data WHERE device_id = $1 OR device_id = $2',
        [matchedDevId, matchedUuid ? matchedUuid.toString() : matchedDevId]
      );
    } catch (_) {}

    // 3. Delete dependent rows in device_assignments, device_line_assignments, etc.
    const dependentTables = [
      'device_assignments',
      'device_line_assignments',
      'device_issue_returns',
      'device_heartbeats',
      'device_health_status',
      'alerts',
      'maintenance_records',
      'device_sim_details'
    ];

    for (const table of dependentTables) {
      try {
        if (matchedUuid) {
          await db.query(`DELETE FROM ${table} WHERE device_id = $1`, [matchedUuid]);
        }
        await db.query(`DELETE FROM ${table} WHERE device_id IN (SELECT id FROM devices WHERE device_code = $1)`, [matchedDevId]);
      } catch (_) {}
    }

    // 4. Delete from devices table
    await db.query('DELETE FROM devices WHERE device_code = $1 OR id::text = $1', [matchedDevId]);

    // 5. Delete from device_registry
    await db.query('DELETE FROM device_registry WHERE device_id = $1 OR id::text = $1', [matchedDevId]);

    res.json({
      success: true,
      message: `Device '${matchedDevId}' and all its telemetry records deleted successfully.`
    });
  } catch (error) {
    console.error('Error in deleteRegistryDevice:', error);
    res.status(500).json({ success: false, message: 'Server error deleting device' });
  }
};

module.exports = {
  getRegistryDevices,
  getRegistryDeviceById,
  getLiveTelemetry,
  ingestDeviceTelemetry,
  upsertRegistryDevice,
  deleteRegistryDevice
};
