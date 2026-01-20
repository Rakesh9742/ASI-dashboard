import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: false, // Disable SSL for local Docker connections
});

pool.on('connect', async (client) => {
  try {
    // Set search path to public schema to ensure tables are found
    await client.query('SET search_path TO public');
    console.log('✅ Connected to PostgreSQL database');
  } catch (error) {
    console.error('❌ Error setting search_path:', error);
  }
});

pool.on('error', (err) => {
  console.error('❌ Unexpected error on idle client', err);
  process.exit(-1);
});

// Test connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('❌ Database connection error:', err);
  } else {
    console.log('✅ Database connection successful:', res.rows[0].now);
  }
});

