const db = require('./config/db');

const sql = `
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS device_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(100) UNIQUE NOT NULL,
    device_name VARCHAR(150) NOT NULL,
    serial_number VARCHAR(100) UNIQUE NOT NULL,
    product_type VARCHAR(50) NOT NULL,
    hardware_version VARCHAR(30) NOT NULL,
    firmware_version VARCHAR(30) NOT NULL,
    manufacturing_date DATE,
    sensors_config JSONB NOT NULL DEFAULT '[]'::jsonb,
    health_status VARCHAR(30) NOT NULL DEFAULT 'ONLINE',
    last_reading_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_error_code VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_device_registry_device_id ON device_registry(device_id);
CREATE INDEX IF NOT EXISTS idx_device_registry_product_type ON device_registry(product_type);
CREATE INDEX IF NOT EXISTS idx_device_registry_health_status ON device_registry(health_status);
CREATE INDEX IF NOT EXISTS idx_device_registry_sensors_gin ON device_registry USING GIN (sensors_config);

CREATE TABLE IF NOT EXISTS device_telemetry (
    id BIGSERIAL PRIMARY KEY,
    device_id VARCHAR(100) NOT NULL REFERENCES device_registry(device_id) ON DELETE CASCADE,
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payload JSONB NOT NULL,
    battery_level NUMERIC(5,2),
    signal_rssi INT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION
);

CREATE INDEX IF NOT EXISTS idx_telemetry_dev_time ON device_telemetry (device_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_payload_gin ON device_telemetry USING GIN (payload);
`;

async function run() {
  try {
    console.log('Connecting to PostgreSQL RDS...');
    await db.query(sql);
    console.log('SUCCESS: device_registry and device_telemetry tables are created and ready!');
    process.exit(0);
  } catch (err) {
    console.error('Error creating tables:', err);
    process.exit(1);
  }
}

run();
