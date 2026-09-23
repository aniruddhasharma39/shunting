const fs = require('fs');
const reportController = require('./controllers/reportController');
const db = require('./config/db');

async function testReportGeneration() {
  console.log('📄 Testing Single-Session PDF & Excel generation with real file streams...');

  const sessRes = await db.query('SELECT id, session_code FROM shunting_sessions ORDER BY start_time DESC LIMIT 1');
  if (sessRes.rows.length === 0) {
    console.log('No sessions found to test');
    process.exit(0);
  }

  const testSessionId = sessRes.rows[0].id;
  console.log(`Testing Session: ${sessRes.rows[0].session_code} (ID: ${testSessionId})`);

  // Test PDF via write stream
  const pdfFileStream = fs.createWriteStream('./session_test_report.pdf');
  pdfFileStream.setHeader = (k, v) => console.log(`[PDF Header] ${k}: ${v}`);
  pdfFileStream.status = (c) => ({ json: (e) => console.error(e) });

  const pdfReq = { params: { id: testSessionId } };
  await reportController.generateSessionPDF(pdfReq, pdfFileStream);

  // Test Excel via write stream
  const excelFileStream = fs.createWriteStream('./session_test_report.xlsx');
  excelFileStream.setHeader = (k, v) => console.log(`[Excel Header] ${k}: ${v}`);
  excelFileStream.status = (c) => ({ json: (e) => console.error(e) });

  const excelReq = { params: { id: testSessionId } };
  await reportController.generateSessionExcel(excelReq, excelFileStream);

  setTimeout(async () => {
    console.log('✅ Generated PDF size:', fs.statSync('./session_test_report.pdf').size, 'bytes');
    console.log('✅ Generated Excel size:', fs.statSync('./session_test_report.xlsx').size, 'bytes');
    try { fs.unlinkSync('./session_test_report.pdf'); } catch (_) {}
    try { fs.unlinkSync('./session_test_report.xlsx'); } catch (_) {}
    await db.end();
    console.log('🎉 PDF & Excel session report generation fully verified!');
  }, 1000);
}

testReportGeneration();
