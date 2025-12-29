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
import fileWatcherService from './services/fileWatcher.service';
import { authenticate } from './middleware/auth.middleware';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
// Configure CORS to allow frontend URL from environment
// In development, allow all localhost origins (for Flutter web dev server)
// In production, use specific FRONTEND_URL
const isDevelopment = process.env.NODE_ENV !== 'production';
const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:8080';

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (like mobile apps or curl requests)
    if (!origin) return callback(null, true);
    
    // In development, allow any localhost origin
    if (isDevelopment && origin.startsWith('http://localhost:')) {
      return callback(null, true);
    }
    
    // In production or if FRONTEND_URL is set, check against allowed origin
    if (origin === frontendUrl) {
      return callback(null, true);
    }
    
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

// Error handling middleware
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error(err.stack);
  res.status(500).json({ 
    error: 'Something went wrong!',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 ASI Dashboard API server running on port ${PORT}`);
  
  // Start file watcher for EDA output files
  try {
    fileWatcherService.startWatching();
    console.log('📁 File watcher started for EDA output files');
  } catch (error) {
    console.error('Failed to start file watcher:', error);
  }
});

