-- Dummy Data Seed Script for SafeShunt AWS PostgreSQL

-- 1. Insert Yards (Hardcoding UUIDs so we can reference them below)
INSERT INTO yards (id, yard_code, yard_name, station, division, zone, status) VALUES 
('11111111-1111-1111-1111-111111111111', 'NY-01', 'North Yard', 'Sector A', 'Div 1', 'Zone 1', 'Active'),
('22222222-2222-2222-2222-222222222222', 'SY-01', 'South Yard', 'Sector B', 'Div 1', 'Zone 1', 'Active')
ON CONFLICT (id) DO NOTHING;

-- 2. Insert Yard Lines
INSERT INTO yard_lines (id, yard_id, line_code, line_name, line_type, status) VALUES 
('33333333-3333-3333-3333-333333333331', '11111111-1111-1111-1111-111111111111', 'LN-101', 'Pit Line 1', 'Pit Line', 'Active'),
('33333333-3333-3333-3333-333333333332', '11111111-1111-1111-1111-111111111111', 'LN-102', 'Stabling Line 2', 'Stabling Line', 'Active'),
('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', 'LN-201', 'Washing Line A', 'Washing Line', 'Active'),
('33333333-3333-3333-3333-333333333334', '22222222-2222-2222-2222-222222222222', 'LN-202', 'Main Shunt Line', 'Main Line', 'Active')
ON CONFLICT DO NOTHING;

-- 3. Insert Devices
-- (DE-042 is assigned to Pit Line 1, DE-088 to Stabling Line 2, DE-019 to Main Shunt Line)
INSERT INTO devices (id, device_code, device_type, battery_level, condition_status, network_status, assigned_line_id) VALUES 
('44444444-4444-4444-4444-444444444441', 'DE-042', 'Dead-End Unit', '80%', 'Good', 'Online', '33333333-3333-3333-3333-333333333331'),
('44444444-4444-4444-4444-444444444442', 'DE-088', 'Dead-End Unit', '45%', 'Good', 'Offline', '33333333-3333-3333-3333-333333333332'),
('44444444-4444-4444-4444-444444444443', 'DE-019', 'Dead-End Unit', '95%', 'Good', 'Online', '33333333-3333-3333-3333-333333333334'),
('44444444-4444-4444-4444-444444444444', 'LD-005', 'Loco Unit', '92%', 'Good', 'Online', NULL),
('44444444-4444-4444-4444-444444444445', 'PD-022', 'Portable', '100%', 'Good', 'Online', NULL),
('44444444-4444-4444-4444-444444444446', 'CD-014', 'Coupling', '88%', 'Good', 'Online', NULL),
('44444444-4444-4444-4444-444444444447', 'LD-001', 'Loco Unit', '45%', 'Good', 'Online', NULL),
('44444444-4444-4444-4444-444444444448', 'PD-011', 'Portable', '60%', 'Good', 'Online', NULL)
ON CONFLICT (device_code) DO NOTHING;

-- 4. Insert Dummy Users (For Issue/Return)
INSERT INTO users (id, full_name, employee_id, email, designation, password_hash) VALUES 
('55555555-5555-5555-5555-555555555551', 'Rajesh Kumar', 'EMP-1102', 'rajesh@railway.gov', 'Loco Pilot', 'dummyhash'),
('55555555-5555-5555-5555-555555555552', 'Amit Singh', 'EMP-2294', 'amit@railway.gov', 'Shunter', 'dummyhash')
ON CONFLICT (employee_id) DO NOTHING;

-- 5. Insert Device Assignments (Current Issues)
INSERT INTO device_assignments (device_id, employee_id, condition_at_issue) VALUES 
('44444444-4444-4444-4444-444444444447', '55555555-5555-5555-5555-555555555551', 'Good'), -- LD-001 to Rajesh
('44444444-4444-4444-4444-444444444448', '55555555-5555-5555-5555-555555555552', 'Good'); -- PD-011 to Amit

-- 6. Insert Alerts
INSERT INTO alerts_logs (alert_type, message, severity) VALUES 
('Speed Violation', 'Loco Unit LD-001 exceeded safe shunting speed in North Yard.', 'Critical'),
('Geofence Alert', 'Portable Device PD-011 left designated safe zone.', 'Warning'),
('Low Battery', 'Dead-End Unit DE-088 battery below 20%.', 'Info');
