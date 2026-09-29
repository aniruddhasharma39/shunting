const express = require('express');
const router = express.Router();
const { getSessions, getSessionDetailsWithLogs, getSessionsForRangeReport } = require('../controllers/sessionController');
const { verifyToken: protect } = require('../middleware/authMiddleware');

router.get('/', protect, getSessions);
router.get('/range-report', protect, getSessionsForRangeReport);
router.get('/:id/logs', protect, getSessionDetailsWithLogs);
router.get('/:id', protect, getSessionDetailsWithLogs);

module.exports = router;
