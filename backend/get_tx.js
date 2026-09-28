const { Client } = require('pg');
const client = new Client({ host: 'safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com', user: 'postgres', password: 'pisolve123', database: 'safeshunt_db', port: 5432, ssl: { rejectUnauthorized: false } });
client.connect().then(() => client.query("SELECT device_code FROM devices WHERE device_type = 'Dead-End' OR device_code ILIKE 'TX%' ORDER BY created_at ASC LIMIT 1")).then(res => { console.log(JSON.stringify(res.rows[0])); process.exit(); });
