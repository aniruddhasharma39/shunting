const db = require('../config/db');

// @desc    Create a new yard
// @route   POST /api/yards
// @access  Super Admin
const createYard = async (req, res) => {
  try {
    const { yard_name, location } = req.body;
    if (!yard_name) {
      return res.status(400).json({ message: 'Yard name is required' });
    }

    const yard_code = 'YRD-' + Math.floor(Math.random() * 10000);
    
    // Removed role-based yard zone/division automatic assignment per user request

    const newYard = await db.query(
      'INSERT INTO yards (yard_code, yard_name, station, division, zone, yard_type, status) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *',
      [yard_code, yard_name, location || 'Unknown', 'N/A', 'N/A', 'Mixed', 'Active']
    );

    // If a zone or division admin creates it, let's automatically assign them to it as well, or just let them see it based on the zone filter.
    // The getYards filter uses y.zone for zone_admin, so they will see it automatically.

    res.status(201).json(newYard.rows[0]);
  } catch (error) {
    console.error('Error in createYard:', error);
    res.status(500).json({ message: 'Server error creating yard' });
  }
};

// @desc    Get all yards
// @route   GET /api/yards
// @access  Super Admin / Yard Admin (filtered)
const getYards = async (req, res) => {
  try {
    let yards;
    let lines;

    let yardConditions = [];
    let yardParams = [];
    const user = req.user;

    // Removed role-based filtering per user request to show all yards

    let yardWhere = yardConditions.length > 0 ? 'WHERE ' + yardConditions.join(' AND ') : '';
    
    yards = await db.query(`SELECT y.* FROM yards y ${yardWhere} ORDER BY y.created_at DESC`, yardParams);
    
    // For lines, filter by the same yards
    let lineWhere = yardConditions.length > 0 ? 'WHERE yl.yard_id IN (SELECT id FROM yards y ' + yardWhere + ')' : '';
    
    lines = await db.query(`
      SELECT yl.*, COALESCE(d.device_code, dr.device_id) as assigned_de, COALESCE(d.id, dr.id) as assigned_device_id 
      FROM yard_lines yl 
      LEFT JOIN devices d ON d.assigned_line_id = yl.id AND (d.device_type = 'Dead-End' OR d.device_code ILIKE 'TX%' OR d.device_code ILIKE 'DE%')
      LEFT JOIN device_registry dr ON dr.assigned_line_id = yl.id AND (dr.product_type ILIKE '%TRANSMITTER%' OR dr.device_id ILIKE 'TX%' OR dr.device_id ILIKE 'DE%')
      ${lineWhere}
      ORDER BY yl.created_at DESC
    `, yardParams);
    
    // Group lines by yard
    const mappedYards = yards.rows.map(y => {
        return {
            ...y,
            lines: lines.rows.filter(l => l.yard_id === y.id)
        };
    });

    res.json(mappedYards);
  } catch (error) {
    console.error('Error in getYards:', error);
    res.status(500).json({ message: 'Server error fetching yards' });
  }
};

// @desc    Create a new line for a yard
// @route   POST /api/yards/:yardId/lines
// @access  Super Admin
const addYardLine = async (req, res) => {
  try {
    const { yardId } = req.params;
    const { line_code, line_name, line_type } = req.body;

    if (!line_code || !line_name || !line_type) {
      return res.status(400).json({ message: 'Line code, name, and type are required' });
    }

    const newLine = await db.query(
      'INSERT INTO yard_lines (yard_id, line_number, line_name, line_type, status) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [yardId, line_code, line_name, line_type, 'Active']
    );

    res.status(201).json(newLine.rows[0]);
  } catch (error) {
    console.error('Error in addYardLine:', error);
    res.status(500).json({ message: 'Server error creating yard line' });
  }
};

// @desc    Get lines for a specific yard
// @route   GET /api/yards/:yardId/lines
// @access  Private
const getYardLines = async (req, res) => {
  try {
    const { yardId } = req.params;
    const lines = await db.query('SELECT * FROM yard_lines WHERE yard_id = $1 ORDER BY created_at DESC', [yardId]);
    res.json(lines.rows);
  } catch (error) {
    console.error('Error in getYardLines:', error);
    res.status(500).json({ message: 'Server error fetching yard lines' });
  }
};

