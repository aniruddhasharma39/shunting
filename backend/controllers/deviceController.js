const db = require('../config/db');

// @desc    Register a new device
// @route   POST /api/devices
// @access  Super Admin / Yard Admin / Hardware Engineer
const registerDevice = async (req, res) => {
  try {
    const { device_code, device_type, yard_id } = req.body;
    if (!device_code || !device_type) {
      return res.status(400).json({ message: 'Device code and type are required' });
    }

    // Default yard if not provided
    let targetYardId = yard_id;
    if (!targetYardId) {
      const yardRes = await db.query('SELECT id FROM yards LIMIT 1');
      targetYardId = yardRes.rows[0]?.id;
    }

    // Determine product_type for device_registry
    let productType = 'RECEIVER';
    if (device_type === 'Dead-End' || device_type === 'Dead-End Unit' || device_code.startsWith('TX') || device_code.startsWith('DE')) {
      productType = 'TRANSMITTER';
    } else if (device_type === 'Portable' || device_code.startsWith('RP') || device_code.startsWith('PD')) {
      productType = 'REPEATER';
    } else if (device_type === 'Coupling' || device_code.startsWith('CD')) {
      productType = 'COUPLING';
    }

    // 1. Insert into device_registry
    const regRes = await db.query(`
      INSERT INTO device_registry (
        device_id, device_name, serial_number, product_type, device_type,
        hardware_version, firmware_version, health_status, yard_id, updated_at
      ) VALUES ($1, $1, $1, $2, $3, '1.0', '1.0.0', 'ONLINE', $4, CURRENT_TIMESTAMP)
      ON CONFLICT (device_id) DO UPDATE SET
        device_type = EXCLUDED.device_type,
        product_type = EXCLUDED.product_type,
        yard_id = COALESCE(EXCLUDED.yard_id, device_registry.yard_id),
        updated_at = CURRENT_TIMESTAMP
      RETURNING *
    `, [device_code, productType, device_type, targetYardId]);

    const regRow = regRes.rows[0];

    // 2. Insert into devices table with matching UUID
    const newDevice = await db.query(`
      INSERT INTO devices (
        id, device_code, device_type, device_name, serial_number, yard_id, firmware_version, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, '1.0.0', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (id) DO UPDATE SET
        device_code = EXCLUDED.device_code,
        device_type = EXCLUDED.device_type,
        yard_id = EXCLUDED.yard_id,
        updated_at = CURRENT_TIMESTAMP
      ON CONFLICT (device_code) DO UPDATE SET
        device_type = EXCLUDED.device_type,
        yard_id = EXCLUDED.yard_id,
        updated_at = CURRENT_TIMESTAMP
      RETURNING *
    `, [regRow.id, device_code, device_type, device_code, device_code, targetYardId]);

    res.status(201).json(newDevice.rows[0]);
  } catch (error) {
    console.error('Error in registerDevice:', error);
    res.status(500).json({ message: 'Server error registering device' });
  }
};

