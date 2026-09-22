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

    const newYard = await db.query(
      'INSERT INTO yards (yard_name, location, status) VALUES ($1, $2, $3) RETURNING *',
      [yard_name, location, 'Active']
    );

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

    if (req.user.role === 'yard_admin') {
      yards = await db.query(`
        SELECT y.* FROM yards y
        JOIN user_yard_assignments uya ON y.id = uya.yard_id
        WHERE uya.user_id = $1
        ORDER BY y.created_at DESC
      `, [req.user.id]);
      
      lines = await db.query(`
        SELECT yl.*, COALESCE(dr.device_id, d.device_code) as assigned_de 
        FROM yard_lines yl 
        LEFT JOIN device_registry dr ON dr.assigned_line_id = yl.id AND (dr.product_type ILIKE '%TRANSMITTER%' OR dr.device_id ILIKE 'TX%' OR dr.device_id ILIKE 'DE%')
        LEFT JOIN devices d ON d.assigned_line_id = yl.id
        JOIN user_yard_assignments uya ON yl.yard_id = uya.yard_id
        WHERE uya.user_id = $1
        ORDER BY yl.created_at DESC
      `, [req.user.id]);
    } else {
      yards = await db.query('SELECT * FROM yards ORDER BY created_at DESC');
      lines = await db.query(`
        SELECT yl.*, COALESCE(dr.device_id, d.device_code) as assigned_de 
        FROM yard_lines yl 
        LEFT JOIN device_registry dr ON dr.assigned_line_id = yl.id AND (dr.product_type ILIKE '%TRANSMITTER%' OR dr.device_id ILIKE 'TX%' OR dr.device_id ILIKE 'DE%')
        LEFT JOIN devices d ON d.assigned_line_id = yl.id
        ORDER BY yl.created_at DESC
      `);
    }
    
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
      'INSERT INTO yard_lines (yard_id, line_code, line_name, line_type, status) VALUES ($1, $2, $3, $4, $5) RETURNING *',
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

module.exports = {
  createYard,
  getYards,
  addYardLine,
  getYardLines,
  assignYardToUser,
  removeYardAssignment
};