// @desc    Assign a yard to a user
// @route   POST /api/yards/assign
// @access  Super Admin
const assignYardToUser = async (req, res) => {
  try {
    const { userId, yardId } = req.body;
    if (!userId || !yardId) {
      return res.status(400).json({ message: 'User ID and Yard ID are required' });
    }
    await db.query(
      'INSERT INTO user_yard_assignments (user_id, yard_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [userId, yardId]
    );
    res.status(201).json({ message: 'Yard assigned successfully' });
  } catch (error) {
    console.error('Error assigning yard:', error);
    res.status(500).json({ message: 'Server error assigning yard' });
  }
};

// @desc    Remove yard assignment from a user
// @route   DELETE /api/yards/assign
// @access  Super Admin
const removeYardAssignment = async (req, res) => {
  try {
    const { userId, yardId } = req.body;
    if (!userId || !yardId) {
      return res.status(400).json({ message: 'User ID and Yard ID are required' });
    }
    await db.query(
      'DELETE FROM user_yard_assignments WHERE user_id = $1 AND yard_id = $2',
      [userId, yardId]
    );
    res.status(200).json({ message: 'Yard assignment removed successfully' });
  } catch (error) {
    console.error('Error removing yard assignment:', error);
    res.status(500).json({ message: 'Server error removing assignment' });
  }
};

// @desc    Delete a yard (cascades to lines)
// @route   DELETE /api/yards/:yardId
// @access  Super Admin
const deleteYard = async (req, res) => {
  try {
    const { yardId } = req.params;

    // Check if any devices are assigned to this yard
    const devicesResult = await db.query('SELECT COUNT(*) FROM devices WHERE yard_id = $1', [yardId]);
    if (parseInt(devicesResult.rows[0].count) > 0) {
      return res.status(400).json({ message: 'Cannot delete yard because there are devices assigned to it.' });
    }

    // Begin transaction to ensure atomic deletion
    await db.query('BEGIN');
    
    // Delete assignments first
    await db.query('DELETE FROM user_yard_assignments WHERE yard_id = $1', [yardId]);
    
    // Delete lines next
    await db.query('DELETE FROM yard_lines WHERE yard_id = $1', [yardId]);
    
    // Delete the yard
    const yardResult = await db.query('DELETE FROM yards WHERE id = $1 RETURNING id', [yardId]);
    
    if (yardResult.rows.length === 0) {
      await db.query('ROLLBACK');
      return res.status(404).json({ message: 'Yard not found' });
    }

    await db.query('COMMIT');
    res.status(200).json({ message: 'Yard deleted successfully' });
  } catch (error) {
    await db.query('ROLLBACK');
    console.error('Error deleting yard:', error);
    res.status(500).json({ message: 'Server error deleting yard' });
  }
};

// @desc    Delete a yard line
// @route   DELETE /api/yards/:yardId/lines/:lineId
// @access  Super Admin
const deleteYardLine = async (req, res) => {
  try {
    const { lineId } = req.params;

    // Check if any devices are assigned to this line
    const devicesResult = await db.query('SELECT COUNT(*) FROM devices WHERE current_line_id = $1', [lineId]);
    if (parseInt(devicesResult.rows[0].count) > 0) {
      return res.status(400).json({ message: 'Cannot delete line because there are devices assigned to it.' });
    }

    await db.query('DELETE FROM yard_lines WHERE id = $1', [lineId]);
    res.status(200).json({ message: 'Yard line deleted successfully' });
  } catch (error) {
    console.error('Error deleting yard line:', error);
    if (error.code === '23503') { // Foreign key constraint violation
      return res.status(400).json({ message: 'Cannot delete line because it is currently in use.' });
    }
    res.status(500).json({ message: 'Server error deleting yard line' });
  }
};

module.exports = {
  createYard,
  getYards,
  addYardLine,
  getYardLines,
  assignYardToUser,
  removeYardAssignment,
  deleteYard,
  deleteYardLine
};
