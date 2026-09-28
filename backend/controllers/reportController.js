const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const db = require('../config/db');

async function getReportData(reportType, filters, user) {
  let tableData = { headers: [], rows: [] };
  
  // Extract filter values
  const { yardId, lineId, employeeId, fromDate, toDate } = filters || {};

  if (reportType === 'Device Inventory') {
    tableData.headers = ['UUID', 'Type', 'Battery', 'Condition', 'Status'];
    
    let query = `
      SELECT d.device_code, d.device_type, d.battery_level, d.condition_status, d.network_status 
      FROM devices d
      LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
    `;
    let params = [];
    let conditions = [];
    
    if (user.role === 'yard_admin') {
       query += ` LEFT JOIN user_yard_assignments uya ON yl.yard_id = uya.yard_id AND uya.user_id = $1 `;
       params.push(user.id);
       conditions.push(`(d.assigned_line_id IS NULL OR uya.yard_id IS NOT NULL)`);
    }
    
    if (yardId) {
       params.push(yardId);
       conditions.push(`yl.yard_id = $${params.length}`);
    }
    if (lineId) {
       params.push(lineId);
       conditions.push(`d.assigned_line_id = $${params.length}`);
    }
    
    if (conditions.length > 0) {
       query += ` WHERE ` + conditions.join(' AND ');
    }
    
    query += ` ORDER BY d.created_at DESC`;
    
    const devices = await db.query(query, params);
    tableData.rows = devices.rows.map(d => [d.device_code, d.device_type, d.battery_level || '--', d.condition_status, d.network_status]);
    
  } else {
    // Sessions
    tableData.headers = ['Date', 'Device', 'Employee', 'Status'];
    let query = `
      SELECT da.issued_at, d.device_code, u.full_name, da.returned_at
      FROM device_assignments da
      JOIN devices d ON da.device_id = d.id
      JOIN users u ON da.employee_id = u.id
      LEFT JOIN yard_lines yl ON d.assigned_line_id = yl.id
    `;
    let params = [];
    let conditions = [];
    
    if (user.role === 'yard_admin') {
       query += ` JOIN user_yard_assignments uya ON yl.yard_id = uya.yard_id `;
       params.push(user.id);
       conditions.push(`uya.user_id = $${params.length}`);
    }
    
    if (yardId) {
       params.push(yardId);
       conditions.push(`yl.yard_id = $${params.length}`);
    }
    if (lineId) {
       params.push(lineId);
       conditions.push(`d.assigned_line_id = $${params.length}`);
    }
    if (employeeId) {
       params.push(employeeId);
       conditions.push(`da.employee_id = $${params.length}`);
    }
    if (fromDate && toDate) {
       params.push(fromDate);
       params.push(toDate);
       conditions.push(`da.issued_at >= $${params.length - 1} AND da.issued_at <= $${params.length}::timestamp + interval '1 day' - interval '1 second'`);
    }
    
    if (conditions.length > 0) {
       query += ` WHERE ` + conditions.join(' AND ');
    }
    
    query += ' ORDER BY da.issued_at DESC LIMIT 500';
    
    const sessions = await db.query(query, params);
    tableData.rows = sessions.rows.map(s => [
      new Date(s.issued_at).toLocaleDateString(), 
      s.device_code, 
      s.full_name, 
      s.returned_at ? 'Finished' : 'Active'
    ]);
  }
  
  if (tableData.rows.length === 0) {
      tableData.rows = [['No data found', '', '', '', '']];
  }
  
  return tableData;
}

