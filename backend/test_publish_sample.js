require('dotenv').config();
const crypto = require('crypto');
const mqtt = require('mqtt');

const AWS_IOT_ENDPOINT = process.env.AWS_IOT_ENDPOINT;
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

const signedUrl = getSignedUrl();
const clientId = `safeshunt_publisher_${Math.random().toString(16).substring(2, 8)}`;
const client = mqtt.connect(signedUrl, { clientId, protocol: 'wss', port: 443 });

client.on('connect', () => {
  console.log('Connected to AWS IoT to publish test packet...');
  const topic = 'devices/TX-01/telemetry';
  const payload = {
    deviceId: 'TX-01',
    deviceType: 'TRANSMITTER',
    battery_pct: 94,
    gsm_rssi: -62,
    latitude: 19.0760,
    longitude: 72.8777,
    speed_kmh: 0.0,
    distance_cm: 2450,
    status: 'ONLINE',
    firmware_version: '2.0.0',
    timestamp: new Date().toISOString()
  };

  client.publish(topic, JSON.stringify(payload), { qos: 0 }, (err) => {
    if (err) {
      console.error('Publish error:', err);
    } else {
      console.log(`✅ Successfully published test packet to ${topic} on AWS IoT Core!`);
      console.log('Payload:', JSON.stringify(payload, null, 2));
    }
    client.end();
    process.exit();
  });
});
