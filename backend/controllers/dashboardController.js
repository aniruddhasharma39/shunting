const db = require('../config/db');

// @desc    Get dashboard summary statistics
// @route   GET /api/dashboard/summary
// @access  Private
const getDashboardSummary = async (req, res) => {
  try {
    const userId = req.user?.id;
    const role = req.user?.role;

    // Real Online count based on 30-second rule from device_telemetry & device_registry
    const countRes = await db.query(`
      SELECT 
        COUNT(*)::int AS total_devices,
        COUNT(CASE WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) >= (NOW() - INTERVAL '30 SECONDS') THEN 1 END)::int AS active_devices,
        COUNT(CASE WHEN GREATEST(dr.last_reading_timestamp, dt.latest_telemetry_time) < (NOW() - INTERVAL '30 SECONDS') OR (dr.last_reading_timestamp IS NULL AND dt.latest_telemetry_time IS NULL) THEN 1 END)::int AS offline_devices
      FROM device_registry dr
      LEFT JOIN (
        SELECT device_id, MAX(recorded_at) AS latest_telemetry_time
        FROM device_telemetry
        GROUP BY device_id
      ) dt ON dr.device_id = dt.device_id
    `);

    const activeDevices = countRes.rows[0]?.active_devices || 0;
    const offlineDevices = countRes.rows[0]?.offline_devices || 0;

    // Total Sessions Today
    const sessionsRes = await db.query(`
      SELECT COUNT(*)::int AS count 
      FROM device_assignments da
      WHERE DATE(da.issued_at) = CURRENT_DATE
    `);
    const totalSessionsToday = sessionsRes.rows[0]?.count || 0;

    // Critical Alerts from real alerts_logs in the last 24 hours (NO MOCK DATA)
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

    // Live Active Sessions (Only real unreturned device assignments)
    let liveSessionsParams = [];
    let liveSessionsQuery = `
      SELECT 
        da.id, 
        da.device_id,
        d.device_code as ld_device, 
        COALESCE(de_dev.device_code, 'N/A') as de_device,
        da.issued_at, 
        COALESCE(yl.line_name, 'Unknown Line') as line_name,
        COALESCE(y.yard_name, 'Unknown Yard') as yard_name
      FROM device_assignments da
      JOIN devices d ON da.device_id = d.id
      LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
      LEFT JOIN yards y ON COALESCE(yl.yard_id, d.yard_id) = y.id
      LEFT JOIN devices de_dev ON de_dev.assigned_line_id = yl.id AND (de_dev.device_type = 'Dead-End' OR de_dev.device_code ILIKE 'TX%')
      WHERE da.returned_at IS NULL
    `;

    if (role === 'yard_admin') {
      liveSessionsParams.push(userId);
      liveSessionsQuery += ` AND COALESCE(yl.yard_id, d.yard_id) IN (SELECT yard_id FROM user_yard_assignments WHERE user_id = $1)`;
    }

    liveSessionsQuery += ' ORDER BY da.issued_at DESC LIMIT 10';
    const liveSessionsRes = await db.query(liveSessionsQuery, liveSessionsParams);

    const liveSessions = [];
    for (let session of liveSessionsRes.rows) {
      // Get real latest telemetry from device_telemetry (or fallback telemetry_data)
      const telemetryRes = await db.query(`
        SELECT payload, recorded_at, distance_cm
        FROM device_telemetry 
        WHERE device_id = $1 
        ORDER BY recorded_at DESC LIMIT 1
      `, [session.ld_device]);

      let realDistance = '--m';
      let isClosing = false;
      let exactLocation = session.yard_name;
      let pitLane = session.line_name;

      if (telemetryRes.rows.length > 0) {
        const row = telemetryRes.rows[0];
        const payload = typeof row.payload === 'string' ? JSON.parse(row.payload) : (row.payload || {});
        
        if (row.distance_cm != null) {
          const meters = (row.distance_cm / 100).toFixed(1);
          realDistance = `${meters}m`;
          isClosing = (row.distance_cm / 100) < 20;
        } else if (payload.distance != null || payload.distance_show != null) {
          realDistance = payload.distance_show || `${payload.distance}m`;
          const numDist = parseFloat(payload.distance || payload.distance_show || 999);
          isClosing = numDist < 20;
        }

        if (payload.location) exactLocation = payload.location;
        if (payload.pit_lane) pitLane = payload.pit_lane;
      }

      liveSessions.push({
        id: session.id,
        yard: exactLocation,
        line: pitLane,
        ldDevice: session.ld_device,
        deDevice: session.de_device,
        distance: realDistance,
        isClosing: isClosing
      });
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
