const express = require('express');
const router = express.Router();
const { registerDevice, getDevices, issueDevice, returnDevice, assignLine, toggleDeviceDisabled, getDeviceAssignments } = require('../controllers/deviceController');
const { verifyToken: protect, requireRole } = require('../middleware/authMiddleware');
const upload = require('../middleware/uploadMiddleware');

router.route('/')
  .get(protect, getDevices)
  .post(protect, registerDevice);

router.post('/issue', protect, upload.fields([{ name: 'user_photo', maxCount: 1 }, { name: 'id_card_photo', maxCount: 1 }]), issueDevice);
router.post('/return', protect, returnDevice);
router.get('/assignments', protect, getDeviceAssignments);
router.put('/:id/assign-line', protect, assignLine);
router.put('/:id/toggle-disabled', protect, requireRole('super_admin', 'yard_admin'), toggleDeviceDisabled);

module.exports = router;
