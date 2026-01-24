import express from 'express';
import bcrypt from 'bcryptjs';
import jwt, { SignOptions } from 'jsonwebtoken';
import { pool } from '../config/database';
import { authenticate, authorize } from '../middleware/auth.middleware';
import { authenticateApiKey } from '../middleware/apiKey.middleware';
import { decryptNumber, encrypt } from '../utils/encryption';
import { getSSHConnection } from '../services/ssh.service';

const router = express.Router();

// Register new user (admin only for creating users with domain)
router.post('/register', authenticate, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    const { username, email, password, full_name, role, domain_id, ssh_user, sshpassword, project_ids, run_directory } = req.body;
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
      `INSERT INTO users (username, email, password_hash, full_name, role, domain_id, ipaddress, port, ssh_user, sshpassword_hash, run_directory)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       RETURNING id, username, email, full_name, role, domain_id, is_active, created_at, ipaddress, port, ssh_user, run_directory`,
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
        sshpasswordHash,
        run_directory || null
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
              u.domain_id, d.name as domain_name, d.code as domain_code, u.run_directory
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
        AND column_name IN ('ipaddress', 'port', 'ssh_user', 'run_directory')
    `);
    
    const existingColumns = columnCheck.rows.map((row: any) => row.column_name);
    const hasIpaddress = existingColumns.includes('ipaddress');
    const hasPort = existingColumns.includes('port');
    const hasSshUser = existingColumns.includes('ssh_user');
    const hasRunDirectory = existingColumns.includes('run_directory');

    // Build query based on available columns
    let sshFields = '';
    if (isAdmin && (hasIpaddress || hasPort || hasSshUser)) {
      const fields = [];
      if (hasIpaddress) fields.push('u.ipaddress');
      if (hasPort) fields.push('u.port');
      if (hasSshUser) fields.push('u.ssh_user');
      sshFields = ', ' + fields.join(', ');
    }

    // Add run_directory if column exists
    let runDirectoryField = '';
    if (hasRunDirectory) {
      runDirectoryField = ', u.run_directory';
    }

    const query = `SELECT u.id, u.username, u.email, u.full_name, u.role, u.is_active, u.domain_id, 
                          u.created_at, u.last_login, d.name as domain_name, d.code as domain_code
                          ${sshFields}${runDirectoryField}
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

    const { ssh_user, sshpassword, full_name, role, domain_id, is_active, run_directory } = req.body;

    // Debug logging for SSH fields
    console.log(`[Update User ${userId}] Received SSH fields:`, {
      ssh_user: ssh_user !== undefined ? (ssh_user ? '***provided***' : 'empty/null') : 'undefined',
      sshpassword: sshpassword !== undefined ? (sshpassword ? '***provided***' : 'empty/null') : 'undefined',
    });

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

    // Check if SSH columns exist by trying to query them directly
    // This is more reliable than information_schema which was failing in production
    let hasSshUser = false;
    let hasSshPasswordHash = false;
    let hasIpaddress = false;
    let hasPort = false;
    let hasRunDirectory = false;
    
    // Try to query each column to verify it exists
    const columnChecks = [
      { name: 'ssh_user', setter: () => { hasSshUser = true; } },
      { name: 'sshpassword_hash', setter: () => { hasSshPasswordHash = true; } },
      { name: 'ipaddress', setter: () => { hasIpaddress = true; } },
      { name: 'port', setter: () => { hasPort = true; } },
      { name: 'run_directory', setter: () => { hasRunDirectory = true; } },
    ];
    
    for (const col of columnChecks) {
      try {
        await pool.query(`SELECT ${col.name} FROM users WHERE id = $1 LIMIT 1`, [userId]);
        col.setter();
      } catch (error: any) {
        // Column doesn't exist (error code 42703 = undefined_column)
        if (error.code === '42703') {
          // Column definitely doesn't exist, leave flag as false
        } else {
          // Other error (might be connection issue), but column might exist
          // For safety, assume it exists if it's not a column error
          col.setter();
        }
      }
    }
    
    console.log(`[Update User ${userId}] Column existence check:`, {
      hasIpaddress,
      hasPort,
      hasSshUser,
      hasSshPasswordHash,
      hasRunDirectory,
    });

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
    // Update IP and port from environment (hardcoded) - only if columns exist
    if (hasIpaddress) {
      updates.push(`ipaddress = $${paramCount++}`);
      values.push(ipaddress || null);
    }
    if (hasPort) {
      updates.push(`port = $${paramCount++}`);
      values.push(port || null);
    }
    
    if (ssh_user !== undefined && hasSshUser) {
      // Only update if a non-empty value is provided, or explicitly set to null/empty
      // If ssh_user is an empty string, convert to null
      const sshUserValue = ssh_user && ssh_user.trim() ? ssh_user.trim() : null;
      updates.push(`ssh_user = $${paramCount++}`);
      values.push(sshUserValue);
      console.log(`[Update User ${userId}] Updating ssh_user:`, sshUserValue ? '***value provided***' : 'null');
    } else {
      console.log(`[Update User ${userId}] NOT updating ssh_user:`, {
        ssh_user_undefined: ssh_user === undefined,
        hasSshUser,
        ssh_user_value: ssh_user !== undefined ? (ssh_user ? '***provided***' : 'empty/null') : 'undefined',
      });
    }
    if (sshpassword !== undefined && hasSshPasswordHash) {
      // Encrypt SSH password if provided
      if (sshpassword && sshpassword.trim()) {
        const sshpasswordHash = encrypt(sshpassword);
        updates.push(`sshpassword_hash = $${paramCount++}`);
        values.push(sshpasswordHash);
        console.log(`[Update User ${userId}] Updating sshpassword_hash: ***encrypted***`);
      } else {
        // Only set to null if explicitly provided (empty string or null)
        // Don't update if undefined (user didn't touch the password field)
        updates.push(`sshpassword_hash = $${paramCount++}`);
        values.push(null);
        console.log(`[Update User ${userId}] Setting sshpassword_hash to null`);
      }
    } else {
      console.log(`[Update User ${userId}] NOT updating sshpassword_hash:`, {
        sshpassword_undefined: sshpassword === undefined,
        hasSshPasswordHash,
        sshpassword_value: sshpassword !== undefined ? (sshpassword ? '***provided***' : 'empty/null') : 'undefined',
      });
    }
    if (run_directory !== undefined && hasRunDirectory) {
      updates.push(`run_directory = $${paramCount++}`);
      values.push(run_directory || null);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    // Build RETURNING clause with only existing columns
    const returningFields = ['id', 'username', 'email', 'full_name', 'role', 'domain_id', 'is_active', 'created_at'];
    if (hasIpaddress) returningFields.push('ipaddress');
    if (hasPort) returningFields.push('port');
    if (hasSshUser) returningFields.push('ssh_user');
    if (hasRunDirectory) returningFields.push('run_directory');

    values.push(userId);
    const query = `UPDATE users SET ${updates.join(', ')} WHERE id = $${paramCount}
                   RETURNING ${returningFields.join(', ')}`;

    console.log(`[Update User ${userId}] Executing query with ${updates.length} updates:`, {
      updates: updates,
      hasSshFields: updates.some(u => u.includes('ssh_user') || u.includes('sshpassword_hash')),
    });

    const result = await pool.query(query, values);
    
    console.log(`[Update User ${userId}] Update successful. Returned user:`, {
      id: result.rows[0]?.id,
      ssh_user: result.rows[0]?.ssh_user || 'null/empty',
      has_sshpassword_hash: result.rows[0]?.sshpassword_hash ? '***has value***' : 'null/empty',
    });

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

/**
 * Extract username from email (first part before first dot)
 * Example: "rakesh.p@sumedhait.com" -> "rakesh"
 */
function extractUsernameFromEmail(email: string | null | undefined): string | null {
  if (!email) return null;
  const emailPrefix = email.split('@')[0];
  // Get first part before first dot (if any)
  const username = emailPrefix.split('.')[0].toLowerCase();
  return username;
}

/**
 * Extract username from directory path
 * Example: "pd/rakesh/pd1" -> "rakesh"
 */
function extractUsernameFromPath(directoryPath: string): string | null {
  if (!directoryPath) return null;
  // Split by '/' and get the second segment (index 1)
  const parts = directoryPath.split('/').filter(part => part.length > 0);
  if (parts.length >= 2) {
    return parts[1].toLowerCase();
  }
  return null;
}

// External API: Set run_directory by username from directory path
// POST /api/auth/external/set-run-directory
// Body: { "directory": "pd/rakesh/pd1" }
router.post('/external/set-run-directory', authenticateApiKey, async (req, res) => {
  try {
    const { directory } = req.body;

    if (!directory || typeof directory !== 'string') {
      return res.status(400).json({ 
        error: 'Invalid request', 
        message: 'Directory path is required. Format: "pd/username/path"' 
      });
    }

    // Extract username from directory path (e.g., "pd/rakesh/pd1" -> "rakesh")
    const usernameFromPath = extractUsernameFromPath(directory);
    
    if (!usernameFromPath) {
      return res.status(400).json({ 
        error: 'Invalid directory format', 
        message: 'Directory path must be in format: "pd/username/path" (e.g., "pd/rakesh/pd1")' 
      });
    }

    console.log(`[External API] Setting run_directory for username: ${usernameFromPath}, directory: ${directory}`);

    // Find user by matching username extracted from email
    // Get all users and check if extracted username matches
    const allUsers = await pool.query('SELECT id, username, email, run_directory FROM users WHERE is_active = true');
    
    let matchedUser = null;
    for (const user of allUsers.rows) {
      const extractedUsername = extractUsernameFromEmail(user.email);
      if (extractedUsername && extractedUsername.toLowerCase() === usernameFromPath.toLowerCase()) {
        matchedUser = user;
        break;
      }
      // Also check if username field matches
      if (user.username && user.username.toLowerCase() === usernameFromPath.toLowerCase()) {
        matchedUser = user;
        break;
      }
    }

    if (!matchedUser) {
      console.log(`[External API] User not found for username: ${usernameFromPath}`);
      return res.status(404).json({ 
        error: 'User not found', 
        message: `No user found matching username "${usernameFromPath}" extracted from directory path "${directory}"` 
      });
    }

    // Update run_directory for the matched user
    const updateResult = await pool.query(
      'UPDATE users SET run_directory = $1 WHERE id = $2 RETURNING id, username, email, run_directory',
      [directory, matchedUser.id]
    );

    console.log(`[External API] Successfully updated run_directory for user: ${matchedUser.email} (ID: ${matchedUser.id})`);

    res.json({
      success: true,
      message: 'Run directory updated successfully',
      user: {
        id: updateResult.rows[0].id,
        username: updateResult.rows[0].username,
        email: updateResult.rows[0].email,
        run_directory: updateResult.rows[0].run_directory
      }
    });
  } catch (error: any) {
    console.error('[External API] Error setting run_directory:', error);
    res.status(500).json({ 
      error: 'Internal server error', 
      message: error.message 
    });
  }
});

export default router;

