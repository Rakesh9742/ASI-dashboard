const { Pool } = require('pg');
require('dotenv').config();

// Create a completely fresh pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false,
  max: 1, // Force a single connection
});

console.log('Testing with a fresh connection pool...\n');

// First, verify we can see the table in information_schema
pool.query(`
  SELECT 
    table_name,
    table_schema
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name IN ('projects', 'project_domains')
  ORDER BY table_name
`)
  .then(res => {
    console.log('Tables found in information_schema:');
    if (res.rows.length === 0) {
      console.log('  ❌ No projects tables found!');
    } else {
      res.rows.forEach(row => {
        console.log(`  ✅ ${row.table_schema}.${row.table_name}`);
      });
    }
    
    // Now try to query the table directly
    return pool.query('SELECT COUNT(*) as count FROM projects');
  })
  .then(res => {
    console.log('\n✅ Direct query to projects table works!');
    console.log('Projects count:', res.rows[0].count);
    pool.end();
  })
  .catch(err => {
    console.error('\n❌ Direct query failed:');
    console.error('Code:', err.code);
    console.error('Message:', err.message);
    
    // List all tables to see what's available
    return pool.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name");
  })
  .then(res => {
    if (res) {
      console.log('\nAll available tables:');
      res.rows.forEach(row => console.log('  -', row.table_name));
    }
    pool.end();
  })
  .catch(err => {
    console.error('Failed:', err.message);
    pool.end();
  });