// @desc    Get all devices (joins device_registry + devices, respects is_disabled)
// @route   GET /api/devices
// @access  Private
const getDevices = async (req, res) => {
  try {
    const { product_type, device_type, status, search, include_disabled } = req.query;

    // Optionally include disabled devices (only for admin view)
    const showDisabled = include_disabled === 'true';

    let query = `
      SELECT 
        COALESCE(d.id, dr.id) as id,
        COALESCE(d.device_code, dr.device_id) as device_code,
        COALESCE(d.device_code, dr.device_id) as device_id,
        COALESCE(
          d.device_type,
          CASE 
            WHEN dr.product_type ILIKE '%RECEIVER%' OR d.device_code ILIKE 'RX%' OR dr.device_id ILIKE 'RX%' OR d.device_code ILIKE 'LD%' OR dr.device_id ILIKE 'LD%' THEN 'Loco Unit'
            WHEN dr.product_type ILIKE '%TRANSMITTER%' OR d.device_code ILIKE 'TX%' OR dr.device_id ILIKE 'TX%' OR d.device_code ILIKE 'DE%' OR dr.device_id ILIKE 'DE%' THEN 'Dead-End'
            WHEN dr.product_type ILIKE '%REPEATER%' OR d.device_code ILIKE 'RP%' OR dr.device_id ILIKE 'RP%' OR d.device_code ILIKE 'PD%' OR dr.device_id ILIKE 'PD%' THEN 'Portable'
            WHEN dr.product_type ILIKE '%COUPLING%' OR d.device_code ILIKE 'CD%' OR dr.device_id ILIKE 'CD%' THEN 'Coupling'
            ELSE 'Loco Unit'
          END
        ) as device_type,
        COALESCE(
          dr.product_type,
          CASE 
            WHEN d.device_code ILIKE 'TX%' OR dr.device_id ILIKE 'TX%' OR d.device_code ILIKE 'DE%' OR dr.device_id ILIKE 'DE%' THEN 'TRANSMITTER'
            WHEN d.device_code ILIKE 'RX%' OR dr.device_id ILIKE 'RX%' OR d.device_code ILIKE 'LD%' OR dr.device_id ILIKE 'LD%' THEN 'RECEIVER'
            WHEN d.device_code ILIKE 'RP%' OR dr.device_id ILIKE 'RP%' OR d.device_code ILIKE 'PD%' OR dr.device_id ILIKE 'PD%' THEN 'REPEATER'
            ELSE 'RECEIVER'
          END
        ) as product_type,
        COALESCE(d.device_name, dr.device_name) as device_name,
        COALESCE(d.serial_number, dr.serial_number) as serial_number,
        COALESCE(d.yard_id, dr.yard_id, yl.yard_id) as yard_id,
        COALESCE(d.assigned_line_id, dr.assigned_line_id) as assigned_line_id,
        COALESCE(d.firmware_version, dr.firmware_version) as firmware_version,
        -- Real battery: from telemetry, then device table, never hardcoded
        CASE 
          WHEN dt.latest_battery IS NOT NULL THEN (dt.latest_battery::text || '%')
          WHEN d.battery_level IS NOT NULL AND d.battery_level != '95%' AND d.battery_level != '90%' THEN d.battery_level
          ELSE NULL
        END as battery_level,
        -- Real status: based on 30-second telemetry rule
        CASE 
          WHEN dt.latest_rec >= (NOW() - INTERVAL '30 SECONDS') THEN 'ONLINE'
          WHEN dr.last_reading_timestamp >= (NOW() - INTERVAL '30 SECONDS') THEN 'ONLINE'
          ELSE 'OFFLINE'
        END as network_status,
        COALESCE(dr.last_reading_timestamp, d.last_heartbeat, dt.latest_rec) as last_heartbeat,
        COALESCE(d.condition_status, 'GOOD') as condition_status,
        d.sim_status,
        yl.line_name,
        yl.line_number,
        y.yard_name,
        COALESCE(dr.is_disabled, FALSE) as is_disabled,
        -- Active assignment info (Holder)
        CASE WHEN active_da.id IS NOT NULL THEN TRUE ELSE FALSE END as is_issued,
        active_da.id as active_assignment_id,
        active_da.employee_id as active_holder_id,
        active_u.full_name as active_holder_name,
        active_u.employee_id as active_holder_employee_id,
        active_da.issued_at as active_issued_at,
        active_da.condition_at_issue as active_condition
      FROM device_registry dr
      LEFT JOIN devices d ON d.device_code = dr.device_id OR d.id = dr.id
      LEFT JOIN (
        SELECT device_id, MAX(recorded_at) as latest_rec, (ARRAY_AGG(battery_level ORDER BY recorded_at DESC))[1] as latest_battery
        FROM device_telemetry
        GROUP BY device_id
      ) dt ON dr.device_id = dt.device_id OR d.device_code = dt.device_id
      LEFT JOIN yard_lines yl ON COALESCE(d.assigned_line_id, dr.assigned_line_id) = yl.id
      LEFT JOIN yards y ON COALESCE(d.yard_id, dr.yard_id, yl.yard_id) = y.id
      LEFT JOIN (
        SELECT DISTINCT ON (device_id) * FROM device_assignments WHERE returned_at IS NULL ORDER BY device_id, issued_at DESC
      ) active_da ON d.id = active_da.device_id OR dr.id = active_da.device_id
      LEFT JOIN users active_u ON active_da.employee_id = active_u.id
      WHERE 1=1
    `;

    if (!showDisabled) {
      query += ` AND (dr.is_disabled IS NULL OR dr.is_disabled = FALSE)`;
    }

    const params = [];

    // Removed role-based filtering per user request to show all devices for all levels

    if (search && search.trim() !== '') {
      params.push(`%${search.trim()}%`);
      const pIdx = params.length;
      query += ` AND (d.device_code ILIKE $${pIdx} OR dr.device_id ILIKE $${pIdx} OR d.device_name ILIKE $${pIdx} OR dr.device_name ILIKE $${pIdx})`;
    }

    query += ' ORDER BY COALESCE(d.created_at, dr.updated_at) DESC';

    const result = await db.query(query, params);
    let rows = result.rows;

    // Apply filters in-memory for product_type and operational status
    if (product_type && product_type !== 'ALL') {
      const targetType = product_type.toUpperCase();
      rows = rows.filter(d => {
        const pType = (d.product_type || '').toUpperCase();
        const dType = (d.device_type || '').toUpperCase();
        const code = (d.device_code || '').toUpperCase();
        if (targetType === 'RECEIVER' || targetType === 'LOCO UNIT') {
          return pType.includes('RECEIVER') || dType.includes('LOCO') || code.startsWith('RX') || code.startsWith('LD');
        } else if (targetType === 'TRANSMITTER' || targetType === 'DEAD-END') {
          return pType.includes('TRANSMITTER') || dType.includes('DEAD') || code.startsWith('TX') || code.startsWith('DE');
        } else if (targetType === 'REPEATER' || targetType === 'PORTABLE') {
          return pType.includes('REPEATER') || dType.includes('PORTABLE') || code.startsWith('RP') || code.startsWith('PD');
        }
        return pType === targetType || dType === targetType;
      });
    }

    if (status) {
      if (status === 'available_for_issue') {
        rows = rows.filter(d => !d.is_issued && !d.is_disabled);
      } else if (status === 'available_for_line') {
        rows = rows.filter(d => !d.assigned_line_id && !d.is_disabled);
      } else if (status === 'issued') {
        rows = rows.filter(d => d.is_issued);
      } else if (status === 'assigned') {
        rows = rows.filter(d => d.assigned_line_id != null);
      }
    }

    res.json(rows);
  } catch (error) {
    console.error('Error in getDevices:', error);
    res.status(500).json({ message: 'Server error fetching devices' });
  }
};

