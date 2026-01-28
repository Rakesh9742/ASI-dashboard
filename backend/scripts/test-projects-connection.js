// Test database connection and projects table
require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false,
});

async function testConnection() {
  try {
    console.log('🔍 Testing database connection...');
    console.log('Database URL:', process.env.DATABASE_URL?.replace(/:[^:@]+@/, ':****@'));
    
    // Test basic connection
    const connectionTest = await pool.query('SELECT NOW() as current_time, current_database() as db_name');
    console.log('✅ Connected to database:', connectionTest.rows[0].db_name);
    console.log('✅ Current time:', connectionTest.rows[0].current_time);
    
    // Check if projects table exists
    const tableCheck = await pool.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'projects'
      ) as projects_exists,
      EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'project_domains'
      ) as project_domains_exists
    `);
    
    console.log('\n📊 Table Status:');
    console.log('  - projects table:', tableCheck.rows[0].projects_exists ? '✅ EXISTS' : '❌ MISSING');
    console.log('  - project_domains table:', tableCheck.rows[0].project_domains_exists ? '✅ EXISTS' : '❌ MISSING');
    
    // Check projects count
    const projectsCount = await pool.query('SELECT COUNT(*) as count FROM projects');
    console.log('  - Projects count:', projectsCount.rows[0].count);
    
    // Check domains count
    const domainsCount = await pool.query('SELECT COUNT(*) as count FROM domains');
    console.log('  - Domains count:', domainsCount.rows[0].count);
    
    // Test a sample query similar to what the API uses
    console.log('\n🔍 Testing projects query (like API)...');
    const projectsQuery = await pool.query(`
      SELECT 
        p.*,
        COALESCE(
          json_agg(
            json_build_object(
              'id', d.id,
              'name', d.name,
              'code', d.code,
              'description', d.description
            )
          ) FILTER (WHERE d.id IS NOT NULL),
          '[]'
        ) as domains
      FROM projects p
      LEFT JOIN project_domains pd ON pd.project_id = p.id
      LEFT JOIN domains d ON d.id = pd.domain_id
      GROUP BY p.id
      ORDER BY p.created_at DESC
    `);
    
    console.log('✅ Projects query successful!');
    console.log('  - Found', projectsQuery.rows.length, 'projects');
    
    console.log('\n✅ All tests passed! Database connection is working correctly.');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

testConnection();
































