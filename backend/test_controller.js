const db = require('./config/db');
const { getSessions } = require('./controllers/sessionController');

const req = { query: { status: 'history' } };
const res = {
  json: (data) => {
    console.log('Returned sessions:', data.length);
    console.log(data.slice(0, 3));
    process.exit();
  },
  status: (code) => res
};

getSessions(req, res).catch(console.error);
