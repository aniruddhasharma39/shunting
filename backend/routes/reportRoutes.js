const express = require('express');
const router = express.Router();
const reportController = require('../controllers/reportController');
const { verifyToken } = require('../middleware/authMiddleware');

// Flexible auth: supports ?token= query param for browser-launched PDF downloads
const flexAuth = (req, res, next) => {
  if (!req.headers.authorization && req.query.token) {
    req.headers.authorization = `Bearer ${req.query.token}`;
  }
  return verifyToken(req, res, next);
};

router.get('/generate/pdf', flexAuth, reportController.generatePDF);
router.get('/generate/excel', flexAuth, reportController.generateExcel);
router.get('/session/:id/pdf', flexAuth, reportController.generateSessionPDF);
router.get('/session/:id/excel', flexAuth, reportController.generateSessionExcel);
router.get('/range/pdf', flexAuth, reportController.generateRangeReportPDF);

module.exports = router;
