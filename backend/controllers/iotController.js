const db = require('../config/db');

// @desc    Ingest telemetry data from devices
// @route   POST /api/iot/telemetry
// @access  Public (or secured via API Key in production)
const ingestTelemetry = async (req, res) => {
  try {
    const { device_id, distance, battery, speed, timestamp, signal, distance_show, location, pit_lane, device_number } = req.body;

    if (!device_id) {
      return res.status(400).json({ message: 'device_id is required' });
    }

    // Prepare JSON payload
    const payload = {
        distance,
        battery,
        speed,
        signal,
        distance_show,
        location,
        pit_lane,
        device_number
    };
    const recordedAt = timestamp ? new Date(timestamp) : new Date();

    // 1. Insert into device_telemetry (primary table for AWS Lambda & Hardware Console)
    await db.query(
      `INSERT INTO device_telemetry (
        device_id, payload, battery_level, signal_rssi, recorded_at
      ) VALUES ($1, $2, $3, $4, $5)`,
      [
        device_id,
        JSON.stringify(payload),
        battery !== undefined ? battery : null,
        signal !== undefined ? signal : null,
        recordedAt
      ]
    );

    // 2. Also insert into legacy telemetry_data for backwards compatibility
    try {
      await db.query(
        'INSERT INTO telemetry_data (device_id, payload, recorded_at) VALUES ($1, $2, $3)',
        [device_id, JSON.stringify(payload), recordedAt]
      );
    } catch (_) {}

    // 3. Update device_registry last_reading_timestamp and health_status to ONLINE
    try {
      await db.query(
        `UPDATE device_registry 
         SET last_reading_timestamp = $1, health_status = 'ONLINE', updated_at = CURRENT_TIMESTAMP 
         WHERE device_id = $2`,
        [recordedAt, device_id]
      );
    } catch (_) {}

    // 4. Update legacy devices table last_heartbeat and battery_level
    try {
      await db.query(
        'UPDATE devices SET last_heartbeat = CURRENT_TIMESTAMP, battery_level = $1 WHERE device_code = $2 OR id::text = $2',
        [battery ? battery.toString() + '%' : null, device_id]
      );
    } catch (_) {}

    // 5. Process Hazard Detection
    if (distance !== undefined && distance < 5.0) {
      try {
        await db.query(
          'INSERT INTO alerts_logs (alert_type, message, severity) VALUES ($1, $2, $3)',
          ['HAZARD_PROXIMITY', `Device ${device_id} reported critical distance: ${distance}m`, 'CRITICAL']
        );
      } catch (_) {}
    }

    res.status(200).json({ success: true, message: 'Telemetry processed and saved to device_telemetry' });
  } catch (error) {
    console.error('Error in ingestTelemetry:', error);
    res.status(500).json({ success: false, message: 'Server error processing telemetry' });
  }
};

// @desc    Get top 20 latest telemetry records for a device from device_telemetry
// @route   GET /api/iot/telemetry/:device_id
// @access  Public (or secured)
const getTelemetryAudit = async (req, res) => {
  try {
    const { device_id } = req.params;

    const result = await db.query(
      'SELECT id, device_id, payload, battery_level, signal_rssi, recorded_at FROM device_telemetry WHERE device_id = $1 ORDER BY recorded_at DESC LIMIT 50',
      [device_id]
    );

    res.status(200).json({ success: true, data: result.rows });
  } catch (error) {
    console.error('Error in getTelemetryAudit:', error);
    res.status(500).json({ success: false, message: 'Server error fetching telemetry audit' });
  }
};

module.exports = {
  ingestTelemetry,
  getTelemetryAudit
};

