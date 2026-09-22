const express = require('express');
const router = express.Router();
const {
  getRegistryDevices,
  getRegistryDeviceById,
  getLiveTelemetry,
  ingestDeviceTelemetry,
  upsertRegistryDevice,
  deleteRegistryDevice
} = require('../controllers/deviceRegistryController');
const { verifyToken, requireRole } = require('../middleware/authMiddleware');

// Telemetry stream & ingestion
router.route('/telemetry/live')
  .get(verifyToken, getLiveTelemetry);

router.route('/telemetry')
  .post(ingestDeviceTelemetry); // Can be called by Lambda or authenticated client

// Accessible by hardware_engineer, super_admin, maintenance_user, yard_admin, viewer
router.route('/')
  .get(verifyToken, requireRole('super_admin', 'hardware_engineer', 'maintenance_user', 'yard_admin', 'viewer'), getRegistryDevices)
  .post(verifyToken, requireRole('super_admin', 'hardware_engineer', 'yard_admin'), upsertRegistryDevice);

router.route('/:deviceId')
  .get(verifyToken, requireRole('super_admin', 'hardware_engineer', 'maintenance_user', 'yard_admin', 'viewer'), getRegistryDeviceById)
  .delete(verifyToken, requireRole('super_admin', 'hardware_engineer', 'yard_admin'), deleteRegistryDevice);

module.exports = router;
