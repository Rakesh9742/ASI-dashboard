const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false,
});

console.log('Connection string:', process.env.DATABASE_URL.replace(/:[^:@]+@/, ':****@'));

pool.query('SELECT * FROM projects LIMIT 1')
  .then(res => {
    console.log('✅ Projects query successful!');
    console.log('Rows:', res.rows.length);
    pool.end();
  })
  .catch(err => {
    console.error('❌ Projects query failed:');
    console.error('Error code:', err.code);
    console.error('Error message:', err.message);
    console.error('Error detail:', err.detail);
    
    // Try to see what tables DO exist
    return pool.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name");
  })
  .then(res => {
    if (res) {
      console.log('\nTables that DO exist:');
      res.rows.forEach(row => console.log('  -', row.table_name));
    }
    pool.end();
  })
  .catch(err => {
    console.error('Failed to list tables:', err.message);
    pool.end();
  });

