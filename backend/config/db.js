const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool(
  process.env.DATABASE_URL
    ? {
        connectionString: process.env.DATABASE_URL,
        ssl: { rejectUnauthorized: false }
      }
    : {
        user: process.env.DB_USER,
        host: process.env.DB_HOST,
        database: process.env.DB_NAME,
        password: process.env.DB_PASSWORD,
        port: process.env.DB_PORT || 5432,
        ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
        connectionTimeoutMillis: 10000, // Fail fast if RDS is unreachable (10s)
        idleTimeoutMillis: 30000,       // Close idle connections after 30s to prevent stale drops
      }
);

pool.on('error', (err, client) => {
  console.error('Unexpected error on idle client (non-fatal):', err.message || err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
};
