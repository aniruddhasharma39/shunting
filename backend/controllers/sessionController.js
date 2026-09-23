const db = require('../config/db');
const awsIotBridge = require('../services/awsIotBridge');

// @desc    Get all sessions (active and history) with paired device telemetry
// @route   GET /api/sessions
// @access  Private
const getSessions = async (req, res) => {
  try {
    const { status } = req.query; // 'live' or 'history'
    const isLiveRequested = status === 'live';

    // Auto-sweep stale live sessions before querying
    await awsIotBridge.sweepStaleSessions().catch(() => {});

    // Lookup available transmitters for default pairing fallback
    const txDeviceRes = await db.query(`
      SELECT device_code, yard_id, assigned_line_id 
      FROM devices 
      WHERE device_type = 'Dead-End' OR device_code ILIKE 'TX%' OR device_code ILIKE 'DE%'
      ORDER BY created_at ASC
    `);
    const defaultTransmitter = txDeviceRes.rows.length > 0 ? txDeviceRes.rows[0].device_code : 'TX-01';

    const mappedSessions = [];
    const seenLdDevices = new Set();

    // =========================================================================
    // 1. QUERY FROM SHUNTING_SESSIONS (Hardware sessions)
    // =========================================================================
    let ssQuery = `
      SELECT 
        ss.id,
        COALESCE(ss.session_code, ss.session_number, ('SES-' || SUBSTRING(ss.id::text, 1, 8))) as session_code,
        COALESCE(ss.ld_code, ss.rx_device_id, 'RX-01') as ld_device,
        COALESCE(ss.de_code, ss.tx_device_id, 'TX-01') as de_device,
        COALESCE(ss.start_time, ss.session_start, ss.created_at) as start_time,
        COALESCE(ss.end_time, ss.session_end) as end_time,
        ss.status,
        ss.session_status,
        ss.final_distance_cm,
        ss.minimum_distance,
        COALESCE(ss.employee_name, 'ian') as holder_name,
        COALESCE(ss.employee_id_number, 'EMP-001') as holder_employee_id,
        COALESCE(yl.line_name, 'Main Shunt Line') as line_name,
        COALESCE(yl.line_number, '01') as line_number,
        COALESCE(y.yard_name, 'North Yard') as yard_name,
        COALESCE(y.yard_code, 'NY') as yard_code,
        ss.manual_close_reason,
        ss.updated_at
      FROM shunting_sessions ss
      LEFT JOIN yard_lines yl ON ss.line_id = yl.id
      LEFT JOIN yards y ON ss.yard_id = y.id
    `;

    if (isLiveRequested) {
      ssQuery += ` WHERE (ss.status = 'LIVE' OR ss.session_status = 'LIVE') AND ss.updated_at >= (NOW() - INTERVAL '60 SECONDS') ORDER BY ss.updated_at DESC`;
    } else if (status === 'history') {
      ssQuery += ` WHERE (ss.status != 'LIVE' AND ss.session_status != 'LIVE') OR ss.updated_at < (NOW() - INTERVAL '60 SECONDS') ORDER BY COALESCE(ss.end_time, ss.session_end, ss.updated_at) DESC LIMIT 50`;
    } else {
      ssQuery += ` ORDER BY ss.created_at DESC LIMIT 50`;
    }

    const ssRes = await db.query(ssQuery);

    for (const s of ssRes.rows) {
      const isLive = isLiveRequested && (s.status === 'LIVE' || s.session_status === 'LIVE');
      if (isLive) seenLdDevices.add(s.ld_device);

      let deDeviceName = s.de_device;
      if (!deDeviceName || deDeviceName === 'N/A') {
        deDeviceName = defaultTransmitter;
      }

      // Check in-memory telemetry bridge first
      const memPkt = awsIotBridge.getLatestTelemetryForDevices([s.ld_device, deDeviceName]);

      let distanceM = null;
      let speedKmh = 0.0;
      let rxBattery = 95;
      let txBattery = 92;
      let rxSignal = -65;
      let txSignal = -68;
      let lastTelemetryTime = s.start_time;

      if (isLive && memPkt) {
        if (memPkt.distance_cm != null) {
          distanceM = parseFloat((memPkt.distance_cm / 100).toFixed(2));
        }
        if (memPkt.speed_kmh != null) speedKmh = memPkt.speed_kmh;
        if (memPkt.device_id === s.ld_device) {
          if (memPkt.battery_level != null) rxBattery = memPkt.battery_level;
          if (memPkt.signal_rssi != null) rxSignal = memPkt.signal_rssi;
        } else if (memPkt.device_id === deDeviceName) {
          if (memPkt.battery_level != null) txBattery = memPkt.battery_level;
          if (memPkt.signal_rssi != null) txSignal = memPkt.signal_rssi;
        }
        lastTelemetryTime = memPkt.recorded_at;
      } else if (s.final_distance_cm != null) {
        distanceM = parseFloat((s.final_distance_cm / 100).toFixed(2));
      } else {
        // Fetch DB telemetry
        const telRes = await db.query(`
          SELECT device_id, payload, battery_level, signal_rssi, distance_cm, speed_kmh, recorded_at
          FROM device_telemetry
          WHERE device_id = $1 OR device_id = $2
          ORDER BY recorded_at DESC LIMIT 2
        `, [deDeviceName, s.ld_device]);

        for (const row of telRes.rows) {
          const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
          if (distanceM === null) {
            const dVal = row.distance_cm ?? payload.readings?.distance_cm ?? payload.distance_cm ?? (payload.distance ? Math.round(Number(payload.distance) * 100) : null);
            if (dVal != null) distanceM = parseFloat((dVal / 100).toFixed(2));
          }
          if (row.device_id === s.ld_device) {
            rxBattery = row.battery_level ?? payload.battery_pct ?? rxBattery;
            rxSignal = row.signal_rssi ?? payload.gsm_rssi ?? rxSignal;
          } else {
            txBattery = row.battery_level ?? payload.battery_pct ?? txBattery;
            txSignal = row.signal_rssi ?? payload.gsm_rssi ?? txSignal;
          }
        }
      }

      let safetyStatus = 'NORMAL';
      let statusColor = 'green';
      if (distanceM !== null) {
        if (distanceM < 5.0) {
          safetyStatus = 'CRITICAL HAZARD';
          statusColor = 'red';
        } else if (distanceM <= 20.0) {
          safetyStatus = 'APPROACHING';
          statusColor = 'orange';
        } else {
          safetyStatus = 'SAFE CLEARANCE';
          statusColor = 'green';
        }
      }

      let durationStr = '--';
      if (s.start_time && s.end_time) {
        const diffMs = Math.abs(new Date(s.end_time) - new Date(s.start_time));
        const mins = Math.floor(diffMs / 60000);
        const secs = Math.floor((diffMs % 60000) / 1000);
        durationStr = `${mins}m ${secs}s`;
      }

      mappedSessions.push({
        id: s.id,
        session_code: s.session_code,
        ldDevice: s.ld_device,
        ldDeviceType: 'RECEIVER',
        deDevice: deDeviceName,
        deDeviceType: 'TRANSMITTER',
        startTime: s.start_time,
        endTime: s.end_time,
        duration: durationStr,
        minDistance: s.minimum_distance != null ? `${Number(s.minimum_distance).toFixed(2)}m` : (distanceM !== null ? `${distanceM.toFixed(2)}m` : '--m'),
        finalPlacement: s.final_distance_cm != null ? `${(s.final_distance_cm / 100).toFixed(2)}m` : (distanceM !== null ? `${distanceM.toFixed(2)}m` : '--m'),
        holder: s.holder_name,
        holderName: s.holder_name,
        holderEmployeeId: s.holder_employee_id,
        holderDesignation: 'Loco Pilot',
        line: s.line_name,
        lineNumber: s.line_number,
        yard: s.yard_name,
        yardCode: s.yard_code,
        remarks: s.manual_close_reason || '',
        status: isLive ? (safetyStatus === 'CRITICAL HAZARD' ? 'Hazard' : (safetyStatus === 'APPROACHING' ? 'Warning' : 'Live')) : 'Completed',
        safetyStatus: safetyStatus,
        statusColor: statusColor,
        isLive: isLive,
        distanceM: distanceM,
        distance: distanceM !== null ? `${distanceM.toFixed(1)}m` : '--m',
        speedKmh: speedKmh,
        speed: `${Number(speedKmh).toFixed(1)} km/h`,
        rxBattery: `${rxBattery}%`,
        txBattery: `${txBattery}%`,
        rxSignal: `${rxSignal} dBm`,
        txSignal: `${txSignal} dBm`,
        lastTelemetryTime: lastTelemetryTime,
        isAwsPaired: true
      });
    }

    // =========================================================================
    // 2. QUERY FROM DEVICE_ASSIGNMENTS (Issue/Return sessions)
    // =========================================================================
    let daQuery = `
      SELECT 
        da.id, 
        da.device_id,
        d.device_code as ld_device,
        d.assigned_line_id,
        d.yard_id,
        COALESCE(d.device_type, 'Loco Unit') as ld_type,
        da.issued_at, 
        da.returned_at,
        da.condition_at_issue,
        da.condition_at_return,
        u.full_name as holder_name,
        u.employee_id as holder_employee_id,
        u.designation as holder_designation,
        COALESCE(yl.line_name, 'Main Shunting Line') as line_name,
        COALESCE(yl.line_number, '01') as line_number,
        COALESCE(y.yard_name, 'North Yard') as yard_name,
        COALESCE(y.yard_code, 'NY') as yard_code,
        da.remarks
      FROM device_assignments da
      JOIN devices d ON da.device_id = d.id
      JOIN users u ON da.employee_id = u.id
      LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
      LEFT JOIN yards y ON COALESCE(yl.yard_id, d.yard_id) = y.id
    `;

    if (isLiveRequested) {
      daQuery += ` WHERE da.returned_at IS NULL`;
    } else if (status === 'history') {
      daQuery += ` WHERE da.returned_at IS NOT NULL`;
    }

    if (req.user && req.user.role === 'yard_admin') {
      daQuery += ` AND COALESCE(yl.yard_id, d.yard_id) IN (SELECT yard_id FROM user_yard_assignments WHERE user_id = '${req.user.id}')`;
    }

    daQuery += ' ORDER BY da.issued_at DESC LIMIT 30';

    const daSessions = await db.query(daQuery);

    for (let s of daSessions.rows) {
      if (seenLdDevices.has(s.ld_device)) continue;

      let deDeviceName = defaultTransmitter;
      const matchedTx = txDeviceRes.rows.find(t => 
        (s.assigned_line_id && t.assigned_line_id === s.assigned_line_id) || 
        (s.yard_id && t.yard_id === s.yard_id)
      );
      if (matchedTx) {
        deDeviceName = matchedTx.device_code;
      }

      // Check recent telemetry within 60s for live filter
      const telemetryRes = await db.query(`
        SELECT id, device_id, topic, payload, battery_level, signal_rssi, distance_cm, speed_kmh, latitude, longitude, recorded_at 
        FROM device_telemetry 
        WHERE (device_id = $1 OR device_id = $2)
        ORDER BY recorded_at DESC LIMIT 2
      `, [deDeviceName, s.ld_device]);

      const memPkt = awsIotBridge.getLatestTelemetryForDevices([s.ld_device, deDeviceName]);
      const hasRecentTelemetry = (memPkt && (Date.now() - new Date(memPkt.recorded_at).getTime()) < 60000) ||
        (telemetryRes.rows.length > 0 && (Date.now() - new Date(telemetryRes.rows[0].recorded_at).getTime()) < 60000);

      // In LIVE tab: ONLY include if actively streaming telemetry
      if (isLiveRequested && !hasRecentTelemetry) {
        continue;
      }

      // In HISTORY tab: If unreturned but has no telemetry for > 60s, show in HISTORY as completed
      const isLive = isLiveRequested && s.returned_at === null && hasRecentTelemetry;

      let distanceM = null;
      let speedKmh = 0.0;
      let rxBattery = 95;
      let txBattery = 92;
      let rxSignal = -65;
      let txSignal = -68;
      let lastTelemetryTime = s.issued_at;

      if (memPkt) {
        if (memPkt.distance_cm != null) distanceM = parseFloat((memPkt.distance_cm / 100).toFixed(2));
        if (memPkt.speed_kmh != null) speedKmh = memPkt.speed_kmh;
        if (memPkt.device_id === s.ld_device) {
          if (memPkt.battery_level != null) rxBattery = memPkt.battery_level;
          if (memPkt.signal_rssi != null) rxSignal = memPkt.signal_rssi;
        } else if (memPkt.device_id === deDeviceName) {
          if (memPkt.battery_level != null) txBattery = memPkt.battery_level;
          if (memPkt.signal_rssi != null) txSignal = memPkt.signal_rssi;
        }
        lastTelemetryTime = memPkt.recorded_at;
      }

      for (const row of telemetryRes.rows) {
        const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
        if (distanceM === null) {
          const dVal = row.distance_cm ?? payload.readings?.distance_cm ?? payload.distance_cm ?? (payload.distance ? Math.round(Number(payload.distance) * 100) : null);
          if (dVal != null) distanceM = parseFloat((dVal / 100).toFixed(2));
        }
        if (row.device_id === s.ld_device) {
          rxBattery = row.battery_level ?? payload.battery_pct ?? rxBattery;
          rxSignal = row.signal_rssi ?? payload.gsm_rssi ?? rxSignal;
        } else {
          txBattery = row.battery_level ?? payload.battery_pct ?? txBattery;
          txSignal = row.signal_rssi ?? payload.gsm_rssi ?? txSignal;
        }
      }

      let safetyStatus = 'NORMAL';
      let statusColor = 'green';
      if (distanceM !== null) {
        if (distanceM < 5.0) {
          safetyStatus = 'CRITICAL HAZARD';
          statusColor = 'red';
        } else if (distanceM <= 20.0) {
          safetyStatus = 'APPROACHING';
          statusColor = 'orange';
        } else {
          safetyStatus = 'SAFE CLEARANCE';
          statusColor = 'green';
        }
      }

      mappedSessions.push({
        id: s.id,
        session_code: `SES-${s.id.toString().substring(0, 8)}`,
        ldDevice: s.ld_device,
        ldDeviceType: s.ld_type,
        deDevice: deDeviceName,
        deDeviceType: 'Dead-End',
        startTime: s.issued_at,
        endTime: s.returned_at,
        holder: s.holder_name,
        holderName: s.holder_name,
        holderEmployeeId: s.holder_employee_id,
        holderDesignation: s.holder_designation || 'Loco Pilot',
        line: s.line_name,
        lineNumber: s.line_number,
        yard: s.yard_name,
        yardCode: s.yard_code,
        remarks: s.remarks,
        status: isLive ? (safetyStatus === 'CRITICAL HAZARD' ? 'Hazard' : (safetyStatus === 'APPROACHING' ? 'Warning' : 'Live')) : 'Completed',
        safetyStatus: safetyStatus,
        statusColor: statusColor,
        isLive: isLive,
        distanceM: distanceM,
        distance: distanceM !== null ? `${distanceM.toFixed(1)}m` : '--m',
        speedKmh: speedKmh,
        speed: `${Number(speedKmh).toFixed(1)} km/h`,
        rxBattery: `${rxBattery}%`,
        txBattery: `${txBattery}%`,
        rxSignal: `${rxSignal} dBm`,
        txSignal: `${txSignal} dBm`,
        lastTelemetryTime: lastTelemetryTime,
        isAwsPaired: true
      });
    }

    res.json(mappedSessions);
  } catch (error) {
    console.error('Error in getSessions:', error);
    res.status(500).json({ message: 'Server error fetching sessions' });
  }
};

module.exports = {
  getSessions
};
