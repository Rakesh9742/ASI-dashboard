import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { pool } from './config/database';
import chipRoutes from './routes/chip.routes';
import designRoutes from './routes/design.routes';
import projectRoutes from './routes/project.routes';
import dashboardRoutes from './routes/dashboard.routes';
import authRoutes from './routes/auth.routes';
import domainRoutes from './routes/domain.routes';
import zohoRoutes from './routes/zoho.routes';
import edaFilesRoutes from './routes/edaFiles.routes';
import sshRoutes from './routes/ssh.routes';
import terminalRoutes, { initializeTerminalWebSocket } from './routes/terminal.routes';
import vncRoutes, { initializeVncWebSocket } from './routes/vnc.routes';
import qmsRoutes from './routes/qms.routes';
import fileWatcherService from './services/fileWatcher.service';
import { authenticate } from './middleware/auth.middleware';
import { createServer } from 'http';

dotenv.config();

// Prevent unhandled promise rejections from crashing the process (e.g. SSH credentials not configured)
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  // Do not exit - keep server running; the request may have already returned 500
});

const app = express();
const PORT = process.env.PORT || 3000;

// Create HTTP server for WebSocket support
const server = createServer(app);

// Increase server timeout for long-running SSH commands (especially those requiring passwords)
// Default is 2 minutes, increase to 5 minutes to handle password prompts
server.timeout = 300000; // 5 minutes in milliseconds
server.keepAliveTimeout = 300000; // Keep connections alive for 5 minutes
server.headersTimeout = 300000; // Wait 5 minutes for headers

// Middleware
// Configure CORS to allow frontend URL from environment
const isDevelopment = process.env.NODE_ENV !== 'production';
const corsOrigin = process.env.CORS_ORIGIN || process.env.FRONTEND_URL;

// Support multiple origins separated by comma
const corsOrigins = corsOrigin ? corsOrigin.split(',').map(origin => origin.trim()) : [];

if (!corsOrigin || corsOrigins.length === 0) {
  console.warn('⚠️  CORS_ORIGIN or FRONTEND_URL is not set in .env file. CORS may not work correctly.');
  console.warn('   Please set CORS_ORIGIN=http://your-frontend-url.com in your .env file');
}

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (like mobile apps or curl requests)
    if (!origin) return callback(null, true);
    
    // Normalize URLs for comparison (remove trailing slashes and normalize protocol)
    const normalizeUrl = (url: string) => {
      let normalized = url.replace(/\/$/, '');
      // Normalize http/https for comparison
      normalized = normalized.replace(/^https?:\/\//, '');
      return normalized;
    };
    
    // In development, be more permissive - allow all localhost origins
    if (isDevelopment) {
      if (origin.startsWith('http://localhost:') || origin.startsWith('https://localhost:') || 
          origin.startsWith('http://127.0.0.1:') || origin.startsWith('https://127.0.0.1:')) {
        return callback(null, true);
      }
    }
    
    // If no configured origins, allow all (prevents accidental CORS lockout)
    if (corsOrigins.length === 0) {
      return callback(null, true);
    }

    // Check against allowed origins from environment variable (works for both dev and production)
    if (corsOrigins.length > 0) {
      const normalizedOrigin = normalizeUrl(origin);
      
      for (const allowedOrigin of corsOrigins) {
        try {
          const normalizedAllowed = normalizeUrl(allowedOrigin);
          
          // Exact match after normalization (protocol-agnostic)
          if (normalizedOrigin === normalizedAllowed) {
            console.log(`✅ CORS allowed origin: ${origin} (matched normalized: ${normalizedOrigin})`);
            return callback(null, true);
          }
          
          // Also check if origin matches by hostname and port (protocol-agnostic)
          const originUrl = new URL(origin);
          const allowedUrl = new URL(allowedOrigin);
          
          // Get ports (handle default ports)
          const getPort = (url: URL) => {
            if (url.port) return url.port;
            return url.protocol === 'https:' ? '443' : '80';
          };
          
          const originPort = getPort(originUrl);
          const allowedPort = getPort(allowedUrl);
          
          // Match by hostname and port (allows http/https flexibility)
          if (originUrl.hostname === allowedUrl.hostname && originPort === allowedPort) {
            console.log(`✅ CORS allowed origin: ${origin} (matched hostname: ${originUrl.hostname}, port: ${originPort})`);
            return callback(null, true);
          }
        } catch (e) {
          // Invalid URL format, continue to next origin
          console.debug(`⚠️  Skipping invalid CORS origin: ${allowedOrigin}`, e);
        }
      }
    }
    
    // Log rejected origin for debugging
    console.warn(`🚫 CORS blocked origin: ${origin} (expected: ${corsOrigin || 'not set'}, NODE_ENV: ${process.env.NODE_ENV || 'not set'})`);
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Root route - API information
app.get('/', (req, res) => {
  res.json({
    message: 'ASI Dashboard API',
    version: '1.0.0',
    status: 'running',
    endpoints: {
      health: '/health',
      auth: '/api/auth',
      zoho: '/api/zoho',
      projects: '/api/projects',
      domains: '/api/domains',
      dashboard: '/api/dashboard',
      edaFiles: '/api/eda-files',
    },
    documentation: 'See API documentation for details'
  });
});

// Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT NOW()');
    res.status(200).json({ 
      status: 'ok', 
      message: 'ASI Dashboard API is running',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ 
      status: 'error', 
      message: 'Database connection failed' 
    });
  }
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/chips', chipRoutes);
app.use('/api/designs', designRoutes);
app.use('/api/projects', projectRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/domains', domainRoutes);
app.use('/api/zoho', zohoRoutes);
app.use('/api/eda-files', edaFilesRoutes);
app.use('/api/ssh', sshRoutes);
app.use('/api/terminal', terminalRoutes);
app.use('/api/vnc', vncRoutes);
app.use('/api/qms', qmsRoutes);

// Error handling middleware
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error(err.stack);
  res.status(500).json({ 
    error: 'Something went wrong!',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Initialize WebSocket server for terminal
initializeTerminalWebSocket(server);

// Initialize WebSocket server for VNC
initializeVncWebSocket(server);

// Start server
server.listen(PORT, async () => {
  console.log(`🚀 ASI Dashboard API server running on port ${PORT}`);
  
  // Start file watcher for EDA output files
  try {
    await fileWatcherService.startWatching();
    console.log('📁 File watcher started for EDA output files');
  } catch (error) {
    console.error('Failed to start file watcher:', error);
  }
});

