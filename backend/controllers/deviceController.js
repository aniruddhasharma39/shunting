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

// @desc    Get all devices
// @route   GET /api/devices
// @access  Private
const getDevices = async (req, res) => {
  try {
    const { product_type, device_type, status, search } = req.query;

    let query = `
      SELECT 
        d.id,
        d.device_code,
        COALESCE(
          d.device_type,
          CASE 
            WHEN dr.product_type ILIKE '%RECEIVER%' OR d.device_code ILIKE 'RX%' OR d.device_code ILIKE 'LD%' THEN 'Loco Unit'
            WHEN dr.product_type ILIKE '%TRANSMITTER%' OR d.device_code ILIKE 'TX%' OR d.device_code ILIKE 'DE%' THEN 'Dead-End'
            WHEN dr.product_type ILIKE '%REPEATER%' OR d.device_code ILIKE 'RP%' OR d.device_code ILIKE 'PD%' THEN 'Portable'
            WHEN dr.product_type ILIKE '%COUPLING%' OR d.device_code ILIKE 'CD%' THEN 'Coupling'
            ELSE 'Loco Unit'
          END
        ) as device_type,
        COALESCE(
          dr.product_type,
          CASE 
            WHEN d.device_code ILIKE 'TX%' OR d.device_code ILIKE 'DE%' THEN 'TRANSMITTER'
            WHEN d.device_code ILIKE 'RX%' OR d.device_code ILIKE 'LD%' THEN 'RECEIVER'
            WHEN d.device_code ILIKE 'RP%' OR d.device_code ILIKE 'PD%' THEN 'REPEATER'
            ELSE 'RECEIVER'
          END
        ) as product_type,
        d.device_name,
        d.serial_number,
        COALESCE(d.yard_id, dr.yard_id, yl.yard_id) as yard_id,
        COALESCE(d.assigned_line_id, dr.assigned_line_id) as assigned_line_id,
        d.firmware_version,
        COALESCE(d.battery_level, (dt.latest_battery::text || '%'), '95%') as battery_level,
        COALESCE(d.network_status, CASE WHEN dt.latest_rec >= (NOW() - INTERVAL '30 SECONDS') THEN 'Online' ELSE 'Offline' END) as network_status,
        COALESCE(d.last_heartbeat, dt.latest_rec) as last_heartbeat,
        d.condition_status,
        d.sim_status,
        yl.line_name,
        yl.line_number,
        y.yard_name,
        -- Active assignment info (Holder)
        CASE WHEN active_da.id IS NOT NULL THEN TRUE ELSE FALSE END as is_issued,
        active_da.id as active_assignment_id,
        active_da.employee_id as active_holder_id,
        active_u.full_name as active_holder_name,
        active_u.employee_id as active_holder_employee_id,
        active_da.issued_at as active_issued_at,
        active_da.condition_at_issue as active_condition
      FROM devices d
      LEFT JOIN device_registry dr ON d.device_code = dr.device_id OR d.id = dr.id
      LEFT JOIN (
        SELECT device_id, MAX(recorded_at) as latest_rec, (ARRAY_AGG(battery_level ORDER BY recorded_at DESC))[1] as latest_battery
        FROM device_telemetry
        GROUP BY device_id
      ) dt ON d.device_code = dt.device_id
      LEFT JOIN yard_lines yl ON COALESCE(d.assigned_line_id, dr.assigned_line_id) = yl.id
      LEFT JOIN yards y ON COALESCE(d.yard_id, dr.yard_id, yl.yard_id) = y.id
      LEFT JOIN (
        SELECT * FROM device_assignments WHERE returned_at IS NULL
      ) active_da ON d.id = active_da.device_id
      LEFT JOIN users active_u ON active_da.employee_id = active_u.id
      WHERE 1=1
    `;

    const params = [];

    if (req.user && req.user.role === 'yard_admin') {
      params.push(req.user.id);
      query += ` AND (COALESCE(d.yard_id, dr.yard_id, yl.yard_id) IN (SELECT yard_id FROM user_yard_assignments WHERE user_id = $${params.length}) OR COALESCE(d.yard_id, dr.yard_id, yl.yard_id) IS NULL)`;
    }

    if (search && search.trim() !== '') {
      params.push(`%${search.trim()}%`);
      const pIdx = params.length;
      query += ` AND (d.device_code ILIKE $${pIdx} OR d.device_name ILIKE $${pIdx} OR d.serial_number ILIKE $${pIdx})`;
    }

    query += ' ORDER BY d.created_at DESC';

    const result = await db.query(query, params);
    let rows = result.rows;

    // Apply filters in-memory for product_type and operational status
    if (product_type && product_type !== 'ALL') {
      const targetType = product_type.toUpperCase();
      rows = rows.filter(d => {
        const pType = (d.product_type || '').toUpperCase();
        const dType = (d.device_type || '').toUpperCase();
        if (targetType === 'RECEIVER' || targetType === 'LOCO UNIT') {
          return pType.includes('RECEIVER') || dType.includes('LOCO') || d.device_code.startsWith('RX') || d.device_code.startsWith('LD');
        } else if (targetType === 'TRANSMITTER' || targetType === 'DEAD-END') {
          return pType.includes('TRANSMITTER') || dType.includes('DEAD') || d.device_code.startsWith('TX') || d.device_code.startsWith('DE');
        } else if (targetType === 'REPEATER' || targetType === 'PORTABLE') {
          return pType.includes('REPEATER') || dType.includes('PORTABLE') || d.device_code.startsWith('RP') || d.device_code.startsWith('PD');
        }
        return pType === targetType || dType === targetType;
      });
    }

    if (status) {
      if (status === 'available_for_issue') {
        // Receivers not currently issued
        rows = rows.filter(d => !d.is_issued);
      } else if (status === 'available_for_line') {
        // Transmitters not currently assigned to a line
        rows = rows.filter(d => !d.assigned_line_id);
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
      // Clear line assignment
      await db.query(
        'UPDATE devices SET assigned_line_id = NULL WHERE id = $1',
        [returned.rows[0].device_id]
      );
      await db.query(
        'UPDATE device_registry SET assigned_line_id = NULL WHERE id = $1',
        [returned.rows[0].device_id]
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

    // Also update device_registry
    await db.query(
      'UPDATE device_registry SET assigned_line_id = $1 WHERE id = $2 OR device_id = $3',
      [assigned_line_id || null, id, result.rows[0].device_code]
    );

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error in assignLine:', error);
    res.status(500).json({ message: 'Server error assigning line' });
  }
};

module.exports = {
  registerDevice,
  getDevices,
  issueDevice,
  returnDevice,
  assignLine
};
