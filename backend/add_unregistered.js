const db = require('./config/db');

async function runMigration() {
  try {
    await db.query(`
      CREATE TABLE IF NOT EXISTS issued_to_unregistered_users (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          full_name VARCHAR(100) NOT NULL,
          mobile_number VARCHAR(20) NOT NULL,
          user_photo_url TEXT NOT NULL,
          id_card_photo_url TEXT NOT NULL,
          issued_device_id UUID NOT NULL REFERENCES devices(id),
          issued_by_user_id UUID REFERENCES users(id),
          issue_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          latitude DECIMAL(10,7),
          longitude DECIMAL(10,7),
          status VARCHAR(30) DEFAULT 'ACTIVE',
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    console.log("Table issued_to_unregistered_users created.");

    await db.query(`ALTER TABLE device_assignments ALTER COLUMN employee_id DROP NOT NULL;`);
    console.log("Dropped NOT NULL from employee_id.");

    await db.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='device_assignments' AND column_name='issue_type') THEN
          ALTER TABLE device_assignments ADD COLUMN issue_type VARCHAR(20) DEFAULT 'REGISTERED';
        END IF;
      END
      $$;
    `);
    console.log("Added issue_type to device_assignments.");

    await db.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='device_assignments' AND column_name='unregistered_user_id') THEN
          ALTER TABLE device_assignments ADD COLUMN unregistered_user_id UUID REFERENCES issued_to_unregistered_users(id);
        END IF;
      END
      $$;
    `);
    console.log("Added unregistered_user_id to device_assignments.");

  } catch (err) {
    console.error("Migration error:", err);
  } finally {
    process.exit(0);
  }
}

runMigration();
