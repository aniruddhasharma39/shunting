require('dotenv').config();
const db = require('./config/db');

async function test() {
  try {
    await db.query(`
      ALTER TABLE shunting_sessions 
      ADD COLUMN IF NOT EXISTS session_code VARCHAR(50),
      ADD COLUMN IF NOT EXISTS rx_device_id VARCHAR(50),
      ADD COLUMN IF NOT EXISTS tx_device_id VARCHAR(50),
      ADD COLUMN IF NOT EXISTS start_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      ADD COLUMN IF NOT EXISTS end_time TIMESTAMP WITH TIME ZONE,
      ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'LIVE',
      ADD COLUMN IF NOT EXISTS final_distance_cm INT,
      ADD COLUMN IF NOT EXISTS min_distance_cm INT,
      ADD COLUMN IF NOT EXISTS start_distance_cm INT,
      ADD COLUMN IF NOT EXISTS distance_trajectory JSONB DEFAULT '[]'::jsonb;
    `);
    console.log('✅ Successfully added tx_device_id, rx_device_id, session_code, status, distance_trajectory columns to shunting_sessions on AWS RDS!');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
}

test();


