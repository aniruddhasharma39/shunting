const express = require('express');
const router = express.Router();
const { createYard, getYards, addYardLine, getYardLines, assignYardToUser, removeYardAssignment, deleteYard, deleteYardLine } = require('../controllers/yardController');
const { verifyToken: protect } = require('../middleware/authMiddleware');

router.route('/')
  .get(protect, getYards)
  .post(protect, createYard);

router.route('/assign')
  .post(protect, assignYardToUser)
  .delete(protect, removeYardAssignment);

router.route('/:yardId')
  .delete(protect, deleteYard);

router.route('/:yardId/lines')
  .get(protect, getYardLines)
  .post(protect, addYardLine);

router.route('/:yardId/lines/:lineId')
  .delete(protect, deleteYardLine);

module.exports = router;
