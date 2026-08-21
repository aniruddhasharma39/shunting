const db = require('../config/db');

// @desc    Get dashboard summary statistics
// @route   GET /api/dashboard/summary
// @access  Private
const getDashboardSummary = async (req, res) => {
  try {
    const userId = req.user.id;
    const role = req.user.role;

    let deviceJoin = '';
    let sessionJoin = '';
    let alertJoin = '';
    let whereClause = '';
    let params = [];
    let alertParams = [];

    if (role === 'yard_admin') {
      deviceJoin = `
        LEFT JOIN yard_lines yl ON devices.assigned_line_id = yl.id
        LEFT JOIN user_yard_assignments uya ON yl.yard_id = uya.yard_id AND uya.user_id = $1
      `;
      whereClause = ' AND (devices.assigned_line_id IS NULL OR uya.yard_id IS NOT NULL)';
      
      sessionJoin = `
        LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
        JOIN user_yard_assignments uya ON yl.yard_id = uya.yard_id AND uya.user_id = $1
      `;
      
      alertJoin = `
        JOIN user_yard_assignments uya ON alerts_logs.yard_id = uya.yard_id AND uya.user_id = $1
      `;
      
      params.push(userId);
      alertParams.push(userId);
    }

    // Total Active Devices
    const activeRes = await db.query(`SELECT COUNT(*) FROM devices ${deviceJoin} WHERE network_status = 'Online' ${whereClause}`, params);
    const activeDevices = parseInt(activeRes.rows[0].count, 10);

    // Total Offline Devices
    const offlineRes = await db.query(`SELECT COUNT(*) FROM devices ${deviceJoin} WHERE network_status != 'Online' ${whereClause}`, params);
    const offlineDevices = parseInt(offlineRes.rows[0].count, 10);

    // Total Sessions Today (simplistic check)
    const sessionsRes = await db.query(`
      SELECT COUNT(*) FROM device_assignments da
      JOIN devices d ON da.device_id = d.id
      ${sessionJoin}
      WHERE DATE(da.issued_at) = CURRENT_DATE
    `, params);
    const totalSessionsToday = parseInt(sessionsRes.rows[0].count, 10);

    // System Status
    // Determine overall health based on critical alerts in the last 24 hours
    const recentAlertsRes = await db.query(`
        SELECT COUNT(*) FROM alerts_logs 
        ${alertJoin}
        WHERE severity = 'CRITICAL' AND timestamp >= NOW() - INTERVAL '24 HOURS'
    `, alertParams);
    const criticalCount = parseInt(recentAlertsRes.rows[0].count, 10);
    const systemStatus = criticalCount > 0 ? (criticalCount > 5 ? 'Warning' : '98%') : '100%';

    // Latest Critical Alert
    const alertRes = await db.query(`
        SELECT alerts_logs.* FROM alerts_logs 
        ${alertJoin}
        WHERE severity = 'CRITICAL' ORDER BY timestamp DESC LIMIT 1
    `, alertParams);
    let criticalAlert = alertRes.rows.length > 0 ? alertRes.rows[0] : null;

    // --- MOCK IoT DATA INJECTION ---
    // If no real alerts from IoT, randomly inject a dummy alert for presentation purposes
    if (!criticalAlert && Math.random() > 0.5) {
        criticalAlert = {
            alert_type: 'HAZARD_PROXIMITY (MOCK)',
            message: 'Simulated IoT: Distance critically low at 12.5m',
            severity: 'CRITICAL',
            timestamp: new Date()
        };
    }

    // Live Sessions
    // Fetch currently active device assignments with mock distance formatting
    const liveSessionsQuery = `
        SELECT 
            da.id, 
            da.device_id,
            d.device_code as ld_device, 
            'DE-MOCK' as de_device, 
            da.issued_at, 
            COALESCE(yl.line_name, 'Unknown Line') as line_name,
            COALESCE(y.yard_name, 'Unknown Yard') as yard_name
        FROM device_assignments da
        JOIN devices d ON da.device_id = d.id
        LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
        LEFT JOIN yards y ON yl.yard_id = y.id
        ${role === 'yard_admin' ? 'JOIN user_yard_assignments uya ON yl.yard_id = uya.yard_id AND uya.user_id = $1' : ''}
        WHERE da.returned_at IS NULL
        ORDER BY da.issued_at DESC
        LIMIT 5
    `;
    const liveSessionsRes = await db.query(liveSessionsQuery, params);
    
    // Fetch real telemetry data for the active sessions
    const liveSessions = [];
    for (let session of liveSessionsRes.rows) {
        // Get the latest telemetry for this device
        const telemetryRes = await db.query(
            'SELECT payload FROM telemetry_data WHERE device_id = $1 ORDER BY recorded_at DESC LIMIT 1',
            [session.device_id]
        );
        
        let realDistance = '--m';
        let isClosing = false;
        
        let exactLocation = session.yard_name;
        let pitLane = session.line_name;

        if (telemetryRes.rows.length > 0) {
            const payload = telemetryRes.rows[0].payload;
            realDistance = payload.distance_show || (payload.distance ? payload.distance + 'm' : '--m');
            
            if (payload.location) exactLocation = payload.location;
            if (payload.pit_lane) pitLane = payload.pit_lane;
            
            // If distance is less than 20m, mark as closing
            const numDistance = parseFloat(payload.distance || payload.distance_show || 999);
            isClosing = numDistance < 20;
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

    // If there are no live sessions in DB, return empty list (no mock data)
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
