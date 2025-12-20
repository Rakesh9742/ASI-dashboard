const { Pool } = require('pg');

// Try connecting directly to Docker container IP
const dockerIP = '172.17.0.2'; // We'll get this from docker inspect

const pool = new Pool({
  host: dockerIP,
  port: 5432,
  user: 'postgres',
  password: 'root',
  database: 'asi',
  ssl: false,
});

console.log(`Testing direct connection to Docker container at ${dockerIP}:5432`);

pool.query('SELECT current_database(), EXISTS (SELECT FROM information_schema.tables WHERE table_schema = \'public\' AND table_name = \'projects\') as exists')
  .then(res => {
    console.log('✅ Connected!');
    console.log('Database:', res.rows[0].current_database);
    console.log('Projects exists:', res.rows[0].exists);
    return pool.query('SELECT * FROM projects LIMIT 1');
  })
  .then(res => {
    console.log('✅ Projects query works! Rows:', res.rows.length);
    pool.end();
  })
  .catch(err => {
    console.error('❌ Error:', err.message);
    pool.end();
  });