// @desc    Issue a device to an employee (and assign to line)
// @route   POST /api/devices/issue
// @access  Yard Admin / Super Admin
const issueDevice = async (req, res) => {
  try {
    const { device_id, employee_id, condition_at_issue, assigned_line_id } = req.body;

    if (!device_id || !employee_id) {
      return res.status(400).json({ message: 'device_id and employee_id are required' });
    }

    // Ensure device is not disabled
    const devCheck = await db.query(
      `SELECT dr.is_disabled FROM device_registry dr WHERE dr.id::text = $1 OR dr.device_id IN (SELECT device_code FROM devices WHERE id::text = $1)`,
      [device_id]
    );
    if (devCheck.rows[0]?.is_disabled === true) {
      return res.status(400).json({ message: 'Device is disabled and cannot be issued' });
    }

    // Ensure device is not already issued
    const issueCheck = await db.query(
      `SELECT id FROM device_assignments WHERE device_id = $1 AND returned_at IS NULL`,
      [device_id]
    );
    if (issueCheck.rows.length > 0) {
      return res.status(400).json({ message: 'Device is already issued. Please return it first.' });
    }

    // Insert assignment
    const assignment = await db.query(
      'INSERT INTO device_assignments (device_id, employee_id, condition_at_issue) VALUES ($1, $2, $3) RETURNING *',
      [device_id, employee_id, condition_at_issue]
    );

    // Update device status and line assignment
    if (assigned_line_id) {
      await db.query(
        'UPDATE devices SET assigned_line_id = $1 WHERE id = $2',
        [assigned_line_id, device_id]
      );
      await db.query(
        'UPDATE device_registry SET assigned_line_id = $1 WHERE id = $2',
        [assigned_line_id, device_id]
      );
    }

    res.status(201).json(assignment.rows[0]);
  } catch (error) {
    console.error('Error in issueDevice:', error);
    res.status(500).json({ message: 'Server error issuing device' });
  }
};

