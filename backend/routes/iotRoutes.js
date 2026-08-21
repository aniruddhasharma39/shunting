const express = require('express');
const router = express.Router();
const { ingestTelemetry, getTelemetryAudit } = require('../controllers/iotController');

// Using basic route without JWT protection since hardware devices usually use API keys or TLS auth
router.post('/telemetry', ingestTelemetry);

router.get('/telemetry/:device_id', getTelemetryAudit);

module.exports = router;
