import express from 'express';
import bcrypt from 'bcryptjs';
import jwt, { SignOptions } from 'jsonwebtoken';
import { pool } from '../config/database';
import { authenticate, authorize } from '../middleware/auth.middleware';

const router = express.Router();

// Register new user (admin only for creating users with domain)
router.post('/register', authenticate, async (req, res) => {
  try {
    const { username, email, password, full_name, role, domain_id } = req.body;
    const currentUser = (req as any).user;

    // Only admins can create users
    if (currentUser?.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can create users' });
    }

    // Validate required fields
    if (!username || !email || !password) {
      return res.status(400).json({ error: 'Username, email, and password are required' });
    }

    // Validate role
    const validRoles = ['admin', 'project_manager', 'lead', 'engineer', 'customer'];
    if (role && !validRoles.includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }

    // Validate domain_id if provided
    if (domain_id) {
      const domainCheck = await pool.query('SELECT id FROM domains WHERE id = $1 AND is_active = true', [domain_id]);
      if (domainCheck.rows.length === 0) {
        return res.status(400).json({ error: 'Invalid domain' });
      }
    }

    // Check if user already exists
    const existingUser = await pool.query(
      'SELECT id FROM users WHERE username = $1 OR email = $2',
      [username, email]
    );

    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: 'Username or email already exists' });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Insert user
    const result = await pool.query(
      `INSERT INTO users (username, email, password_hash, full_name, role, domain_id)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, username, email, full_name, role, domain_id, is_active, created_at`,
      [username, email, passwordHash, full_name || null, role || 'engineer', domain_id || null]
    );

    res.status(201).json({
      message: 'User created successfully',
      user: result.rows[0]
    });
  } catch (error: any) {
    console.error('Error registering user:', error);
    res.status(500).json({ error: error.message });
  }
});

// Login
router.post('/login', async (req, res) => {
  try {
    const { username, email, password } = req.body;

    if ((!username && !email) || !password) {
      return res.status(400).json({ error: 'Username/email and password are required' });
    }

    // Find user by username or email
    const result = await pool.query(
      'SELECT * FROM users WHERE (username = $1 OR email = $1) AND is_active = true',
      [username || email]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];

    // Verify password
    const isValidPassword = await bcrypt.compare(password, user.password_hash);

    if (!isValidPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Update last login
    await pool.query(
      'UPDATE users SET last_login = NOW() WHERE id = $1',
      [user.id]
    );

    // Generate JWT token
    const jwtSecret = process.env.JWT_SECRET || 'your-secret-key';
    const jwtExpiresIn = process.env.JWT_EXPIRES_IN || '7d';
    
    const token = jwt.sign(
      {
        id: user.id,
        username: user.username,
        email: user.email,
        role: user.role
      },
      jwtSecret,
      { expiresIn: jwtExpiresIn } as SignOptions
    );

    res.json({
      message: 'Login successful',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        full_name: user.full_name,
        role: user.role
      }
    });
  } catch (error: any) {
    console.error('Error logging in:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get current user profile
router.get('/me', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const result = await pool.query(
      'SELECT id, username, email, full_name, role, is_active, created_at, last_login FROM users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(result.rows[0]);
  } catch (error: any) {
    console.error('Error fetching user profile:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get all users (admin only)
router.get('/users', authenticate, authorize('admin'), async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.email, u.full_name, u.role, u.is_active, u.domain_id, 
              u.created_at, u.last_login, d.name as domain_name, d.code as domain_code
       FROM users u
       LEFT JOIN domains d ON u.domain_id = d.id
       ORDER BY u.created_at DESC`
    );

    res.json(result.rows);
  } catch (error: any) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

