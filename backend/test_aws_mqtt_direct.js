require('dotenv').config();
const crypto = require('crypto');
const mqtt = require('mqtt');

const AWS_IOT_ENDPOINT = process.env.AWS_IOT_ENDPOINT || 'a18ey7y7yi6gdo-ats.iot.ap-south-1.amazonaws.com';
const AWS_REGION = process.env.AWS_REGION || 'ap-south-1';
const AWS_ACCESS_KEY_ID = process.env.AWS_ACCESS_KEY_ID;
const AWS_SECRET_ACCESS_KEY = process.env.AWS_SECRET_ACCESS_KEY;

function getSignatureKey(key, dateStamp, regionName, serviceName) {
  const kDate = crypto.createHmac('sha256', 'AWS4' + key).update(dateStamp).digest();
  const kRegion = crypto.createHmac('sha256', kDate).update(regionName).digest();
  const kService = crypto.createHmac('sha256', kRegion).update(serviceName).digest();
  const kSigning = crypto.createHmac('sha256', kService).update('aws4_request').digest();
  return kSigning;
}

function getSignedUrl() {
  const date = new Date();
  const amzDate = date.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.substr(0, 8);
  const service = 'iotdevicegateway';

  const algorithm = 'AWS4-HMAC-SHA256';
  const credentialScope = `${dateStamp}/${AWS_REGION}/${service}/aws4_request`;

  const canonicalQuerystring = [
    `X-Amz-Algorithm=${algorithm}`,
    `X-Amz-Credential=${encodeURIComponent(`${AWS_ACCESS_KEY_ID}/${credentialScope}`)}`,
    `X-Amz-Date=${amzDate}`,
    `X-Amz-SignedHeaders=host`
  ].join('&');

  const canonicalHeaders = `host:${AWS_IOT_ENDPOINT}\n`;
  const signedHeaders = 'host';
  const payloadHash = crypto.createHash('sha256').update('').digest('hex');

  const canonicalRequest = [
    'GET',
    '/mqtt',
    canonicalQuerystring,
    canonicalHeaders,
    signedHeaders,
    payloadHash
  ].join('\n');

  const stringToSign = [
    algorithm,
    amzDate,
    credentialScope,
    crypto.createHash('sha256').update(canonicalRequest).digest('hex')
  ].join('\n');

  const signingKey = getSignatureKey(AWS_SECRET_ACCESS_KEY, dateStamp, AWS_REGION, service);
  const signature = crypto.createHmac('sha256', signingKey).update(stringToSign).digest('hex');

  return `wss://${AWS_IOT_ENDPOINT}:443/mqtt?${canonicalQuerystring}&X-Amz-Signature=${signature}`;
}

console.log('================================================================');
console.log('        SAFE-SHUNT: AWS IoT Core Direct MQTT Live Client         ');
console.log('================================================================');
console.log('Endpoint:', AWS_IOT_ENDPOINT);
console.log('Region:  ', AWS_REGION);
console.log('Key ID:  ', AWS_ACCESS_KEY_ID);
console.log('Connecting to AWS IoT Core over Secure WebSocket (SigV4)...');

const signedUrl = getSignedUrl();
const clientId = `safeshunt_backend_monitor_${Math.random().toString(16).substring(2, 10)}`;

const client = mqtt.connect(signedUrl, {
  clientId,
  protocol: 'wss',
  port: 443,
  clean: true,
  reconnectPeriod: 3000,
  connectTimeout: 10000,
});

client.on('connect', () => {
  console.log('\n>>> SUCCESS: Connected to AWS IoT Core MQTT Broker directly! <<<');
  console.log('Client ID:', clientId);

  const topics = ['devices/TX-01/telemetry', 'devices/+/telemetry', 'devices/#'];
  client.subscribe(topics, (err, granted) => {
    if (err) {
      console.error('Subscription error:', err);
    } else {
      console.log('\nSubscribed to topics:');
      granted.forEach(g => console.log(`  ✓ Topic: ${g.topic} (QoS ${g.qos})`));
      console.log('\nWaiting for live MQTT packets from TX-01...');
      console.log('----------------------------------------------------------------\n');
    }
  });
});

client.on('message', (topic, message) => {
  const timeIST = new Date().toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata' });
  const dateIST = new Date().toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata' });
  console.log(`\n================== [ LIVE MQTT PACKET RECEIVED ] ==================`);
  console.log(`Timestamp : ${dateIST} ${timeIST} IST`);
  console.log(`Topic     : ${topic}`);

  try {
    const payload = JSON.parse(message.toString());
    console.log(`Payload   :`);
    console.log(JSON.stringify(payload, null, 2));

    // Print highlights
    if (payload.battery !== undefined || payload.battery_pct !== undefined || payload.battery_level !== undefined) {
      console.log(`🔋 Battery: ${payload.battery ?? payload.battery_pct ?? payload.battery_level}%`);
    }
    if (payload.signal !== undefined || payload.gsm_rssi !== undefined || payload.signal_rssi !== undefined) {
      console.log(`📶 Signal : ${payload.signal ?? payload.gsm_rssi ?? payload.signal_rssi} dBm`);
    }
    if (payload.distance !== undefined || payload.distance_cm !== undefined) {
      console.log(`📏 Distance: ${payload.distance ?? payload.distance_cm}`);
    }
  } catch (_) {
    console.log(`Raw Message: ${message.toString()}`);
  }
  console.log(`===================================================================\n`);
});

client.on('error', (err) => {
  console.error('\n❌ MQTT Error:', err.message || err);
});

client.on('close', () => {
  console.log('ℹ️ MQTT connection closed.');
});

process.on('SIGINT', () => {
  console.log('\nDisconnecting from AWS IoT Core...');
  client.end();
  process.exit();
});
