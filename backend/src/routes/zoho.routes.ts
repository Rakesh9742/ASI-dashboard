import express from 'express';
import jwt, { SignOptions } from 'jsonwebtoken';
import zohoService from '../services/zoho.service';
import { authenticate } from '../middleware/auth.middleware';

const router = express.Router();

// Map Zoho People designation/role to app role
function mapZohoRoleToAppRole(designation: string | undefined): string {
  if (!designation) {
    console.log('No designation found, defaulting to engineer');
    return 'engineer'; // Default to engineer if no designation
  }

  const designationLower = designation.toLowerCase().trim();
  
  console.log(`Mapping Zoho designation: "${designation}" (normalized: "${designationLower}")`);

  // Admin/Management roles
  const adminKeywords = [
    'admin', 'administrator', 'manager', 'director', 'head', 'lead', 
    'ceo', 'cto', 'cfo', 'vp', 'vice president', 'president',
    'founder', 'owner', 'principal', 'senior manager', 'general manager'
  ];
  
  // Project Manager roles
  const projectManagerKeywords = [
    'project manager', 'pm', 'program manager', 'product manager',
    'delivery manager', 'project lead', 'project coordinator'
  ];
  
  // Lead roles (senior technical)
  const leadKeywords = [
    'tech lead', 'technical lead', 'team lead', 'senior lead',
    'engineering lead', 'development lead', 'architect', 'senior architect',
    'principal engineer', 'staff engineer', 'senior staff engineer'
  ];
  
  // Engineer roles
  const engineerKeywords = [
    'engineer', 'developer', 'programmer', 'software engineer',
    'dev', 'sde', 'software developer', 'junior engineer', 'associate engineer'
  ];
  
  // Customer/Client roles
  const customerKeywords = [
    'customer', 'client', 'stakeholder', 'external'
  ];

  // Check for admin roles
  if (adminKeywords.some(keyword => designationLower.includes(keyword))) {
    console.log(`Mapped "${designation}" to role: admin`);
    return 'admin';
  }
  
  // Check for project manager roles
  if (projectManagerKeywords.some(keyword => designationLower.includes(keyword))) {
    console.log(`Mapped "${designation}" to role: project_manager`);
    return 'project_manager';
  }
  
  // Check for lead roles
  if (leadKeywords.some(keyword => designationLower.includes(keyword))) {
    console.log(`Mapped "${designation}" to role: lead`);
    return 'lead';
  }
  
  // Check for engineer roles
  if (engineerKeywords.some(keyword => designationLower.includes(keyword))) {
    console.log(`Mapped "${designation}" to role: engineer`);
    return 'engineer';
  }
  
  // Check for customer roles
  if (customerKeywords.some(keyword => designationLower.includes(keyword))) {
    console.log(`Mapped "${designation}" to role: customer`);
    return 'customer';
  }
  
  // Default to engineer if no match found
  console.log(`No match found for "${designation}", defaulting to engineer`);
  return 'engineer';
}

/**
 * GET /api/zoho/auth
 * Get authorization URL to start OAuth flow
 */
