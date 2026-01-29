import express from 'express';
import jwt, { SignOptions } from 'jsonwebtoken';
import zohoService from '../services/zoho.service';
import { authenticate, authorize } from '../middleware/auth.middleware';
import { pool } from '../config/database';

const router = express.Router();

// Map Zoho People designation/role to app role
function mapZohoRoleToAppRole(designation: string | undefined): string {
  if (!designation) {
    console.log('No designation found, defaulting to engineer');
    return 'engineer'; // Default to engineer if no designation
  }

  const designationLower = designation.toLowerCase().trim();

  // Admin/Management roles - These roles should have full admin access matching DB admin role
  // Note: Check AFTER project_manager to avoid conflicts (project manager is more specific)
  const adminKeywords = [
    'admin', 'administrator', 'director', 'head of', 'head',
    'ceo', 'cto', 'cfo', 'vp', 'vice president', 'president',
    'founder', 'owner', 'principal', 'senior manager', 'general manager',
    'executive', 'exec', 'chief', 'head of department', 'department head',
    'manager' // General manager (not project manager - checked first)
  ];
  
  // Project Manager roles - Check FIRST (more specific than general manager)
  const projectManagerKeywords = [
    'project manager', 'pm', 'program manager', 'product manager',
    'delivery manager', 'project lead', 'project coordinator'
  ];
  
  // Lead roles (senior technical) - Check after admin to avoid conflicts
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

  // Check for project manager roles FIRST (more specific than general manager/admin)
  if (projectManagerKeywords.some(keyword => designationLower.includes(keyword))) {
    console.log(`Mapped "${designation}" to role: project_manager`);
    return 'project_manager';
  }
  
  // Check for admin roles (after project_manager to avoid conflicts)
  if (adminKeywords.some(keyword => designationLower.includes(keyword))) {
    console.log(`Mapped "${designation}" to role: admin`);
    return 'admin';
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
 * Get authorization URL to start OAuth flow (admin only; non-admin use Zoho only for login)
 */
router.get('/auth', authenticate, authorize('admin'), (req, res) => {
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
    const { code, error, state, error_description } = req.query;

    if (error) {
      return res.status(400).send(`
        <html>
          <head><title>Authorization Error</title></head>
          <body>
            <h1>❌ Authorization Failed</h1>
            <p>Error: ${error}</p>
            ${error_description ? `<p>Description: ${error_description}</p>` : ''}
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
        
        // Extract user info from Zoho response (email and name only - no role from Zoho for non-admin)
        const email = zohoUserInfo.email || zohoUserInfo.Email || zohoUserInfo.mail || zohoUserInfo.Mail;
        const fullName = zohoUserInfo.display_name || zohoUserInfo.Display_Name ||
                        zohoUserInfo.name || zohoUserInfo.Name ||
                        `${zohoUserInfo.first_name || ''} ${zohoUserInfo.last_name || ''}`.trim() ||
                        email?.split('@')[0] || 'Zoho User';

        if (!email) {
          throw new Error('Could not retrieve email from Zoho account. Please ensure your Zoho account has an email address.');
        }

        // Check if user exists by email - role is always from DB / user_projects, never from Zoho
        const userResult = await pool.query(
          'SELECT * FROM users WHERE email = $1',
          [email]
        );

        let userId: number;
        let user: any;

        if (userResult.rows.length === 0) {
          // Create new user: default role 'engineer'; admin assigns projects/roles via user_projects
          const username = email.split('@')[0] + '_zoho';
          const insertResult = await pool.query(
            `INSERT INTO users (username, email, password_hash, full_name, role, is_active)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING id, username, email, full_name, role, is_active, created_at`,
            [username, email, 'zoho_oauth_user', fullName || null, 'engineer', true]
          );
          user = insertResult.rows[0];
          userId = user.id;
        } else {
          // Existing user: keep DB role; do not overwrite from Zoho
          user = userResult.rows[0];
          userId = user.id;
          await pool.query(
            'UPDATE users SET last_login = NOW(), full_name = COALESCE($1, full_name) WHERE id = $2',
            [fullName || null, userId]
          );
          user = (await pool.query(
            'SELECT id, username, email, full_name, role, is_active, created_at FROM users WHERE id = $1',
            [userId]
          )).rows[0];
        }

        // Global role = users table only. Project-based role = user_projects only (resolved per-request in APIs).
        const globalRole = user.role;

        // Save Zoho tokens for this user
        await zohoService.saveTokens(userId, tokenData);

        // Generate JWT token for our system (role = users.role, not a mix of user_projects)
        const jwtSecret = process.env.JWT_SECRET || 'your-secret-key';
        const jwtExpiresIn = process.env.JWT_EXPIRES_IN || '7d';
        
        const jwtToken = jwt.sign(
          {
            id: user.id,
            username: user.username,
            email: user.email,
            role: globalRole
          },
          jwtSecret,
          { expiresIn: jwtExpiresIn } as SignOptions
        );

        // Establish SSH connection in background (non-blocking) to avoid login delay
        const { getSSHConnection } = await import('../services/ssh.service');
        getSSHConnection(user.id).then(() => {
          // SSH connection established in background
        }).catch((err: any) => {
          console.error(`Failed to establish SSH connection for user ${user.id} (background, Zoho login):`, err);
          // Connection will be retried when user actually needs SSH functionality
        });

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
                  
                  if (window.opener) {
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
      if (!tokenData.refresh_token || tokenData.refresh_token.trim() === '') {
        console.error(`[ZOHO CALLBACK] ERROR: No refresh_token received for user ${userId}`);
        throw new Error('Zoho did not return a refresh_token. Please re-authorize with consent. (Scopes: AaaServer.profile.read, profile, email, ZohoProjects.projects.READ, ZohoProjects.portals.READ, ZohoPeople.people.ALL)');
      }

      // Save tokens to database
      try {
        await zohoService.saveTokens(userId, tokenData);
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
 * Get all portals (workspaces) from Zoho Projects (admin only; non-admin use DB only)
 */
router.get('/portals', authenticate, authorize('admin'), async (req, res) => {
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
 * Get all projects from Zoho Projects (admin only; non-admin use DB only, Zoho is for auth only)
 */
router.get('/projects', authenticate, authorize('admin'), async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { portalId } = req.query;
    
    const projects = await zohoService.getProjects(
      userId, 
      portalId as string | undefined
    );
    
    // Get SSH username for run directory lookup
    let userUsername: string | null = null;
    if (userId) {
      try {
        const { executeSSHCommand } = await import('../services/ssh.service');
        const whoamiResult = await executeSSHCommand(userId, 'whoami', 1);
        if (whoamiResult.stdout && whoamiResult.stdout.trim()) {
          userUsername = whoamiResult.stdout.trim();
        }
      } catch (e) {
        // If SSH command fails, try to get from database
        try {
          const zohoRunResult = await pool.query(
            `SELECT DISTINCT user_name 
             FROM zoho_project_run_directories 
             WHERE user_id = $1 AND user_name IS NOT NULL
             ORDER BY updated_at DESC, created_at DESC
             LIMIT 1`,
            [userId]
          );
          if (zohoRunResult.rows.length > 0 && zohoRunResult.rows[0].user_name) {
            userUsername = zohoRunResult.rows[0].user_name;
          }
        } catch (dbError) {
          // Silent fallback
        }
      }
    }
    
    // Get portal ID for export status check
    let currentPortalId = portalId as string | undefined;
    if (!currentPortalId) {
      try {
        const portals = await zohoService.getPortals(userId);
        if (portals.length > 0) {
          currentPortalId = portals[0].id;
        }
      } catch (e) {
        console.log('Could not get portal ID for export status check:', e);
      }
    }

    const projectsWithMembers = await Promise.all(
      projects.map(async (project) => {
        try {
          // Get project members (roles table)
          const members = await zohoService.getProjectMembers(
            userId,
            project.id || project.id_string,
            portalId as string | undefined
          );
          
          // Helper function to extract role name from role object/string
          const extractRoleName = (role: any): string => {
            if (!role) return 'Employee';
            if (typeof role === 'string') return role;
            if (typeof role === 'object') {
              return role.name || role.role || role.designation || role.value || role.label || role.title || 'Employee';
            }
            return String(role);
          };
          
          // Helper function to extract status
          const extractStatus = (status: any): string => {
            if (!status) return 'active';
            if (typeof status === 'string') return status;
            if (status === 1 || status === '1' || status === true) return 'active';
            if (status === 0 || status === '0' || status === false) return 'inactive';
            return String(status);
          };
          
          // Format members with proper role extraction
          // Prioritize project_profile first as it contains the correct role for the project
          const formattedMembers = members.map(m => {
            const roleName = extractRoleName(m.project_profile || m.role || m.project_role || m.role_in_project);
            const status = extractStatus(m.status);
            return {
              id: m.id || m.zpuid || m.zuid,
              name: m.name || `${m.first_name || ''} ${m.last_name || ''}`.trim() || m.email?.split('@')[0] || 'Unknown',
              email: m.email || m.Email || m.mail || 'N/A',
              role: roleName,
              role_mapped: zohoService.mapZohoProjectRoleToAppRole(roleName),
              status: status,
              first_name: m.first_name,
              last_name: m.last_name,
              zpuid: m.zpuid,
              zuid: m.zuid
            };
          });
          
          // Check export status from zoho_project_exports table
          // This should be visible to all users who have access to the project
          let exportedToLinux = false;
          try {
            const projectIdStr = project.id?.toString() || project.id_string?.toString() || '';
            // Try with portal_id first, then without portal_id (for projects exported without portal_id)
            const exportResult = await pool.query(
              `SELECT exported_to_linux FROM zoho_project_exports 
               WHERE zoho_project_id = $1 
               AND (portal_id = $2 OR portal_id IS NULL) 
               ORDER BY 
                 CASE WHEN portal_id = $2 THEN 1 ELSE 2 END,
                 portal_id DESC NULLS LAST 
               LIMIT 1`,
              [projectIdStr, currentPortalId]
            );
            if (exportResult.rows.length > 0) {
              exportedToLinux = exportResult.rows[0].exported_to_linux === true;
            } else {
              // Also try without portal_id constraint to catch exports that might not have portal_id set
              const exportResultNoPortal = await pool.query(
                'SELECT exported_to_linux FROM zoho_project_exports WHERE zoho_project_id = $1 ORDER BY exported_at DESC LIMIT 1',
                [projectIdStr]
              );
              if (exportResultNoPortal.rows.length > 0) {
                exportedToLinux = exportResultNoPortal.rows[0].exported_to_linux === true;
              }
            }
          } catch (e) {
            // If table doesn't exist or query fails, continue without export status
          }
          
          // Get ALL run directories for this Zoho project (by logged-in user_id)
          let zohoRunDirectories: string[] = [];
          if (userId) {
            try {
              const zohoRunDirResult = await pool.query(
                `SELECT run_directory, user_name, zoho_project_id, zoho_project_name, block_name, experiment_name, user_id, updated_at, created_at
                 FROM zoho_project_run_directories 
                 WHERE (zoho_project_id = $1 OR LOWER(zoho_project_name) = LOWER($2))
                   AND user_id = $3
                 ORDER BY updated_at DESC, created_at DESC`,
                [(project.id || project.id_string).toString(), project.name, userId]
              );
              
              if (zohoRunDirResult.rows.length > 0) {
                zohoRunDirectories = zohoRunDirResult.rows
                  .filter(row => row.run_directory)
                  .map(row => row.run_directory);
              }
            } catch (runDirError) {
              // Silent error handling
            }
          }
          
          return {
            id: project.id,
            name: project.name,
            description: project.description,
            status: project.status,
            start_date: project.start_date,
            end_date: project.end_date,
            owner_name: project.owner_name,
            owner_id: project.owner_id,
            owner_email: project.owner_email,
            created_time: project.created_time,
            source: 'zoho',
            zoho_project_id: project.id, // Add zoho_project_id field for consistency
            exported_to_linux: exportedToLinux, // Add export status flag
            portal_id: currentPortalId, // Include portal ID
            run_directory: zohoRunDirectories.length > 0 ? zohoRunDirectories[0] : null, // Latest run directory (for backward compatibility)
            run_directories: zohoRunDirectories, // All run directories for the logged-in user
            // Include roles/members table with properly formatted data
            members: formattedMembers,
            roles: formattedMembers.map(m => ({
              name: m.name,
              email: m.email,
              role: m.role,
              role_mapped: m.role_mapped,
              status: m.status,
              id: m.id
            })),
            // Include full project data for reference
            raw: project
          };
        } catch (memberError: any) {
          console.error(`   ❌ Error fetching members for project ${project.name}:`, memberError.message);
          // Return project without members if fetch fails
          return {
            id: project.id,
            name: project.name,
            description: project.description,
            status: project.status,
            start_date: project.start_date,
            end_date: project.end_date,
            owner_name: project.owner_name,
            owner_id: project.owner_id,
            owner_email: project.owner_email,
            created_time: project.created_time,
            source: 'zoho',
            zoho_project_id: project.id, // Add zoho_project_id field for consistency
            exported_to_linux: false, // Default to false on error
            portal_id: currentPortalId,
            members: [],
            roles: [],
            raw: project
          };
        }
      })
    );
    
    console.log('\n========================================\n');
    
    res.json({
      success: true,
      count: projectsWithMembers.length,
      projects: projectsWithMembers
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
 * Helper: resolve a single domain id from code or id.
 */
async function resolveOneDomainId(domainCode?: string | null, domainId?: number | null): Promise<number | null> {
  if (domainId != null) {
    const byId = await pool.query('SELECT id FROM domains WHERE id = $1 AND is_active = true', [domainId]);
    if (byId.rows.length > 0) return byId.rows[0].id;
  }
  if (domainCode && String(domainCode).trim()) {
    const code = String(domainCode).trim().toUpperCase();
    const byCode = await pool.query('SELECT id FROM domains WHERE UPPER(code) = $1 AND is_active = true', [code]);
    if (byCode.rows.length > 0) return byCode.rows[0].id;
  }
  return null;
}

/**
 * Resolve multiple domain ids from request only (no default). From arrays or single domainCode/domainId.
 */
async function resolveDomainIdsFromRequest(opts: {
  domainCodes?: string[] | string | null;
  domainIds?: number[] | number | null;
  domainCode?: string | null;
  domainId?: number | null;
}): Promise<number[]> {
  const ids: number[] = [];
  const seen = new Set<number>();
  const rawIds = Array.isArray(opts.domainIds) ? opts.domainIds : opts.domainIds != null ? [opts.domainIds] : [];
  for (const id of rawIds) {
    const resolved = await resolveOneDomainId(null, id);
    if (resolved != null && !seen.has(resolved)) { seen.add(resolved); ids.push(resolved); }
  }
  const rawCodes = Array.isArray(opts.domainCodes) ? opts.domainCodes : opts.domainCodes != null && typeof opts.domainCodes === 'string' ? [opts.domainCodes] : [];
  for (const code of rawCodes) {
    const resolved = await resolveOneDomainId(code, null);
    if (resolved != null && !seen.has(resolved)) { seen.add(resolved); ids.push(resolved); }
  }
  if (ids.length === 0 && (opts.domainCode != null || opts.domainId != null)) {
    const one = await resolveOneDomainId(opts.domainCode ?? undefined, opts.domainId ?? undefined);
    if (one != null) ids.push(one);
  }
  return ids;
}

/**
 * Fetch domains from Zoho the same way as project plan: get tasks via getTasks (which has fallback to projects list), extract tasklist_name from each task, map to our domain ids.
 */
async function getDomainIdsFromZohoTasklists(userId: number, zohoProjectId: string, portalId?: string): Promise<number[]> {
  try {
    const tasks = await zohoService.getTasks(userId, zohoProjectId, portalId || undefined);
    const tasklistNames = new Set<string>();
    for (const task of tasks) {
      const name = (task.tasklist_name ?? task.tasklistName ?? '').toString().trim();
      if (name) tasklistNames.add(name);
    }
    if (tasklistNames.size === 0) {
      console.log('[Sync Projects] No tasklist names from Zoho tasks for project', zohoProjectId);
      return [];
    }
    console.log('[Sync Projects] Zoho tasklists (domains) from tasks:', [...tasklistNames].join(', '));
    const domainIds: number[] = [];
    const seen = new Set<number>();
    for (const tasklistName of tasklistNames) {
      const did = await domainIdFromTasklistName(tasklistName);
      if (did != null && !seen.has(did)) {
        seen.add(did);
        domainIds.push(did);
      } else if (!did) {
        console.log('[Sync Projects] No matching domain for tasklist:', tasklistName);
      }
    }
    return domainIds;
  } catch (e: any) {
    console.warn('[Sync Projects] Failed to get domains from Zoho tasks (project plan logic):', e.message);
    return [];
  }
}

/**
 * Extract technology_node, start_date, target_date from Zoho project. Uses same logic as project list (project.routes).
 * Logs Zoho field names and values. Returns { technology_node, start_date, target_date } for DB (dates as YYYY-MM-DD or null).
 */
function extractZohoProjectDetails(zohoProject: any): { technology_node: string | null; start_date: string | null; target_date: string | null } {
  const keys = zohoProject ? Object.keys(zohoProject) : [];
  console.log('[Sync Projects] Zoho project keys:', keys.join(', '));

  let technology_node: string | null = null;
  if (zohoProject?.technology_node) {
    technology_node = String(zohoProject.technology_node).trim();
  } else if (zohoProject?.technology) {
    technology_node = String(zohoProject.technology).trim();
  } else if (zohoProject?.technologyNode) {
    technology_node = String(zohoProject.technologyNode).trim();
  } else if (zohoProject?.technology_code) {
    technology_node = String(zohoProject.technology_code).trim();
  } else if (zohoProject?.['Technology Node']) {
    technology_node = String(zohoProject['Technology Node']).trim();
  } else if (zohoProject?.['technology node']) {
    technology_node = String(zohoProject['technology node']).trim();
  }
  const customFields = zohoProject?.custom_fields;
  if (!technology_node && Array.isArray(customFields)) {
    for (const f of customFields) {
      if (f && typeof f === 'object') {
        const val = f.technology_node ?? f.technologyNode ?? f.technology ?? f.value ?? f.content;
        if (val != null && String(val).trim()) {
          technology_node = String(val).trim();
          break;
        }
        const label = (f?.label ?? f?.name ?? f?.field_name ?? '').toLowerCase();
        if ((label.includes('technology') || label.includes('node')) && (f.value ?? f.content) != null) {
          technology_node = String(f.value ?? f.content).trim();
          break;
        }
        for (const k of Object.keys(f)) {
          if (k.toLowerCase().includes('technology') && f[k]) {
            technology_node = String(f[k]).trim();
            break;
          }
        }
        if (technology_node) break;
      }
    }
  }
  if (!technology_node && typeof customFields === 'object' && !Array.isArray(customFields)) {
    for (const k of Object.keys(customFields)) {
      if ((k.toLowerCase().includes('technology') || k.toLowerCase().includes('node')) && customFields[k]) {
        technology_node = String(customFields[k]).trim();
        break;
      }
    }
  }
  if (!technology_node && zohoProject) {
    for (const key of Object.keys(zohoProject)) {
      const keyLower = key.toLowerCase();
      if ((keyLower.includes('technology') || (keyLower.includes('tech') && keyLower.includes('node'))) && zohoProject[key]) {
        technology_node = String(zohoProject[key]).trim();
        break;
      }
    }
  }
  console.log('[Sync Projects] Zoho technology_node:', technology_node ?? '(not found)');

  // Start date: try common Zoho field names and custom_fields by label
  let startRaw =
    zohoProject?.start_date ??
    zohoProject?.start_date_format ??
    zohoProject?.Start_Date ??
    zohoProject?.start_date_long ??
    zohoProject?.start_time ??
    zohoProject?.begin_date ??
    zohoProject?.planned_start ??
    zohoProject?.created_time;
  // End/target date: try common Zoho field names
  let endRaw =
    zohoProject?.end_date ??
    zohoProject?.end_date_format ??
    zohoProject?.End_Date ??
    zohoProject?.target_date ??
    zohoProject?.end_date_long ??
    zohoProject?.due_date ??
    zohoProject?.deadline ??
    zohoProject?.end_time ??
    zohoProject?.planned_end ??
    zohoProject?.completion_date;

  // Search custom_fields for date-like fields by label (reuse customFields from above)
  if ((!startRaw || !endRaw) && (Array.isArray(customFields) || (typeof customFields === 'object' && customFields))) {
    const arr = Array.isArray(customFields) ? customFields : [customFields];
    for (const f of arr) {
      if (!f || typeof f !== 'object') continue;
      const label = (f.label ?? f.name ?? f.field_name ?? '').toString().toLowerCase();
      const val = f.value ?? f.content ?? f.date_value;
      if (val == null) continue;
      if (!startRaw && (label.includes('start') || label.includes('begin') || label === 'start date')) {
        startRaw = val;
        break;
      }
    }
    for (const f of arr) {
      if (!f || typeof f !== 'object') continue;
      const label = (f.label ?? f.name ?? f.field_name ?? '').toString().toLowerCase();
      const val = f.value ?? f.content ?? f.date_value;
      if (val == null) continue;
      if (!endRaw && (label.includes('end') || label.includes('target') || label.includes('due') || label.includes('deadline') || label === 'end date' || label === 'target date')) {
        endRaw = val;
        break;
      }
    }
  }
  // Fallback: any top-level key containing "start" or "end"/"target"/"due"
  if (!startRaw && zohoProject) {
    for (const key of Object.keys(zohoProject)) {
      const k = key.toLowerCase();
      if ((k.includes('start') || k.includes('begin')) && (zohoProject[key] != null)) {
        startRaw = zohoProject[key];
        break;
      }
    }
  }
  if (!endRaw && zohoProject) {
    for (const key of Object.keys(zohoProject)) {
      const k = key.toLowerCase();
      if ((k.includes('end') || k.includes('target') || k.includes('due') || k.includes('deadline')) && (zohoProject[key] != null)) {
        endRaw = zohoProject[key];
        break;
      }
    }
  }

  console.log('[Sync Projects] Zoho start_date (start_date, start_date_format, created_time, custom_fields, etc.):', startRaw ?? '(not found)');
  console.log('[Sync Projects] Zoho end_date / target_date (end_date, target_date, deadline, due_date, custom_fields, etc.):', endRaw ?? '(not found)');

  const toDate = (v: any): string | null => {
    if (v == null && v !== 0) return null;
    if (typeof v === 'number') {
      const d = new Date(v < 1e12 ? v * 1000 : v);
      if (!Number.isNaN(d.getTime())) return d.toISOString().slice(0, 10);
      return null;
    }
    const s = String(v).trim();
    if (!s) return null;
    const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (m) return `${m[1]}-${m[2]}-${m[3]}`;
    const d = new Date(s);
    if (!Number.isNaN(d.getTime())) return d.toISOString().slice(0, 10);
    return null;
  };

  return {
    technology_node: technology_node || null,
    start_date: toDate(startRaw),
    target_date: toDate(endRaw),
  };
}

/**
 * Map Zoho tasklist name to our domain id (match by domain name or code).
 */
async function domainIdFromTasklistName(tasklistName: string): Promise<number | null> {
  if (!tasklistName || !String(tasklistName).trim()) return null;
  const name = String(tasklistName).trim();
  const normalized = name.toLowerCase();
  const byCode = await pool.query(
    'SELECT id FROM domains WHERE is_active = true AND (LOWER(code) = $1 OR LOWER(TRIM(name)) = $1) LIMIT 1',
    [normalized]
  );
  if (byCode.rows.length > 0) return byCode.rows[0].id;
  const byNameLike = await pool.query(
    'SELECT id FROM domains WHERE is_active = true AND (LOWER(TRIM(name)) LIKE $1 OR LOWER(code) LIKE $1) LIMIT 1',
    [`%${normalized}%`]
  );
  return byNameLike.rows.length > 0 ? byNameLike.rows[0].id : null;
}

/**
 * True if the tasklist is PD (Physical Design). Only PD tasklist tasks are synced as blocks; DV and others are skipped.
 */
function isPDTasklist(tasklistName: string | null | undefined): boolean {
  if (!tasklistName || !String(tasklistName).trim()) return false;
  const name = String(tasklistName).trim().toLowerCase();
  return (
    name.includes('pd') ||
    name.includes('physical') ||
    name.includes('physical design')
  );
}

/**
 * Sync blocks and block-to-user assignments from Zoho tasks (same mapping as UI: task = block, task owner = assigned user).
 * Only tasks under the PD tasklist are added as blocks; DV and other tasklists are skipped.
 * Call when admin does Sync Projects.
 */
async function syncBlocksAndBlockUsers(
  asiProjectId: number,
  zohoProjectId: string,
  portalId: string | undefined,
  userId: number
): Promise<{ blocksUpserted: number; assignmentsUpserted: number; errors: string[] }> {
  const errors: string[] = [];
  let blocksUpserted = 0;
  let assignmentsUpserted = 0;
  try {
    const tasks = await zohoService.getTasks(userId, zohoProjectId, portalId);
    if (tasks.length === 0) {
      console.log('[Sync Projects] No Zoho tasks for project', zohoProjectId, '- skipping blocks sync');
      return { blocksUpserted: 0, assignmentsUpserted: 0, errors: [] };
    }
    const blockUsersExists = await pool.query(
      `SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'block_users')`
    );
    const hasBlockUsersTable = blockUsersExists.rows[0]?.exists === true;
    for (const task of tasks) {
      const tasklistName = (task.tasklist_name ?? task.tasklistName ?? '').toString().trim();
      if (!isPDTasklist(tasklistName)) continue;
      const blockName = (task.name ?? task.task_name ?? '').toString().trim();
      if (!blockName) continue;
      let blockId: number;
      try {
        const upsert = await pool.query(
          `INSERT INTO blocks (project_id, block_name) VALUES ($1, $2)
           ON CONFLICT (project_id, block_name) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
           RETURNING id`,
          [asiProjectId, blockName]
        );
        blockId = upsert.rows[0].id;
        blocksUpserted++;
      } catch (e: any) {
        errors.push(`Block "${blockName}": ${e.message || 'insert failed'}`);
        continue;
      }
      const ownerEmails: string[] = [];
      const ownerEmail = task.owner_email ?? task.owner?.email ?? null;
      if (ownerEmail && String(ownerEmail).trim()) ownerEmails.push(String(ownerEmail).trim());
      const details = task.details ?? {};
      const owners = details.owners ?? (Array.isArray(details.Owners) ? details.Owners : []);
      if (Array.isArray(owners)) {
        for (const o of owners) {
          const email = o?.email ?? o?.Email ?? null;
          if (email && String(email).trim() && !ownerEmails.includes(String(email).trim())) {
            ownerEmails.push(String(email).trim());
          }
        }
      }
      if (!hasBlockUsersTable) continue;
      for (const email of ownerEmails) {
        try {
          const userRow = await pool.query('SELECT id FROM users WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))', [email]);
          if (userRow.rows.length === 0) continue;
          const uid = userRow.rows[0].id;
          await pool.query(
            `INSERT INTO block_users (block_id, user_id) VALUES ($1, $2) ON CONFLICT (block_id, user_id) DO NOTHING`,
            [blockId, uid]
          );
          assignmentsUpserted++;
        } catch (e: any) {
          errors.push(`Block "${blockName}" user ${email}: ${e.message || 'assign failed'}`);
        }
      }
    }
    console.log('[Sync Projects] Blocks and assignments synced:', { blocksUpserted, assignmentsUpserted, errors: errors.length });
  } catch (e: any) {
    console.warn('[Sync Projects] syncBlocksAndBlockUsers failed:', e.message);
    errors.push(e.message || 'sync blocks failed');
  }
  return { blocksUpserted, assignmentsUpserted, errors };
}

/**
 * Ensure project has domains linked. Domains come only from Zoho tasklists (mapped to our domains) or from request; no default.
 */
async function ensureProjectHasDomains(
  projectId: number,
  opts: {
    domainIdsFromZoho?: number[];
    domainCodes?: string[] | string | null;
    domainIds?: number[] | number | null;
    domainCode?: string | null;
    domainId?: number | null;
  }
): Promise<void> {
  const seen = new Set<number>();
  const domainIds: number[] = [];
  if (opts.domainIdsFromZoho && opts.domainIdsFromZoho.length > 0) {
    for (const id of opts.domainIdsFromZoho) {
      if (!seen.has(id)) { seen.add(id); domainIds.push(id); }
    }
  }
  const fromRequest = await resolveDomainIdsFromRequest(opts);
  for (const id of fromRequest) {
    if (!seen.has(id)) { seen.add(id); domainIds.push(id); }
  }
  if (domainIds.length === 0) {
    console.log('[Sync Projects] No domains to link (none from Zoho tasklists and none in request). project_id:', projectId);
    return;
  }
  const linked: string[] = [];
  for (const did of domainIds) {
    await pool.query(
      'INSERT INTO project_domains (project_id, domain_id) VALUES ($1, $2) ON CONFLICT (project_id, domain_id) DO NOTHING',
      [projectId, did]
    );
    const domainInfo = await pool.query('SELECT name, code FROM domains WHERE id = $1', [did]);
    const dname = domainInfo.rows[0]?.name ?? '?';
    const dcode = domainInfo.rows[0]?.code ?? '?';
    linked.push(`${dname} (${dcode})`);
  }
  console.log('[Sync Projects] Domains linked to project (from Zoho tasklists / request) | project_id:', projectId, '| domains:', linked.join(', '), '| stored in: project_domains (project_id, domain_id)');
}

/**
 * Fetch project name and linked domains from DB (same as CAD setup uses) and log for admin.
 */
async function logProjectAndDomains(projectId: number, context: string): Promise<void> {
  const projectRow = await pool.query('SELECT name FROM projects WHERE id = $1', [projectId]);
  const asiProjectName = projectRow.rows[0]?.name ?? '?';
  const domainsRows = await pool.query(
    `SELECT d.id, d.name, d.code FROM project_domains pd
     JOIN domains d ON d.id = pd.domain_id
     WHERE pd.project_id = $1 ORDER BY d.name`,
    [projectId]
  );
  const domainList = domainsRows.rows.length > 0
    ? domainsRows.rows.map((r: any) => `${r.name} (${r.code})`).join(', ')
    : '(none yet)';
  console.log('[Sync Projects]', context, '| Project:', asiProjectName, '(id:', projectId + ')', '| Domains:', domainList, '| DB: projects, project_domains, domains');
}

/**
 * GET /api/zoho/projects/sync-members/preview
 * Admin-only. Returns project name and domains that would be added/linked (no DB writes). For confirmation dialog.
 * Query: zohoProjectId, portalId?, zohoProjectName?
 */
router.get(
  '/projects/sync-members/preview',
  authenticate,
  authorize('admin'),
  async (req, res) => {
    try {
      const userId = (req as any).user?.id;
      const zohoProjectId = req.query.zohoProjectId as string | undefined;
      const portalId = req.query.portalId as string | undefined;
      const zohoProjectName = req.query.zohoProjectName as string | undefined;

      if (!zohoProjectId) {
        return res.status(400).json({ error: 'zohoProjectId is required' });
      }

      const zohoIdStr = zohoProjectId.toString();
      const projectName = zohoProjectName?.trim() || `Project from Zoho ${zohoIdStr}`;

      let existingProjectId: number | null = null;
      let displayProjectName = projectName;
      const mappingResult = await pool.query(
        'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1',
        [zohoIdStr]
      );
      if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
        existingProjectId = mappingResult.rows[0].local_project_id;
        const nameRow = await pool.query('SELECT name FROM projects WHERE id = $1', [existingProjectId]);
        if (nameRow.rows.length > 0) displayProjectName = nameRow.rows[0].name;
      }
      if (existingProjectId == null) {
        const byName = await pool.query(
          'SELECT id, name FROM projects WHERE LOWER(name) = LOWER($1)',
          [projectName]
        );
        if (byName.rows.length > 0) {
          existingProjectId = byName.rows[0].id;
          displayProjectName = byName.rows[0].name;
        }
      }

      const domainIds = await getDomainIdsFromZohoTasklists(userId, zohoIdStr, portalId);
      const domains: { id: number; name: string; code: string }[] = [];
      for (const did of domainIds) {
        const row = await pool.query('SELECT id, name, code FROM domains WHERE id = $1', [did]);
        if (row.rows.length > 0) {
          domains.push({
            id: row.rows[0].id,
            name: row.rows[0].name ?? '',
            code: row.rows[0].code ?? '',
          });
        }
      }

      const zohoProjectPreview = await zohoService.getProjectWithFallback(userId, zohoIdStr, portalId || undefined);
      const { technology_node: technologyNode, start_date: startDate, target_date: targetDate } = zohoProjectPreview
        ? extractZohoProjectDetails(zohoProjectPreview)
        : { technology_node: null, start_date: null, target_date: null };

      return res.json({
        projectName: displayProjectName,
        projectId: existingProjectId ?? undefined,
        existingProject: existingProjectId != null,
        domains,
        technology_node: technologyNode ?? undefined,
        start_date: startDate ?? undefined,
        target_date: targetDate ?? undefined,
        message: existingProjectId != null
          ? `Project "${displayProjectName}" will be updated; domains will be linked.`
          : `Project "${displayProjectName}" and domains will be added to the database.`,
      });
    } catch (error: any) {
      console.error('[API] GET /api/zoho/projects/sync-members/preview error:', error);
      res.status(500).json({
        error: error.message || 'Failed to get sync preview',
      });
    }
  }
);

/**
 * POST /api/zoho/projects/sync-members
 * Admin-only. Creates ASI project and domain link if needed, then syncs members.
 * Body: { zohoProjectId, portalId?, zohoProjectName?, domainCode?, domainId?, domainCodes?, domainIds? }
 * Domains come from Zoho tasklists (tasklist names mapped to our domains); optional request domainCodes/domainIds override. No default domains.
 */
router.post(
  '/projects/sync-members',
  authenticate,
  authorize('admin'),
  async (req, res) => {
    try {
      const userId = (req as any).user?.id;
      const { zohoProjectId, portalId, zohoProjectName, domainCode, domainId, domainCodes, domainIds } = req.body;

      console.log('[Sync Projects] Request received:', {
        zohoProjectId,
        portalId: portalId ?? '(not provided)',
        zohoProjectName: zohoProjectName ?? '(not provided)',
        domainCode: domainCode ?? '(not provided)',
        domainId: domainId ?? '(not provided)',
        domainCodes: domainCodes ?? '(not provided)',
        domainIds: domainIds ?? '(not provided)',
        userId,
      });

      if (!zohoProjectId) {
        return res.status(400).json({ error: 'zohoProjectId is required' });
      }

      const zohoIdStr = zohoProjectId.toString();
      const projectName = zohoProjectName || `Project from Zoho ${zohoIdStr}`;

      // Fetch Zoho project (with fallback) for technology_node, start_date, target_date
      const zohoProject = await zohoService.getProjectWithFallback(userId, zohoIdStr, portalId || undefined);
      const { technology_node: technologyNode, start_date: startDate, target_date: targetDate } = zohoProject
        ? extractZohoProjectDetails(zohoProject)
        : { technology_node: null, start_date: null, target_date: null };

      // Resolve ASI project: from mapping, or by name, or create
      let asiProjectId: number | null = null;
      const mappingResult = await pool.query(
        'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1',
        [zohoIdStr]
      );
      if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
        asiProjectId = mappingResult.rows[0].local_project_id;
        await logProjectAndDomains(asiProjectId!, 'Using existing project (from mapping)');
      }
      if (asiProjectId == null) {
        const byName = await pool.query(
          'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
          [projectName]
        );
        if (byName.rows.length > 0) {
          asiProjectId = byName.rows[0].id;
          await logProjectAndDomains(asiProjectId!, 'Using existing project (matched by name)');
        }
      }
      if (asiProjectId == null) {
        const createResult = await pool.query(
          `INSERT INTO projects (name, created_by, technology_node, start_date, target_date, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
           RETURNING id`,
          [projectName, userId, technologyNode, startDate, targetDate]
        );
        asiProjectId = createResult.rows[0].id;
        console.log('[Sync Projects] Project created | id:', asiProjectId, '| name:', projectName, '| technology_node:', technologyNode ?? '(none)', '| start_date:', startDate ?? '(none)', '| target_date:', targetDate ?? '(none)', '| stored in: projects (id, name, created_by, technology_node, start_date, target_date, created_at, updated_at)');
        await pool.query(
          `INSERT INTO zoho_projects_mapping (zoho_project_id, local_project_id, zoho_project_name)
           VALUES ($1, $2, $3)
           ON CONFLICT (zoho_project_id) DO UPDATE SET
             local_project_id = EXCLUDED.local_project_id,
             zoho_project_name = COALESCE(EXCLUDED.zoho_project_name, zoho_projects_mapping.zoho_project_name),
             updated_at = CURRENT_TIMESTAMP`,
          [zohoIdStr, asiProjectId, projectName]
        );
        console.log('[Sync Projects] Mapping stored | zoho_project_id:', zohoIdStr, '| local_project_id:', asiProjectId, '| zoho_project_name:', projectName, '| stored in: zoho_projects_mapping (zoho_project_id, local_project_id, zoho_project_name)');
        const domainIdsFromZoho = await getDomainIdsFromZohoTasklists(userId, zohoIdStr, portalId);
        await ensureProjectHasDomains(asiProjectId!, { domainIdsFromZoho, domainCodes, domainIds, domainCode, domainId });
        await logProjectAndDomains(asiProjectId!, 'After create and domain link');
      } else {
        await pool.query(
          `INSERT INTO zoho_projects_mapping (zoho_project_id, local_project_id, zoho_project_name)
           VALUES ($1, $2, $3)
           ON CONFLICT (zoho_project_id) DO UPDATE SET
             zoho_project_name = COALESCE(EXCLUDED.zoho_project_name, zoho_projects_mapping.zoho_project_name),
             updated_at = CURRENT_TIMESTAMP`,
          [zohoIdStr, asiProjectId, projectName]
        );
        console.log('[Sync Projects] Mapping stored | zoho_project_id:', zohoIdStr, '| local_project_id:', asiProjectId, '| zoho_project_name:', projectName, '| stored in: zoho_projects_mapping (zoho_project_id, local_project_id, zoho_project_name)');
        const domainIdsFromZoho = await getDomainIdsFromZohoTasklists(userId, zohoIdStr, portalId);
        await ensureProjectHasDomains(asiProjectId!, { domainIdsFromZoho, domainCodes, domainIds, domainCode, domainId });
        // Update existing project with technology_node, start_date, target_date from Zoho
        if (technologyNode != null || startDate != null || targetDate != null) {
          await pool.query(
            `UPDATE projects SET technology_node = COALESCE($2, technology_node), start_date = COALESCE($3, start_date), target_date = COALESCE($4, target_date), updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
            [asiProjectId, technologyNode, startDate, targetDate]
          );
          console.log('[Sync Projects] Updated project | id:', asiProjectId, '| technology_node:', technologyNode ?? '(unchanged)', '| start_date:', startDate ?? '(unchanged)', '| target_date:', targetDate ?? '(unchanged)');
        }
        await logProjectAndDomains(asiProjectId!, 'After ensuring domain');
      }

      if (asiProjectId == null) {
        return res.status(500).json({
          success: false,
          error: 'Failed to resolve or create ASI project',
        });
      }

      console.log('[Sync Projects] Syncing members: ASI project id', asiProjectId, ', Zoho project id', zohoIdStr);
      const result = await zohoService.syncProjectMembers(
        asiProjectId,
        zohoIdStr,
        portalId || undefined,
        userId
      );

      const blocksResult = await syncBlocksAndBlockUsers(asiProjectId, zohoIdStr, portalId || undefined, userId);
      if (blocksResult.errors.length > 0) {
        console.log('[Sync Projects] Block sync warnings:', blocksResult.errors);
      }

      console.log('[Sync Projects] Done:', {
        asiProjectId,
        zohoProjectId: zohoIdStr,
        totalMembers: result?.totalMembers ?? '(n/a)',
        createdUsers: result?.createdUsers ?? '(n/a)',
        updatedAssignments: result?.updatedAssignments ?? '(n/a)',
        blocksUpserted: blocksResult.blocksUpserted,
        blockAssignmentsUpserted: blocksResult.assignmentsUpserted,
        errors: (result?.errors?.length ?? 0) > 0 ? result.errors : 'none',
      });

      res.json({
        success: true,
        message: 'Project members synced successfully',
        ...result,
        asiProjectId,
        blocksUpserted: blocksResult.blocksUpserted,
        blockAssignmentsUpserted: blocksResult.assignmentsUpserted,
        blockSyncErrors: blocksResult.errors.length > 0 ? blocksResult.errors : undefined,
      });
    } catch (error: any) {
      console.error('[API] POST /api/zoho/projects/sync-members error:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Failed to sync project members',
      });
    }
  }
);

