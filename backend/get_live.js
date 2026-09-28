const { Client } = require('pg');
const client = new Client({ host: 'safeshunt-db.c5oesqouwl70.ap-south-1.rds.amazonaws.com', user: 'postgres', password: 'pisolve123', database: 'safeshunt_db', port: 5432, ssl: { rejectUnauthorized: false } });
client.connect().then(() => client.query("SELECT * FROM shunting_sessions WHERE status = 'LIVE' OR session_status = 'LIVE'")).then(res => { console.log(JSON.stringify(res.rows, null, 2)); process.exit(); });
