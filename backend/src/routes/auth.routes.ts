import express from 'express';
import bcrypt from 'bcryptjs';
import jwt, { SignOptions } from 'jsonwebtoken';
import { pool } from '../config/database';
import { authenticate, authorize } from '../middleware/auth.middleware';
import { decryptNumber, encrypt } from '../utils/encryption';
import { getSSHConnection } from '../services/ssh.service';

const router = express.Router();

// Register new user (admin only for creating users with domain)
router.post('/register', authenticate, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const { username, email, password, full_name, role, domain_id, ssh_user, sshpassword, project_ids } = req.body;
    const currentUser = (req as any).user;

    // Only admins can create users
    if (currentUser?.role !== 'admin') {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Only admins can create users' });
    }

    // Validate required fields
    if (!username || !email || !password) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Username, email, and password are required' });
    }

    // Get IP and port from environment variables (hardcoded)
    const ipaddress = process.env.SSH_IP || null;
    let port = null;
    if (process.env.SSH_PORT) {
      try {
        port = decryptNumber(process.env.SSH_PORT);
      } catch (error) {
        console.error('Error decrypting SSH_PORT:', error);
        port = null;
      }
    }

    // Validate role
    const validRoles = ['admin', 'project_manager', 'lead', 'engineer', 'customer', 'cad_engineer'];
    if (role && !validRoles.includes(role)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Invalid role' });
    }

    // Validate project_ids for customer role
    if (role === 'customer') {
      if (!project_ids || !Array.isArray(project_ids) || project_ids.length === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'At least one project must be selected for customer role' });
      }
      
      // Validate that all project_ids exist
      const projectIds = project_ids.map((id: any) => parseInt(id)).filter((id: number) => !isNaN(id));
      if (projectIds.length !== project_ids.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid project IDs' });
      }
      
      const projectCheck = await client.query(
        'SELECT id FROM projects WHERE id = ANY($1::int[])',
        [projectIds]
      );
      
      if (projectCheck.rows.length !== projectIds.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'One or more project IDs are invalid' });
      }
    }

    // Validate domain_id if provided
    if (domain_id) {
      const domainCheck = await client.query('SELECT id FROM domains WHERE id = $1 AND is_active = true', [domain_id]);
      if (domainCheck.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Invalid domain' });
      }
    }

    // Validate port from environment
    if (port !== null && (port < 1 || port > 65535)) {
        await client.query('ROLLBACK');
      return res.status(500).json({ error: 'Invalid SSH port configuration' });
    }

    // Check if user already exists
    const existingUser = await client.query(
      'SELECT id FROM users WHERE username = $1 OR email = $2',
      [username, email]
    );

    if (existingUser.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Username or email already exists' });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Encrypt SSH password if provided
    let sshpasswordHash = null;
    if (sshpassword) {
      // Encrypt the SSH password instead of hashing (so it can be decrypted when needed)
      sshpasswordHash = encrypt(sshpassword);
    }

    // Insert user
    const result = await client.query(
      `INSERT INTO users (username, email, password_hash, full_name, role, domain_id, ipaddress, port, ssh_user, sshpassword_hash)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING id, username, email, full_name, role, domain_id, is_active, created_at, ipaddress, port, ssh_user`,
      [
        username, 
        email, 
        passwordHash, 
        full_name || null, 
        role || 'engineer', 
        domain_id || null,
        ipaddress || null,
        port,
        ssh_user || null,
        sshpasswordHash
      ]
    );

    const newUserId = result.rows[0].id;

    // If customer role, assign projects
    if (role === 'customer' && project_ids && Array.isArray(project_ids)) {
      const projectIds = project_ids.map((id: any) => parseInt(id)).filter((id: number) => !isNaN(id));
      
      if (projectIds.length > 0) {
        // Insert user-project relationships
        for (const projectId of projectIds) {
          await client.query(
            'INSERT INTO user_projects (user_id, project_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
            [newUserId, projectId]
          );
        }
      }
    }

    await client.query('COMMIT');

    res.status(201).json({
      message: 'User created successfully',
      user: result.rows[0]
    });
  } catch (error: any) {
    await client.query('ROLLBACK');
    console.error('Error registering user:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
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

    // Establish SSH connection at login time (only once per login)
    // Check if connection already exists, if not create it
    try {
      await getSSHConnection(user.id);
      console.log(`SSH connection established for user ${user.id} during login`);
    } catch (err: any) {
      console.error(`Failed to establish SSH connection for user ${user.id} during login:`, err);
      // Don't fail login if SSH connection fails, but log the error
      // User can still use the app, but SSH commands won't work until connection is established
    }

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
    const currentUser = (req as any).user;
    const isAdmin = currentUser?.role === 'admin';

    // Check if SSH columns exist in the database
    const columnCheck = await pool.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND table_name = 'users' 
        AND column_name IN ('ipaddress', 'port', 'ssh_user')
    `);
    
    const existingColumns = columnCheck.rows.map((row: any) => row.column_name);
    const hasIpaddress = existingColumns.includes('ipaddress');
    const hasPort = existingColumns.includes('port');
    const hasSshUser = existingColumns.includes('ssh_user');

    // Build query based on available columns
    let sshFields = '';
    if (isAdmin && (hasIpaddress || hasPort || hasSshUser)) {
      const fields = [];
      if (hasIpaddress) fields.push('u.ipaddress');
      if (hasPort) fields.push('u.port');
      if (hasSshUser) fields.push('u.ssh_user');
      sshFields = ', ' + fields.join(', ');
    }

    const query = `SELECT u.id, u.username, u.email, u.full_name, u.role, u.is_active, u.domain_id, 
                          u.created_at, u.last_login, d.name as domain_name, d.code as domain_code
                          ${sshFields}
                   FROM users u
                   LEFT JOIN domains d ON u.domain_id = d.id
                   ORDER BY u.created_at DESC`;

    const result = await pool.query(query);

    res.json(result.rows);
  } catch (error: any) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: error.message });
  }
});

// Update user (admin only) - can update SSH credentials
router.put('/users/:id', authenticate, async (req, res) => {
  try {
    const currentUser = (req as any).user;
    const userId = parseInt(req.params.id);

    // Only admins can update users
    if (currentUser?.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can update users' });
    }

    const { ssh_user, sshpassword, full_name, role, domain_id, is_active } = req.body;

    // Get IP and port from environment variables (hardcoded)
    const ipaddress = process.env.SSH_IP || null;
    let port = null;
    if (process.env.SSH_PORT) {
      try {
        port = decryptNumber(process.env.SSH_PORT);
      } catch (error) {
        console.error('Error decrypting SSH_PORT:', error);
        port = null;
      }
    }

    // Validate role if provided
    if (role) {
      const validRoles = ['admin', 'project_manager', 'lead', 'engineer', 'customer'];
      if (!validRoles.includes(role)) {
        return res.status(400).json({ error: 'Invalid role' });
      }
    }

    // Validate domain_id if provided
    if (domain_id !== undefined && domain_id !== null) {
      const domainCheck = await pool.query('SELECT id FROM domains WHERE id = $1 AND is_active = true', [domain_id]);
      if (domainCheck.rows.length === 0) {
        return res.status(400).json({ error: 'Invalid domain' });
      }
    }

    // Check if user exists
    const userCheck = await pool.query('SELECT id FROM users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Build update query dynamically
    const updates: string[] = [];
    const values: any[] = [];
    let paramCount = 1;

    if (full_name !== undefined) {
      updates.push(`full_name = $${paramCount++}`);
      values.push(full_name);
    }
    if (role !== undefined) {
      updates.push(`role = $${paramCount++}`);
      values.push(role);
    }
    if (domain_id !== undefined) {
      updates.push(`domain_id = $${paramCount++}`);
      values.push(domain_id);
    }
    if (is_active !== undefined) {
      updates.push(`is_active = $${paramCount++}`);
      values.push(is_active);
    }
    // Always update IP and port from environment (hardcoded)
      updates.push(`ipaddress = $${paramCount++}`);
      values.push(ipaddress || null);
      updates.push(`port = $${paramCount++}`);
    values.push(port || null);
    
    if (ssh_user !== undefined) {
      updates.push(`ssh_user = $${paramCount++}`);
      values.push(ssh_user || null);
    }
    if (sshpassword !== undefined) {
      // Encrypt SSH password if provided
      if (sshpassword) {
        const sshpasswordHash = encrypt(sshpassword);
        updates.push(`sshpassword_hash = $${paramCount++}`);
        values.push(sshpasswordHash);
      } else {
        updates.push(`sshpassword_hash = $${paramCount++}`);
        values.push(null);
      }
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    values.push(userId);
    const query = `UPDATE users SET ${updates.join(', ')} WHERE id = $${paramCount}
                   RETURNING id, username, email, full_name, role, domain_id, is_active, 
                             created_at, ipaddress, port, ssh_user`;

    const result = await pool.query(query, values);

    // If SSH password was updated, close any existing SSH connections for this user
    // so they will be re-established with the new password on next login
    if (sshpassword !== undefined) {
      try {
        const { closeSSHConnection } = await import('../services/ssh.service');
        closeSSHConnection(userId);
        console.log(`Closed existing SSH connection for user ${userId} after password update`);
      } catch (err) {
        console.error(`Error closing SSH connection for user ${userId}:`, err);
        // Don't fail the update if closing connection fails
      }
    }

    res.json({
      message: 'User updated successfully',
      user: result.rows[0],
      sshConnectionClosed: sshpassword !== undefined // Indicate if SSH connection was closed
    });
  } catch (error: any) {
    console.error('Error updating user:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

