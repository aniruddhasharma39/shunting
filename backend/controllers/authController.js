const db = require('../config/db');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'safeshunt_default_secret_key_change_me';

// Map designation strings to role codes
const designationToRole = {
  'Super Administrator': 'super_admin',
  'Zone Administrator': 'zone_admin',
  'Division Administrator': 'division_admin',
  'Yard Administrator': 'yard_admin',
  'Shunting Supervisor': 'supervisor',
  'Shunter': 'shunter',
};

// Helper for generating JWT token (now includes role)
const generateToken = (userId, employeeId, role) => {
  return jwt.sign(
    { id: userId, employeeId, role }, 
    JWT_SECRET, 
    { expiresIn: '30d' }
  );
};

const getAssignedYards = async (userId) => {
  const result = await db.query(
    `SELECT y.id, y.yard_name, y.station AS location, y.status
     FROM user_yard_assignments uya
     JOIN yards y ON uya.yard_id = y.id
     WHERE uya.user_id = $1 AND y.status = 'Active'`,
    [userId]
  );
  return result.rows;
};

const getAssignedZones = async (userId) => {
  const result = await db.query(
    `SELECT zone_name FROM user_zone_assignments WHERE user_id = $1`,
    [userId]
  );
  return result.rows.map(row => row.zone_name);
};

const getAssignedDivisions = async (userId) => {
  const result = await db.query(
    `SELECT division_name FROM user_division_assignments WHERE user_id = $1`,
    [userId]
  );
  return result.rows.map(row => row.division_name);
};

exports.register = async (req, res) => {
  const { fullName, employeeId, email, designation, password, assignedYards, assignedZones, assignedDivisions } = req.body;

  try {
    // 1. Check if user already exists
    const userExists = await db.query('SELECT * FROM users WHERE employee_id = $1', [employeeId]);
    if (userExists.rows.length > 0) {
      return res.status(400).json({ message: 'User with this Employee ID already exists' });
    }

    // 2. Derive role from designation
    const role = designationToRole[designation] || 'shunter';

    // Check if this is the first user in the system
    const userCountResult = await db.query('SELECT COUNT(*) FROM users');
    const isFirstUser = parseInt(userCountResult.rows[0].count) === 0;
    let isActive = isFirstUser; // Only the first user is active automatically

    if (req.body.isAdminCreatingUser) {
      const authHeader = req.headers.authorization;
      if (authHeader && authHeader.startsWith('Bearer ')) {
        const token = authHeader.split(' ')[1];
        try {
          const decoded = jwt.verify(token, JWT_SECRET);
          if (decoded.role === 'super_admin' || decoded.role === 'zone_admin' || decoded.role === 'division_admin' || decoded.role === 'yard_admin') {
            isActive = true;
          }
        } catch (err) {
          console.warn('Admin creation token verification failed', err);
        }
      }
    }

    // 3. Hash password
    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);

    // Start transaction for user creation and assignments
    await db.query('BEGIN');

    // 4. Insert user into DB
    const newUser = await db.query(
      'INSERT INTO users (full_name, employee_id, email, designation, password_hash, role, is_active) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id, full_name, employee_id, email, designation, role',
      [fullName, employeeId, email, designation, passwordHash, role, isActive]
    );

    const user = newUser.rows[0];

    // Assign Yards
    if (assignedYards && Array.isArray(assignedYards)) {
      for (const yardId of assignedYards) {
        await db.query('INSERT INTO user_yard_assignments (user_id, yard_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [user.id, yardId]);
      }
    }
    // Assign Zones
    if (assignedZones && Array.isArray(assignedZones)) {
      for (const zoneName of assignedZones) {
        await db.query('INSERT INTO user_zone_assignments (user_id, zone_name) VALUES ($1, $2) ON CONFLICT DO NOTHING', [user.id, zoneName]);
      }
    }
    // Assign Divisions
    if (assignedDivisions && Array.isArray(assignedDivisions)) {
      for (const divisionName of assignedDivisions) {
        await db.query('INSERT INTO user_division_assignments (user_id, division_name) VALUES ($1, $2) ON CONFLICT DO NOTHING', [user.id, divisionName]);
      }
      // Also link division admin to their parent zone (from request body)
      // This enables the hierarchy tree to correctly place them under their Zone Admin
      if (role === 'division_admin' && req.body.parentZone) {
        await db.query('INSERT INTO user_zone_assignments (user_id, zone_name) VALUES ($1, $2) ON CONFLICT DO NOTHING', [user.id, req.body.parentZone]);
      }
    }

    await db.query('COMMIT');

    const createdAssignedYards = await getAssignedYards(user.id);
    const createdAssignedZones = await getAssignedZones(user.id);
    const createdAssignedDivisions = await getAssignedDivisions(user.id);

    // 5. Return success and token (if active)
    res.status(201).json({
      message: isActive ? 'User registered successfully' : 'Registration successful! Please wait for admin approval.',
      user: {
        id: user.id,
        fullName: user.full_name,
        employeeId: user.employee_id,
        email: user.email,
        designation: user.designation,
        role: user.role,
        assignedYards: createdAssignedYards,
        assignedZones: createdAssignedZones,
        assignedDivisions: createdAssignedDivisions,
      },
      token: isActive ? generateToken(user.id, user.employee_id, user.role) : null
    });

  } catch (error) {
    await db.query('ROLLBACK');
    console.error('Error in register:', error);
    res.status(500).json({ message: 'Server error during registration' });
  }
};

