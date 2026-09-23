const express = require('express');
const router = express.Router();
const { getSessions, getSessionDetailsWithLogs } = require('../controllers/sessionController');
const { verifyToken: protect } = require('../middleware/authMiddleware');

router.get('/', protect, getSessions);
router.get('/:id/logs', protect, getSessionDetailsWithLogs);
router.get('/:id', protect, getSessionDetailsWithLogs);

module.exports = router;