/**
 * POST /api/zoho/projects/:projectId/mark-exported
 * Mark a Zoho project as exported to Linux
 */
router.post('/projects/:projectId/mark-exported', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { projectId } = req.params;
    const { portalId, projectName } = req.body;
    
    if (!projectId) {
      return res.status(400).json({ 
        success: false,
        error: 'Project ID is required' 
      });
    }
    
    // Remove 'zoho_' prefix if present
    const actualProjectId = projectId.toString().startsWith('zoho_') 
      ? projectId.toString().replace('zoho_', '') 
      : projectId.toString();
    
    // Get portal ID if not provided
    let currentPortalId = portalId;
    if (!currentPortalId) {
      try {
        const portals = await zohoService.getPortals(userId);
        if (portals.length > 0) {
          currentPortalId = portals[0].id;
        }
      } catch (e) {
        console.log('Could not get portal ID, continuing without it:', e);
      }
    }
    
    // Get project name if not provided
    let currentProjectName = projectName;
    if (!currentProjectName) {
      try {
        const project = await zohoService.getProject(userId, actualProjectId, currentPortalId);
        currentProjectName = project.name || 'Unknown Project';
      } catch (e) {
        console.log('Could not get project name, using default:', e);
        currentProjectName = 'Unknown Project';
      }
    }
    
    // Insert or update export status
    // Check if a record already exists for this project
    let existingRecord;
    if (currentPortalId) {
      // First check for record with matching portal_id
      const checkWithPortal = await pool.query(
        'SELECT id FROM zoho_project_exports WHERE zoho_project_id = $1 AND portal_id = $2',
        [actualProjectId, currentPortalId]
      );
      if (checkWithPortal.rows.length > 0) {
        existingRecord = checkWithPortal.rows[0];
      } else {
        // Check for record with NULL portal_id (will update it to include portal_id)
        const checkNull = await pool.query(
          'SELECT id FROM zoho_project_exports WHERE zoho_project_id = $1 AND portal_id IS NULL',
          [actualProjectId]
        );
        if (checkNull.rows.length > 0) {
          existingRecord = checkNull.rows[0];
        }
      }
    } else {
      // Check for record with NULL portal_id
      const checkNull = await pool.query(
        'SELECT id FROM zoho_project_exports WHERE zoho_project_id = $1 AND portal_id IS NULL',
        [actualProjectId]
      );
      if (checkNull.rows.length > 0) {
        existingRecord = checkNull.rows[0];
      }
    }
    
    let result;
    if (existingRecord) {
      // Update existing record
      result = await pool.query(
        `UPDATE zoho_project_exports 
         SET exported_to_linux = $1,
             exported_at = CURRENT_TIMESTAMP,
             exported_by = $2,
             zoho_project_name = COALESCE($3, zoho_project_exports.zoho_project_name),
             portal_id = COALESCE($4, zoho_project_exports.portal_id),
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $5
         RETURNING *`,
        [true, userId, currentProjectName, currentPortalId || null, existingRecord.id]
      );
    } else {
      // Insert new record
      result = await pool.query(
        `INSERT INTO zoho_project_exports 
         (zoho_project_id, portal_id, zoho_project_name, exported_to_linux, exported_at, exported_by)
         VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, $5)
         RETURNING *`,
        [actualProjectId, currentPortalId || null, currentProjectName, true, userId]
      );
    }

    // Also set setup_completed and exported_to_linux on the linked local project (projects table only)
    try {
      const mappingResult = await pool.query(
        'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1 OR zoho_project_id::text = $1',
        [actualProjectId]
      );
      if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
        await pool.query(
          `UPDATE projects SET setup_completed = true, setup_completed_at = CURRENT_TIMESTAMP, exported_to_linux = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
          [mappingResult.rows[0].local_project_id]
        );
      }
    } catch (e) {
      // Non-fatal: export was saved; project table update is best-effort
    }

    res.json({
      success: true,
      message: 'Project marked as exported to Linux',
      export: result.rows[0]
    });
  } catch (error: any) {
    console.error('Error marking project as exported:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

/**
 * GET /api/zoho/projects/:projectId
 * Get single project details from Zoho Projects (admin only; non-admin use DB only)
 */
router.get('/projects/:projectId', authenticate, authorize('admin'), async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { projectId } = req.params;
    const { portalId } = req.query;
    
    const project = await zohoService.getProject(
      userId,
      projectId,
      portalId as string | undefined
    );
    
    // Get project members (roles table)
    let members: any[] = [];
    let formattedMembers: any[] = [];
    
    // Helper function to extract role name from role object/string
    const extractRoleName = (role: any): string => {
      if (!role) return 'Employee';
      if (typeof role === 'string') return role;
      if (typeof role === 'object') {
        return role.name || role.role || role.designation || role.value || role.label || role.title || 'Employee';
      }
      return String(role);
    };
    
    // Helper function to extract status
    const extractStatus = (status: any): string => {
      if (!status) return 'active';
      if (typeof status === 'string') return status;
      if (status === 1 || status === '1' || status === true) return 'active';
      if (status === 0 || status === '0' || status === false) return 'inactive';
      return String(status);
    };
    
    try {
      members = await zohoService.getProjectMembers(
        userId,
        projectId,
        portalId as string | undefined
      );
      
      // Format members with proper role extraction
      // Prioritize project_profile first as it contains the correct role for the project
      formattedMembers = members.map((m: any) => {
        const roleName = extractRoleName(m.project_profile || m.role || m.project_role || m.role_in_project);
        const status = extractStatus(m.status);
        return {
          id: m.id || m.zpuid || m.zuid,
          name: m.name || `${m.first_name || ''} ${m.last_name || ''}`.trim() || m.email?.split('@')[0] || 'Unknown',
          email: m.email || m.Email || m.mail || 'N/A',
          role: roleName,
          role_mapped: zohoService.mapZohoProjectRoleToAppRole(roleName),
          status: status,
          first_name: m.first_name,
          last_name: m.last_name,
          zpuid: m.zpuid,
          zuid: m.zuid
        };
      });
      
    } catch (memberError: any) {
      console.error(`❌ Error fetching members for project ${project.name}:`, memberError.message);
      formattedMembers = []; // Ensure it's initialized even on error
    }
    
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
        owner_id: project.owner_id,
        owner_email: project.owner_email,
        created_time: project.created_time,
        source: 'zoho',
        // Include roles/members table with properly formatted data
        members: formattedMembers,
        roles: formattedMembers.map((m: any) => ({
          name: m.name,
          email: m.email,
          role: m.role,
          role_mapped: m.role_mapped,
          status: m.status,
          id: m.id
        })),
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
 * GET /api/zoho/projects/:zohoProjectId/members
 * Get all members for a Zoho project (admin only; non-admin use DB only)
 */
router.get('/projects/:zohoProjectId/members', authenticate, authorize('admin'), async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { zohoProjectId } = req.params;
    const { portalId } = req.query;

    console.log(`[API] GET /api/zoho/projects/${zohoProjectId}/members - userId: ${userId}, portalId: ${portalId}`);

    const members = await zohoService.getProjectMembers(
      userId,
      zohoProjectId,
      portalId as string | undefined
    );

    // Map roles for preview
    const mappedMembers = members.map(member => {
      const email = member.email || member.Email || member.mail || 'N/A';
      const name = member.name || member.Name || member.full_name || email?.split('@')[0] || 'Unknown';
      const zohoRole = member.role || member.Role || member.project_role || 'Employee';
      const asiRole = zohoService.mapZohoProjectRoleToAppRole(zohoRole);
      
      return {
        email,
        name,
        zoho_role: zohoRole,
        asi_role: asiRole,
        status: member.status || 'active',
        id: member.id
      };
    });

    console.log(`[API] Returning ${mappedMembers.length} mapped members`);

    res.json({
      success: true,
      count: mappedMembers.length,
      members: mappedMembers
    });
  } catch (error: any) {
    console.error('[API] Error fetching project members:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * GET /api/zoho/projects/:projectId/tasks
 * Get all tasks for a Zoho project (admin only; non-admin use DB only)
 */
router.get('/projects/:projectId/tasks', authenticate, authorize('admin'), async (req, res) => {
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
 * Get all milestones for a Zoho project (admin only; non-admin use DB only)
 */
router.get('/projects/:projectId/milestones', authenticate, authorize('admin'), async (req, res) => {
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

