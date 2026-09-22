const db = require('../config/db');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'safeshunt_default_secret_key_change_me';

// Map designation strings to role codes
const designationToRole = {
  'Super Administrator': 'super_admin',
  'Yard Administrator': 'yard_admin',
  'Maintenance User': 'maintenance_user',
  'Hardware Engineer': 'hardware_engineer',
  'Viewer / Control Room User': 'viewer',
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

exports.register = async (req, res) => {
  const { fullName, employeeId, email, designation, password } = req.body;

  try {
    // 1. Check if user already exists
    const userExists = await db.query('SELECT * FROM users WHERE employee_id = $1', [employeeId]);
    if (userExists.rows.length > 0) {
      return res.status(400).json({ message: 'User with this Employee ID already exists' });
    }

    // 2. Derive role from designation
    const role = designationToRole[designation] || 'viewer';

    // Check if this is the first user in the system
    const userCountResult = await db.query('SELECT COUNT(*) FROM users');
    const isFirstUser = parseInt(userCountResult.rows[0].count) === 0;
    const isActive = isFirstUser; // Only the first user is active automatically

    // 3. Hash password
    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);

    // 4. Insert user into DB (now with role)
    const newUser = await db.query(
      'INSERT INTO users (full_name, employee_id, email, designation, password_hash, role, is_active) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id, full_name, employee_id, email, designation, role',
      [fullName, employeeId, email, designation, passwordHash, role, isActive]
    );

    const user = newUser.rows[0];

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
        assignedYards: [], // New user has no yards assigned yet
      },
      token: isActive ? generateToken(user.id, user.employee_id, user.role) : null
    });

  } catch (error) {
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

    // 4. Fetch assigned yards (for yard_admin and all roles for context)
    const assignedYards = await getAssignedYards(user.id);

    // 5. Return user data and token
    res.status(200).json({
      message: 'Login successful',
      user: {
        id: user.id,
        fullName: user.full_name,
        employeeId: user.employee_id,
        email: user.email,
        designation: user.designation,
        role: user.role || 'viewer',
        profile_pic_url: user.profile_pic_url,
        assignedYards: assignedYards,
      },
      token: generateToken(user.id, user.employee_id, user.role || 'viewer')
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

// GET /api/auth/users - List all users (Super Admin only)
exports.listUsers = async (req, res) => {
  try {
    const result = await db.query(
      `SELECT id, full_name, employee_id, email, designation, role, is_active, created_at, profile_pic_url
       FROM users ORDER BY created_at DESC`
    );

    // For each user, fetch their assigned yards
    const users = await Promise.all(result.rows.map(async (user) => {
      const yards = await getAssignedYards(user.id);
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
      };
    }));

    res.status(200).json({ users });
  } catch (error) {
    console.error('Error in listUsers:', error);
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