// @desc    Return a device
// @route   POST /api/devices/return
// @access  Yard Admin / Super Admin
const returnDevice = async (req, res) => {
  try {
    const { assignment_id, condition_at_return, fault_reported, remarks } = req.body;

    if (!assignment_id) {
      return res.status(400).json({ message: 'assignment_id is required' });
    }

    const returned = await db.query(
      `UPDATE device_assignments 
       SET returned_at = CURRENT_TIMESTAMP, condition_at_return = $1, fault_reported = $2, remarks = $3 
       WHERE id = $4 RETURNING *`,
      [condition_at_return, fault_reported, remarks, assignment_id]
    );

    if (returned.rows.length > 0) {
      const deviceId = returned.rows[0].device_id;

      // Get the device_code so we can match it against session fields
      const deviceRes = await db.query(
        'SELECT device_code FROM devices WHERE id = $1',
        [deviceId]
      );
      const deviceCode = deviceRes.rows[0]?.device_code;

      // Close any active LIVE sessions involving this device (REMOVED - no longer related to sessions)
      /*
      if (deviceCode) {
        await db.query(`
          UPDATE shunting_sessions
          SET 
            session_end = NOW(),
            end_time = NOW(),
            session_status = 'COMPLETED',
            status = 'COMPLETED',
            manual_close_reason = 'Device Returned',
            updated_at = NOW()
          WHERE (rx_device_id = $1 OR ld_code = $1 OR tx_device_id = $1 OR de_code = $1)
            AND (status = 'LIVE' OR session_status = 'LIVE')
        `, [deviceCode]);
      }
      */

      // Clear line assignment
      await db.query(
        'UPDATE devices SET assigned_line_id = NULL WHERE id = $1',
        [deviceId]
      );
      await db.query(
        'UPDATE device_registry SET assigned_line_id = NULL WHERE id = $1',
        [deviceId]
      );
    }

    res.json(returned.rows[0]);
  } catch (error) {
    console.error('Error in returnDevice:', error);
    res.status(500).json({ message: 'Server error returning device' });
  }
};

