const express = require('express');
const router = express.Router();
const {
  getRegistryDevices,
  getRegistryDeviceById,
  getLiveTelemetry,
  ingestDeviceTelemetry,
  upsertRegistryDevice,
  deleteRegistryDevice,
  uploadDeviceImagesOnly,
  toggleRegistryDeviceDisabled
} = require('../controllers/deviceRegistryController');
const { verifyToken, requireRole } = require('../middleware/authMiddleware');
const multer = require('multer');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 } // 5MB limit
});
// Telemetry stream & ingestion
router.route('/telemetry/live')
  .get(verifyToken, getLiveTelemetry);

router.route('/telemetry')
  .post(ingestDeviceTelemetry); // Can be called by Lambda or authenticated client

// Accessible by super_admin, zone_admin, division_admin, yard_admin
router.route('/')
  .get(verifyToken, requireRole('super_admin', 'zone_admin', 'division_admin', 'yard_admin'), getRegistryDevices)
  .post(verifyToken, requireRole('super_admin', 'yard_admin'), upload.fields([{ name: 'device_image', maxCount: 1 }, { name: 'device_sim', maxCount: 1 }]), upsertRegistryDevice);

router.route('/:deviceId')
  .get(verifyToken, requireRole('super_admin', 'zone_admin', 'division_admin', 'yard_admin'), getRegistryDeviceById)
  .delete(verifyToken, requireRole('super_admin', 'yard_admin'), deleteRegistryDevice);

router.route('/:deviceId/images')
  .post(verifyToken, requireRole('super_admin', 'yard_admin'), upload.fields([{ name: 'device_image', maxCount: 1 }, { name: 'device_sim', maxCount: 1 }]), uploadDeviceImagesOnly);

router.put('/:deviceId/toggle-disabled', verifyToken, requireRole('super_admin', 'yard_admin'), toggleRegistryDeviceDisabled);

module.exports = router;
