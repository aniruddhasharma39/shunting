-- ==========================================================
-- SafeShunt Application Complete Database Schema
-- Compatible with PostgreSQL 13+ / AWS RDS PostgreSQL
-- ==========================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. USERS TABLE
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(100) NOT NULL,
    employee_id VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    designation VARCHAR(50) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'viewer',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_employee_id ON users(employee_id);

-- 2. YARDS TABLE
CREATE TABLE IF NOT EXISTS yards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    yard_code VARCHAR(20) UNIQUE NOT NULL,
    yard_name VARCHAR(100) NOT NULL,
    station VARCHAR(100) NOT NULL,
    division VARCHAR(100) NOT NULL,
    zone VARCHAR(100) NOT NULL,
    yard_type VARCHAR(30) NOT NULL DEFAULT 'Mixed',
    status VARCHAR(20) NOT NULL DEFAULT 'Active',
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. USER YARD ASSIGNMENTS (Many-to-Many: Yard Admins <-> Yards)
CREATE TABLE IF NOT EXISTS user_yard_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    yard_id UUID NOT NULL REFERENCES yards(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID REFERENCES users(id),
    UNIQUE(user_id, yard_id)
);

CREATE INDEX IF NOT EXISTS idx_user_yard_assignments_user_id ON user_yard_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_user_yard_assignments_yard_id ON user_yard_assignments(yard_id);

-- 4. YARD LINES TABLE
CREATE TABLE IF NOT EXISTS yard_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    yard_id UUID NOT NULL REFERENCES yards(id) ON DELETE CASCADE,
    line_type VARCHAR(50) NOT NULL DEFAULT 'Other',
    line_number VARCHAR(50),
    line_name VARCHAR(100) NOT NULL,
    dead_end_name VARCHAR(100),
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    approach_direction VARCHAR(50),
    warning_distance DOUBLE PRECISION DEFAULT 50.0,
    slow_distance DOUBLE PRECISION DEFAULT 20.0,
    stop_distance DOUBLE PRECISION DEFAULT 5.0,
    status VARCHAR(50) NOT NULL DEFAULT 'Active',
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_yard_lines_yard_id ON yard_lines(yard_id);

-- 5. DEVICES TABLE
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_code VARCHAR(50) UNIQUE NOT NULL,
    device_type VARCHAR(50) NOT NULL,
    device_name VARCHAR(100) NOT NULL,
    serial_number VARCHAR(100) NOT NULL,
    yard_id UUID NOT NULL REFERENCES yards(id) ON DELETE CASCADE,
    registration_date DATE NOT NULL DEFAULT CURRENT_DATE,
    installation_date DATE,
    firmware_version VARCHAR(50),
    rf_available BOOLEAN NOT NULL DEFAULT true,
    gsm_available BOOLEAN NOT NULL DEFAULT true,
    device_status VARCHAR(50) NOT NULL DEFAULT 'Active',
    online_status VARCHAR(50) DEFAULT 'Offline',
    last_heartbeat TIMESTAMP,
    battery_available BOOLEAN DEFAULT false,
    battery_type VARCHAR(50),
    battery_install_date DATE,
    battery_replacement_due DATE,
    charging_method VARCHAR(50),
    power_source VARCHAR(50),
    sensor_available BOOLEAN DEFAULT false,
    camera_available BOOLEAN DEFAULT false,
    last_maintenance_date DATE,
    next_maintenance_date DATE,
    assigned_line_id UUID REFERENCES yard_lines(id) ON DELETE SET NULL,
    network_status VARCHAR(50) DEFAULT 'Online',
    battery_level VARCHAR(20) DEFAULT '90%',
    condition_status VARCHAR(50) DEFAULT 'Good',
    sim_status VARCHAR(50) DEFAULT 'Active',
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_devices_yard_id ON devices(yard_id);
CREATE INDEX IF NOT EXISTS idx_devices_device_code ON devices(device_code);
CREATE INDEX IF NOT EXISTS idx_devices_assigned_line ON devices(assigned_line_id);

-- 5A. DEVICE ASSIGNMENTS TABLE (Issue/Return Log used by Dashboard & Sessions)
CREATE TABLE IF NOT EXISTS device_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    returned_at TIMESTAMP,
    condition_at_issue VARCHAR(50) DEFAULT 'Good',
    condition_at_return VARCHAR(50),
    fault_reported VARCHAR(50),
    remarks TEXT
);

-- 5B. ALERTS & LOGS TABLE (Used by Dashboard Alerts)
CREATE TABLE IF NOT EXISTS alerts_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_type VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    severity VARCHAR(50) NOT NULL,
    yard_id UUID REFERENCES yards(id) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. DEVICE SIM DETAILS
