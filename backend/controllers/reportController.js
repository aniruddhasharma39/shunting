const ExcelJS = require('exceljs');
const PDFDocument = require('pdfkit-table');
const db = require('../config/db');
const path = require('path');
const fs = require('fs');

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
    
    const navyBlue = '#003580';
    const saffron = '#FF6600';
    const deepGreen = '#046A38';

    // Top banner
    doc.rect(0, 0, doc.page.width, 90).fill(navyBlue);

    // IR Logo on the LEFT
    const irLogoPath = path.join(__dirname, '../assets/ir_logo.jpg');
    if (fs.existsSync(irLogoPath)) {
      try { doc.image(irLogoPath, 14, 8, { width: 68, height: 68 }); } catch (_) {}
    }

    // Azadi Logo on the RIGHT
    const azadiLogoPath = path.join(__dirname, '../assets/azadi_logo.png');
    if (fs.existsSync(azadiLogoPath)) {
      try { doc.image(azadiLogoPath, doc.page.width - 90, 8, { width: 72, height: 68 }); } catch (_) {}
    }

    // Center text block
    doc.fillColor('white').fontSize(9).font('Helvetica')
       .text('Government of India', 0, 11, { align: 'center' })
       .text('Ministry of Railways', 0, 23, { align: 'center' });

    doc.fillColor('white').fontSize(18).font('Helvetica-Bold')
       .text('INDIAN RAILWAYS', 0, 35, { align: 'center' });

    doc.fillColor('#E8D5A3').fontSize(10).font('Helvetica')
       .text('SafeShunt - Reports & Audits', 0, 57, { align: 'center' });

    // Tricolor stripe
    doc.rect(0, 72, doc.page.width, 5).fill(saffron);
    doc.rect(0, 77, doc.page.width, 5).fill('white');
    doc.rect(0, 82, doc.page.width, 5).fill(deepGreen);

    doc.y = 105;
    
    doc.fillColor('black').fontSize(14).font('Helvetica-Bold').text(`Report Type: ${reportType || 'Standard'}`, 40, doc.y, { align: 'left' });
    doc.fontSize(10).font('Helvetica').text(`Generated On: ${new Date().toLocaleString()}`, { align: 'left' });
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
      COALESCE(ss.session_number, ('SES-' || SUBSTRING(ss.id::text, 1, 8))) as session_code,
      COALESCE(ss.ld_code, ss.ld_device_id::text) as ld_device,
      COALESCE(ss.de_code, ss.de_device_id::text) as de_device,
      COALESCE(ss.session_start, ss.created_at) as start_time,
      ss.session_end as end_time,
      ss.session_status as status,
      ss.session_status,
      ss.final_placement_distance as final_distance_cm,
      ss.minimum_distance,
      NULL::jsonb as distance_trajectory,
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
    WHERE ss.id::text = $1 OR ss.session_number = $1
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
      SELECT COALESCE(distance_cm, (payload->>'distance_cm')::numeric, (payload->>'distance')::numeric * 100) as distance_cm, 
             COALESCE(speed_kmh, (payload->>'speed_kmh')::numeric, 0.0) as speed_kmh, 
             COALESCE(battery_level, (payload->'diagnostics'->>'battery_pct')::numeric, (payload->>'battery_pct')::numeric) as battery_level, 
             recorded_at
      FROM device_telemetry
      WHERE (device_id = $1::text OR device_id = $2::text)
        AND recorded_at >= ($3::timestamptz - INTERVAL '5 MINUTES')
        AND recorded_at <= ($4::timestamptz + INTERVAL '5 MINUTES')
      ORDER BY recorded_at ASC LIMIT 1000
    `, [session.ld_device, session.de_device || session.ld_device, session.start_time, session.end_time || new Date()]);
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

    if (distM > 30) {
      // 10 second polling for > 30m
      if (tMs - lastTime45 >= 10000) {
        filteredPoints.push(pt);
        lastTime45 = tMs;
      }
    } else if (distM > 15) {
      // 5 second polling for 15-30m
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
    if (grp.startPt.distCm > 3000) zone = '>30m Zone (10s)';
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

  const avgBattery = battCount > 0 ? Math.round(totalBatt / battCount) : null;
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

    const doc = new PDFDocument({ margin: 40, size: 'A4', layout: 'portrait' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="Session_Report_${session.session_code}.pdf"`);
    
    const streamPromise = new Promise((resolve, reject) => {
      res.on('finish', resolve);
      res.on('error', reject);
      doc.on('error', reject);
    });

    doc.pipe(res);

    // -----------------------------------------------------------------------
    // HEADER: Indian Railways Official Branding
    // -----------------------------------------------------------------------
    const navyBlue = '#003580';
    const saffron = '#FF6600';
    const deepGreen = '#046A38';

    // Top banner
    doc.rect(0, 0, doc.page.width, 90).fill(navyBlue);

    // IR Logo on the LEFT
    const irLogoPath = path.join(__dirname, '../assets/ir_logo.jpg');
    if (fs.existsSync(irLogoPath)) {
      try { doc.image(irLogoPath, 14, 8, { width: 68, height: 68 }); } catch (_) {}
    }

    // Azadi Logo on the RIGHT
    const azadiLogoPath = path.join(__dirname, '../assets/azadi_logo.png');
    if (fs.existsSync(azadiLogoPath)) {
      try { doc.image(azadiLogoPath, doc.page.width - 90, 8, { width: 72, height: 68 }); } catch (_) {}
    }

    // Center text block — English only (Helvetica cannot render Devanagari)
    doc.fillColor('white').fontSize(9).font('Helvetica')
       .text('Government of India', 0, 11, { align: 'center' })
       .text('Ministry of Railways', 0, 23, { align: 'center' });

    doc.fillColor('white').fontSize(18).font('Helvetica-Bold')
       .text('INDIAN RAILWAYS', 0, 35, { align: 'center' });

    doc.fillColor('#E8D5A3').fontSize(10).font('Helvetica')
       .text('SafeShunt — Official Session Audit Report', 0, 57, { align: 'center' });

    // Tricolor stripe
    doc.rect(0, 72, doc.page.width, 5).fill(saffron);
    doc.rect(0, 77, doc.page.width, 5).fill('white');
    doc.rect(0, 82, doc.page.width, 5).fill(deepGreen);

    doc.y = 105;

    // -----------------------------------------------------------------------
    // METADATA BOX
    // -----------------------------------------------------------------------
    doc.fillColor(navyBlue).fontSize(11).font('Helvetica-Bold')
       .text('SESSION METADATA & PARAMETERS', 40, doc.y);
    doc.moveDown(0.4);

    const metaY = doc.y;
    doc.rect(40, metaY, doc.page.width - 80, 135).strokeColor('#CCCCCC').lineWidth(1).stroke();

    const col1X = 55;
    const col2X = doc.page.width / 2 + 10;
    let rowY = metaY + 10;
    const rowH = 18;

    function metaRow(label, value, x, y, highlight = false) {
      doc.fillColor('#555555').fontSize(8).font('Helvetica').text(label + ':', x, y, { width: 120 });
      doc.fillColor(highlight ? saffron : '#111111').fontSize(9).font('Helvetica-Bold').text(value || 'N/A', x + 122, y, { width: 140 });
    }

    metaRow('Session Code', session.session_code, col1X, rowY);
    metaRow('Generated On', new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }), col2X, rowY);
    rowY += rowH;
    metaRow('Receiver (Loco Unit)', session.ld_device, col1X, rowY);
    metaRow('Transmitter (Dead-End)', session.de_device || 'N/A', col2X, rowY);
    rowY += rowH;
    metaRow('Assigned Yard', session.yard_name === 'N/A' ? 'Not Assigned' : session.yard_name, col1X, rowY);
    metaRow('Track / Pit Line', session.line_name === 'N/A' ? 'Not Assigned' : session.line_name, col2X, rowY);
    rowY += rowH;
    metaRow('Loco Pilot / Holder', session.holder_name === 'N/A' ? 'Not Assigned' : `${session.holder_name} (${session.holder_employee_id})`, col1X, rowY);
    metaRow('Avg Device Battery', avgBattery !== null ? `${avgBattery}%` : 'N/A', col2X, rowY);
    rowY += rowH;
    metaRow('Session Start (IST)', session.start_time ? new Date(session.start_time).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }) : '--', col1X, rowY);
    metaRow('Session End (IST)', session.end_time ? new Date(session.end_time).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }) : 'LIVE', col2X, rowY);
    rowY += rowH;
    metaRow('Initial Distance', `${initialDistance} m`, col1X, rowY, true);
    metaRow('Final Distance', `${finalDistance} m`, col2X, rowY, true);
    rowY += rowH;

    if (session.manual_close_reason) {
      metaRow('Close Remarks', session.manual_close_reason, col1X, rowY);
    }

    doc.y = metaY + 145;
    doc.moveDown(0.8);

    // -----------------------------------------------------------------------
    // TELEMETRY TABLE
    // -----------------------------------------------------------------------
    doc.fillColor(navyBlue).fontSize(11).font('Helvetica-Bold')
       .text('TABULAR TELEMETRY STREAM LOGS', 40, doc.y);
    doc.moveDown(0.4);

    const tableRows = logs.length > 0 ? logs : [['1', '--:--', '-- m', '0.0 km/h', 'No data < 45m']];

    // Guard: ensure all cell values are finite strings (prevent NaN crash)
    const safeRows = tableRows.map(row =>
      row.map(cell => {
        const s = String(cell ?? '--');
        // Check for NaN in any numeric-looking value
        return s === 'NaN' || s === 'undefined' ? '--' : s;
      })
    );

    const tableData = {
      headers: ['#', 'Time Range (IST)', 'Distance', 'Speed', 'Distance Zone (Polling)'],
      rows: safeRows
    };

    await doc.table(tableData, {
      prepareHeader: () => doc.font("Helvetica-Bold").fontSize(9),
      prepareRow: (row, indexColumn, indexRow, rectRow, rectCell) => {
        doc.font("Helvetica").fontSize(8);
        // Only add background if rectRow is valid
        if (rectRow && typeof rectRow.x === 'number' && isFinite(rectRow.x) &&
            typeof rectRow.y === 'number' && isFinite(rectRow.y) &&
            typeof rectRow.width === 'number' && isFinite(rectRow.width) &&
            typeof rectRow.height === 'number' && isFinite(rectRow.height)) {
          if (indexColumn === 0) {
            const zone = (row && row[4]) ? row[4] : '';
            const bgColor = zone.includes('<15m') ? '#FFF3F3'
              : zone.includes('15-30m') ? '#FFF8E8'
              : zone.includes('30-45m') ? '#FFFFF0'
              : '#FFFFFF';
            doc.addBackground(rectRow, bgColor, 0.6);
          }
        }
      }
    });

    // Footer
    doc.moveDown(1.5);
    doc.rect(40, doc.y, doc.page.width - 80, 0.5).fill('#CCCCCC');
    doc.moveDown(0.5);
    doc.fillColor('#888888').fontSize(8).font('Helvetica')
       .text(`This is a computer-generated report by SafeShunt — Indian Railways Shunting Safety System. Generated: ${new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}`, 40, doc.y, { align: 'center' });

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
    sheet.addRow(['Receiver (Loco Unit)', session.ld_device, 'Transmitter (Dead-End)', session.de_device || 'N/A']);
    sheet.addRow(['Loco Pilot (Holder)', `${session.holder_name} (${session.holder_employee_id})`, 'Yard / Location', `${session.yard_name} (${session.yard_code})`]);
    sheet.addRow(['Track / Pit Line', `${session.line_name} (Line ${session.line_number})`, 'Session Status', session.status || session.session_status]);
    sheet.addRow(['Session Start', session.start_time ? new Date(session.start_time).toLocaleString() : '--', 'Session End', session.end_time ? new Date(session.end_time).toLocaleString() : 'LIVE']);
    sheet.addRow(['Final Placement Distance', session.final_distance_cm != null ? `${(session.final_distance_cm / 100).toFixed(2)} m` : '-- m', 'Minimum Clearance', session.minimum_distance != null ? `${Number(session.minimum_distance).toFixed(2)} m` : '-- m']);
    if (session.manual_close_reason) {
      sheet.addRow(['Close Remarks', session.manual_close_reason]);
    }
    sheet.addRow([]);

    sheet.addRow(['Tabular Telemetry Logs:']);
    const headers = ['#', 'Time (IST)', 'Distance', 'Approach Speed', 'Distance Zone'];
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
      sheet.addRow(['1', '--:--', '-- m', '0.0 km/h', 'No data < 45m']);
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

