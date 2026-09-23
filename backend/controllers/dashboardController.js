const db = require('../config/db');
const awsIotBridge = require('../services/awsIotBridge');

// @desc    Get dashboard summary statistics
// @route   GET /api/dashboard/summary
// @access  Private
const getDashboardSummary = async (req, res) => {
  try {
    const userId = req.user?.id;
    const role = req.user?.role;

    // Run background sweep to ensure stale sessions are transitioned to history
    awsIotBridge.sweepStaleSessions().catch(() => {});

    // 1. Real Online count based on 45-second rule from device_telemetry & device_registry
    const countRes = await db.query(`
      SELECT 
        COUNT(*)::int AS total_devices,
        COUNT(CASE WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) >= (NOW() - INTERVAL '45 SECONDS') THEN 1 END)::int AS active_devices,
        COUNT(CASE WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) < (NOW() - INTERVAL '45 SECONDS') OR (dr.last_reading_timestamp IS NULL AND dt.latest_telemetry_time IS NULL) THEN 1 END)::int AS offline_devices
      FROM device_registry dr
      LEFT JOIN (
        SELECT device_id, MAX(recorded_at) AS latest_telemetry_time
        FROM device_telemetry
        GROUP BY device_id
      ) dt ON dr.device_id = dt.device_id
    `);

    const activeDevices = countRes.rows[0]?.active_devices || 0;
    const offlineDevices = countRes.rows[0]?.offline_devices || 0;

    // 2. Total Sessions Today (from both shunting_sessions and device_assignments)
    const sessionsRes = await db.query(`
      SELECT (
        (SELECT COUNT(*)::int FROM shunting_sessions WHERE DATE(COALESCE(start_time, session_start, created_at)) = CURRENT_DATE) +
        (SELECT COUNT(*)::int FROM device_assignments WHERE DATE(issued_at) = CURRENT_DATE)
      ) AS count
    `);
    const totalSessionsToday = sessionsRes.rows[0]?.count || 0;

    // 3. Critical Alerts from real alerts_logs in the last 24 hours
    const alertRes = await db.query(`
      SELECT * FROM alerts_logs 
      WHERE severity = 'CRITICAL' 
        AND alert_type NOT ILIKE '%MOCK%' 
        AND message NOT ILIKE '%Simulated%'
        AND timestamp >= (NOW() - INTERVAL '24 HOURS')
      ORDER BY timestamp DESC LIMIT 1
    `);
    const criticalAlert = alertRes.rows.length > 0 ? alertRes.rows[0] : null;

    const criticalCountRes = await db.query(`
      SELECT COUNT(*)::int AS count FROM alerts_logs 
      WHERE severity = 'CRITICAL' 
        AND alert_type NOT ILIKE '%MOCK%' 
        AND message NOT ILIKE '%Simulated%'
        AND timestamp >= (NOW() - INTERVAL '24 HOURS')
    `);
    const criticalCount = criticalCountRes.rows[0]?.count || 0;
    const systemStatus = criticalCount > 0 ? (criticalCount > 5 ? 'Warning' : 'Degraded') : '100% Operational';

    // 4. Live Active Sessions
    // Find all registered transmitters to avoid any 'N/A' pairing
    const txDeviceRes = await db.query(`
      SELECT device_code, yard_id, assigned_line_id 
      FROM devices 
      WHERE device_type = 'Dead-End' OR device_code ILIKE 'TX%' OR device_code ILIKE 'DE%'
      ORDER BY created_at ASC
    `);
    const defaultTransmitter = txDeviceRes.rows.length > 0 ? txDeviceRes.rows[0].device_code : 'TX-01';

    // Query active hardware shunting sessions first
    let ssQuery = `
      SELECT 
        ss.id,
        COALESCE(ss.ld_code, ss.rx_device_id, 'RX-01') as ld_device,
        COALESCE(ss.de_code, ss.tx_device_id, 'TX-01') as de_device,
        COALESCE(ss.start_time, ss.session_start, ss.created_at) as start_time,
        COALESCE(yl.line_name, 'Main Shunt Line') as line_name,
        COALESCE(y.yard_name, 'North Yard') as yard_name,
        ss.final_distance_cm,
        ss.updated_at
      FROM shunting_sessions ss
      LEFT JOIN yard_lines yl ON ss.line_id = yl.id
      LEFT JOIN yards y ON ss.yard_id = y.id
      WHERE (ss.status = 'LIVE' OR ss.session_status = 'LIVE')
        AND ss.updated_at >= (NOW() - INTERVAL '60 SECONDS')
      ORDER BY ss.updated_at DESC
      LIMIT 10
    `;
    const liveShuntingRes = await db.query(ssQuery);

    const liveSessions = [];
    const seenLdDevices = new Set();

    for (let session of liveShuntingRes.rows) {
      seenLdDevices.add(session.ld_device);

      let deDeviceName = session.de_device;
      if (!deDeviceName || deDeviceName === 'N/A') {
        deDeviceName = defaultTransmitter;
      }

      // Check sub-second in-memory bridge buffer first
      const memPkt = awsIotBridge.getLatestTelemetryForDevices([session.ld_device, deDeviceName]);

      let realDistance = '--m';
      let isClosing = false;
      let exactLocation = session.yard_name;
      let pitLane = session.line_name;

      if (memPkt && memPkt.distance_cm != null) {
        const meters = (memPkt.distance_cm / 100).toFixed(1);
        realDistance = `${meters}m`;
        isClosing = (memPkt.distance_cm / 100) < 5.0;
      } else if (session.final_distance_cm != null) {
        const meters = (session.final_distance_cm / 100).toFixed(1);
        realDistance = `${meters}m`;
        isClosing = (session.final_distance_cm / 100) < 5.0;
      } else {
        const telRes = await db.query(`
          SELECT payload, distance_cm FROM device_telemetry
          WHERE device_id = $1 OR device_id = $2
          ORDER BY recorded_at DESC LIMIT 1
        `, [deDeviceName, session.ld_device]);

        if (telRes.rows.length > 0) {
          const row = telRes.rows[0];
          const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
          const distVal = row.distance_cm ?? payload.readings?.distance_cm ?? payload.distance_cm ?? (payload.distance ? Math.round(Number(payload.distance) * 100) : null);
          if (distVal != null) {
            const meters = (distVal / 100).toFixed(1);
            realDistance = `${meters}m`;
            isClosing = (distVal / 100) < 5.0;
          }
        }
      }

      liveSessions.push({
        id: session.id,
        yard: exactLocation,
        line: pitLane,
        ldDevice: session.ld_device,
        deDevice: deDeviceName,
        distance: realDistance,
        isClosing: isClosing
      });
    }

    // 5. Also check for raw active telemetry streams in last 60 seconds (hardware auto-detect)
    if (liveSessions.length === 0) {
      const activeRawTel = await db.query(`
        SELECT DISTINCT ON (device_id) device_id, topic, payload, distance_cm, recorded_at
        FROM device_telemetry
        WHERE recorded_at >= (NOW() - INTERVAL '60 SECONDS')
        ORDER BY device_id, recorded_at DESC
      `);

      for (const row of activeRawTel.rows) {
        const devId = row.device_id;
        if (seenLdDevices.has(devId)) continue;

        const paired = awsIotBridge.derivePairedDevice(devId, {});
        const rxId = devId.startsWith('RX') || devId.startsWith('LD') ? devId : paired;
        const txId = devId.startsWith('TX') || devId.startsWith('DE') ? devId : paired;

        seenLdDevices.add(rxId);

        const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
        const distVal = row.distance_cm ?? payload.readings?.distance_cm ?? payload.distance_cm ?? (payload.distance ? Math.round(Number(payload.distance) * 100) : null);
        let realDistance = '--m';
        let isClosing = false;
        if (distVal != null) {
          const meters = (distVal / 100).toFixed(1);
          realDistance = `${meters}m`;
          isClosing = (distVal / 100) < 5.0;
        }

        liveSessions.push({
          id: `live_${rxId}_${txId}`,
          yard: 'North Yard',
          line: 'Main Shunt Line',
          ldDevice: rxId,
          deDevice: txId,
          distance: realDistance,
          isClosing: isClosing
        });
      }
    }

    // Also check device_assignments (if actively streaming telemetry in the last 60s)
    let daQuery = `
      SELECT 
        da.id, 
        da.device_id,
        d.device_code as ld_device, 
        d.yard_id,
        d.assigned_line_id,
        COALESCE(yl.line_name, 'Unknown Line') as line_name,
        COALESCE(y.yard_name, 'Unknown Yard') as yard_name,
        da.issued_at
      FROM device_assignments da
      JOIN devices d ON da.device_id = d.id
      LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
      LEFT JOIN yards y ON COALESCE(yl.yard_id, d.yard_id) = y.id
      WHERE da.returned_at IS NULL
    `;

    if (role === 'yard_admin') {
      daQuery += ` AND COALESCE(yl.yard_id, d.yard_id) IN (SELECT yard_id FROM user_yard_assignments WHERE user_id = '${userId}')`;
    }

    daQuery += ' ORDER BY da.issued_at DESC LIMIT 5';
    const daRes = await db.query(daQuery);

    for (let session of daRes.rows) {
      if (seenLdDevices.has(session.ld_device)) continue;

      let deDeviceName = defaultTransmitter;
      const matchedTx = txDeviceRes.rows.find(t => 
        (session.assigned_line_id && t.assigned_line_id === session.assigned_line_id) || 
        (session.yard_id && t.yard_id === session.yard_id)
      );
      if (matchedTx) {
        deDeviceName = matchedTx.device_code;
      }

      // Check if telemetry was received within the active 60s window
      const telemetryRes = await db.query(`
        SELECT payload, recorded_at, distance_cm
        FROM device_telemetry 
        WHERE (device_id = $1 OR device_id = $2)
          AND recorded_at >= (NOW() - INTERVAL '60 SECONDS')
        ORDER BY recorded_at DESC LIMIT 1
      `, [deDeviceName, session.ld_device]);

      const memPkt = awsIotBridge.getLatestTelemetryForDevices([session.ld_device, deDeviceName]);

      if (telemetryRes.rows.length > 0 || (memPkt && (Date.now() - new Date(memPkt.recorded_at).getTime()) < 60000)) {
        let realDistance = '--m';
        let isClosing = false;
        let exactLocation = session.yard_name;
        let pitLane = session.line_name;

        if (memPkt && memPkt.distance_cm != null) {
          const meters = (memPkt.distance_cm / 100).toFixed(1);
          realDistance = `${meters}m`;
          isClosing = (memPkt.distance_cm / 100) < 5.0;
        } else if (telemetryRes.rows.length > 0) {
          const row = telemetryRes.rows[0];
          const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
          const distVal = row.distance_cm ?? payload.readings?.distance_cm ?? payload.distance_cm ?? (payload.distance ? Math.round(Number(payload.distance) * 100) : null);
          if (distVal != null) {
            const meters = (distVal / 100).toFixed(1);
            realDistance = `${meters}m`;
            isClosing = (distVal / 100) < 5.0;
          }
          if (payload.location) exactLocation = payload.location;
          if (payload.pit_lane) pitLane = payload.pit_lane;
        }

        liveSessions.push({
          id: session.id,
          yard: exactLocation,
          line: pitLane,
          ldDevice: session.ld_device,
          deDevice: deDeviceName,
          distance: realDistance,
          isClosing: isClosing
        });
      }
    }

    res.json({
      health: {
        activeDevices,
        offlineDevices,
        totalSessionsToday,
        systemStatus
      },
      criticalAlert,
      liveSessions
    });
  } catch (error) {
    console.error('Error fetching dashboard summary:', error);
    res.status(500).json({ message: 'Server error fetching dashboard data' });
  }
};

module.exports = {
  getDashboardSummary
};
