const { Client } = require('pg');
const client = new Client({ host: 'safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com', user: 'postgres', password: process.env.DB_PASSWORD, database: 'safeshunt_db', port: 5432, ssl: { rejectUnauthorized: false } });
client.connect().then(() => client.query("SELECT device_id, payload FROM device_telemetry WHERE device_id = 'RX-03' ORDER BY recorded_at DESC LIMIT 1")).then(res => { console.log(JSON.stringify(res.rows[0])); process.exit(); });
