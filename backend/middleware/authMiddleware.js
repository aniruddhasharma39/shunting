const jwt = require('jsonwebtoken');
const db = require('../config/db');

const JWT_SECRET = process.env.JWT_SECRET || 'safeshunt_default_secret_key_change_me';

// In-memory token cache: { token -> { user, expiry } }
// Eliminates a DB lookup on every authenticated API request.
// Cache TTL is 5 minutes — user changes (deactivation, role change) reflect within 5 minutes.
const _tokenCache = new Map();
const TOKEN_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

// Middleware: Verify JWT token and attach user to request
const verifyToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Access denied. No token provided.' });
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, JWT_SECRET);

    // Validate that decoded.id is a valid UUID before querying DB
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(decoded.id)) {
      return res.status(401).json({ message: 'Invalid or legacy token. Please login again.' });
    }

    // --- Cache check: skip DB if we have a fresh cached user ---
    const cached = _tokenCache.get(token);
    if (cached && cached.expiry > Date.now()) {
      req.user = cached.user;
      return next();
    }

    // Fetch user from DB to ensure they still exist and are active
    const userResult = await db.query(
      'SELECT id, full_name, employee_id, email, designation, role, is_active FROM users WHERE id = $1',
      [decoded.id]
    );

    if (userResult.rows.length === 0) {
      return res.status(401).json({ message: 'User not found.' });
    }

    const user = userResult.rows[0];

    if (!user.is_active) {
      return res.status(403).json({ message: 'Account is deactivated. Contact administrator.' });
    }

    // Attach user info to request
    req.user = {
      id: user.id,
      fullName: user.full_name,
      employeeId: user.employee_id,
      email: user.email,
      designation: user.designation,
      role: user.role,
    };

    // If yard_admin or supervisor or shunter, also fetch assigned yard IDs
    if (['yard_admin', 'supervisor', 'shunter'].includes(user.role)) {
      const yardResult = await db.query(
        'SELECT yard_id FROM user_yard_assignments WHERE user_id = $1',
        [user.id]
      );
      req.user.assignedYardIds = yardResult.rows.map(r => r.yard_id);
    }

    // If zone_admin, fetch assigned zones
    if (user.role === 'zone_admin') {
      const zoneResult = await db.query(
        'SELECT zone_name FROM user_zone_assignments WHERE user_id = $1',
        [user.id]
      );
      req.user.assignedZones = zoneResult.rows.map(r => r.zone_name);
    }

    // If division_admin, fetch assigned divisions
    if (user.role === 'division_admin') {
      const divisionResult = await db.query(
        'SELECT division_name FROM user_division_assignments WHERE user_id = $1',
        [user.id]
      );
      req.user.assignedDivisions = divisionResult.rows.map(r => r.division_name);
    }

    // Cache the user object for TOKEN_CACHE_TTL_MS
    _tokenCache.set(token, { user: req.user, expiry: Date.now() + TOKEN_CACHE_TTL_MS });

    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ message: 'Token expired. Please login again.' });
    }
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ message: 'Invalid token.' });
    }
    console.error('Auth middleware error:', error);
    return res.status(500).json({ message: 'Server error during authentication.' });
  }
};

// Middleware: Check if user has one of the required roles
const requireRole = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ message: 'Authentication required.' });
    }

    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ 
        message: `Access denied. Required role: ${allowedRoles.join(' or ')}. Your role: ${req.user.role}.` 
      });
    }

    next();
  };
};

module.exports = { verifyToken, requireRole };
