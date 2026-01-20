import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

// Parse DATABASE_URL to extract connection parameters
// Format: postgresql://user:password@host:port/database
const parseDatabaseUrl = () => {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error('DATABASE_URL environment variable is not set');
  }

  // If URL format, parse it
  if (url.startsWith('postgresql://') || url.startsWith('postgres://')) {
    const urlObj = new URL(url);
    return {
      host: urlObj.hostname,
      port: parseInt(urlObj.port || '5432'),
      user: urlObj.username,
      password: urlObj.password,
      database: urlObj.pathname.slice(1), // Remove leading '/'
    };
  }

  // Fallback: use individual env vars if DATABASE_URL is not in URL format
  return {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || process.env.PASSWORD || '',
    database: process.env.DB_NAME || 'asi',
  };
};

const dbConfig = parseDatabaseUrl();

export const pool = new Pool({
  host: dbConfig.host,
  port: dbConfig.port,
  user: dbConfig.user,
  password: dbConfig.password,
  database: dbConfig.database,
  ssl: false, // Disable SSL for local Docker connections
  // CRITICAL: Force search_path to public for all connections
  options: '-c search_path=public',
});

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

