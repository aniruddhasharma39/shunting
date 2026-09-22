-- ====================================================================
-- SafeShunt Database Schema Extension: AWS Fleet Provisioning, OTA Updates & Telemetry
-- Compatible with PostgreSQL 13+ / AWS RDS PostgreSQL
-- ====================================================================

-- 1. EXTEND DEVICES TABLE FOR HARDWARE & AWS FLEET PROVISIONING METADATA
ALTER TABLE devices ADD COLUMN IF NOT EXISTS mac_address VARCHAR(50);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS hardware_version VARCHAR(50);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS aws_thing_name VARCHAR(100);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS aws_thing_arn TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS aws_iot_endpoint TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS certificate_arn TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS certificate_id VARCHAR(100);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS provisioning_template VARCHAR(100);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS provisioning_status VARCHAR(50) DEFAULT 'UNPROVISIONED'; -- UNPROVISIONED, PROVISIONING, PROVISIONED, REVOKED
ALTER TABLE devices ADD COLUMN IF NOT EXISTS provisioned_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_devices_aws_thing_name ON devices(aws_thing_name);
CREATE INDEX IF NOT EXISTS idx_devices_provisioning_status ON devices(provisioning_status);

-- 2. OTA FIRMWARE RELEASES TABLE
CREATE TABLE IF NOT EXISTS ota_firmware_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firmware_version VARCHAR(50) NOT NULL UNIQUE,
    target_device_type VARCHAR(50) NOT NULL, -- e.g., 'LD', 'DE', 'PD', 'CD'
    target_hardware_version VARCHAR(50) NOT NULL,
    binary_url TEXT NOT NULL,                -- S3 URL or firmware storage link
    sha256_checksum VARCHAR(64) NOT NULL,    -- SHA256 checksum for binary integrity validation
    min_compatible_version VARCHAR(50),      -- Minimum FW version required to update
    release_notes TEXT,
    is_critical BOOLEAN DEFAULT false,
    status VARCHAR(30) DEFAULT 'ACTIVE',     -- ACTIVE, DEPRECATED, ARCHIVED
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ota_fw_type_version ON ota_firmware_releases(target_device_type, target_hardware_version);

-- 3. OTA UPDATE JOBS TABLE (Tracks update executions per device)
CREATE TABLE IF NOT EXISTS ota_update_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aws_job_id VARCHAR(100),                 -- AWS IoT Job ID if using AWS IoT Jobs
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    firmware_id UUID NOT NULL REFERENCES ota_firmware_releases(id) ON DELETE CASCADE,
    target_version VARCHAR(50) NOT NULL,
    previous_version VARCHAR(50),
    job_status VARCHAR(50) DEFAULT 'QUEUED',  -- QUEUED, IN_PROGRESS, DOWNLOADING, INSTALLING, SUCCESS, FAILED, TIMED_OUT, CANCELLED
    progress_pct INTEGER DEFAULT 0,
    error_code VARCHAR(100),
    error_message TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ota_jobs_device_id ON ota_update_jobs(device_id);
CREATE INDEX IF NOT EXISTS idx_ota_jobs_status ON ota_update_jobs(job_status);

-- 4. HIGH-FREQUENCY DEVICE TELEMETRY TABLE
CREATE TABLE IF NOT EXISTS device_telemetry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    recorded_at TIMESTAMP NOT NULL,
    
    -- Telemetry Key Metrics
    distance_meters DOUBLE PRECISION,
    speed_kmh DOUBLE PRECISION,
    battery_percentage INTEGER,
    battery_voltage DOUBLE PRECISION,
    temperature_celsius DOUBLE PRECISION,
    rssi_gsm INTEGER,                       -- GSM Signal Strength (dBm)
    rssi_rf INTEGER,                        -- RF Signal Strength (dBm)
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    
    -- Additional status flags and flexible raw payload
    status_flags JSONB DEFAULT '{}'::jsonb,
    raw_payload JSONB NOT NULL,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Fast Time-Series Indexing for querying latest telemetry per device
CREATE INDEX IF NOT EXISTS idx_telemetry_device_time ON device_telemetry(device_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_recorded_at ON device_telemetry(recorded_at DESC);
