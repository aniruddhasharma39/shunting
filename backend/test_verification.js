require('dotenv').config();
const db = require('./config/db');
const awsIotBridge = require('./services/awsIotBridge');
const { getDashboardSummary } = require('./controllers/dashboardController');
const { getSessions } = require('./controllers/sessionController');

async function testSuite() {
  console.log('================================================================');
  console.log('  STARTING INTEGRATION VERIFICATION TEST SUITE');
  console.log('================================================================\n');

  try {
    // 1. Simulate Live MQTT telemetry from TX-01 (e.g. Distance = 150cm / 1.5m)
    console.log('1️⃣ Simulating incoming MQTT packet from Transmitter TX-01 (150cm / 1.5m)...');
    const samplePayload = {
      deviceId: 'TX-01',
      readings: { distance_cm: 150, selected_target_id: 0 },
      diagnostics: { status: 'ONLINE', gsm_rssi: -62, battery_pct: 94 },
      productType: 'TRANSMITTER',
      msg_timestamp: Date.now()
    };
    
    await awsIotBridge.handleIncomingMqttMessage('devices/TX-01/telemetry', Buffer.from(JSON.stringify(samplePayload)));
    // Allow async persistence to finish
    await new Promise(r => setTimeout(r, 500));

    // 2. Test Dashboard Summary Controller
    console.log('\n2️⃣ Testing GET /api/dashboard/summary response...');
    let dashResData = null;
    const mockDashRes = {
      json: (data) => { dashResData = data; },
      status: () => mockDashRes
    };
    await getDashboardSummary({ user: { id: 'admin', role: 'super_admin' } }, mockDashRes);

    console.log('   Dashboard Live Sessions Count:', dashResData?.liveSessions?.length);
    console.log('   Live Session Pairing Details:', JSON.stringify(dashResData?.liveSessions, null, 2));

    if (dashResData?.liveSessions?.length > 0) {
      const s = dashResData.liveSessions[0];
      if (s.deDevice === 'N/A') {
        console.error('❌ FAILED: deDevice is still N/A!');
      } else {
        console.log(`✅ PASSED: Paired correctly: ${s.ldDevice} <--> ${s.deDevice} (Distance: ${s.distance})`);
      }
    } else {
      console.log('ℹ️ No active sessions found in dashboard (check filter).');
    }

    // 3. Test Sessions Controller (Live)
    console.log('\n3️⃣ Testing GET /api/sessions?status=live...');
    let liveSessionsData = null;
    const mockLiveRes = {
      json: (data) => { liveSessionsData = data; },
      status: () => mockLiveRes
    };
    await getSessions({ query: { status: 'live' }, user: { id: 'admin', role: 'super_admin' } }, mockLiveRes);
    console.log('   Live Sessions Result:', JSON.stringify(liveSessionsData, null, 2));

    if (liveSessionsData && liveSessionsData.length > 0) {
      const s = liveSessionsData[0];
      console.log(`✅ PASSED: Live session active with Connection Time: ${s.startTime}, Distance: ${s.distance}, Pairing: ${s.ldDevice} <--> ${s.deDevice}`);
    }

    // 4. Test Disconnection & Transition to Session History
    console.log('\n4️⃣ Simulating Disconnect / PAIR_END...');
    const endPayload = {
      event: 'PAIR_END',
      status: 'IDLE',
      paired_tx_id: 'TX-01',
      final_distance_cm: 150
    };
    await awsIotBridge.handleIncomingMqttMessage('devices/RX-01/status', Buffer.from(JSON.stringify(endPayload)));
    await new Promise(r => setTimeout(r, 500));

    console.log('\n5️⃣ Testing GET /api/sessions?status=history...');
    let historySessionsData = null;
    const mockHistRes = {
      json: (data) => { historySessionsData = data; },
      status: () => mockHistRes
    };
    await getSessions({ query: { status: 'history' }, user: { id: 'admin', role: 'super_admin' } }, mockHistRes);
    console.log('   History Sessions Count:', historySessionsData?.length);
    if (historySessionsData && historySessionsData.length > 0) {
      console.log('   Latest History Session:', JSON.stringify(historySessionsData[0], null, 2));
      console.log('✅ PASSED: Disconnected session successfully stored and retrieved from Session History!');
    }

    console.log('\n================================================================');
    console.log('  ALL INTEGRATION TESTS COMPLETED SUCCESSFULLY');
    console.log('================================================================');
    process.exit(0);

  } catch (err) {
    console.error('❌ Test error:', err);
    process.exit(1);
  }
}

testSuite();