CREATE TABLE IF NOT EXISTS device_sim_details (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    sim_available BOOLEAN NOT NULL DEFAULT false,
    sim_number VARCHAR(50),
    sim_operator VARCHAR(50),
    sim_iccid VARCHAR(50),
    sim_activation_date DATE,
    last_recharge_date DATE,
    recharge_valid_until DATE,
    recharge_plan VARCHAR(100),
    sim_status VARCHAR(50) NOT NULL DEFAULT 'Active',
    recharge_reminder_days INTEGER DEFAULT 7,
    remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. DEVICE LINE ASSIGNMENTS (DE Devices to Lines)
CREATE TABLE IF NOT EXISTS device_line_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    line_id UUID NOT NULL REFERENCES yard_lines(id) ON DELETE CASCADE,
    yard_id UUID NOT NULL REFERENCES yards(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    removed_at TIMESTAMP,
    assigned_by UUID REFERENCES users(id),
    removed_by UUID REFERENCES users(id),
    removal_reason TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 8. DEVICE ISSUE AND RETURN (Portable LD/PD Units)
CREATE TABLE IF NOT EXISTS device_issue_returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    yard_id UUID NOT NULL REFERENCES yards(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    employee_name VARCHAR(100) NOT NULL,
    employee_id_number VARCHAR(50) NOT NULL,
    designation VARCHAR(50),
    issue_datetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expected_return_time TIMESTAMP,
    device_condition_at_issue VARCHAR(50) DEFAULT 'Good',
    battery_pct_at_issue INTEGER,
    issued_by UUID REFERENCES users(id),
    return_datetime TIMESTAMP,
    device_condition_at_return VARCHAR(50),
    battery_pct_at_return INTEGER,
    fault_reported BOOLEAN DEFAULT false,
    fault_description TEXT,
    received_by UUID REFERENCES users(id),
    remarks TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'Issued',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 9. DEVICE HEARTBEATS
CREATE TABLE IF NOT EXISTS device_heartbeats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    device_type VARCHAR(50),
    device_timestamp TIMESTAMP NOT NULL,
    yard_id UUID REFERENCES yards(id) ON DELETE CASCADE,
    online_status VARCHAR(50),
    gsm_status VARCHAR(50),
    rf_status VARCHAR(50),
    power_status VARCHAR(50),
    sensor_status VARCHAR(50),
    firmware_version VARCHAR(50),
    fault_code VARCHAR(50),
    connected_device_id UUID,
    cloud_receipt_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 10. DEVICE HEALTH STATUS
CREATE TABLE IF NOT EXISTS device_health_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    health_status VARCHAR(50) NOT NULL DEFAULT 'Unknown',
    last_heartbeat TIMESTAMP,
    time_since_last_heartbeat INTERVAL,
    heartbeats_expected_today INTEGER DEFAULT 0,
    heartbeats_received_today INTEGER DEFAULT 0,
    missed_heartbeats INTEGER DEFAULT 0,
    power_status VARCHAR(50),
    gsm_status VARCHAR(50),
    rf_status VARCHAR(50),
    sensor_status VARCHAR(50),
    active_alert TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 11. SHUNTING SESSIONS
CREATE TABLE IF NOT EXISTS shunting_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_number VARCHAR(50),
    session_date DATE NOT NULL DEFAULT CURRENT_DATE,
    yard_id UUID NOT NULL REFERENCES yards(id) ON DELETE CASCADE,
    employee_name VARCHAR(100),
    employee_id_number VARCHAR(50),
    issue_record_id UUID REFERENCES device_issue_returns(id),
    ld_device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    ld_code VARCHAR(50),
    de_device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    de_code VARCHAR(50),
    line_id UUID REFERENCES yard_lines(id),
    dead_end_name VARCHAR(100),
    session_start TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    session_end TIMESTAMP,
    duration INTERVAL,
    minimum_distance DOUBLE PRECISION,
    final_placement_distance DOUBLE PRECISION,
    alerts_generated INTEGER DEFAULT 0,
    communication_failure BOOLEAN DEFAULT false,
    session_status VARCHAR(50) NOT NULL DEFAULT 'Active',
    manual_close_reason TEXT,
    closed_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 12. SESSION EVENTS
CREATE TABLE IF NOT EXISTS session_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES shunting_sessions(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL,
    event_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    distance DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    movement_direction VARCHAR(50),
    zone VARCHAR(50),
    description TEXT,
    device_timestamp TIMESTAMP,
    cloud_receipt_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 13. ALERTS TABLE
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_type VARCHAR(50) NOT NULL,
    alert_subtype VARCHAR(50) NOT NULL,
    title VARCHAR(100) NOT NULL,
    description TEXT,
    severity VARCHAR(50) NOT NULL DEFAULT 'Info',
    yard_id UUID REFERENCES yards(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    session_id UUID REFERENCES shunting_sessions(id) ON DELETE CASCADE,
    line_id UUID REFERENCES yard_lines(id) ON DELETE CASCADE,
    alert_status VARCHAR(50) NOT NULL DEFAULT 'Open',
    acknowledged_by UUID REFERENCES users(id),
    acknowledged_at TIMESTAMP,
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP,
    resolution_remarks TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 14. MAINTENANCE RECORDS
CREATE TABLE IF NOT EXISTS maintenance_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    maintenance_type VARCHAR(50) NOT NULL,
    description TEXT,
    performed_by VARCHAR(100),
    performed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    next_maintenance_date DATE,
    parts_replaced TEXT,
    cost NUMERIC,
    remarks TEXT,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 15. AUDIT LOGS
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action_type VARCHAR(50) NOT NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id UUID,
    user_id UUID REFERENCES users(id),
    user_name VARCHAR(100),
    details JSONB,
    ip_address VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 16. REPORT HISTORY
CREATE TABLE IF NOT EXISTS report_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_type VARCHAR(50) NOT NULL,
    report_format VARCHAR(50) NOT NULL,
    filters JSONB,
    generated_by UUID REFERENCES users(id),
    generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    file_path TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 17. OPTIONAL TELEMETRY DATA
CREATE TABLE IF NOT EXISTS telemetry_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    payload JSONB NOT NULL,
    recorded_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_telemetry_device_time ON telemetry_data(device_id, recorded_at DESC);
