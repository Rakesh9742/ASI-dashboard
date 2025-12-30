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

    // Check if this is a Zoho OAuth user (hasn't set a password yet)
    if (user.password_hash === 'zoho_oauth_user') {
      return res.status(401).json({
        error: 'This account uses Zoho OAuth login',
        hint: 'Please use "Login with Zoho" button instead, or set a password in your profile settings',
        requiresZohoAuth: true
      });
    }

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
      `SELECT u.id, u.username, u.email, u.full_name, u.role, u.is_active, u.created_at, u.last_login,
              u.domain_id, d.name as domain_name, d.code as domain_code
       FROM users u
       LEFT JOIN domains d ON u.domain_id = d.id
       WHERE u.id = $1`,
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

// Set password for Zoho OAuth users (allows them to login with username/password)
router.post('/set-password', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { password } = req.body;

    if (!password || password.length < 6) {
      return res.status(400).json({ error: 'Password is required and must be at least 6 characters' });
    }

    // Get current user
    const userResult = await pool.query(
      'SELECT password_hash FROM users WHERE id = $1',
      [userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const user = userResult.rows[0];

    // Only allow setting password if user is a Zoho OAuth user (hasn't set password yet)
    if (user.password_hash !== 'zoho_oauth_user') {
      return res.status(400).json({
        error: 'Password already set',
        hint: 'Use the change password endpoint to update your password'
      });
    }

    // Hash the new password
    const passwordHash = await bcrypt.hash(password, 10);

    // Update user password
    await pool.query(
      'UPDATE users SET password_hash = $1 WHERE id = $2',
      [passwordHash, userId]
    );

    res.json({
      message: 'Password set successfully. You can now login with username and password.',
      success: true
    });
  } catch (error: any) {
    console.error('Error setting password:', error);
    res.status(500).json({ error: error.message });
  }
});

// Change password (for users who already have a password)
router.post('/change-password', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: 'Current password and new password (min 6 characters) are required' });
    }

    // Get current user
    const userResult = await pool.query(
      'SELECT password_hash FROM users WHERE id = $1',
      [userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const user = userResult.rows[0];

    // Skip password verification for Zoho OAuth users (they don't have a password yet)
    if (user.password_hash !== 'zoho_oauth_user') {
      // Verify current password
      const isValidPassword = await bcrypt.compare(currentPassword, user.password_hash);
      if (!isValidPassword) {
        return res.status(401).json({ error: 'Current password is incorrect' });
      }
    }

    // Hash the new password
    const passwordHash = await bcrypt.hash(newPassword, 10);

    // Update user password
    await pool.query(
      'UPDATE users SET password_hash = $1 WHERE id = $2',
      [passwordHash, userId]
    );

    res.json({
      message: 'Password changed successfully',
      success: true
    });
  } catch (error: any) {
    console.error('Error changing password:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get all users (accessible by team members)
router.get('/users', authenticate, authorize('admin', 'project_manager', 'lead', 'engineer'), async (req, res) => {
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