exports.login = async (req, res) => {
  const { loginId, password } = req.body;

  try {
    // 1. Find user by employee ID or Email
    const userResult = await db.query('SELECT * FROM users WHERE employee_id = $1 OR email = $1', [loginId]);
    
    if (userResult.rows.length === 0) {
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    const user = userResult.rows[0];

    // 2. Check if user is active
    if (user.is_active === false) {
      return res.status(403).json({ message: 'Account is pending approval or deactivated. Contact administrator.' });
    }

    // 3. Verify password
    const isMatch = await bcrypt.compare(password, user.password_hash);
    if (!isMatch) {
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    // 4. Fetch assigned yards, zones, divisions
    const assignedYards = await getAssignedYards(user.id);
    const assignedZones = await getAssignedZones(user.id);
    const assignedDivisions = await getAssignedDivisions(user.id);

    // 5. Return user data and token
    res.status(200).json({
      message: 'Login successful',
      user: {
        id: user.id,
        fullName: user.full_name,
        employeeId: user.employee_id,
        email: user.email,
        designation: user.designation,
        role: user.role || 'shunter',
        profile_pic_url: user.profile_pic_url,
        assignedYards: assignedYards,
        assignedZones: assignedZones,
        assignedDivisions: assignedDivisions,
      },
      token: generateToken(user.id, user.employee_id, user.role || 'shunter')
    });

  } catch (error) {
    console.error('Error in login:', error);
    res.status(500).json({ message: 'Server error during login' });
  }
};

// GET /api/auth/me - Get current user profile with role and assigned yards
exports.getMe = async (req, res) => {
  try {
    const userResult = await db.query('SELECT * FROM users WHERE id = $1', [req.user.id]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }
    const user = userResult.rows[0];
    const assignedYards = await getAssignedYards(req.user.id);
    const assignedZones = await getAssignedZones(req.user.id);
    const assignedDivisions = await getAssignedDivisions(req.user.id);

    res.status(200).json({
      user: {
        id: user.id,
        fullName: user.full_name,
        employeeId: user.employee_id,
        email: user.email,
        designation: user.designation,
        role: user.role,
        profile_pic_url: user.profile_pic_url,
        assignedYards: assignedYards,
        assignedZones: assignedZones,
        assignedDivisions: assignedDivisions,
      },
    });
  } catch (error) {
    console.error('Error in getMe:', error);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.uploadProfilePicture = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'No image file provided' });
    }
    const userId = req.user.id;
    // Ensure cross-platform path formatting (e.g. uploads/filename.jpg)
    const filePath = '/' + req.file.path.replace(/\\/g, '/');

    await db.query('UPDATE users SET profile_pic_url = $1 WHERE id = $2', [filePath, userId]);

    res.json({ 
      message: 'Profile picture updated successfully', 
      profile_pic_url: filePath 
    });
  } catch (err) {
    console.error('Error uploading profile picture:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.deleteProfilePicture = async (req, res) => {
  try {
    const userId = req.user.id;
    await db.query('UPDATE users SET profile_pic_url = NULL WHERE id = $1', [userId]);

    res.json({ message: 'Profile picture deleted successfully' });
  } catch (err) {
    console.error('Error deleting profile picture:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /api/auth/users - List all users
exports.listUsers = async (req, res) => {
  try {
    let query = `SELECT id, full_name, employee_id, email, designation, role, is_active, created_at, profile_pic_url FROM users`;
    let params = [];
    
    if (req.user.role === 'yard_admin') {
      query += ` WHERE role IN ('supervisor', 'shunter')`;
    }
    
    query += ` ORDER BY created_at ASC`;
    
    const result = await db.query(query, params);

    // For each user, fetch their assigned yards, zones, divisions
    const users = await Promise.all(result.rows.map(async (user) => {
      const yards = await getAssignedYards(user.id);
      const zones = await getAssignedZones(user.id);
      const divisions = await getAssignedDivisions(user.id);
      return {
        id: user.id,
        fullName: user.full_name,
        employeeId: user.employee_id,
        email: user.email,
        designation: user.designation,
        role: user.role,
        isActive: user.is_active,
        createdAt: user.created_at,
        profile_pic_url: user.profile_pic_url,
        assignedYards: yards,
        assignedZones: zones,
        assignedDivisions: divisions,
      };
    }));

    res.status(200).json({ users });
  } catch (error) {
    console.error('Error in listUsers:', error);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /api/auth/zones - List all distinct zones
exports.listZones = async (req, res) => {
  try {
    const result = await db.query(`
      SELECT DISTINCT zone_name FROM user_zone_assignments
      INNER JOIN users ON users.id = user_zone_assignments.user_id
      WHERE users.role = 'zone_admin'
      ORDER BY zone_name
    `);
    res.json({ zones: result.rows.map(r => r.zone_name) });
  } catch (error) {
    console.error('Error in listZones:', error);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /api/auth/divisions - List all distinct divisions
exports.listDivisions = async (req, res) => {
  try {
    const result = await db.query(`
      SELECT DISTINCT division_name FROM user_division_assignments
      INNER JOIN users ON users.id = user_division_assignments.user_id
      WHERE users.role = 'division_admin'
      ORDER BY division_name
    `);
    res.json({ divisions: result.rows.map(r => r.division_name) });
  } catch (error) {
    console.error('Error in listDivisions:', error);
    res.status(500).json({ message: 'Server error' });
  }
};

// DELETE /api/auth/users/:id/zone/:zoneName - Remove zone assignment
exports.removeZoneAssignment = async (req, res) => {
  try {
    const { id, zoneName } = req.params;
    await db.query('DELETE FROM user_zone_assignments WHERE user_id = $1 AND zone_name = $2', [id, decodeURIComponent(zoneName)]);
    res.json({ message: 'Zone assignment removed.' });
  } catch (error) {
    console.error('Error in removeZoneAssignment:', error);
    res.status(500).json({ message: 'Server error' });
  }
};

// DELETE /api/auth/users/:id/division/:divisionName - Remove division assignment
exports.removeDivisionAssignment = async (req, res) => {
  try {
    const { id, divisionName } = req.params;
    await db.query('DELETE FROM user_division_assignments WHERE user_id = $1 AND division_name = $2', [id, decodeURIComponent(divisionName)]);
    res.json({ message: 'Division assignment removed.' });
  } catch (error) {
    console.error('Error in removeDivisionAssignment:', error);
    res.status(500).json({ message: 'Server error' });
  }
};

// PUT /api/auth/users/:id/toggle-active - Activate/deactivate user (Super Admin only)
exports.toggleUserActive = async (req, res) => {
  try {
    const { id } = req.params;

    // Prevent deactivating yourself
    if (id === req.user.id) {
      return res.status(400).json({ message: 'You cannot deactivate your own account.' });
    }

    // Role Hierarchy check for yard_admin
    if (req.user.role === 'yard_admin') {
      const targetUserCheck = await db.query('SELECT role FROM users WHERE id = $1', [id]);
      if (targetUserCheck.rows.length === 0) return res.status(404).json({ message: 'User not found' });
      if (!['supervisor', 'shunter'].includes(targetUserCheck.rows[0].role)) {
        return res.status(403).json({ message: 'Forbidden: You do not have permission to manage this user role.' });
      }
    }

    // Role Hierarchy check for zone_admin
    if (req.user.role === 'zone_admin') {
      const targetUserCheck = await db.query('SELECT role FROM users WHERE id = $1', [id]);
      if (targetUserCheck.rows.length === 0) return res.status(404).json({ message: 'User not found' });
      if (['super_admin', 'zone_admin'].includes(targetUserCheck.rows[0].role)) {
        return res.status(403).json({ message: 'Forbidden: You do not have permission to manage this user role.' });
      }
    }

    const result = await db.query(
      'UPDATE users SET is_active = NOT is_active WHERE id = $1 RETURNING id, full_name, is_active',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found.' });
    }

    const user = result.rows[0];
    res.status(200).json({
      message: `User ${user.full_name} is now ${user.is_active ? 'active' : 'deactivated'}.`,
      isActive: user.is_active,
    });
  } catch (error) {
    console.error('Error in toggleUserActive:', error);
    res.status(500).json({ message: 'Server error' });
  }
};

// DELETE /api/auth/users/:id - Delete user completely (Super Admin only)
exports.deleteUser = async (req, res) => {
  try {
    const { id } = req.params;

    // Prevent deleting yourself
    if (id === req.user.id) {
      return res.status(400).json({ message: 'You cannot delete your own account.' });
    }

    // Role Hierarchy check for yard_admin
    if (req.user.role === 'yard_admin') {
      const targetUserCheck = await db.query('SELECT role FROM users WHERE id = $1', [id]);
      if (targetUserCheck.rows.length === 0) return res.status(404).json({ message: 'User not found' });
      if (!['supervisor', 'shunter'].includes(targetUserCheck.rows[0].role)) {
        return res.status(403).json({ message: 'Forbidden: You do not have permission to manage this user role.' });
      }
    }

    // Role Hierarchy check for zone_admin
    if (req.user.role === 'zone_admin') {
      const targetUserCheck = await db.query('SELECT role FROM users WHERE id = $1', [id]);
      if (targetUserCheck.rows.length === 0) return res.status(404).json({ message: 'User not found' });
      if (['super_admin', 'zone_admin'].includes(targetUserCheck.rows[0].role)) {
        return res.status(403).json({ message: 'Forbidden: You do not have permission to manage this user role.' });
      }
    }

    const result = await db.query(
      'DELETE FROM users WHERE id = $1 RETURNING id',
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found.' });
    }

    res.status(200).json({ message: 'User deleted successfully.' });
  } catch (error) {
    console.error('Error in deleteUser:', error);
    if (error.code === '23503') { // Foreign key violation
      res.status(400).json({ message: 'Cannot delete user because they are associated with existing records (e.g., assignments or sessions).' });
    } else {
      res.status(500).json({ message: 'Server error' });
    }
  }
};
