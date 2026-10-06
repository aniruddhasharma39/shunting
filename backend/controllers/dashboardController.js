const db = require('../config/db');
const awsIotBridge = require('../services/awsIotBridge');

// @desc    Get dashboard summary statistics
// @route   GET /api/dashboard/summary
// @access  Private
const getDashboardSummary = async (req, res) => {
  try {
    const user = req.user;
    let yardWhereClause = '';
    let yardParams = [];
    
    if (user && user.role === 'zone_admin') {
      // The user wants to see ALL devices, regardless of zone or division, for KPIs.
      yardWhereClause = '';
    } else if (user && user.role === 'division_admin') {
      yardWhereClause = '';
    } else if (user && ['yard_admin', 'supervisor', 'shunter'].includes(user.role)) {
      yardWhereClause = '';
    }

    const whereDr = yardWhereClause ? 'WHERE (' + yardWhereClause.replace(/yard_id/g, 'COALESCE(dr.yard_id, yl.yard_id)') + ' OR COALESCE(dr.yard_id, yl.yard_id) IS NULL)' : '';
    const andSs = yardWhereClause ? 'AND (' + yardWhereClause.replace(/yard_id/g, 'ss.yard_id') + ' OR ss.yard_id IS NULL)' : '';
    const andDr = yardWhereClause ? 'AND (' + yardWhereClause.replace(/yard_id/g, 'COALESCE(dr.yard_id, yl.yard_id)') + ' OR COALESCE(dr.yard_id, yl.yard_id) IS NULL)' : '';

    // Run background sweep to ensure stale sessions are transitioned to history
    awsIotBridge.sweepStaleSessions().catch(() => {});

    // 1. Real Online count based on 45-second rule from device_telemetry & device_registry
    let query1 = `
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
      LEFT JOIN yard_lines yl ON dr.assigned_line_id = yl.id
      ${whereDr}
    `;
    const countRes = await db.query(query1, yardParams);

    const activeDevices = countRes.rows[0]?.active_devices || 0;
    const offlineDevices = countRes.rows[0]?.offline_devices || 0;

    // 2. Total Sessions Today (strictly from hardware shunting_sessions, completely decoupled from assignments)
    let query2 = `
      SELECT COUNT(*)::int AS count 
      FROM shunting_sessions ss
      WHERE DATE(COALESCE(ss.start_time, ss.session_start, ss.created_at)) = CURRENT_DATE
        AND NOT (ss.final_distance_cm IS NULL AND (ss.distance_trajectory IS NULL OR ss.distance_trajectory = '[]'::jsonb))
        ${andSs}
    `;
    const sessionsRes = await db.query(query2, yardParams);
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
    const systemStatus = criticalCount > 0 ? (criticalCount > 5 ? 'Warning' : 'Degraded') : 'Operational';

    // 4. Live Active Sessions
    const txDeviceRes = await db.query(`
      SELECT device_code, yard_id, assigned_line_id 
      FROM devices 
      WHERE device_type = 'Dead-End' OR device_code ILIKE 'TX%' OR device_code ILIKE 'DE%'
      ORDER BY created_at ASC
    `);
    const defaultTransmitter = txDeviceRes.rows.length > 0 ? txDeviceRes.rows[0].device_code : 'TX-01';

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
        ${andSs}
      ORDER BY ss.updated_at DESC
      LIMIT 10
    `;
    const liveShuntingRes = await db.query(ssQuery, yardParams);

    const liveSessions = [];
    const seenLdDevices = new Set();

    for (let session of liveShuntingRes.rows) {
      seenLdDevices.add(session.ld_device);

      let deDeviceName = session.de_device;
      if (!deDeviceName || deDeviceName === 'N/A') {
        deDeviceName = defaultTransmitter;
      }

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
      let queryRaw = `
        SELECT DISTINCT ON (dt.device_id) dt.device_id, dt.topic, dt.payload, dt.distance_cm, dt.recorded_at
        FROM device_telemetry dt
        LEFT JOIN device_registry dr ON dt.device_id = dr.device_id
        LEFT JOIN yard_lines yl ON dr.assigned_line_id = yl.id
        WHERE dt.recorded_at >= (NOW() - INTERVAL '60 SECONDS')
        ${andDr}
        ORDER BY dt.device_id, dt.recorded_at DESC
      `;
      const activeRawTel = await db.query(queryRaw, yardParams);

      for (const row of activeRawTel.rows) {
        const devId = row.device_id;
        const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
        
        const paired = awsIotBridge.derivePairedDevice(devId, payload);
        const rxId = devId.startsWith('RX') || devId.startsWith('LD') ? devId : paired;
        const txId = devId.startsWith('TX') || devId.startsWith('DE') ? devId : paired;

        if (seenLdDevices.has(rxId)) continue;
        seenLdDevices.add(rxId);
        
        const readings = payload.readings || {};
        const selectedTargetId = readings.selected_target_id || payload.selected_target_id;
        const isExplicitlyPaired = payload.paired_tx_id || payload.paired_rx_id || payload.paired_device || payload.status === 'PAIRED' || payload.event === 'PAIR_START' || (selectedTargetId && selectedTargetId > 0);
        if (!isExplicitlyPaired) continue;
        
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
