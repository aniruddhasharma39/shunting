const express = require('express');
const router = express.Router();
const { registerDevice, getDevices, issueDevice, returnDevice, assignLine, toggleDeviceDisabled } = require('../controllers/deviceController');
const { verifyToken: protect, requireRole } = require('../middleware/authMiddleware');

router.route('/')
  .get(protect, getDevices)
  .post(protect, registerDevice);

router.post('/issue', protect, issueDevice);
router.post('/return', protect, returnDevice);
router.put('/:id/assign-line', protect, assignLine);
router.put('/:id/toggle-disabled', protect, requireRole('super_admin', 'hardware_engineer', 'yard_admin'), toggleDeviceDisabled);

module.exports = router;
