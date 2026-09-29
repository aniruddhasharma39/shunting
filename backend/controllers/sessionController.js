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
      SELECT dr.device_id as device_code, dr.yard_id, dr.assigned_line_id 
      FROM device_registry dr
      WHERE (dr.product_type ILIKE '%TRANSMITTER%' OR dr.device_id ILIKE 'TX%' OR dr.device_id ILIKE 'DE%')
        AND (dr.is_disabled IS NULL OR dr.is_disabled = FALSE)
      ORDER BY dr.updated_at ASC
    `);
    const defaultTransmitter = txDeviceRes.rows.length > 0 ? txDeviceRes.rows[0].device_code : null;

    // Fetch all known device IDs from device_registry (to validate sessions)
    const knownDevicesRes = await db.query(`
      SELECT device_id FROM device_registry
      WHERE (is_disabled IS NULL OR is_disabled = FALSE)
    `);
    const knownDeviceIds = new Set(knownDevicesRes.rows.map(r => r.device_id));

    const mappedSessions = [];
    const seenLdDevices = new Set();

    // =========================================================================
    // 1. QUERY FROM SHUNTING_SESSIONS (Hardware sessions)
    // =========================================================================
    let ssQuery = `
      SELECT 
        ss.id,
        COALESCE(ss.session_code, ss.session_number, ('SES-' || SUBSTRING(ss.id::text, 1, 8))) as session_code,
        COALESCE(ss.ld_code, ss.rx_device_id) as ld_device,
        COALESCE(ss.de_code, ss.tx_device_id) as de_device,
        COALESCE(ss.start_time, ss.session_start, ss.created_at) as start_time,
        COALESCE(ss.end_time, ss.session_end) as end_time,
        ss.status,
        ss.session_status,
        ss.final_distance_cm,
        ss.minimum_distance,
        ss.employee_name as holder_name,
        ss.employee_id_number as holder_employee_id,
        yl.line_name,
        yl.line_number,
        y.yard_name,
        y.yard_code,
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
      // Skip sessions with device IDs that don't exist in device_registry
      const ldDev = s.ld_device;
      const deDev = s.de_device;
      
      if (!ldDev || (knownDeviceIds.size > 0 && !knownDeviceIds.has(ldDev))) {
        continue; // Skip sessions referencing non-existent devices
      }

      const isLive = isLiveRequested && (s.status === 'LIVE' || s.session_status === 'LIVE');
      if (isLive) seenLdDevices.add(ldDev);

      let deDeviceName = deDev;
      if (!deDeviceName || deDeviceName === 'N/A') {
        // Try to find a TX device assigned to the same yard/line
        const matchedTx = txDeviceRes.rows.find(t =>
          (s.line_id && t.assigned_line_id === s.line_id) ||
          (s.yard_id && t.yard_id === s.yard_id)
        );
        deDeviceName = matchedTx ? matchedTx.device_code : defaultTransmitter;
      }

      // Check in-memory telemetry bridge first
      const memPkt = awsIotBridge.getLatestTelemetryForDevices([ldDev, deDeviceName].filter(Boolean));

      let distanceM = null;
      let speedKmh = 0.0;
      let rxBattery = null;
      let txBattery = null;
      let rxSignal = -65;
      let txSignal = -68;
      let lastTelemetryTime = s.start_time;

      if (isLive && memPkt) {
        if (memPkt.distance_cm != null) {
          distanceM = parseFloat((memPkt.distance_cm / 100).toFixed(2));
        }
        if (memPkt.speed_kmh != null) speedKmh = memPkt.speed_kmh;
        if (memPkt.device_id === ldDev) {
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
        `, [deDeviceName || ldDev, ldDev]);

        for (const row of telRes.rows) {
          const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
          if (distanceM === null) {
            const dVal = row.distance_cm ?? payload.readings?.distance_cm ?? payload.distance_cm ?? (payload.distance ? Math.round(Number(payload.distance) * 100) : null);
            if (dVal != null) distanceM = parseFloat((dVal / 100).toFixed(2));
          }
          if (row.device_id === ldDev) {
            rxBattery = row.battery_level ?? payload.battery_pct ?? rxBattery;
            rxSignal = row.signal_rssi ?? payload.gsm_rssi ?? rxSignal;
          } else {
            txBattery = row.battery_level ?? payload.battery_pct ?? txBattery;
            txSignal = row.signal_rssi ?? payload.gsm_rssi ?? txSignal;
          }
        }
      }

      // Get real battery from device_registry if still null
      if (rxBattery === null) {
        const drRes = await db.query(
          `SELECT health_status, last_reading_timestamp FROM device_registry WHERE device_id = $1`,
          [ldDev]
        );
        // battery_level not stored in registry directly; leave as null to show '--'
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
        ldDevice: ldDev,
        ldDeviceType: 'RECEIVER',
        deDevice: deDeviceName,
        deDeviceType: 'TRANSMITTER',
        startTime: s.start_time,
        endTime: s.end_time,
        duration: durationStr,
        minDistance: s.minimum_distance != null ? `${Number(s.minimum_distance).toFixed(2)}m` : (distanceM !== null ? `${distanceM.toFixed(2)}m` : '--m'),
        finalPlacement: s.final_distance_cm != null ? `${(s.final_distance_cm / 100).toFixed(2)}m` : (distanceM !== null ? `${distanceM.toFixed(2)}m` : '--m'),
        holder: s.holder_name || null,
        holderName: s.holder_name || null,
        holderEmployeeId: s.holder_employee_id || null,
        holderDesignation: 'Loco Pilot',
        line: s.line_name || null,
        lineNumber: s.line_number || null,
        yard: s.yard_name || null,
        yardCode: s.yard_code || null,
        remarks: s.manual_close_reason || '',
        status: isLive ? (safetyStatus === 'CRITICAL HAZARD' ? 'Hazard' : (safetyStatus === 'APPROACHING' ? 'Warning' : 'Live')) : 'Completed',
        safetyStatus: safetyStatus,
        statusColor: statusColor,
        isLive: isLive,
        distanceM: distanceM,
        distance: distanceM !== null ? `${distanceM.toFixed(1)}m` : '--m',
        speedKmh: speedKmh,
        speed: `${Number(speedKmh).toFixed(1)} km/h`,
        rxBattery: rxBattery !== null ? `${rxBattery}%` : '--',
        txBattery: txBattery !== null ? `${txBattery}%` : '--',
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
        yl.line_name,
        yl.line_number,
        y.yard_name,
        y.yard_code,
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
      
      // Skip sessions with devices not in device_registry
      if (knownDeviceIds.size > 0 && s.ld_device && !knownDeviceIds.has(s.ld_device)) {
        continue;
      }

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
      `, [deDeviceName || s.ld_device, s.ld_device]);

      const memPkt = awsIotBridge.getLatestTelemetryForDevices([s.ld_device, deDeviceName].filter(Boolean));
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
      let rxBattery = null;
      let txBattery = null;
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
          if (rxBattery === null) rxBattery = row.battery_level ?? payload.battery_pct ?? null;
          rxSignal = row.signal_rssi ?? payload.gsm_rssi ?? rxSignal;
        } else {
          if (txBattery === null) txBattery = row.battery_level ?? payload.battery_pct ?? null;
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

      let durationStr = '--';
      if (s.issued_at && s.returned_at) {
        const diffMs = Math.abs(new Date(s.returned_at) - new Date(s.issued_at));
        const mins = Math.floor(diffMs / 60000);
        const secs = Math.floor((diffMs % 60000) / 1000);
        durationStr = `${mins}m ${secs}s`;
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
        duration: durationStr,
        minDistance: '--m',
        finalPlacement: '--m',
        holder: s.holder_name,
        holderName: s.holder_name,
        holderEmployeeId: s.holder_employee_id,
        holderDesignation: s.holder_designation || 'Loco Pilot',
        line: s.line_name || null,
        lineNumber: s.line_number || null,
        yard: s.yard_name || null,
        yardCode: s.yard_code || null,
        remarks: s.remarks,
        status: isLive ? (safetyStatus === 'CRITICAL HAZARD' ? 'Hazard' : (safetyStatus === 'APPROACHING' ? 'Warning' : 'Live')) : 'Completed',
        safetyStatus: safetyStatus,
        statusColor: statusColor,
        isLive: isLive,
        distanceM: distanceM,
        distance: distanceM !== null ? `${distanceM.toFixed(1)}m` : '--m',
        speedKmh: speedKmh,
        speed: `${Number(speedKmh).toFixed(1)} km/h`,
        rxBattery: rxBattery !== null ? `${rxBattery}%` : '--',
        txBattery: txBattery !== null ? `${txBattery}%` : '--',
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

// @desc    Get single session details with complete tabular telemetry logs
// @route   GET /api/sessions/:id/logs
// @access  Private
const getSessionDetailsWithLogs = async (req, res) => {
  try {
    const { id } = req.params;

    // 1. Try to find in shunting_sessions first
    let ssQuery = `
      SELECT 
        ss.id,
        COALESCE(ss.session_code, ss.session_number, ('SES-' || SUBSTRING(ss.id::text, 1, 8))) as session_code,
        COALESCE(ss.ld_code, ss.rx_device_id) as ld_device,
        COALESCE(ss.de_code, ss.tx_device_id) as de_device,
        COALESCE(ss.start_time, ss.session_start, ss.created_at) as start_time,
        COALESCE(ss.end_time, ss.session_end) as end_time,
        ss.status,
        ss.session_status,
        ss.final_distance_cm,
        ss.minimum_distance,
        ss.distance_trajectory,
        ss.employee_name as holder_name,
        ss.employee_id_number as holder_employee_id,
        yl.line_name,
        yl.line_number,
        y.yard_name,
        y.yard_code,
        ss.manual_close_reason,
        ss.created_at,
        ss.updated_at
      FROM shunting_sessions ss
      LEFT JOIN yard_lines yl ON ss.line_id = yl.id
      LEFT JOIN yards y ON ss.yard_id = y.id
      WHERE ss.id::text = $1 OR ss.session_code = $1 OR ss.session_number = $1
      LIMIT 1
    `;
    const ssRes = await db.query(ssQuery, [id]);

    let sessionMeta = null;
    let rawTrajectory = [];

    if (ssRes.rows.length > 0) {
      const s = ssRes.rows[0];
      rawTrajectory = s.distance_trajectory || [];
      if (typeof rawTrajectory === 'string') {
        try { rawTrajectory = JSON.parse(rawTrajectory); } catch (_) { rawTrajectory = []; }
      }

      let durationStr = '--';
      if (s.start_time && s.end_time) {
        const diffMs = Math.abs(new Date(s.end_time) - new Date(s.start_time));
        const mins = Math.floor(diffMs / 60000);
        const secs = Math.floor((diffMs % 60000) / 1000);
        durationStr = `${mins}m ${secs}s`;
      }

      sessionMeta = {
        id: s.id,
        session_code: s.session_code,
        ldDevice: s.ld_device,
        deDevice: s.de_device,
        startTime: s.start_time,
        endTime: s.end_time,
        duration: durationStr,
        finalPlacement: s.final_distance_cm != null ? `${(s.final_distance_cm / 100).toFixed(2)}m` : '--m',
        finalDistanceCm: s.final_distance_cm,
        minDistance: s.minimum_distance != null ? `${Number(s.minimum_distance).toFixed(2)}m` : '--m',
        holder: s.holder_name || null,
        holderName: s.holder_name || null,
        holderEmployeeId: s.holder_employee_id || null,
        holderDesignation: 'Loco Pilot',
        yard: s.yard_name || null,
        yardCode: s.yard_code || null,
        line: s.line_name || null,
        lineNumber: s.line_number || null,
        status: s.status || s.session_status || 'Completed',
        remarks: s.manual_close_reason || ''
      };
    } else {
      // 2. Check device_assignments
      const daRes = await db.query(`
        SELECT 
          da.id, 
          da.device_id,
          d.device_code as ld_device,
          d.assigned_line_id,
          d.yard_id,
          da.issued_at, 
          da.returned_at,
          da.condition_at_issue,
          da.condition_at_return,
          u.full_name as holder_name,
          u.employee_id as holder_employee_id,
          u.designation as holder_designation,
          yl.line_name,
          yl.line_number,
          y.yard_name,
          y.yard_code,
          da.remarks
        FROM device_assignments da
        JOIN devices d ON da.device_id = d.id
        JOIN users u ON da.employee_id = u.id
        LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
        LEFT JOIN yards y ON COALESCE(yl.yard_id, d.yard_id) = y.id
        WHERE da.id::text = $1
        LIMIT 1
      `, [id]);

      if (daRes.rows.length === 0) {
        return res.status(404).json({ success: false, message: 'Session not found' });
      }

      const s = daRes.rows[0];
      const deDeviceName = null;

      let durationStr = '--';
      if (s.issued_at && s.returned_at) {
        const diffMs = Math.abs(new Date(s.returned_at) - new Date(s.issued_at));
        const mins = Math.floor(diffMs / 60000);
        const secs = Math.floor((diffMs % 60000) / 1000);
        durationStr = `${mins}m ${secs}s`;
      }

      sessionMeta = {
        id: s.id,
        session_code: `SES-${s.id.toString().substring(0, 8)}`,
        ldDevice: s.ld_device,
        deDevice: deDeviceName,
        startTime: s.issued_at,
        endTime: s.returned_at,
        duration: durationStr,
        finalPlacement: '--m',
        finalDistanceCm: null,
        minDistance: '--m',
        holder: s.holder_name,
        holderName: s.holder_name,
        holderEmployeeId: s.holder_employee_id,
        holderDesignation: s.holder_designation || 'Loco Pilot',
        yard: s.yard_name || null,
        yardCode: s.yard_code || null,
        line: s.line_name || null,
        lineNumber: s.line_number || null,
        status: s.returned_at ? 'Completed' : 'Live',
        remarks: s.remarks || ''
      };
    }

    // 3. Build Tabular Logs
    const tabularLogs = [];

    // If trajectory points exist in JSON
    if (Array.isArray(rawTrajectory) && rawTrajectory.length > 0) {
      rawTrajectory.forEach((pt, index) => {
        const timestamp = pt.t ? new Date(pt.t).toISOString() : sessionMeta.startTime;
        const distCm = pt.d_cm ?? pt.distance_cm ?? (pt.distance ? Math.round(Number(pt.distance) * 100) : null);
        const distM = distCm != null ? parseFloat((distCm / 100).toFixed(2)) : null;
        const speed = pt.speed_kmh ?? 0.0;
        const battery = pt.battery ?? null;
        const signal = pt.signal ?? -65;

        let safetyStatus = 'NORMAL';
        if (distM !== null) {
          if (distM < 5.0) safetyStatus = 'CRITICAL HAZARD';
          else if (distM <= 20.0) safetyStatus = 'APPROACHING';
          else safetyStatus = 'SAFE CLEARANCE';
        }

        const dateObj = new Date(timestamp);
        const timeStr = !isNaN(dateObj.getTime()) ? dateObj.toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour12: false }) : '--:--:--';

        tabularLogs.push({
          index: index + 1,
          time: timeStr,
          timestamp: timestamp,
          distance_cm: distCm,
          distance_m: distM,
          distance_display: distM !== null ? `${distM.toFixed(2)}m` : '--m',
          speed_kmh: speed,
          speed_display: `${Number(speed).toFixed(1)} km/h`,
          rx_battery: battery !== null ? `${battery}%` : '--',
          tx_battery: battery !== null ? `${battery}%` : '--',
          signal_rssi: `${signal} dBm`,
          safety_status: safetyStatus
        });
      });
    }

    // If tabularLogs is still empty or few, query device_telemetry directly
    if (tabularLogs.length < 5 && sessionMeta.startTime) {
      const startTime = sessionMeta.startTime;
      const endTime = sessionMeta.endTime || new Date();

      const telRes = await db.query(`
        SELECT id, device_id, topic, payload, battery_level, signal_rssi, distance_cm, speed_kmh, recorded_at
        FROM device_telemetry
        WHERE (device_id = $1 OR device_id = $2)
          AND recorded_at >= ($3::timestamptz - INTERVAL '5 MINUTES')
          AND recorded_at <= ($4::timestamptz + INTERVAL '5 MINUTES')
        ORDER BY recorded_at ASC
        LIMIT 100
      `, [sessionMeta.ldDevice, sessionMeta.deDevice || sessionMeta.ldDevice, startTime, endTime]);

      if (telRes.rows.length > 0) {
        tabularLogs.length = 0; // replace with granular DB logs
        telRes.rows.forEach((row, index) => {
          const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
          const distCm = row.distance_cm ?? payload.readings?.distance_cm ?? payload.distance_cm ?? (payload.distance ? Math.round(Number(payload.distance) * 100) : null);
          const distM = distCm != null ? parseFloat((distCm / 100).toFixed(2)) : null;
          const speed = row.speed_kmh ?? payload.speed_kmh ?? 0.0;
          const battery = row.battery_level ?? payload.diagnostics?.battery_pct ?? payload.battery_pct ?? null;
          const signal = row.signal_rssi ?? payload.diagnostics?.gsm_rssi ?? payload.gsm_rssi ?? -65;

          let safetyStatus = 'NORMAL';
          if (distM !== null) {
            if (distM < 5.0) safetyStatus = 'CRITICAL HAZARD';
            else if (distM <= 20.0) safetyStatus = 'APPROACHING';
            else safetyStatus = 'SAFE CLEARANCE';
          }

          const dateObj = new Date(row.recorded_at);
          const timeStr = !isNaN(dateObj.getTime()) ? dateObj.toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour12: false }) : '--:--:--';

          tabularLogs.push({
            index: index + 1,
            time: timeStr,
            timestamp: row.recorded_at,
            deviceId: row.device_id,
            distance_cm: distCm,
            distance_m: distM,
            distance_display: distM !== null ? `${distM.toFixed(2)}m` : '--m',
            speed_kmh: speed,
            speed_display: `${Number(speed).toFixed(1)} km/h`,
            rx_battery: battery !== null ? `${battery}%` : '--',
            tx_battery: battery !== null ? `${battery}%` : '--',
            signal_rssi: `${signal} dBm`,
            safety_status: safetyStatus
          });
        });
      }
    }

    res.json({
      success: true,
      session: sessionMeta,
      logsCount: tabularLogs.length,
      tabularLogs: tabularLogs
    });
  } catch (error) {
    console.error('Error in getSessionDetailsWithLogs:', error);
    res.status(500).json({ success: false, message: 'Server error fetching session logs' });
  }
};