// =========================================================================
// RANGE-BASED BULK SESSION REPORT (PDF)
// =========================================================================

exports.generateRangeReportPDF = async (req, res) => {
  try {
    const { from_date, to_date, yard, pilot, device, dur_op, dur_val, sort_by, sort_asc } = req.query;

    if (!from_date || !to_date) {
      return res.status(400).json({ error: 'from_date and to_date are required' });
    }

    // Fetch sessions in range - only real devices
    const knownDevicesRes = await db.query(`
      SELECT device_id FROM device_registry
      WHERE (is_disabled IS NULL OR is_disabled = FALSE)
    `);
    const knownDeviceIds = new Set(knownDevicesRes.rows.map(r => r.device_id));

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

    const ssRes = await db.query(sessionsQuery, params);

    const sessions = ssRes.rows.filter(s => {
      if (!s.ld_device) return false;
      if (knownDeviceIds.size > 0 && !knownDeviceIds.has(s.ld_device)) return false;
      return true;
    });

    // Create PDF
    const doc = new PDFDocument({ margin: 35, size: 'A4', layout: 'portrait' });
    res.setHeader('Content-Type', 'application/pdf');
    const safeFrom = from_date.replace(/[^0-9\-]/g, '');
    const safeTo = to_date.replace(/[^0-9\-]/g, '');
    res.setHeader('Content-Disposition', `attachment; filename="SafeShunt_Sessions_${safeFrom}_to_${safeTo}.pdf"`);

    const streamPromise = new Promise((resolve, reject) => {
      res.on('finish', resolve);
      res.on('error', reject);
      doc.on('error', reject);
    });
    doc.pipe(res);

    const navyBlue = '#003580';
    const saffron = '#FF6600';
    const deepGreen = '#046A38';

    // ---- HEADER BANNER ----
    doc.rect(0, 0, doc.page.width, 90).fill(navyBlue);

    const irLogoPath = path.join(__dirname, '../assets/ir_logo.jpg');
    if (fs.existsSync(irLogoPath)) {
      try { doc.image(irLogoPath, 14, 8, { width: 68, height: 68 }); } catch (_) {}
    }

    // Azadi Logo on the RIGHT
    const azadiLogoPathBulk = path.join(__dirname, '../assets/azadi_logo.png');
    if (fs.existsSync(azadiLogoPathBulk)) {
      try { doc.image(azadiLogoPathBulk, doc.page.width - 90, 8, { width: 72, height: 68 }); } catch (_) {}
    }

    // Center text — English only (Helvetica cannot render Devanagari)
    doc.fillColor('white').fontSize(9).font('Helvetica')
       .text('Government of India', 0, 11, { align: 'center' })
       .text('Ministry of Railways', 0, 23, { align: 'center' });

    doc.fillColor('white').fontSize(17).font('Helvetica-Bold')
       .text('INDIAN RAILWAYS', 0, 35, { align: 'center' });
    doc.fillColor('#E8D5A3').fontSize(10.5).font('Helvetica')
       .text('SafeShunt — Bulk Sessions Report', 0, 57, { align: 'center' });

    doc.rect(0, 72, doc.page.width, 5).fill(saffron);
    doc.rect(0, 77, doc.page.width, 5).fill('white');
    doc.rect(0, 82, doc.page.width, 5).fill(deepGreen);

    doc.y = 100;

    // ---- REPORT METADATA ----
    const fromLabel = new Date(from_date).toLocaleDateString('en-IN', { day: '2-digit', month: 'long', year: 'numeric' });
    const toLabel = new Date(to_date).toLocaleDateString('en-IN', { day: '2-digit', month: 'long', year: 'numeric' });

    doc.rect(35, doc.y, doc.page.width - 70, 52).strokeColor('#CCCCCC').lineWidth(1).stroke();
    const mY = doc.y + 8;
    doc.fillColor('#333333').fontSize(9).font('Helvetica')
       .text(`Date Range: ${fromLabel}  —  ${toLabel}`, 50, mY)
       .text(`Total Sessions: ${sessions.length}`, 50, mY + 14)
       .text(`Generated At: ${new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}`, 50, mY + 28);
    doc.y = doc.y + 60;

    // ---- SESSION CARDS (table per session) ----
    if (sessions.length === 0) {
      doc.fillColor('#888888').fontSize(12).font('Helvetica')
         .text('No sessions found for the selected date range.', { align: 'center' });
    }

    for (let i = 0; i < sessions.length; i++) {
      const s = sessions[i];

      // Page break check
      if (doc.y > doc.page.height - 160) {
        doc.addPage();
        doc.y = 40;
      }

      // Duration
      let durationStr = '--';
      if (s.start_time && s.end_time) {
        const diffMs = Math.abs(new Date(s.end_time) - new Date(s.start_time));
        const mins = Math.floor(diffMs / 60000);
        const secs = Math.floor((diffMs % 60000) / 1000);
        durationStr = `${mins}m ${secs}s`;
      }

      const startDistStr = s.minimum_distance != null ? `${Number(s.minimum_distance).toFixed(2)} m` : '--';
      const endDistStr = s.final_distance_cm != null ? `${(s.final_distance_cm / 100).toFixed(2)} m` : '--';

      const cardY = doc.y;
      const cardHeight = 108;
      const cardWidth = doc.page.width - 70;

      // Card background
      doc.roundedRect(35, cardY, cardWidth, cardHeight, 8)
         .fillAndStroke('#F8FAFF', '#D0D8E8');

      // Card header bar
      doc.roundedRect(35, cardY, cardWidth, 22, 8)
         .fill(navyBlue);

      doc.fillColor('white').fontSize(8.5).font('Helvetica-Bold')
         .text(s.session_code, 50, cardY + 6)
         .text(s.start_time ? new Date(s.start_time).toLocaleDateString('en-IN') : '--', 0, cardY + 6, { align: 'right', width: doc.page.width - 70 - 20 });

      // Card body
      const bY = cardY + 28;
      const col = (cardWidth - 20) / 3;

      // Col 1: Devices
      doc.fillColor('#555555').fontSize(7.5).font('Helvetica')
         .text('Receiver (Loco)', 50, bY)
         .text('Transmitter (DE)', 50, bY + 14)
         .text('Duration', 50, bY + 28)
         .text('Shunting Start', 50, bY + 42);

      doc.fillColor('#111111').fontSize(8).font('Helvetica-Bold')
         .text(s.ld_device || '--', 155, bY, { width: col - 10 })
         .text(s.de_device || 'N/A', 155, bY + 14, { width: col - 10 })
         .text(durationStr, 155, bY + 28, { width: col - 10 })
         .text(s.start_time ? new Date(s.start_time).toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour12: true }) : '--', 155, bY + 42, { width: col - 10 });

      // Col 2: Distances
      const c2X = 35 + 10 + col;
      doc.fillColor('#555555').fontSize(7.5).font('Helvetica')
         .text('Start Distance', c2X, bY)
         .text('End Distance', c2X, bY + 14)
         .text('Yard', c2X, bY + 28)
         .text('Track / Pit Line', c2X, bY + 42);

      doc.fillColor('#111111').fontSize(8).font('Helvetica-Bold')
         .text(startDistStr, c2X + 80, bY, { width: col - 10 })
         .text(endDistStr, c2X + 80, bY + 14, { width: col - 10 })
         .text(s.yard_name || 'Not Assigned', c2X + 80, bY + 28, { width: col - 10 })
         .text(s.line_name || 'Not Assigned', c2X + 80, bY + 42, { width: col - 10 });

      // Col 3: Person
      const c3X = 35 + 10 + col * 2;
      doc.fillColor('#555555').fontSize(7.5).font('Helvetica')
         .text('Issued To', c3X, bY)
         .text('Employee ID', c3X, bY + 14)
         .text('Shunting End', c3X, bY + 28);

      doc.fillColor('#111111').fontSize(8).font('Helvetica-Bold')
         .text(s.holder_name || 'N/A', c3X + 65, bY, { width: col - 5 })
         .text(s.holder_employee_id || 'N/A', c3X + 65, bY + 14, { width: col - 5 })
         .text(s.end_time ? new Date(s.end_time).toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour12: true }) : '--', c3X + 65, bY + 28, { width: col - 5 });

      // Separator line
      doc.rect(35, cardY + 78, cardWidth, 0.5).fill('#D0D8E8');

      // Card footer
      const footY = cardY + 84;
      const ldStatus = s.ld_device ? 'Real Device' : 'Unknown';
      doc.fillColor('#888888').fontSize(7).font('Helvetica')
         .text(`Session ID: ${s.id}  |  Device Pair: ${s.ld_device || '--'} ↔ ${s.de_device || 'N/A'}  |  ${ldStatus}`, 50, footY, { align: 'left' });

      doc.y = cardY + cardHeight + 10;
    }

    // ---- REPORT FOOTER ----
    doc.moveDown(1);
    doc.rect(35, doc.y, doc.page.width - 70, 0.5).fill('#CCCCCC');
    doc.moveDown(0.4);
    doc.fillColor('#AAAAAA').fontSize(7.5).font('Helvetica')
       .text(`SafeShunt — Indian Railways Shunting Safety System | Computer Generated Report | ${new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}`, 0, doc.y, { align: 'center' });

    doc.end();
    await streamPromise;
  } catch (error) {
    console.error('Range Report PDF Error:', error);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to generate range report PDF' });
    }
  }
};
