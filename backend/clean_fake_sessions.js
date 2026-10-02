const db = require('./config/db');

async function clean() {
  try {
    const res = await db.query(`
      DELETE FROM shunting_sessions 
      WHERE (final_distance_cm IS NULL OR distance_trajectory = '[]'::jsonb)
    `);
    console.log(`Deleted ${res.rowCount} fake/ghost sessions.`);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}

clean();
