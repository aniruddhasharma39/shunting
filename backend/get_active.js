const { Client } = require('pg');
const client = new Client({ host: 'safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com', user: 'postgres', password: 'pisolve123', database: 'safeshunt_db', port: 5432, ssl: { rejectUnauthorized: false } });
client.connect().then(() => client.query("SELECT DISTINCT device_id FROM device_telemetry WHERE recorded_at >= NOW() - INTERVAL '5 minutes'")).then(res => { console.log(res.rows.map(r => r.device_id)); process.exit(); });
