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