// @desc    Get sessions within a date range for bulk report
// @route   GET /api/sessions/range-report
// @access  Private
const getSessionsForRangeReport = async (req, res) => {
  try {
    const { from_date, to_date } = req.query;

    if (!from_date || !to_date) {
      return res.status(400).json({ success: false, message: 'from_date and to_date are required' });
    }

    // Fetch known device IDs
    const knownDevicesRes = await db.query(`
      SELECT device_id FROM device_registry
      WHERE (is_disabled IS NULL OR is_disabled = FALSE)
    `);
    const knownDeviceIds = new Set(knownDevicesRes.rows.map(r => r.device_id));

    const sessionsQuery = `
      SELECT 
        ss.id,
        COALESCE(ss.session_code, ss.session_number, ('SES-' || SUBSTRING(ss.id::text, 1, 8))) as session_code,
        COALESCE(ss.ld_code, ss.rx_device_id) as ld_device,
        COALESCE(ss.de_code, ss.tx_device_id) as de_device,
        COALESCE(ss.start_time, ss.session_start, ss.created_at) as start_time,
        COALESCE(ss.end_time, ss.session_end) as end_time,
        ss.status,
        ss.session_status,
        ss.final_distance_cm,
        ss.minimum_distance,
        ss.employee_name as holder_name,
        ss.employee_id_number as holder_employee_id,
        yl.line_name,
        yl.line_number,
        y.yard_name,
        y.yard_code
      FROM shunting_sessions ss
      LEFT JOIN yard_lines yl ON ss.line_id = yl.id
      LEFT JOIN yards y ON ss.yard_id = y.id
      WHERE COALESCE(ss.start_time, ss.session_start, ss.created_at) >= $1::timestamptz
        AND COALESCE(ss.start_time, ss.session_start, ss.created_at) <= $2::timestamptz + INTERVAL '1 day' - INTERVAL '1 second'
      ORDER BY COALESCE(ss.start_time, ss.session_start, ss.created_at) ASC
      LIMIT 500
    `;

    const ssRes = await db.query(sessionsQuery, [from_date, to_date]);

    // Filter and map sessions - only real devices
    const sessions = ssRes.rows
      .filter(s => {
        const ldDev = s.ld_device;
        if (!ldDev) return false;
        if (knownDeviceIds.size > 0 && !knownDeviceIds.has(ldDev)) return false;
        return true;
      })
      .map(s => {
        let durationStr = '--';
        if (s.start_time && s.end_time) {
          const diffMs = Math.abs(new Date(s.end_time) - new Date(s.start_time));
          const mins = Math.floor(diffMs / 60000);
          const secs = Math.floor((diffMs % 60000) / 1000);
          durationStr = `${mins}m ${secs}s`;
        }

        return {
          id: s.id,
          session_code: s.session_code,
          ldDevice: s.ld_device,
          deDevice: s.de_device,
          startTime: s.start_time,
          endTime: s.end_time,
          duration: durationStr,
          startDistance: s.minimum_distance != null ? `${Number(s.minimum_distance).toFixed(2)}m` : '--m',
          endDistance: s.final_distance_cm != null ? `${(s.final_distance_cm / 100).toFixed(2)}m` : '--m',
          holderName: s.holder_name || null,
          holderEmployeeId: s.holder_employee_id || null,
          yard: s.yard_name || null,
          yardCode: s.yard_code || null,
          line: s.line_name || null,
          lineNumber: s.line_number || null,
          status: s.status || s.session_status || 'Completed'
        };
      });

    res.json({
      success: true,
      fromDate: from_date,
      toDate: to_date,
      totalSessions: sessions.length,
      sessions
    });
  } catch (error) {
    console.error('Error in getSessionsForRangeReport:', error);
    res.status(500).json({ success: false, message: 'Server error fetching sessions for report' });
  }
};

module.exports = {
  getSessions,
  getSessionDetailsWithLogs,
  getSessionsForRangeReport
};
