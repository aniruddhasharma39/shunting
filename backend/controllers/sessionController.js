const db = require('../config/db');

// @desc    Get all sessions (active and history)
// @route   GET /api/sessions
// @access  Private
const getSessions = async (req, res) => {
  try {
    const { status } = req.query; // 'live' or 'history'
    let queryStr = `
        SELECT 
            da.id, 
            da.device_id,
            d.device_code as ld_device, 
            'DE-MOCK' as de_device, 
            da.issued_at, 
            da.returned_at,
            u.full_name as holder_name,
            COALESCE(yl.line_name, 'Unknown Line') as line_name,
            COALESCE(y.yard_name, 'Unknown Yard') as yard_name,
            da.remarks
        FROM device_assignments da
        JOIN devices d ON da.device_id = d.id
        JOIN users u ON da.employee_id = u.id
        LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
        LEFT JOIN yards y ON yl.yard_id = y.id
    `;

    let queryParams = [];
    let whereClauses = [];

    if (status === 'live') {
        whereClauses.push('da.returned_at IS NULL');
    } else if (status === 'history') {
        whereClauses.push('da.returned_at IS NOT NULL');
    }

    if (req.user.role === 'yard_admin') {
        queryParams.push(req.user.id);
        whereClauses.push(`yl.yard_id IN (SELECT yard_id FROM user_yard_assignments WHERE user_id = $${queryParams.length})`);
    }

    if (whereClauses.length > 0) {
        queryStr += ' WHERE ' + whereClauses.join(' AND ');
    }

    queryStr += ' ORDER BY da.issued_at DESC ';

    const sessions = await db.query(queryStr, queryParams);
    
    // Map data for frontend
    const mappedSessions = [];
    for (let s of sessions.rows) {
        const isLive = s.returned_at === null;
        
        let queryParamsT = [s.device_id];
        let queryStrT = `SELECT payload FROM telemetry_data WHERE device_id = $1`;
        if (isLive) {
            queryStrT += ` ORDER BY recorded_at DESC LIMIT 1`;
        } else {
            queryParamsT.push(s.returned_at);
            queryStrT += ` AND recorded_at <= $2 ORDER BY recorded_at DESC LIMIT 1`;
        }

        const telemetryRes = await db.query(queryStrT, queryParamsT);
        let exactLocation = 'Unknown';
        let pitLane = 'N/A';
        let distance = '0m';

        if (telemetryRes.rows.length > 0) {
            const payload = telemetryRes.rows[0].payload;
            if (payload) {
                exactLocation = payload.location || exactLocation;
                pitLane = payload.pit_lane || pitLane;
                distance = payload.distance_show || payload.distance || distance;
            }
        }

        mappedSessions.push({
            id: s.id,
            ldDevice: s.ld_device,
            deDevice: s.de_device,
            startTime: s.issued_at,
            endTime: s.returned_at,
            holder: s.holder_name,
            line: s.line_name,
            yard: s.yard_name,
            remarks: s.remarks,
            status: isLive ? 'live' : 'history',
            exactLocation: exactLocation,
            pitLane: pitLane,
            distance: distance,
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
