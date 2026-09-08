const fs = require('fs');
const db = require('./config/db');

async function run() {
  try {
    const schema = fs.readFileSync('schema.sql', 'utf8');
    await db.query(schema);
    console.log('schema created');

    const seed = fs.readFileSync('seed.sql', 'utf8');
    await db.query(seed);
    console.log('seed data inserted');
  } catch (err) {
    console.error(err);
  } finally {
    process.exit();
  }
}
run();
