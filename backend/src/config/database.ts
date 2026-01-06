import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

// Create pool configuration with support for both connection string and individual params
const getPoolConfig = () => {
  // If DATABASE_URL is provided, use it
  if (process.env.DATABASE_URL) {
    return {
      connectionString: process.env.DATABASE_URL,
      ssl: false, // Disable SSL for local Docker connections
    };
  }
  
  // Otherwise, use individual parameters
  const dbPassword = process.env.DB_PASSWORD || '';
  
  // Ensure password is always a string
  const password = String(dbPassword);
  
  const config = {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || 'ASI',
    user: process.env.DB_USER || 'postgres',
    password: password,
    ssl: false, // Disable SSL for local Docker connections
  };
  
  console.log('📋 [DATABASE] Using individual parameters:', {
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    hasPassword: password.length > 0
  });
  
  return config;
};

export const pool = new Pool(getPoolConfig());

pool.on('connect', () => {
  console.log('✅ Connected to PostgreSQL database');
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