exports.generatePDF = async (req, res) => {
  try {
    const reportType = req.query.reportType;
    const filters = req.query.filters ? JSON.parse(req.query.filters) : {};
    
    const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'portrait' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${(reportType || 'Report').replace(/ /g, '_')}.pdf"`);
    
    const streamPromise = new Promise((resolve, reject) => {
      res.on('finish', resolve);
      res.on('error', reject);
      doc.on('error', reject);
    });

    doc.pipe(res);
    
    doc.fontSize(20).text('SafeShunt - Reports & Audits', { align: 'center' });
    doc.moveDown();
    doc.fontSize(14).text(`Report Type: ${reportType || 'Standard'}`, { align: 'left' });
    doc.fontSize(10).text(`Generated On: ${new Date().toLocaleString()}`, { align: 'left' });
    doc.moveDown();

    doc.fontSize(12).text('Applied Filters:', { underline: true });
    doc.fontSize(10);
    // Only print display strings, skip internal IDs
    for (const [key, value] of Object.entries(filters || {})) {
       if (!key.endsWith('Id') && key !== 'fromDate' && key !== 'toDate') {
          doc.text(`${key}: ${value}`);
       }
    }
    doc.moveDown(2);

    const tableData = await getReportData(reportType, filters, req.user);
    tableData.title = `${reportType || 'Data'} Results`;

    await doc.table(tableData, { 
      prepareHeader: () => doc.font("Helvetica-Bold").fontSize(10),
      prepareRow: (row, indexColumn, indexRow, rectRow, rectCell) => doc.font("Helvetica").fontSize(10)
    });
    
    doc.end();
    await streamPromise;
  } catch (error) {
    console.error("PDF Generation Error:", error);
    if (!res.headersSent) {
       res.status(500).json({ error: 'Failed to generate PDF' });
    }
  }
};

