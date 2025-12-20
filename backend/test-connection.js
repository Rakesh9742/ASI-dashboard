const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false,
});

pool.query(`
  SELECT 
    current_database() as db_name,
    EXISTS (
      SELECT FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name = 'projects'
    ) as projects_exists,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public') as total_tables
`)
  .then(res => {
    console.log('Connection Test Results:');
    console.log('Database:', res.rows[0].db_name);
    console.log('Projects table exists:', res.rows[0].projects_exists);
    console.log('Total tables in public schema:', res.rows[0].total_tables);
    return pool.query('SELECT table_name FROM information_schema.tables WHERE table_schema = \'public\' ORDER BY table_name');
  })
  .then(res => {
    console.log('\nAll tables in public schema:');
    res.rows.forEach(row => console.log('  -', row.table_name));
    pool.end();
  })
  .catch(err => {
    console.error('Error:', err.message);
    pool.end();
  });

