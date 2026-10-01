import re

with open('../backend/controllers/reportController.js', 'r', encoding='utf-8') as f:
    code = f.read()

# Replace the query parameter extraction
code = code.replace(
    "const { from_date, to_date } = req.query;",
    "const { from_date, to_date, yard, pilot, device, dur_op, dur_val, sort_by, sort_asc } = req.query;"
)

# Replace the SQL query logic
old_query_logic = """    const sessionsQuery = `
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
      ORDER BY COALESCE(ss.start_time, ss.session_start, ss.created_at) ASC
      LIMIT 500
    `;
    const ssRes = await db.query(sessionsQuery, [from_date, to_date]);"""


new_query_logic = """    let sessionsQuery = `
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
    
    if (yard && yard !== 'null') {
      params.push(yard);
      sessionsQuery += ` AND y.yard_name = $${params.length}`;
    }
    if (pilot && pilot !== 'null') {
      params.push(pilot);
      sessionsQuery += ` AND ss.employee_name = $${params.length}`;
    }
    if (device && device.trim() !== '') {
      params.push(`%${device}%`);
      sessionsQuery += ` AND (COALESCE(ss.ld_code, ss.rx_device_id) ILIKE $${params.length} OR COALESCE(ss.de_code, ss.tx_device_id) ILIKE $${params.length})`;
    }
    if (dur_op && dur_val && dur_val > 0) {
       let op = dur_op;
       if (op === '=') {
          sessionsQuery += ` AND ABS(EXTRACT(EPOCH FROM (COALESCE(ss.end_time, ss.session_end) - COALESCE(ss.start_time, ss.session_start, ss.created_at))) / 60 - ${parseFloat(dur_val)}) <= 5`;
       } else {
          sessionsQuery += ` AND EXTRACT(EPOCH FROM (COALESCE(ss.end_time, ss.session_end) - COALESCE(ss.start_time, ss.session_start, ss.created_at))) / 60 ${op} ${parseFloat(dur_val)}`;
       }
    }

    let sortCol = "COALESCE(ss.start_time, ss.session_start, ss.created_at)";
    if (sort_by === 'Session End') {
       sortCol = "COALESCE(ss.end_time, ss.session_end)";
    }
    let sortDir = (sort_asc === 'true') ? "ASC" : "DESC";

    sessionsQuery += ` ORDER BY ${sortCol} ${sortDir} LIMIT 500`;

    const ssRes = await db.query(sessionsQuery, params);"""

code = code.replace(old_query_logic, new_query_logic)

with open('../backend/controllers/reportController.js', 'w', encoding='utf-8') as f:
    f.write(code)

print("Backend update done")
