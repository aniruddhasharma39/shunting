/**
 * SafeShunt RDS Database Dump Utility
 * Exports schema and table contents from AWS RDS into a local SQL dump file.
 * Run using: node export_rds_data.js [output_file.sql]
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const outputFile = process.argv[2] || path.join(__dirname, 'rds_dump.sql');

const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT || 5432,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
});

async function exportRdsData() {
  console.log('==================================================');
  console.log(' SafeShunt AWS RDS -> Local SQL Exporter');
  console.log('==================================================');
  console.log(`RDS Host:   ${process.env.DB_HOST}`);
  console.log(`Database:   ${process.env.DB_NAME}`);
  console.log(`Output File:${outputFile}`);
  console.log('--------------------------------------------------');

  const stream = fs.createWriteStream(outputFile, { flags: 'w' });
  stream.write(`-- SafeShunt RDS Data Dump\n-- Generated on: ${new Date().toISOString()}\n\n`);

  try {
    // 1. Get list of all public user tables
    const tablesRes = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
      ORDER BY table_name;
    `);

    const tables = tablesRes.rows.map(r => r.table_name);
    console.log(`Found ${tables.length} tables to export: ${tables.join(', ')}`);

    for (const table of tables) {
      console.log(`Exporting table '${table}'...`);
      const dataRes = await pool.query(`SELECT * FROM "${table}"`);
      
      if (dataRes.rows.length === 0) {
        stream.write(`-- Table '${table}' has 0 rows.\n\n`);
        continue;
      }

      stream.write(`-- Data for table '${table}' (${dataRes.rows.length} rows)\n`);

      const columns = dataRes.fields.map(f => `"${f.name}"`).join(', ');

      for (const row of dataRes.rows) {
        const values = dataRes.fields.map(f => {
          const val = row[f.name];
          if (val === null || val === undefined) return 'NULL';
          if (typeof val === 'boolean' || typeof val === 'number') return val;
          if (typeof val === 'object') return `'${JSON.stringify(val).replace(/'/g, "''")}'`;
          return `'${String(val).replace(/'/g, "''")}'`;
        }).join(', ');

        stream.write(`INSERT INTO "${table}" (${columns}) VALUES (${values}) ON CONFLICT DO NOTHING;\n`);
      }
      stream.write('\n');
    }

    console.log('--------------------------------------------------');
    console.log(`✅ AWS RDS export completed successfully!`);
    console.log(`Saved dump file to: ${outputFile}`);
  } catch (err) {
    console.error('❌ Error during RDS export:', err);
  } finally {
    stream.end();
    await pool.end();
  }
}

exportRdsData();