router.get('/auth', authenticate, (req, res) => {
  try {
    const userId = (req as any).user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'User not authenticated' });
    }

    const authUrl = zohoService.getAuthorizationUrl(userId.toString());
    res.json({ authUrl, message: 'Redirect user to this URL to authorize' });
  } catch (error: any) {
    console.error('Error generating auth URL:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/zoho/login-auth
 * Get authorization URL for Zoho OAuth login (no authentication required)
 * This is for users who want to login with Zoho
 */
router.get('/login-auth', async (req, res) => {
  try {
    // Generate a temporary state token for login flow
    // In production, you might want to use a more secure state management
    const state = `login_${Date.now()}_${Math.random().toString(36).substring(7)}`;
    
    const authUrl = zohoService.getAuthorizationUrl(state);
    res.json({ 
      authUrl, 
      state,
      message: 'Redirect user to this URL to login with Zoho' 
    });
  } catch (error: any) {
    console.error('Error generating Zoho login auth URL:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/zoho/callback
 * OAuth callback endpoint - receives authorization code
 * Note: This endpoint doesn't require authentication as it's called by Zoho
 * The state parameter can contain user ID or login token
 */
router.get('/callback', async (req, res) => {
  try {
    const { code, error, state } = req.query;

    if (error) {
      return res.status(400).send(`
        <html>
          <head><title>Authorization Error</title></head>
          <body>
            <h1>❌ Authorization Failed</h1>
            <p>Error: ${error}</p>
            <p>Please try again from the application.</p>
          </body>
        </html>
      `);
    }

    if (!code) {
      return res.status(400).send(`
        <html>
          <head><title>Authorization Error</title></head>
          <body>
            <h1>❌ Authorization Code Missing</h1>
            <p>No authorization code received from Zoho.</p>
            <p>Please try again from the application.</p>
          </body>
        </html>
      `);
    }

    // Exchange code for tokens first
    const tokenData = await zohoService.exchangeCodeForToken(code as string);
    
    // Log token data for debugging (without sensitive info)
    console.log('Token data received:', {
      has_access_token: !!tokenData.access_token,
      has_refresh_token: !!tokenData.refresh_token,
      expires_in: tokenData.expires_in,
      expires_in_type: typeof tokenData.expires_in,
      token_type: tokenData.token_type,
      scope: tokenData.scope
    });

    // Check if this is a login flow (state starts with "login_")
    const isLoginFlow = state && (state as string).startsWith('login_');
    
    if (isLoginFlow) {
      // This is a Zoho OAuth login - get user info and create/login user
      try {
        // Ensure refresh token is present for long-term sessions
        if (!tokenData.refresh_token || tokenData.refresh_token.trim() === '') {
          throw new Error('Zoho did not return a refresh_token. Please re-authorize with consent. (Scopes: AaaServer.profile.read, profile, email, ZohoProjects.projects.READ, ZohoProjects.portals.READ, ZohoPeople.people.ALL)');
        }

        // Get user info from Zoho using the access token
        const zohoUserInfo = await zohoService.getZohoUserInfo(tokenData.access_token!);
        
        // Import pool and jwt for user creation/login
        const { pool } = await import('../config/database');
        const jwt = (await import('jsonwebtoken')).default;
        
        // Extract user info from Zoho response
        // Zoho user info structure may vary, try multiple possible fields
        const email = zohoUserInfo.email || zohoUserInfo.Email || zohoUserInfo.mail || zohoUserInfo.Mail;
        const fullName = zohoUserInfo.display_name || zohoUserInfo.Display_Name || 
                        zohoUserInfo.name || zohoUserInfo.Name ||
                        `${zohoUserInfo.first_name || ''} ${zohoUserInfo.last_name || ''}`.trim() ||
                        email?.split('@')[0] || 'Zoho User';

        // Fetch Zoho People record to determine role/designation
        console.log('\n========================================');
        console.log('=== FETCHING ZOHO PEOPLE RECORD ===');
        console.log('Email:', email);
        console.log('========================================\n');
        
        let peopleRecord: any = {};
        let designation = '';
        
        try {
          peopleRecord = await zohoService.getZohoPeopleRecord(tokenData.access_token!, email);
          
          console.log('\n=== ZOHO PEOPLE RECORD RECEIVED ===');
          console.log('Full record:', JSON.stringify(peopleRecord, null, 2));
          console.log('Record keys:', peopleRecord ? Object.keys(peopleRecord) : 'No record');
          console.log('Record type:', Array.isArray(peopleRecord) ? 'Array' : typeof peopleRecord);
          
          // Handle array response (sometimes Zoho returns array)
          if (Array.isArray(peopleRecord) && peopleRecord.length > 0) {
            peopleRecord = peopleRecord[0];
            console.log('Extracted first record from array');
          }
          
          // Try multiple possible field names for designation/role
          designation = peopleRecord?.Designation || 
                       peopleRecord?.designation || 
                       peopleRecord?.Designation_ID?.name ||
                       peopleRecord?.designation_id?.name ||
                       peopleRecord?.Designation_ID?.Designation ||
                       peopleRecord?.designation_id?.designation ||
                       peopleRecord?.Role || 
                       peopleRecord?.role ||
                       peopleRecord?.Job_Title ||
                       peopleRecord?.job_title ||
                       peopleRecord?.Title ||
                       peopleRecord?.title ||
                       peopleRecord?.Job_Role ||
                       peopleRecord?.job_role ||
                       '';
          
          console.log('\n=== EXTRACTED DESIGNATION ===');
          console.log('Designation value:', designation || '(NOT FOUND)');
          console.log('Designation type:', typeof designation);
          console.log('Is empty?', !designation || designation.trim() === '');
        } catch (peopleError: any) {
          console.error('\n❌ ERROR FETCHING ZOHO PEOPLE RECORD:', peopleError.message);
          console.error('This is OK - will use default role mapping');
          designation = ''; // Will default to engineer
        }
        
        const mappedRole = mapZohoRoleToAppRole(designation);
        
        console.log('\n=== ROLE MAPPING RESULT ===');
        console.log('Original designation from Zoho People:', designation || '(empty - not found)');
        console.log('Mapped role:', mappedRole);
        console.log('========================================\n');

        if (!email) {
          throw new Error('Could not retrieve email from Zoho account. Please ensure your Zoho account has an email address.');
        }

        // Check if user exists by email
        let userResult = await pool.query(
          'SELECT * FROM users WHERE email = $1',
          [email]
        );

        let userId: number;
        let user: any;

        if (userResult.rows.length === 0) {
          // Create new user from Zoho
          const username = email.split('@')[0] + '_zoho';
          const insertResult = await pool.query(
            `INSERT INTO users (username, email, password_hash, full_name, role, is_active)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING id, username, email, full_name, role, is_active, created_at`,
            [username, email, 'zoho_oauth_user', fullName || null, mappedRole, true]
          );
          user = insertResult.rows[0];
          userId = user.id;
          console.log('\n=== CREATED NEW USER ===');
          console.log('User ID:', userId);
          console.log('Email:', email);
          console.log('Username:', username);
          console.log('Assigned role:', mappedRole);
          console.log('Designation from Zoho:', designation || '(not found)');
          console.log('=====================================\n');
        } else {
          // User exists, use existing user
          user = userResult.rows[0];
          userId = user.id;
          
          // Update last login, full name, and role
          console.log('\n=== UPDATING EXISTING USER ===');
          console.log('User ID:', userId);
          console.log('Email:', email);
          console.log('Current role in DB:', user.role);
          console.log('New mapped role:', mappedRole);
          console.log('Designation from Zoho:', designation || '(not found)');
          
          // ALWAYS update the role from Zoho People, overwriting any previous role
          await pool.query(
            'UPDATE users SET last_login = NOW(), full_name = COALESCE($1, full_name), role = $2 WHERE id = $3',
            [fullName || null, mappedRole, userId]
          );
          
          // Fetch updated user to get the new role
          const updatedUserResult = await pool.query(
            'SELECT id, username, email, full_name, role, is_active, created_at FROM users WHERE id = $1',
            [userId]
          );
          user = updatedUserResult.rows[0];
          
          console.log('Role after update:', user.role);
          console.log('Logged in existing user:', { userId, email, oldRole: userResult.rows[0].role, newRole: mappedRole, actualRoleInDB: user.role });
          console.log('=====================================\n');
        }

        // Save Zoho tokens for this user
        await zohoService.saveTokens(userId, tokenData);

        // Generate JWT token for our system
        const jwtSecret = process.env.JWT_SECRET || 'your-secret-key';
        const jwtExpiresIn = process.env.JWT_EXPIRES_IN || '7d';
        
        const jwtToken = jwt.sign(
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
        try {
          const { getSSHConnection } = await import('../services/ssh.service');
          await getSSHConnection(user.id);
          console.log(`SSH connection established for user ${user.id} during Zoho login`);
        } catch (err: any) {
          console.error(`Failed to establish SSH connection for user ${user.id} during Zoho login:`, err);
          // Don't fail login if SSH connection fails
        }

        // Return success page with token (for frontend to capture)
        return res.send(`
          <html>
            <head>
              <title>Zoho Login Success</title>
              <style>
                body {
                  font-family: Arial, sans-serif;
                  display: flex;
                  justify-content: center;
                  align-items: center;
                  height: 100vh;
                  margin: 0;
                  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                }
                .container {
                  background: white;
                  padding: 40px;
                  border-radius: 16px;
                  box-shadow: 0 10px 40px rgba(0,0,0,0.2);
                  text-align: center;
                  max-width: 400px;
                }
                h1 { color: #4caf50; margin-bottom: 20px; }
                p { color: #666; margin-bottom: 30px; }
                .token-info {
                  background: #f5f5f5;
                  padding: 15px;
                  border-radius: 8px;
                  margin: 20px 0;
                  font-size: 12px;
                  word-break: break-all;
                }
              </style>
            </head>
            <body>
              <div class="container">
                <h1>✅ Login Successful!</h1>
                <p>You have successfully logged in with Zoho.</p>
                <p>You can close this window and return to the application.</p>
                <script>
                  // Store token in localStorage and notify parent window
                  const token = '${jwtToken}';
                  const user = ${JSON.stringify(user)};
                  
                  console.log('Zoho login callback - Token received:', token ? 'Yes' : 'No');
                  console.log('Zoho login callback - User data:', user);
                  console.log('Zoho login callback - User role:', user?.role);
                  console.log('Zoho login callback - Has window.opener:', !!window.opener);
                  
                  if (window.opener) {
                    console.log('Sending postMessage to parent window...');
                    try {
                      window.opener.postMessage({
                        type: 'ZOHO_LOGIN_SUCCESS',
                        token: token,
                        user: user
                      }, '*');
                      console.log('postMessage sent successfully');
                      setTimeout(() => {
                        console.log('Closing popup window...');
                        window.close();
                      }, 2000);
                    } catch (e) {
                      console.error('Error sending postMessage:', e);
                      // Fallback to localStorage
                      localStorage.setItem('zoho_login_token', token);
                      localStorage.setItem('zoho_login_user', JSON.stringify(user));
                    }
                  } else {
                    console.log('No window.opener, using localStorage fallback');
                    // If no opener, store in localStorage and show message
                    localStorage.setItem('zoho_login_token', token);
                    localStorage.setItem('zoho_login_user', JSON.stringify(user));
                    document.body.innerHTML = '<div class="container"><h1>✅ Login Successful!</h1><p>Token saved. Please return to the application and refresh the page.</p><p>If the application does not detect your login automatically, please copy the token from browser console.</p></div>';
                  }
                </script>
              </div>
            </body>
          </html>
        `);
      } catch (error: any) {
        console.error('Error in Zoho login flow:', error);
        return res.status(500).send(`
          <html>
            <head><title>Login Error</title></head>
            <body>
              <h1>❌ Login Failed</h1>
              <p>${error.message}</p>
              <p>Please try again.</p>
            </body>
          </html>
        `);
      }
    } else {
      // Regular OAuth flow - state contains user ID
      if (!state) {
        return res.status(400).send(`
          <html>
            <head><title>Authorization Error</title></head>
            <body>
              <h1>❌ Invalid Request</h1>
              <p>State parameter missing. Please initiate OAuth from the application.</p>
            </body>
          </html>
        `);
      }

      const userId = parseInt(state as string, 10);
      if (isNaN(userId)) {
        return res.status(400).send(`
          <html>
            <head><title>Authorization Error</title></head>
            <body>
              <h1>❌ Invalid User ID</h1>
              <p>Invalid user ID in state parameter.</p>
              <p>Please try again from the application.</p>
            </body>
          </html>
        `);
      }

      // Require refresh token for regular connect flow
      console.log(`[ZOHO CALLBACK] Processing regular OAuth flow for user ${userId}`);
      console.log(`[ZOHO CALLBACK] Token data check:`, {
        has_access_token: !!tokenData.access_token,
        has_refresh_token: !!tokenData.refresh_token,
        refresh_token_length: tokenData.refresh_token?.length || 0
      });
      
      if (!tokenData.refresh_token || tokenData.refresh_token.trim() === '') {
        console.error(`[ZOHO CALLBACK] ERROR: No refresh_token received for user ${userId}`);
        throw new Error('Zoho did not return a refresh_token. Please re-authorize with consent. (Scopes: AaaServer.profile.read, profile, email, ZohoProjects.projects.READ, ZohoProjects.portals.READ, ZohoPeople.people.ALL)');
      }

      // Save tokens to database
      console.log(`[ZOHO CALLBACK] Attempting to save tokens for user ${userId}`);
      try {
        await zohoService.saveTokens(userId, tokenData);
        console.log(`[ZOHO CALLBACK] ✅ Successfully saved tokens for user ${userId}`);
      } catch (saveError: any) {
        console.error(`[ZOHO CALLBACK] ❌ Failed to save tokens for user ${userId}:`, saveError.message);
        throw saveError;
      }

      // Redirect to success page or return success response
      return res.send(`
        <html>
          <head><title>Zoho Authorization Success</title></head>
          <body>
            <h1>✅ Authorization Successful!</h1>
            <p>You have successfully connected your Zoho Projects account.</p>
            <p>You can close this window and return to the application.</p>
            <script>
              setTimeout(() => {
                window.close();
              }, 3000);
            </script>
          </body>
        </html>
      `);
    }
  } catch (error: any) {
    console.error('Error in OAuth callback:', error);
    res.status(500).send(`
      <html>
        <head><title>Authorization Error</title></head>
        <body>
          <h1>❌ Authorization Failed</h1>
          <p>${error.message}</p>
          <p>Please try again.</p>
        </body>
      </html>
    `);
  }
});

/**
 * GET /api/zoho/status
 * Check if user has valid Zoho token
 */
router.get('/status', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const hasToken = await zohoService.hasValidToken(userId);
    
    // Get token expiration details
    let tokenInfo = null;
    if (hasToken) {
      const { pool } = await import('../config/database');
      const result = await pool.query(
        'SELECT expires_at, created_at, updated_at FROM zoho_tokens WHERE user_id = $1',
        [userId]
      );
      
      if (result.rows.length > 0) {
        const token = result.rows[0];
        const expiresAt = new Date(token.expires_at);
        const now = new Date();
        const timeUntilExpiry = expiresAt.getTime() - now.getTime();
        const minutesUntilExpiry = Math.floor(timeUntilExpiry / (1000 * 60));
        const secondsUntilExpiry = Math.floor((timeUntilExpiry % (1000 * 60)) / 1000);
        
        tokenInfo = {
          expires_at: token.expires_at,
          expires_at_readable: expiresAt.toISOString(),
          time_until_expiry_minutes: minutesUntilExpiry,
          time_until_expiry_seconds: secondsUntilExpiry,
          will_auto_refresh: minutesUntilExpiry < 5,
          created_at: token.created_at,
          updated_at: token.updated_at
        };
      }
    }
    
    res.json({ 
      connected: hasToken,
      message: hasToken ? 'Zoho Projects is connected' : 'Zoho Projects is not connected',
      token_info: tokenInfo
    });
  } catch (error: any) {
    console.error('Error checking Zoho status:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/zoho/portals
 * Get all portals (workspaces) from Zoho Projects
 */
router.get('/portals', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const portals = await zohoService.getPortals(userId);
    res.json(portals);
  } catch (error: any) {
    console.error('Error fetching portals:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/zoho/people/test
 * Test Zoho People lookup for a given email (defaults to current user's email)
 */
router.get('/people/test', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const currentEmail = (req as any).user?.email;
    const email = (req.query.email as string) || currentEmail;

    if (!email) {
      return res.status(400).json({ error: 'Email is required to test Zoho People lookup' });
    }

    // Get a valid access token for the user
    const accessToken = await zohoService.getValidAccessToken(userId);

    // Fetch people record
    const record = await zohoService.getZohoPeopleRecord(accessToken, email);

    res.json({
      success: true,
      email,
      record,
    });
  } catch (error: any) {
    console.error('Error fetching Zoho People record:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/zoho/people/employees
 * Fetch employees list from Zoho People (paginated)
 * Query params: page (default 1), perPage (default 200)
 */
router.get('/people/employees', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const page = parseInt((req.query.page as string) || '1', 10);
    const perPage = parseInt((req.query.perPage as string) || '200', 10);

    const accessToken = await zohoService.getValidAccessToken(userId);
    const employees = await zohoService.getZohoPeopleEmployees(accessToken, page, perPage);

    res.json({
      success: true,
      page,
      perPage,
      count: employees.length,
      employees,
    });
  } catch (error: any) {
    console.error('Error fetching Zoho People employees:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/zoho/projects
 * Get all projects from Zoho Projects
 */
router.get('/projects', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { portalId } = req.query;
    
    const projects = await zohoService.getProjects(
      userId, 
      portalId as string | undefined
    );
    
    res.json({
      success: true,
      count: projects.length,
      projects: projects.map(project => ({
        id: project.id,
        name: project.name,
        description: project.description,
        status: project.status,
        start_date: project.start_date,
        end_date: project.end_date,
        owner_name: project.owner_name,
        created_time: project.created_time,
        source: 'zoho',
        // Include full project data for reference
        raw: project
      }))
    });
  } catch (error: any) {
    console.error('Error fetching Zoho projects:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

/**
 * GET /api/zoho/projects/:projectId
 * Get single project details from Zoho Projects
 */
router.get('/projects/:projectId', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { projectId } = req.params;
    const { portalId } = req.query;
    
    const project = await zohoService.getProject(
      userId,
      projectId,
      portalId as string | undefined
    );
    
    res.json({
      success: true,
      project: {
        id: project.id,
        name: project.name,
        description: project.description,
        status: project.status,
        start_date: project.start_date,
        end_date: project.end_date,
        owner_name: project.owner_name,
        created_time: project.created_time,
        source: 'zoho',
        raw: project
      }
    });
  } catch (error: any) {
    console.error('Error fetching Zoho project:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

/**
 * GET /api/zoho/projects/:projectId/tasks
 * Get all tasks for a Zoho project (including subtasks)
 */
router.get('/projects/:projectId/tasks', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { projectId } = req.params;
    const { portalId } = req.query;
    
    // Extract actual project ID if it's prefixed with "zoho_"
    const actualProjectId = projectId.startsWith('zoho_') 
      ? projectId.replace('zoho_', '') 
      : projectId;
    
    const tasks = await zohoService.getTasks(
      userId,
      actualProjectId,
      portalId as string | undefined
    );
    
    // Log response structure for debugging
    const tasksWithSubtasks = tasks.filter(t => t.subtasks && Array.isArray(t.subtasks) && t.subtasks.length > 0);
    console.log(`📤 Sending ${tasks.length} tasks to frontend, ${tasksWithSubtasks.length} have subtasks`);
    if (tasksWithSubtasks.length > 0) {
      tasksWithSubtasks.forEach((task, idx) => {
        console.log(`   Task ${idx + 1}: "${task.name || task.task_name}" has ${task.subtasks.length} subtasks`);
      });
    }
    
    res.json({
      success: true,
      count: tasks.length,
      tasks: tasks
    });
  } catch (error: any) {
    console.error('Error fetching Zoho tasks:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

/**
 * GET /api/zoho/projects/:projectId/milestones
 * Get all milestones for a Zoho project
 */
router.get('/projects/:projectId/milestones', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { projectId } = req.params;
    const { portalId } = req.query;
    
    // Extract actual project ID if it's prefixed with "zoho_"
    const actualProjectId = projectId.startsWith('zoho_') 
      ? projectId.replace('zoho_', '') 
      : projectId;
    
    const milestones = await zohoService.getMilestones(
      userId,
      actualProjectId,
      portalId as string | undefined
    );
    
    console.log(`📤 Route: Returning ${milestones.length} milestones to frontend`);
    if (milestones.length > 0) {
      console.log(`📋 Route: Sample milestone keys:`, Object.keys(milestones[0]));
    }
    
    res.json({
      success: true,
      count: milestones.length,
      milestones: milestones
    });
  } catch (error: any) {
    console.error('Error fetching Zoho milestones:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

/**
 * POST /api/zoho/disconnect
 * Revoke and remove Zoho tokens
 */
router.post('/disconnect', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    await zohoService.revokeTokens(userId);
    
    res.json({ 
      success: true,
      message: 'Zoho Projects disconnected successfully' 
    });
  } catch (error: any) {
    console.error('Error disconnecting Zoho:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

