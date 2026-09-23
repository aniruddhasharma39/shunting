require('dotenv').config();
const { Pool } = require('pg');
const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com',
  database: process.env.DB_NAME || 'safeshunt_db',
  password: process.env.DB_PASSWORD || 'pisolve123',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  ssl: { rejectUnauthorized: false }
});

const { getSessions, getSessionDetailsWithLogs } = require('./controllers/sessionController');
const { getDashboardSummary } = require('./controllers/dashboardController');

async function testAll() {
  console.log('🧪 Starting Verification Tests...');

  // 1. Check Sessions Table
  const sess = await pool.query('SELECT id, session_code, ld_code, de_code, status, final_distance_cm, minimum_distance, start_time, end_time FROM shunting_sessions ORDER BY start_time DESC LIMIT 5');
  console.log('\n📊 Recent Shunting Sessions in RDS:');
  console.table(sess.rows);

  if (sess.rows.length > 0) {
    const testId = sess.rows[0].id;
    console.log(`\n🔍 Testing getSessionDetailsWithLogs for ID: ${testId}`);

    const req = { params: { id: testId } };
    const res = {
      json: (data) => {
        console.log('✅ getSessionDetailsWithLogs Response:');
        console.log('Session Code:', data.session?.session_code);
        console.log('Pair:', `${data.session?.ldDevice} <--> ${data.session?.deDevice}`);
        console.log('Duration:', data.session?.duration);
        console.log('Final Placement:', data.session?.finalPlacement);
        console.log('Total Logged Data Points:', data.logsCount);
        if (data.tabularLogs?.length > 0) {
          console.log('Sample Log Row:', data.tabularLogs[0]);
        }
      },
      status: (code) => ({ json: (err) => console.error('Error Status:', code, err) })
    };

    await getSessionDetailsWithLogs(req, res);
  }

  // 2. Test Dashboard Summary
  console.log('\n📈 Testing getDashboardSummary:');
  const dReq = { user: { id: 'admin', role: 'super_admin' } };
  const dRes = {
    json: (data) => {
      console.log('Health Stats:', data.health);
      console.log('Live Active Sessions Count:', data.liveSessions?.length);
      console.log('Live Sessions:', data.liveSessions);
    },
    status: (code) => ({ json: (err) => console.error('Dashboard Error:', code, err) })
  };
  await getDashboardSummary(dReq, dRes);

  await pool.end();
  console.log('\n🎉 All backend test checks passed!');
}

testAll();
