require('dotenv').config();
const db = require('./config/db');
(async () => {
    try {
        let from_date = '2026-09-28';
        let to_date = '2026-09-29';
        let sort_by = 'Session Start';
        let sort_asc = 'false';
        let sessionsQuery = `
      SELECT 
        ss.id,
        COALESCE(ss.session_code, ss.session_number, ('SES-' || SUBSTRING(ss.id::text, 1, 8))) as session_code,
        COALESCE(ss.ld_code, ss.rx_device_id) as ld_device,
        COALESCE(ss.de_code, ss.tx_device_id) as de_device,
        COALESCE(ss.start_time, ss.session_start, ss.created_at) as start_time,
        COALESCE(ss.end_time, ss.session_end) as end_time,
        ss.final_distance_cm,
        ss.minimum_distance,
        ss.employee_name as holder_name,
        ss.employee_id_number as holder_employee_id,
        yl.line_name,
        y.yard_name
      FROM shunting_sessions ss
      LEFT JOIN yard_lines yl ON ss.line_id = yl.id
      LEFT JOIN yards y ON ss.yard_id = y.id
      WHERE COALESCE(ss.start_time, ss.session_start, ss.created_at) >= $1::timestamptz
        AND COALESCE(ss.start_time, ss.session_start, ss.created_at) <= $2::timestamptz + INTERVAL '1 day' - INTERVAL '1 second'
    `;
    let params = [from_date, to_date];
    let sortCol = 'COALESCE(ss.start_time, ss.session_start, ss.created_at)';
    let sortDir = (sort_asc === 'true') ? 'ASC' : 'DESC';
    sessionsQuery += ` ORDER BY ${sortCol} ${sortDir} LIMIT 500`;
    console.log(sessionsQuery);
    const ssRes = await db.query(sessionsQuery, params);
    console.log('Success! Rows:', ssRes.rows.length);
    process.exit(0);
    } catch(e) {
        console.error(e);
        process.exit(1);
    }
})();
