require('dotenv').config();
const dashboardController = require('./controllers/dashboardController');

// Mock req, res
const req = { user: { role: 'super_admin' } };
const res = {
  json: (data) => {
    console.log(JSON.stringify(data.liveSessions, null, 2));
    process.exit();
  },
  status: (code) => res
};

dashboardController.getDashboardStats(req, res).catch(console.error);