// @desc    Assign device to a line
// @route   PUT /api/devices/:id/assign-line
// @access  Yard Admin / Super Admin
const assignLine = async (req, res) => {
  try {
    const { id } = req.params;
    const { assigned_line_id } = req.body;

    const result = await db.query(
      'UPDATE devices SET assigned_line_id = $1 WHERE id = $2 RETURNING *',
      [assigned_line_id || null, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Device not found' });
    }

    // Also update device_registry - sync yard_id from line's yard if assigning
    if (assigned_line_id) {
      const lineRes = await db.query('SELECT yard_id FROM yard_lines WHERE id = $1', [assigned_line_id]);
      const lineYardId = lineRes.rows[0]?.yard_id;
      await db.query(
        'UPDATE device_registry SET assigned_line_id = $1, yard_id = COALESCE($2, yard_id) WHERE id = $3 OR device_id = $4',
        [assigned_line_id || null, lineYardId || null, id, result.rows[0].device_code]
      );
      if (lineYardId) {
        await db.query(
          'UPDATE devices SET yard_id = $1 WHERE id = $2',
          [lineYardId, id]
        );
      }
    } else {
      await db.query(
        'UPDATE device_registry SET assigned_line_id = NULL WHERE id = $1 OR device_id = $2',
        [id, result.rows[0].device_code]
      );
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error in assignLine:', error);
    res.status(500).json({ message: 'Server error assigning line' });
  }
};

// @desc    Toggle device disabled/enabled
// @route   PUT /api/devices/:id/toggle-disabled
// @access  Super Admin / Hardware Engineer
const toggleDeviceDisabled = async (req, res) => {
  try {
    const { id } = req.params;

    // Find device in registry
    const findRes = await db.query(
      `SELECT dr.id, dr.device_id, COALESCE(dr.is_disabled, FALSE) as is_disabled
       FROM device_registry dr
       WHERE dr.device_id = $1 OR dr.id::text = $1`,
      [id]
    );

    if (findRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Device not found' });
    }

    const device = findRes.rows[0];
    const newState = !device.is_disabled;

    // Ensure column exists first (idempotent migration)
    try {
      await db.query(`ALTER TABLE device_registry ADD COLUMN IF NOT EXISTS is_disabled BOOLEAN DEFAULT FALSE`);
    } catch (_) {}

    await db.query(
      `UPDATE device_registry SET is_disabled = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`,
      [newState, device.id]
    );

    res.json({
      success: true,
      deviceId: device.device_id,
      is_disabled: newState,
      message: `Device ${device.device_id} has been ${newState ? 'disabled' : 'enabled'} successfully`
    });
  } catch (error) {
    console.error('Error in toggleDeviceDisabled:', error);
    res.status(500).json({ success: false, message: 'Server error toggling device state' });
  }
};

// @desc    Get device assignment history (Issue/Return Logs)
// @route   GET /api/devices/assignments
// @access  Yard Admin / Super Admin
const getDeviceAssignments = async (req, res) => {
  try {
    let query = `
      SELECT 
        da.id,
        da.device_id,
        COALESCE(d.device_code, dr.device_id) as device_code,
        COALESCE(d.device_type, dr.product_type) as device_type,
        da.employee_id,
        u.full_name as employee_name,
        u.employee_id as employee_code,
        da.issued_at + interval '5 hours 30 minutes' as issued_at,
        da.returned_at + interval '5 hours 30 minutes' as returned_at,
        da.condition_at_issue,
        da.condition_at_return,
        da.fault_reported,
        da.remarks
      FROM device_assignments da
      LEFT JOIN devices d ON da.device_id = d.id
      LEFT JOIN device_registry dr ON d.device_code = dr.device_id OR d.id = dr.id
      LEFT JOIN users u ON da.employee_id = u.id
      WHERE 1=1
    `;
    
    const params = [];
    const { startDate, endDate, devices } = req.query;

    if (startDate && endDate) {
      params.push(startDate);
      params.push(endDate);
      query += ` AND da.issued_at >= $${params.length - 1} AND da.issued_at <= $${params.length}::timestamp + interval '1 day' - interval '1 second'`;
    }

    if (devices) {
      const deviceList = devices.split(',').map(d => d.trim());
      const placeholders = deviceList.map((_, i) => `$${params.length + i + 1}`).join(',');
      query += ` AND COALESCE(d.device_code, dr.device_id) IN (${placeholders})`;
      params.push(...deviceList);
    }
    
    // Removed role-based filtering per user request to show all device assignments for all levels

    query += ' ORDER BY da.issued_at DESC LIMIT 500';

    const result = await db.query(query, params);
    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error('Error fetching device assignments:', error);
    res.status(500).json({ success: false, message: 'Server error fetching assignments' });
  }
};

module.exports = {
  registerDevice,
  getDevices,
  issueDevice,
  returnDevice,
  assignLine,
  toggleDeviceDisabled,
  getDeviceAssignments
};
