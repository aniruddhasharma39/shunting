require('dotenv').config();
const db = require('./config/db');
db.query("UPDATE devices SET network_status = 'Offline' WHERE id != 'ee7d38dc-615a-4b4f-8b84-15cf158396eb'").then(() => { console.log('Done'); process.exit(0); });
