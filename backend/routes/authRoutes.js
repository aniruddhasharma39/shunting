const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const { verifyToken, requireRole } = require('../middleware/authMiddleware');
const upload = require('../middleware/uploadMiddleware');

// @route   POST /api/auth/profile/picture
// @desc    Upload profile picture
// @access  Private
router.post('/profile/picture', verifyToken, upload.single('profile_pic'), authController.uploadProfilePicture);

// @route   DELETE /api/auth/profile/picture
// @desc    Delete profile picture
// @access  Private
router.delete('/profile/picture', verifyToken, authController.deleteProfilePicture);

// @route   POST /api/auth/register
// @desc    Register a new user
// @access  Public
router.post('/register', authController.register);

// @route   POST /api/auth/login
// @desc    Login user and get token
// @access  Public
router.post('/login', authController.login);

// @route   GET /api/auth/me
// @desc    Get current user profile with role and assigned yards
// @access  Private (any authenticated user)
router.get('/me', verifyToken, authController.getMe);

// @route   GET /api/auth/users
// @desc    List all users (for user management & assigning devices)
// @access  Private (Super Admin & Yard Admin)
router.get('/users', verifyToken, requireRole('super_admin', 'yard_admin'), authController.listUsers);

// @route   PUT /api/auth/users/:id/toggle-active
// @desc    Activate or deactivate a user
// @access  Private (Super Admin only)
router.put('/users/:id/toggle-active', verifyToken, requireRole('super_admin'), authController.toggleUserActive);

// @route   DELETE /api/auth/users/:id
// @desc    Delete a user completely
// @access  Private (Super Admin only)
router.delete('/users/:id', verifyToken, requireRole('super_admin'), authController.deleteUser);

module.exports = router;