exports.generateExcel = async (req, res) => {
  try {
    const reportType = req.query.reportType;
    const filters = req.query.filters ? JSON.parse(req.query.filters) : {};
    const safeReportType = reportType || 'Report';

    const workbook = new ExcelJS.Workbook();
    workbook.creator = 'SafeShunt';
    workbook.created = new Date();

    const sheet = workbook.addWorksheet(safeReportType.substring(0, 31));

    sheet.addRow(['SafeShunt - Reports & Audits']);
    sheet.addRow([`Report Type: ${safeReportType}`]);
    sheet.addRow([`Generated On: ${new Date().toLocaleString()}`]);
    sheet.addRow([]);

    sheet.addRow(['Applied Filters:']);
    for (const [key, value] of Object.entries(filters || {})) {
       if (!key.endsWith('Id') && key !== 'fromDate' && key !== 'toDate') {
          sheet.addRow([key, value]);
       }
    }
    sheet.addRow([]);

    const tableData = await getReportData(reportType, filters, req.user);

    const headerRow = sheet.addRow(tableData.headers);
    headerRow.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FF1A2A42' }
    };
    headerRow.font = { color: { argb: 'FFFFFFFF' }, bold: true };

    sheet.addRows(tableData.rows);

    sheet.columns.forEach(column => {
      column.width = 20;
    });

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="${safeReportType.replace(/ /g, '_')}.xlsx"`);

    await workbook.xlsx.write(res);
    res.end();

  } catch (error) {
    console.error("Excel Generation Error:", error);
    if (!res.headersSent) {
       res.status(500).json({ error: 'Failed to generate Excel' });
    }
  }
};

// =========================================================================
// SINGLE SESSION AUDIT REPORT EXPORT (PDF & EXCEL)
// =========================================================================

async function fetchSessionDataForReport(sessionId) {
  const ssQuery = `
    SELECT 
      ss.id,
      COALESCE(ss.session_code, ss.session_number, ('SES-' || SUBSTRING(ss.id::text, 1, 8))) as session_code,
      COALESCE(ss.ld_code, ss.rx_device_id, 'N/A') as ld_device,
      COALESCE(ss.de_code, ss.tx_device_id, 'N/A') as de_device,
      COALESCE(ss.start_time, ss.session_start, ss.created_at) as start_time,
      COALESCE(ss.end_time, ss.session_end) as end_time,
      ss.status,
      ss.session_status,
      ss.final_distance_cm,
      ss.minimum_distance,
      ss.distance_trajectory,
      COALESCE(ss.employee_name, 'N/A') as holder_name,
      COALESCE(ss.employee_id_number, 'N/A') as holder_employee_id,
      COALESCE(yl.line_name, 'N/A') as line_name,
      COALESCE(yl.line_number, 'N/A') as line_number,
      COALESCE(y.yard_name, 'N/A') as yard_name,
      COALESCE(y.yard_code, 'N/A') as yard_code,
      ss.manual_close_reason
    FROM shunting_sessions ss
    LEFT JOIN yard_lines yl ON ss.line_id = yl.id
    LEFT JOIN yards y ON ss.yard_id = y.id
    WHERE ss.id::text = $1 OR ss.session_code = $1 OR ss.session_number = $1
    LIMIT 1
  `;
  const ssRes = await db.query(ssQuery, [sessionId]);

  let session = null;
  let rawTrajectory = [];

  if (ssRes.rows.length > 0) {
    session = ssRes.rows[0];
    rawTrajectory = session.distance_trajectory || [];
    if (typeof rawTrajectory === 'string') {
      try { rawTrajectory = JSON.parse(rawTrajectory); } catch (_) { rawTrajectory = []; }
    }
  }

  // Normalize points
  let points = [];
  if (Array.isArray(rawTrajectory) && rawTrajectory.length > 0) {
    rawTrajectory.forEach(pt => {
      const ts = pt.t ? new Date(pt.t) : new Date(session?.start_time);
      const dCm = pt.d_cm ?? pt.distance_cm ?? (pt.distance ? Math.round(Number(pt.distance) * 100) : null);
      if (dCm != null) {
        points.push({ time: ts, distCm: dCm, speed: pt.speed_kmh ?? 0.0, batt: pt.battery ?? null });
      }
    });
  } else if (session) {
    const telRes = await db.query(`
      SELECT distance_cm, speed_kmh, battery_level, recorded_at
      FROM device_telemetry
      WHERE (device_id = $1 OR device_id = $2)
        AND recorded_at >= ($3::timestamptz - INTERVAL '5 MINUTES')
        AND recorded_at <= ($4::timestamptz + INTERVAL '5 MINUTES')
      ORDER BY recorded_at ASC LIMIT 1000
    `, [session.ld_device, session.de_device, session.start_time, session.end_time || new Date()]);
    telRes.rows.forEach(row => {
      if (row.distance_cm != null) {
        points.push({ time: new Date(row.recorded_at), distCm: row.distance_cm, speed: row.speed_kmh ?? 0.0, batt: row.battery_level });
      }
    });
  }

  // Filter based on distance
  let filteredPoints = [];
  let lastTime45 = 0;
  let lastTime30 = 0;
  let totalBatt = 0;
  let battCount = 0;

  points.sort((a,b) => a.time - b.time);

  points.forEach(pt => {
    if (pt.batt != null) { totalBatt += pt.batt; battCount++; }
    
    let distM = pt.distCm / 100;
    let tMs = pt.time.getTime();

    if (distM > 45) {
      // Exclude completely
      return;
    } else if (distM > 30) {
      // 10 second polling
      if (tMs - lastTime45 >= 10000) {
        filteredPoints.push(pt);
        lastTime45 = tMs;
      }
    } else if (distM > 15) {
      // 5 second polling
      if (tMs - lastTime30 >= 5000) {
        filteredPoints.push(pt);
        lastTime30 = tMs;
      }
    } else {
      // Max readings (all)
      filteredPoints.push(pt);
    }
  });

  // Group consecutive identical distances
  let compressed = [];
  let currentGroup = null;

  filteredPoints.forEach(pt => {
    if (!currentGroup) {
      currentGroup = { startPt: pt, endPt: pt, count: 1 };
    } else {
      if (pt.distCm === currentGroup.startPt.distCm && pt.speed === currentGroup.startPt.speed) {
        currentGroup.endPt = pt;
        currentGroup.count++;
      } else {
        compressed.push(currentGroup);
        currentGroup = { startPt: pt, endPt: pt, count: 1 };
      }
    }
  });
  if (currentGroup) compressed.push(currentGroup);

  const logs = [];
  compressed.forEach((grp, idx) => {
    let t1 = grp.startPt.time.toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour12: false });
    let t2 = grp.endPt.time.toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour12: false });
    let timeStr = (t1 === t2) ? t1 : `${t1} - ${t2}`;
    let dM = (grp.startPt.distCm / 100).toFixed(2);
    
    let zone = '';
    if (grp.startPt.distCm > 3000) zone = '30-45m Zone (10s)';
    else if (grp.startPt.distCm > 1500) zone = '15-30m Zone (5s)';
    else zone = '<15m Zone (Max)';

    logs.push([
      (idx + 1).toString(),
      timeStr,
      `${dM} m`,
      `${Number(grp.startPt.speed).toFixed(1)} km/h`,
      zone
    ]);
  });

  const avgBattery = battCount > 0 ? Math.round(totalBatt / battCount) : 95;
  const initialDistance = points.length > 0 ? (points[0].distCm / 100).toFixed(2) : '--';
  const finalDistance = points.length > 0 ? (points[points.length - 1].distCm / 100).toFixed(2) : '--';

  return { session, logs, avgBattery, initialDistance, finalDistance };
}

exports.generateSessionPDF = async (req, res) => {
  try {
    const { id } = req.params;
    const { session, logs, avgBattery, initialDistance, finalDistance } = await fetchSessionDataForReport(id);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    const doc = new PDFDocument({ margin: 30, size: 'A4', layout: 'portrait' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="Session_Report_${session.session_code}.pdf"`);
    
    const streamPromise = new Promise((resolve, reject) => {
      res.on('finish', resolve);
      res.on('error', reject);
      doc.on('error', reject);
    });

    doc.pipe(res);

    // Title & Header (Professional Formal Style for Indian Railways)
    doc.fontSize(22).font('Helvetica-Bold').text('INDIAN RAILWAYS', { align: 'center' });
    doc.fontSize(16).font('Helvetica-Bold').text('SafeShunt - Official Session Audit Report', { align: 'center' });
    doc.moveDown(0.5);
    doc.fontSize(10).font('Helvetica').text(`Generated On: ${new Date().toLocaleString()}`, { align: 'center' });
    doc.moveDown(1.5);

    // Metadata Summary Section
    doc.fontSize(12).font('Helvetica-Bold').text('SESSION METADATA & PARAMETERS:');
    doc.moveDown(0.5);
    doc.fontSize(10).font('Helvetica');

    const metaLeft = [
      `Session Code: ${session.session_code}`,
      `Receiver (Loco Unit): ${session.ld_device}`,
      `Transmitter (Dead-End): ${session.de_device}`,
      `Loco Pilot / Holder: ${session.holder_name === 'N/A' ? 'Not Assigned' : session.holder_name} (${session.holder_employee_id})`,
      `Yard / Location: ${session.yard_name === 'N/A' ? 'Not Assigned' : session.yard_name} (${session.yard_code})`
    ];

    const metaRight = [
      `Track / Pit Line: ${session.line_name === 'N/A' ? 'Not Assigned' : session.line_name} (Line ${session.line_number})`,
      `Session Start: ${session.start_time ? new Date(session.start_time).toLocaleString() : '--'}`,
      `Session End: ${session.end_time ? new Date(session.end_time).toLocaleString() : 'LIVE'}`,
      `Initial Shunting Distance: ${initialDistance} m`,
      `Final Reached Distance: ${finalDistance} m`
    ];

    metaLeft.forEach((line, i) => {
      doc.text(`${line.padEnd(50)}   |   ${metaRight[i] || ''}`);
    });
    
    doc.moveDown(0.5);
    doc.text(`Average Device Battery (Session Lifetime): ${avgBattery}%`);

    if (session.manual_close_reason) {
      doc.moveDown(0.5);
      doc.text(`Close Remarks / Note: ${session.manual_close_reason}`);
    }

    doc.moveDown(1.5);
    doc.fontSize(12).font('Helvetica-Bold').text('TABULAR TELEMETRY STREAM LOGS:');
    doc.moveDown(0.5);

    const tableData = {
      headers: ['#', 'Time Range (IST)', 'Distance', 'Speed', 'Distance Zone (Polling)'],
      rows: logs.length > 0 ? logs : [['1', '--:--', '-- m', '0.0 km/h', 'No data < 45m']]
    };

    await doc.table(tableData, {
      prepareHeader: () => doc.font("Helvetica-Bold").fontSize(10),
      prepareRow: (row, indexColumn, indexRow, rectRow, rectCell) => {
        // Apply slight background tinting dynamically based on Zone
        const zone = row[4] || '';
        if (indexColumn === 0 && zone !== 'Distance Zone (Polling)') {
            doc.addBackground(rectRow, (zone.includes('<15m') ? '#ffebee' : (zone.includes('15-30m') ? '#fff3e0' : (zone.includes('30-45m') ? '#fffde7' : '#ffffff'))), doc);
        }
        doc.font("Helvetica").fontSize(9);
      }
    });

    doc.end();
    await streamPromise;
  } catch (error) {
    console.error('Session PDF Error:', error);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to generate Session PDF' });
    }
  }
};

exports.generateSessionExcel = async (req, res) => {
  try {
    const { id } = req.params;
    const { session, logs } = await fetchSessionDataForReport(id);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    const workbook = new ExcelJS.Workbook();
    workbook.creator = 'SafeShunt';
    workbook.created = new Date();

    const sheet = workbook.addWorksheet(`Session_${session.session_code}`.substring(0, 31));

    sheet.addRow(['SafeShunt - Hardware Session Audit Report']);
    sheet.addRow([`Session Code: ${session.session_code}`]);
    sheet.addRow([`Generated On: ${new Date().toLocaleString()}`]);
    sheet.addRow([]);

    sheet.addRow(['Session Metadata:']);
    sheet.addRow(['Receiver (Loco Unit)', session.ld_device, 'Transmitter (Dead-End)', session.de_device]);
    sheet.addRow(['Loco Pilot (Holder)', `${session.holder_name} (${session.holder_employee_id})`, 'Yard / Location', `${session.yard_name} (${session.yard_code})`]);
    sheet.addRow(['Track / Pit Line', `${session.line_name} (Line ${session.line_number})`, 'Session Status', session.status || session.session_status]);
    sheet.addRow(['Session Start', session.start_time ? new Date(session.start_time).toLocaleString() : '--', 'Session End', session.end_time ? new Date(session.end_time).toLocaleString() : 'LIVE']);
    sheet.addRow(['Final Placement Distance', session.final_distance_cm != null ? `${(session.final_distance_cm / 100).toFixed(2)} m` : '-- m', 'Minimum Clearance', session.minimum_distance != null ? `${Number(session.minimum_distance).toFixed(2)} m` : '-- m']);
    if (session.manual_close_reason) {
      sheet.addRow(['Close Remarks', session.manual_close_reason]);
    }
    sheet.addRow([]);

    sheet.addRow(['Tabular Telemetry Logs:']);
    const headers = ['#', 'Time (IST)', 'Distance', 'Approach Speed', 'Battery', 'Signal RSSI', 'Safety Status'];
    const headerRow = sheet.addRow(headers);
    headerRow.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FF1A2A42' }
    };
    headerRow.font = { color: { argb: 'FFFFFFFF' }, bold: true };

    if (logs.length > 0) {
      logs.forEach(r => sheet.addRow(r));
    } else {
      sheet.addRow(['1', '--:--', '-- m', '0.0 km/h', '95%', '-65 dBm', 'NORMAL']);
    }

    sheet.columns.forEach(column => {
      column.width = 22;
    });

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="Session_Report_${session.session_code}.xlsx"`);

    await workbook.xlsx.write(res);
    res.end();
  } catch (error) {
    console.error('Session Excel Error:', error);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to generate Session Excel' });
    }
  }
};

