import express from 'express';
import { pool } from '../config/database';
import { authenticate, authorize } from '../middleware/auth.middleware';
import zohoService from '../services/zoho.service';

const router = express.Router();

// Shape helpers
const fetchProjectWithDomains = async (projectId: number, client: any) => {
  const projectResult = await client.query(
    `
      SELECT 
        p.*,
        COALESCE(
          json_agg(
            json_build_object(
              'id', d.id,
              'name', d.name,
              'code', d.code,
              'description', d.description
            )
          ) FILTER (WHERE d.id IS NOT NULL),
          '[]'
        ) as domains
      FROM projects p
      LEFT JOIN project_domains pd ON pd.project_id = p.id
      LEFT JOIN domains d ON d.id = pd.domain_id
      WHERE p.id = $1
      GROUP BY p.id
    `,
    [projectId]
  );

  return projectResult.rows[0];
};

/**
 * Check if a project has matching EDA output (is "mapped")
 * A project is mapped if there's EDA output data for it
 */
async function checkProjectMapping(projectName: string): Promise<boolean> {
  try {
    const result = await pool.query(
      `
        SELECT COUNT(DISTINCT p.id) as count
        FROM projects p
        INNER JOIN blocks b ON b.project_id = p.id
        INNER JOIN runs r ON r.block_id = b.id
        INNER JOIN stages s ON s.run_id = r.id
        WHERE LOWER(p.name) = LOWER($1)
        LIMIT 1
      `,
      [projectName]
    );
    
    return (result.rows[0]?.count || 0) > 0;
  } catch (error: any) {
    console.error('Error checking project mapping:', error);
    return false;
  }
}

// List projects with their domains (optionally include Zoho projects)
router.get('/', authenticate, async (req, res) => {
  try {
    const { includeZoho } = req.query;
    const userId = (req as any).user?.id;
    const userRole = (req as any).user?.role;

    // Build query based on user role
    // Engineers see projects they created
    // Customers see projects assigned via user_projects table
    // Admin, project_manager, and lead see all projects
    let projectFilter = '';
    let joinClause = '';
    const queryParams: any[] = [];
    
    console.log('Project filtering - User ID:', userId, 'Role:', userRole);
    
    if (userRole === 'customer') {
      // Customers see projects assigned to them via user_projects table
      joinClause = 'INNER JOIN user_projects up ON p.id = up.project_id';
      projectFilter = 'WHERE up.user_id = $1';
      queryParams.push(userId);
      console.log('Filtering projects for customer - only projects assigned via user_projects:', userId);
    } else if (userRole === 'engineer') {
      // Engineers see projects they created OR projects assigned via user_projects
      // Check if user_projects table exists first
      const tableExistsResult = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' 
          AND table_name = 'user_projects'
        );
      `);
      
      const tableExists = tableExistsResult.rows[0]?.exists || false;
      
      if (tableExists) {
        joinClause = 'LEFT JOIN user_projects up ON p.id = up.project_id';
        projectFilter = 'WHERE (p.created_by = $1 AND p.created_by IS NOT NULL) OR up.user_id = $1';
      } else {
        // If user_projects table doesn't exist, only filter by created_by
        joinClause = '';
        projectFilter = 'WHERE p.created_by = $1 AND p.created_by IS NOT NULL';
      }
      queryParams.push(userId);
      console.log('Filtering projects for engineer - projects created by user or assigned via user_projects:', userId);
    } else {
      console.log('No filter applied - showing all projects for role:', userRole);
    }
    // Admin, project_manager, and lead see all projects (no filter)

    // Get local projects
    const result = await pool.query(
      `
        SELECT 
          p.*,
          COALESCE(
            json_agg(
              json_build_object(
                'id', d.id,
                'name', d.name,
                'code', d.code,
                'description', d.description
              )
            ) FILTER (WHERE d.id IS NOT NULL),
            '[]'
          ) as domains
        FROM projects p
        ${joinClause}
        LEFT JOIN project_domains pd ON pd.project_id = p.id
        LEFT JOIN domains d ON d.id = pd.domain_id
        ${projectFilter}
        GROUP BY p.id
        ORDER BY p.created_at DESC
      `,
      queryParams
    );

    // Check mapping status for local projects
    const localProjects = await Promise.all(
      result.rows.map(async (p: any) => {
        const isMapped = await checkProjectMapping(p.name);
        return {
          ...p,
          source: 'local',
          is_mapped: isMapped
        };
      })
    );
    
    console.log(`Found ${localProjects.length} local projects for user ${userId} (role: ${userRole})`);

    // If includeZoho is requested, fetch from Zoho Projects
    if (includeZoho === 'true' || includeZoho === '1') {
      try {
        const zohoService = (await import('../services/zoho.service')).default;
        const hasToken = await zohoService.hasValidToken(userId);
        
        if (hasToken) {
          const { portalId } = req.query;
          const zohoProjects = await zohoService.getProjects(
            userId,
            portalId as string | undefined
          );

          // Filter Zoho projects based on user role
          // For engineers: Zoho API typically returns only projects they have access to
          // But we can also filter by owner or members if available
          let filteredZohoProjects = zohoProjects;
          
          if (userRole === 'engineer' || userRole === 'customer') {
            // For engineers, Zoho Projects API should already return only accessible projects
            // But we can add additional filtering if needed
            // For now, Zoho API returns projects the user has access to, so we keep all
            console.log(`Filtering Zoho projects for ${userRole} role: ${zohoProjects.length} projects available`);
          }

          // Check mapping status for Zoho projects (show all, but indicate mapping status)
          // Also get linked ASI project ID from zoho_projects_mapping table
          // Get portal ID to include in project data
          let currentPortalId = portalId as string | undefined;
          if (!currentPortalId) {
            const portals = await zohoService.getPortals(userId);
            if (portals.length > 0) {
              currentPortalId = portals[0].id;
            }
          }
          
          const formattedZohoProjects = await Promise.all(
            filteredZohoProjects.map(async (zp: any) => {
              const isMapped = await checkProjectMapping(zp.name);
              
              // Get linked ASI project ID from zoho_projects_mapping table
              let asiProjectId: number | null = null;
              try {
                const mappingResult = await pool.query(
                  'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1',
                  [zp.id]
                );
                if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
                  asiProjectId = mappingResult.rows[0].local_project_id;
                }
              } catch (e) {
                // If table doesn't exist or query fails, continue without ASI project ID
                console.log('Could not get ASI project ID from mapping table:', e);
              }
              
              // If no mapping found but project is mapped, try to find ASI project by name
              if (isMapped && asiProjectId == null) {
                try {
                  const nameMatchResult = await pool.query(
                    'SELECT id FROM projects WHERE LOWER(name) = LOWER($1) LIMIT 1',
                    [zp.name]
                  );
                  if (nameMatchResult.rows.length > 0) {
                    asiProjectId = nameMatchResult.rows[0].id;
                  }
                } catch (e) {
                  console.log('Could not find ASI project by name:', e);
                }
              }
              
              return {
                id: `zoho_${zp.id}`,
                name: zp.name,
                client: zp.owner_name || null,
                technology_node: null,
                start_date: zp.start_date || null,
                target_date: zp.end_date || null,
                plan: zp.description || null,
                created_at: zp.created_time || null,
                updated_at: zp.created_time || null,
                domains: [],
                source: 'zoho',
                zoho_project_id: zp.id,
                zoho_data: {
                  ...zp,
                  portal_id: currentPortalId, // Store portal ID in zoho_data
                  portal: currentPortalId
                },
                is_mapped: isMapped,
                asi_project_id: asiProjectId, // Add linked ASI project ID
                portal_id: currentPortalId // Also store at top level for easy access
              };
            })
          );

          console.log(`Showing ${formattedZohoProjects.length} Zoho projects for ${userRole} (mapping status included)`);

          // Filter out local projects that are already mapped to Zoho projects
          // Only include unmapped local projects in the 'all' array to avoid duplicates
          // When a Zoho project is mapped, show only the Zoho version (not the local one)
          const unmappedLocalProjects = localProjects.filter((lp: any) => !lp.is_mapped);

          // Combine unmapped local projects with all Zoho projects (mapped and unmapped)
          // This shows Zoho projects when mapped, and local projects when not mapped
          const allProjects = [
            ...unmappedLocalProjects,
            ...formattedZohoProjects
          ];

          console.log(`Total projects: ${allProjects.length} (${unmappedLocalProjects.length} unmapped local, ${localProjects.length - unmappedLocalProjects.length} mapped local excluded, ${formattedZohoProjects.length} Zoho projects)`);

          return res.json({
            local: localProjects, // Keep all local projects in separate array for reference
            zoho: formattedZohoProjects, // Keep all Zoho projects in separate array for reference
            all: allProjects, // Show unmapped local + all Zoho projects (mapped Zoho projects will show as green)
            counts: {
              local: localProjects.length,
              zoho: formattedZohoProjects.length,
              total: allProjects.length
            }
          });
        } else {
          // Zoho not connected, return only local projects
          return res.json({
            local: localProjects,
            zoho: [],
            all: localProjects,
            counts: {
              local: localProjects.length,
              zoho: 0,
              total: localProjects.length
            },
            message: 'Zoho Projects not connected. Use /api/zoho/auth to connect.'
          });
        }
      } catch (zohoError: any) {
        // If Zoho fetch fails, still return local projects
        console.error('Error fetching Zoho projects:', zohoError);
        return res.json({
          local: localProjects,
          zoho: [],
          all: localProjects,
          counts: {
            local: localProjects.length,
            zoho: 0,
            total: localProjects.length
          },
          error: `Failed to fetch Zoho projects: ${zohoError.message}`
        });
      }
    }

    // Default: return only local projects
    res.json(localProjects);
  } catch (error: any) {
    console.error('Error fetching projects:', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete project (admin only) - MUST come before GET /:id to avoid route conflicts
router.delete('/:id', authenticate, authorize('admin'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const projectId = parseInt(id, 10);
    
    console.log(`DELETE /api/projects/${id} - Attempting to delete project ${projectId}`);
    
    if (isNaN(projectId)) {
      return res.status(400).json({ error: 'Invalid project ID' });
    }

    await client.query('BEGIN');

    // Check if project exists
    const projectCheck = await client.query('SELECT id, name FROM projects WHERE id = $1', [projectId]);
    
    if (projectCheck.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Project not found' });
    }

    // Delete project domains first (foreign key constraint)
    await client.query('DELETE FROM project_domains WHERE project_id = $1', [projectId]);

    // Delete the project
    await client.query('DELETE FROM projects WHERE id = $1', [projectId]);

    await client.query('COMMIT');
    
    console.log(`Project ${projectId} deleted successfully`);
    
    res.json({ 
      message: 'Project deleted successfully',
      deletedProject: projectCheck.rows[0]
    });
  } catch (error: any) {
    await client.query('ROLLBACK');
    console.error('Error deleting project:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// Get single project with domains
router.get('/:id', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `
        SELECT 
          p.*,
          COALESCE(
            json_agg(
              json_build_object(
                'id', d.id,
                'name', d.name,
                'code', d.code,
                'description', d.description
              )
            ) FILTER (WHERE d.id IS NOT NULL),
            '[]'
          ) as domains
        FROM projects p
        LEFT JOIN project_domains pd ON pd.project_id = p.id
        LEFT JOIN domains d ON d.id = pd.domain_id
        WHERE p.id = $1
        GROUP BY p.id
      `,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Project not found' });
    }

    res.json(result.rows[0]);
  } catch (error: any) {
    console.error('Error fetching project:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create a new project with domains
router.post(
  '/',
  authenticate,
  authorize('admin', 'project_manager'),
  async (req, res) => {
    const client = await pool.connect();
    try {
      const {
        name,
        client: clientName,
        technology_node,
        start_date,
        target_date,
        plan,
        domain_ids,
      } = req.body;

      if (!name || !technology_node) {
        return res.status(400).json({ error: 'Name and technology node are required' });
      }

      if (!Array.isArray(domain_ids) || domain_ids.length === 0) {
        return res.status(400).json({ error: 'At least one domain is required' });
      }

      await client.query('BEGIN');

      // Normalize ids to integers and validate they are active
      const domainIds = (domain_ids as any[]).map((id) => Number(id));

      const domainCheck = await client.query(
        `SELECT id FROM domains WHERE id = ANY($1::int[]) AND is_active = true`,
        [domainIds]
      );

      if (domainCheck.rows.length !== domainIds.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'One or more domains are invalid or inactive' });
      }

      const currentUserId = (req as any).user?.id || null;

      const insertResult = await client.query(
        `
          INSERT INTO projects (
            name, client, technology_node, start_date, target_date, plan, created_by
          ) VALUES ($1, $2, $3, $4, $5, $6, $7)
          RETURNING id
        `,
        [
          name,
          clientName || null,
          technology_node,
          start_date || null,
          target_date || null,
          plan || null,
          currentUserId,
        ]
      );

      const projectId = insertResult.rows[0].id;

      // Link domains
      const valuesPlaceholders = domainIds
        .map((_, index) => `($1, $${index + 2})`)
        .join(',');
      await client.query(
        `INSERT INTO project_domains (project_id, domain_id) VALUES ${valuesPlaceholders}`,
        [projectId, ...domainIds]
      );

      const project = await fetchProjectWithDomains(projectId, client);

      await client.query('COMMIT');
      res.status(201).json(project);
    } catch (error: any) {
      await client.query('ROLLBACK');
      console.error('Error creating project:', error);
      res.status(500).json({ error: error.message });
    } finally {
      client.release();
    }
  }
);

/**
 * GET /api/projects/:projectId/blocks
 * Get all blocks for a specific project
 */
router.get(
  '/:projectId/blocks',
  authenticate,
  async (req, res) => {
    try {
      const projectId = parseInt(req.params.projectId, 10);
      const userId = (req as any).user?.id;
      const userRole = (req as any).user?.role;
      
      if (isNaN(projectId)) {
        return res.status(400).json({ error: 'Invalid project ID' });
      }

      // Check if user has access to this project
      let hasAccess = false;
      
      if (userRole === 'admin' || userRole === 'project_manager' || userRole === 'lead') {
        // Admins, project managers, and leads have access to all projects
        hasAccess = true;
      } else {
        // Check if engineer/customer has access via created_by or user_projects
        const accessCheck = await pool.query(
          `
            SELECT COUNT(*) as count
            FROM projects p
            LEFT JOIN user_projects up ON p.id = up.project_id
            WHERE p.id = $1
              AND (
                (p.created_by = $2 AND p.created_by IS NOT NULL)
                OR up.user_id = $2
              )
          `,
          [projectId, userId]
        );
        hasAccess = (parseInt(accessCheck.rows[0]?.count || '0', 10) > 0);
      }

      if (!hasAccess) {
        return res.status(403).json({ 
          error: 'Access denied',
          message: 'You do not have access to this project'
        });
      }

      const result = await pool.query(
        `
          SELECT id, block_name, project_id, created_at
          FROM blocks
          WHERE project_id = $1
          ORDER BY block_name
        `,
        [projectId]
      );

      res.json({
        success: true,
        data: result.rows,
      });
    } catch (error: any) {
      console.error('Error fetching blocks:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * GET /api/projects/:projectId/run-history
 * Get run history for a project (optionally filtered by block and experiment)
 */
router.get(
  '/:projectId/run-history',
  authenticate,
  async (req, res) => {
    try {
      const projectId = parseInt(req.params.projectId, 10);
      const { blockName, experiment, limit = '20' } = req.query;
      
      if (isNaN(projectId)) {
        return res.status(400).json({ error: 'Invalid project ID' });
      }

      // Get user info for filtering
      const userId = (req as any).user?.id;
      const userRole = (req as any).user?.role;
      const username = (req as any).user?.username;

      let query = `
        SELECT DISTINCT
          s.id as stage_id,
          s.stage_name as command,
          s.timestamp,
          s.run_status,
          s.runtime as duration,
          r.experiment,
          r.rtl_tag,
          r.user_name,
          b.block_name,
          p.name as project_name
        FROM stages s
        INNER JOIN runs r ON s.run_id = r.id
        INNER JOIN blocks b ON r.block_id = b.id
        INNER JOIN projects p ON b.project_id = p.id
        WHERE p.id = $1
      `;

      const params: any[] = [projectId];
      let paramCount = 1;

      // Filter by block name if provided
      if (blockName) {
        paramCount++;
        query += ` AND b.block_name = $${paramCount}`;
        params.push(blockName);
      }

      // Filter by experiment if provided
      if (experiment) {
        paramCount++;
        query += ` AND r.experiment = $${paramCount}`;
        params.push(experiment);
      }

      // Filter by user role: engineers and customers only see their own runs
      if (userRole === 'engineer' || userRole === 'customer') {
        if (username) {
          paramCount++;
          query += ` AND r.user_name = $${paramCount}`;
          params.push(username);
        }
      }
      // Admin, project_manager, and lead see all runs (no additional filter)

      query += ` ORDER BY s.timestamp DESC LIMIT $${paramCount + 1}`;
      params.push(parseInt(limit as string, 10));

      const result = await pool.query(query, params);

      // Format the response to match the frontend expectations
      const runHistory = result.rows.map((row: any) => {
        const timestamp = row.timestamp ? new Date(row.timestamp) : null;
        const now = new Date();
        
        // Calculate relative time
        let relativeTime = 'Unknown';
        if (timestamp) {
          const diffMs = now.getTime() - timestamp.getTime();
          const diffMins = Math.floor(diffMs / (1000 * 60));
          const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
          const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
          
          if (diffMins < 1) {
            relativeTime = 'just now';
          } else if (diffMins < 60) {
            relativeTime = `about ${diffMins} ${diffMins === 1 ? 'minute' : 'minutes'} ago`;
          } else if (diffHours < 24) {
            relativeTime = `about ${diffHours} ${diffHours === 1 ? 'hour' : 'hours'} ago`;
          } else {
            relativeTime = `about ${diffDays} ${diffDays === 1 ? 'day' : 'days'} ago`;
          }
        }

        // Format status
        let status = 'UNKNOWN';
        if (row.run_status) {
          const statusLower = row.run_status.toLowerCase();
          if (statusLower === 'pass' || statusLower === 'completed') {
            status = 'COMPLETED';
          } else if (statusLower === 'fail' || statusLower === 'failed') {
            status = 'FAILED';
          } else {
            status = row.run_status.toUpperCase();
          }
        }

        // Format command (stage name)
        const commandMap: { [key: string]: string } = {
          'syn': 'Execute synthesis',
          'init': 'Initialize design',
          'floorplan': 'Floorplan',
          'place': 'Place',
          'cts': 'Clock tree synthesis',
          'postcts': 'Post-CTS optimization',
          'route': 'Place and route',
          'postroute': 'Post-route optimization',
        };
        const command = commandMap[row.command?.toLowerCase()] || row.command || 'Unknown command';

        return {
          timestamp: relativeTime,
          exactTime: timestamp ? timestamp.toISOString().replace('T', ' ').substring(0, 19) : '',
          command: command,
          status: status,
          duration: row.duration || 'N/A',
          experiment: row.experiment,
          rtlTag: row.rtl_tag,
          blockName: row.block_name,
        };
      });

      res.json({
        success: true,
        data: runHistory,
      });
    } catch (error: any) {
      console.error('Error fetching run history:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * POST /api/projects/:projectId/sync-zoho-members
 * Sync members from Zoho project to ASI project
 * Requires: projectId (ASI), zohoProjectId, portalId (optional)
 */
router.post(
  '/:projectId/sync-zoho-members',
  authenticate,
  authorize('admin', 'project_manager', 'lead'),
  async (req, res) => {
    const projectId = parseInt(req.params.projectId, 10);
    const userId = (req as any).user?.id;
    const userRole = (req as any).user?.role;
    const { zohoProjectId, portalId } = req.body;
    
    try {

      console.log(`[API] POST /api/projects/${projectId}/sync-zoho-members - userId: ${userId}, role: ${userRole}`);
      console.log(`[API] Request body:`, { zohoProjectId, portalId });

      if (isNaN(projectId)) {
        console.error(`[API] Invalid project ID: ${req.params.projectId}`);
        return res.status(400).json({ error: 'Invalid project ID' });
      }

      if (!zohoProjectId) {
        console.error(`[API] Missing zohoProjectId in request body`);
        return res.status(400).json({ error: 'zohoProjectId is required' });
      }

      // Verify project exists
      const projectCheck = await pool.query(
        'SELECT id, name FROM projects WHERE id = $1',
        [projectId]
      );

      if (projectCheck.rows.length === 0) {
        console.error(`[API] Project ${projectId} not found`);
        return res.status(404).json({ error: 'Project not found' });
      }

      const projectName = projectCheck.rows[0].name;
      console.log(`[API] Project found: ${projectName} (ID: ${projectId})`);

      // Import zohoService
      const zohoService = (await import('../services/zoho.service')).default;

      console.log(`[API] Starting sync for project ${projectId} from Zoho project ${zohoProjectId}...`);

      // Sync members
      const result = await zohoService.syncProjectMembers(
        projectId,
        zohoProjectId,
        portalId,
        userId
      );

      console.log(`[API] Sync completed:`, {
        totalMembers: result.totalMembers,
        createdUsers: result.createdUsers,
        updatedAssignments: result.updatedAssignments,
        errors: result.errors.length
      });

      if (result.errors.length > 0) {
        console.warn(`[API] Sync completed with ${result.errors.length} errors:`, result.errors);
      }

      res.json({
        success: true,
        message: 'Project members synced successfully',
        ...result
      });
    } catch (error: any) {
      console.error('[API] Error syncing project members:', {
        message: error.message,
        stack: error.stack,
        projectId,
        zohoProjectId,
        userId
      });
      res.status(500).json({
        success: false,
        error: error.message || 'Failed to sync project members',
        details: process.env.NODE_ENV === 'development' ? error.stack : undefined
      });
    }
  }
);

/**
 * GET /api/projects/:projectIdentifier/user-role
 * Get user's role for a specific project (project-specific role from user_projects, or global role)
 * projectIdentifier can be: project ID (number), project name, or Zoho project ID
 */
router.get('/:projectIdentifier/user-role', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const { projectIdentifier } = req.params;
    
    if (!userId) {
      return res.status(401).json({ error: 'User not authenticated' });
    }

    // Get user's global role first
    const userResult = await pool.query(
      'SELECT role FROM users WHERE id = $1',
      [userId]
    );
    
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    const globalRole = userResult.rows[0].role;
    
    // Try to find ASI project ID from various identifiers
    let asiProjectId: number | null = null;
    
    // Check if projectIdentifier is a number (ASI project ID)
    const numericId = parseInt(projectIdentifier, 10);
    if (!isNaN(numericId)) {
      const projectCheck = await pool.query(
        'SELECT id FROM projects WHERE id = $1',
        [numericId]
      );
      if (projectCheck.rows.length > 0) {
        asiProjectId = numericId;
      }
    }
    
    // If not found by ID, try by name
    if (!asiProjectId) {
      const projectByName = await pool.query(
        'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
        [projectIdentifier]
      );
      if (projectByName.rows.length > 0) {
        asiProjectId = projectByName.rows[0].id;
      }
    }
    
    // If still not found, try Zoho project ID mapping
    if (!asiProjectId) {
      const zohoMapping = await pool.query(
        `SELECT local_project_id FROM zoho_projects_mapping 
         WHERE zoho_project_id = $1 OR zoho_project_id::text = $1`,
        [projectIdentifier]
      );
      if (zohoMapping.rows.length > 0) {
        asiProjectId = zohoMapping.rows[0].local_project_id;
      }
    }
    
    // If we found an ASI project ID, check for project-specific role
    let projectRole: string | null = null;
    if (asiProjectId) {
      const userProjectResult = await pool.query(
        'SELECT role FROM user_projects WHERE user_id = $1 AND project_id = $2',
        [userId, asiProjectId]
      );
      if (userProjectResult.rows.length > 0) {
        projectRole = userProjectResult.rows[0].role;
      }
    }
    
    // Determine effective role: project-specific role if exists, otherwise global role
    const effectiveRole = projectRole || globalRole;
    
    // Determine available view types based on role
    const availableViewTypes: string[] = [];
    if (effectiveRole === 'management') {
      // Management role only sees management view
      availableViewTypes.push('management');
    } else if (effectiveRole === 'cad_engineer') {
      // CAD engineer has a dedicated CAD view
      availableViewTypes.push('cad');
    } else if (effectiveRole === 'engineer' || effectiveRole === 'customer') {
      availableViewTypes.push('engineer');
    } else if (effectiveRole === 'lead') {
      availableViewTypes.push('engineer', 'lead');
    } else if (effectiveRole === 'project_manager' || effectiveRole === 'admin') {
      // Admins and PMs can see all engineering, CAD, and management views
      availableViewTypes.push('engineer', 'lead', 'manager', 'management', 'cad');
    }
    
    // If customer, also add customer view
    if (effectiveRole === 'customer') {
      availableViewTypes.push('customer');
    }
    
    return res.json({
      success: true,
      globalRole,
      projectRole: projectRole || null,
      effectiveRole,
      availableViewTypes,
      asiProjectId: asiProjectId || null,
    });
  } catch (error: any) {
    console.error('Error getting user project role:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/projects/map-zoho-project
 * Map a Zoho project to an ASI project
 * If asiProjectId is not provided, creates a new ASI project with the same name
 * Requires: admin, project_manager, or lead role
 */
router.post(
  '/map-zoho-project',
  authenticate,
  authorize('admin', 'project_manager', 'lead'),
  async (req, res) => {
    try {
      const { zohoProjectId, asiProjectId, portalId, zohoProjectName, createIfNotExists } = req.body;
      const userId = (req as any).user?.id;
      
      if (!zohoProjectId) {
        return res.status(400).json({ 
          error: 'zohoProjectId is required' 
        });
      }

      let finalAsiProjectId = asiProjectId;
      let asiProjectName: string;

      // If asiProjectId is provided, verify it exists
      if (finalAsiProjectId) {
        const projectCheck = await pool.query(
          'SELECT id, name FROM projects WHERE id = $1',
          [finalAsiProjectId]
        );

        if (projectCheck.rows.length === 0) {
          return res.status(404).json({ error: 'ASI project not found' });
        }

        asiProjectName = projectCheck.rows[0].name;
      } else {
        // No ASI project ID provided - check if we should create one
        if (!createIfNotExists) {
          return res.status(400).json({ 
            error: 'asiProjectId is required. Set createIfNotExists=true to create a new ASI project automatically.' 
          });
        }

        // Create new ASI project with the same name as Zoho project
        const projectName = zohoProjectName || `Project from Zoho ${zohoProjectId}`;
        
        // Check if project with same name already exists
        const existingCheck = await pool.query(
          'SELECT id, name FROM projects WHERE LOWER(name) = LOWER($1)',
          [projectName]
        );

        if (existingCheck.rows.length > 0) {
          // Use existing project
          finalAsiProjectId = existingCheck.rows[0].id;
          asiProjectName = existingCheck.rows[0].name;
        } else {
          // Create new project
          const createResult = await pool.query(
            `INSERT INTO projects (name, created_by, created_at, updated_at)
             VALUES ($1, $2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
             RETURNING id, name`,
            [projectName, userId]
          );

          finalAsiProjectId = createResult.rows[0].id;
          asiProjectName = createResult.rows[0].name;
        }
      }

      // Insert or update mapping
      const result = await pool.query(
        `INSERT INTO zoho_projects_mapping 
         (zoho_project_id, local_project_id, zoho_project_name, portal_id)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (zoho_project_id)
         DO UPDATE SET 
           local_project_id = EXCLUDED.local_project_id,
           zoho_project_name = COALESCE(EXCLUDED.zoho_project_name, zoho_projects_mapping.zoho_project_name),
           portal_id = COALESCE(EXCLUDED.portal_id, zoho_projects_mapping.portal_id),
           updated_at = CURRENT_TIMESTAMP
         RETURNING *`,
        [
          zohoProjectId.toString(),
          finalAsiProjectId,
          zohoProjectName || null,
          portalId || null
        ]
      );

      res.json({
        success: true,
        message: `Successfully mapped Zoho project "${zohoProjectName || zohoProjectId}" to ASI project "${asiProjectName}"`,
        mapping: result.rows[0],
        asiProjectId: finalAsiProjectId,
        asiProjectName: asiProjectName,
        created: !asiProjectId // Indicates if ASI project was created
      });
    } catch (error: any) {
      console.error('Error mapping Zoho project:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * GET /api/projects/management/status
 * Get project status overview for management view
 * Returns status for all projects with RTL, DV, PD, AL, DFT stages and milestone information
 */
router.get('/management/status', authenticate, async (req, res) => {
  try {
    const userRole = (req as any).user?.role;
    const userId = (req as any).user?.id;
    
    // Only management role and admin can access this endpoint
    if (userRole !== 'management' && userRole !== 'admin') {
      return res.status(403).json({ error: 'Access denied. Management or admin role required.' });
    }

    // Get all projects (both local and Zoho mapped)
    const projectsResult = await pool.query(
      `SELECT 
        p.id,
        p.name,
        zpm.zoho_project_id
      FROM projects p
      LEFT JOIN zoho_projects_mapping zpm ON zpm.local_project_id = p.id
      ORDER BY p.name`
    );

    const projects = await Promise.all(
      projectsResult.rows.map(async (project: any) => {
        const projectData: any = {
          project_id: project.id,
          project_name: project.name,
        };

        // If project is mapped to Zoho, fetch real data
        if (project.zoho_project_id && userId) {
          try {
            // portalId is optional - getProjectManagementStatus will fetch it automatically if not provided
            const zohoStatus = await zohoService.getProjectManagementStatus(
              userId,
              project.zoho_project_id.toString(),
              undefined // portalId will be fetched automatically from user's token
            );
            
            // Add all project details from Zoho
            projectData.project_details = zohoStatus.project_details;
            projectData.rtl = zohoStatus.rtl;
            projectData.dv = zohoStatus.dv;
            projectData.pd = zohoStatus.pd;
            projectData.al = zohoStatus.al;
            projectData.dft = zohoStatus.dft;
            projectData.tickets = zohoStatus.tickets;
            projectData.tasks = zohoStatus.tasks;
            projectData.milestones_by_stage = zohoStatus.milestones_by_stage;
          } catch (zohoError: any) {
            console.error(`Error fetching Zoho data for project ${project.name}:`, zohoError.message);
            // Fall back to default values if Zoho fetch fails
            const defaultStatus = {
              overdue: 0,
              pending: 0,
              total: 0
            };
            projectData.rtl = { current_stage: 'N/A', milestone_status: defaultStatus };
            projectData.dv = { current_stage: 'N/A', milestone_status: defaultStatus };
            projectData.pd = { current_stage: 'N/A', milestone_status: defaultStatus };
            projectData.al = { current_stage: 'N/A', milestone_status: defaultStatus };
            projectData.dft = { current_stage: 'N/A', milestone_status: defaultStatus };
            projectData.tickets = { pending: 0, total: 0, open: 0, closed: 0 };
            projectData.tasks = { total: 0, open: 0, closed: 0 };
            projectData.project_details = {
              name: project.name,
              status: 'N/A',
              progress_percentage: 0
            };
          }
        } else {
          // For non-Zoho projects, return placeholder data
          const defaultStatus = {
            overdue: 0,
            pending: 0,
            total: 0
          };
          projectData.rtl = { current_stage: 'bronze/silver/gold', milestone_status: defaultStatus };
          projectData.dv = { current_stage: 'bronze/silver/gold', milestone_status: defaultStatus };
          projectData.pd = { current_stage: 'bronze/silver/gold', milestone_status: defaultStatus };
          projectData.al = { current_stage: 'bronze/silver/gold', milestone_status: defaultStatus };
          projectData.dft = { current_stage: 'bronze/silver/gold', milestone_status: defaultStatus };
          projectData.tickets = { pending: 0, total: 0, open: 0, closed: 0 };
          projectData.tasks = { total: 0, open: 0, closed: 0 };
          projectData.project_details = {
            name: project.name,
            status: 'N/A',
            progress_percentage: 0
          };
        }

        return projectData;
      })
    );

    res.json({
      success: true,
      projects: projects
    });
  } catch (error: any) {
    console.error('Error getting management status:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/projects/:projectIdentifier/cad-status
 * Get task and issue summary for CAD engineer view for a single project
 * Access:
 *  - Global role cad_engineer or admin, OR
 *  - Project-specific role cad_engineer in user_projects for this project
 */
router.get('/:projectIdentifier/cad-status', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const globalRole = (req as any).user?.role;
    const { projectIdentifier } = req.params;

    if (!userId) {
      return res.status(401).json({ error: 'User not authenticated' });
    }

    // Resolve ASI project ID from identifier (id, name, or Zoho project id)
    let asiProjectId: number | null = null;

    // Check if projectIdentifier is a number (ASI project ID)
    const numericId = parseInt(projectIdentifier, 10);
    if (!isNaN(numericId)) {
      const projectCheck = await pool.query('SELECT id FROM projects WHERE id = $1', [numericId]);
      if (projectCheck.rows.length > 0) {
        asiProjectId = numericId;
      }
    }

    // If not found by ID, try by name
    if (!asiProjectId) {
      const projectByName = await pool.query(
        'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
        [projectIdentifier]
      );
      if (projectByName.rows.length > 0) {
        asiProjectId = projectByName.rows[0].id;
      }
    }

    // If still not found, try Zoho project ID mapping
    if (!asiProjectId) {
      const zohoMapping = await pool.query(
        `SELECT local_project_id FROM zoho_projects_mapping 
         WHERE zoho_project_id = $1 OR zoho_project_id::text = $1`,
        [projectIdentifier]
      );
      if (zohoMapping.rows.length > 0) {
        asiProjectId = zohoMapping.rows[0].local_project_id;
      }
    }

    if (!asiProjectId) {
      return res.status(404).json({ error: 'Project not found' });
    }

    // Check project-specific CAD role (user_projects.role = 'cad_engineer')
    let hasCadAccess = false;
    if (globalRole === 'admin' || globalRole === 'cad_engineer') {
      hasCadAccess = true;
    } else {
      const upResult = await pool.query(
        `SELECT 1 FROM user_projects 
         WHERE user_id = $1 AND project_id = $2 AND role = 'cad_engineer'`,
        [userId, asiProjectId]
      );
      if (upResult.rows.length > 0) {
        hasCadAccess = true;
      }
    }

    if (!hasCadAccess) {
      return res.status(403).json({
        error: 'Access denied',
        message: 'CAD engineer access required for this project',
      });
    }

    // Get project name
    const projectResult = await pool.query(
      'SELECT name FROM projects WHERE id = $1',
      [asiProjectId]
    );
    const projectName = projectResult.rows[0]?.name || projectIdentifier;

    // Get Zoho project mapping
    const mappingResult = await pool.query(
      'SELECT zoho_project_id FROM zoho_projects_mapping WHERE local_project_id = $1',
      [asiProjectId]
    );

    let tasks: any[] = [];
    let bugs: any[] = [];
    let projectDetails: any = null; // Store for fallback use
    let zohoProjectId: string | null = null;

    // Try to get Zoho project ID from mapping first
    if (mappingResult.rows.length > 0) {
      zohoProjectId = mappingResult.rows[0].zoho_project_id;
    } else {
      // If not mapped, try to find the Zoho project by name
      try {
        const zohoService = (await import('../services/zoho.service')).default;
        const portals = await zohoService.getPortals(userId);
        
        if (portals.length > 0) {
          const portalId = portals[0].id;
          
          // Get all projects from Zoho and find by name
          const allProjects = await zohoService.getProjects(userId, portalId);
          const matchingProject = allProjects.find((p: any) => 
            p.name && p.name.toLowerCase() === projectName.toLowerCase()
          );
          
          if (matchingProject) {
            zohoProjectId = matchingProject.id_string || matchingProject.id;
          }
        }
      } catch (searchError: any) {
        // Silently fail - will use fallback counts if available
      }
    }

    // If we have a Zoho project ID (from mapping or search), fetch tasks and issues
    if (zohoProjectId) {

      // First, try to get project details to get task/issue counts as fallback
      try {
        projectDetails = await zohoService.getProject(userId, zohoProjectId.toString());
      } catch (projectError: any) {
        // Silently fail - will use fallback counts if available
      }

      // Fetch tasks and bugs/issues directly from Zoho
      // Use Promise.allSettled to handle partial failures gracefully
      const [tasksResult, bugsResult] = await Promise.allSettled([
        zohoService.getTasks(userId, zohoProjectId.toString()),
        zohoService.getBugs(userId, zohoProjectId.toString()),
      ]);

      // Extract results, using empty arrays if rejected
      if (tasksResult.status === 'fulfilled') {
        tasks = tasksResult.value || [];
      } else {
        console.error(`[CAD Status] Error fetching tasks:`, tasksResult.reason?.message || tasksResult.reason);
        tasks = []; // Use empty array on error
      }

      if (bugsResult.status === 'fulfilled') {
        bugs = bugsResult.value || [];
        console.log(`[CAD Status] Successfully fetched ${bugs.length} bugs for project ${projectName}`);
        
        // If bugs array is empty but project details show issue counts, log a warning
        if (bugs.length === 0 && projectDetails?.issues) {
          const totalIssues = (projectDetails.issues.open_count || 0) + (projectDetails.issues.closed_count || 0);
          if (totalIssues > 0) {
            console.warn(`[CAD Status] ⚠️  getBugs() returned 0 bugs but project details show ${totalIssues} issues. This might indicate a pagination or API issue.`);
          }
        }
      } else {
        console.error(`[CAD Status] Error fetching bugs for project ${projectName}:`, bugsResult.reason?.message || bugsResult.reason);
        console.error(`[CAD Status] Bug error stack:`, bugsResult.reason?.stack);
        bugs = []; // Use empty array on error
        
        // If we have project details, log the expected counts
        if (projectDetails?.issues) {
          const totalIssues = (projectDetails.issues.open_count || 0) + (projectDetails.issues.closed_count || 0);
          console.log(`[CAD Status] Project details indicate ${totalIssues} total issues (${projectDetails.issues.open_count || 0} open, ${projectDetails.issues.closed_count || 0} closed)`);
        }
      }

      console.log(`[CAD Status] Final result: ${tasks.length} tasks and ${bugs.length} bugs for project ${projectName}`);
    } else {
      // If not mapped, try to find the Zoho project by name
      console.log(`[CAD Status] Project ${projectName} (ASI ID: ${asiProjectId}) is NOT mapped. Searching for Zoho project by name...`);
      try {
        const portals = await zohoService.getPortals(userId);
        
        if (portals.length > 0) {
          const portalId = portals[0].id;
          console.log(`[CAD Status] Searching for Zoho project "${projectName}" in portal ${portalId}...`);
          
          // Get all projects from Zoho and find by name
          const allProjects = await zohoService.getProjects(userId, portalId);
          const matchingProject = allProjects.find((p: any) => 
            p.name && p.name.toLowerCase() === projectName.toLowerCase()
          );
          
          if (matchingProject) {
            const foundZohoProjectId = matchingProject.id_string || matchingProject.id;
            console.log(`[CAD Status] ✅ Found Zoho project "${projectName}" with ID: ${foundZohoProjectId}`);
            
            // Fetch project details for counts
            try {
              projectDetails = await zohoService.getProject(userId, foundZohoProjectId.toString());
              console.log(`[CAD Status] Got project details. Task counts: open=${projectDetails?.tasks?.open_count || 0}, closed=${projectDetails?.tasks?.closed_count || 0}`);
              console.log(`[CAD Status] Issue counts: open=${projectDetails?.issues?.open_count || 0}, closed=${projectDetails?.issues?.closed_count || 0}`);
            } catch (projectError: any) {
              console.warn(`[CAD Status] Could not fetch project details:`, projectError.message);
            }
            
            // Fetch tasks and bugs using the found Zoho project ID
            console.log(`[CAD Status] Fetching tasks and bugs for Zoho project ${foundZohoProjectId} (type: ${typeof foundZohoProjectId})...`);
            const [tasksResult, bugsResult] = await Promise.allSettled([
              zohoService.getTasks(userId, foundZohoProjectId.toString()),
              zohoService.getBugs(userId, foundZohoProjectId.toString()),
            ]);

            // Extract results
            if (tasksResult.status === 'fulfilled') {
              tasks = tasksResult.value || [];
              console.log(`[CAD Status] Successfully fetched ${tasks.length} tasks for project ${projectName}`);
            } else {
              console.error(`[CAD Status] Error fetching tasks:`, tasksResult.reason?.message || tasksResult.reason);
              tasks = [];
            }

            if (bugsResult.status === 'fulfilled') {
              bugs = bugsResult.value || [];
              console.log(`[CAD Status] Successfully fetched ${bugs.length} bugs for project ${projectName}`);
            } else {
              console.error(`[CAD Status] Error fetching bugs:`, bugsResult.reason?.message || bugsResult.reason);
              bugs = [];
            }
          } else {
            console.warn(`[CAD Status] ⚠️  Could not find Zoho project with name "${projectName}" in portal ${portalId}`);
            console.warn(`[CAD Status] To map this project, use POST /api/projects/map-zoho-project with zohoProjectId and asiProjectId=${asiProjectId}`);
          }
        }
      } catch (searchError: any) {
        console.error(`[CAD Status] Error searching for Zoho project:`, searchError.message);
        console.warn(`[CAD Status] To map this project, use POST /api/projects/map-zoho-project with zohoProjectId and asiProjectId=${asiProjectId}`);
      }
    }
    // If not mapped and not found, tasks and bugs remain empty arrays (default values)

    const summarizeItems = (items: any[]) => {
      const summary = {
        total: items.length,
        todo: 0,
        in_progress: 0,
        completed: 0,
      };

      items.forEach((item: any) => {
        const rawStatus =
          (item.status || item.status_name || item.status_details || '').toString().toLowerCase();

        let bucket: 'todo' | 'in_progress' | 'completed' = 'todo';

        if (
          rawStatus.includes('closed') ||
          rawStatus.includes('completed') ||
          rawStatus.includes('done') ||
          rawStatus.includes('fixed') ||
          rawStatus.includes('resolved')
        ) {
          bucket = 'completed';
        } else if (
          rawStatus.includes('in progress') ||
          rawStatus.includes('in-progress') ||
          rawStatus.includes('progress') ||
          rawStatus.includes('review') ||
          rawStatus.includes('reopen')
        ) {
          bucket = 'in_progress';
        } else if (
          rawStatus.includes('open') ||
          rawStatus.includes('todo') ||
          rawStatus.includes('to do')
        ) {
          bucket = 'todo';
        } else {
          // If status is unknown, treat as in progress
          bucket = 'in_progress';
        }

        summary[bucket]++;
      });

      return summary;
    };

    // If tasks/bugs arrays are empty but we have project details with counts, use those as fallback
    // This handles cases where getTasks/getBugs fail but project details show task/issue counts
    let taskSummary = summarizeItems(tasks);
    let issueSummary = summarizeItems(bugs);
    
    // Use project details counts as fallback if we don't have tasks/bugs
    if (projectDetails) {
      // If tasks array is empty but project details show task counts, use those
      if (tasks.length === 0 && projectDetails?.tasks) {
        const openCount = projectDetails.tasks.open_count || 0;
        const closedCount = projectDetails.tasks.closed_count || 0;
        const totalCount = openCount + closedCount;
        
        if (totalCount > 0) {
          console.log(`[CAD Status] Using project details task counts as fallback: ${totalCount} total (${openCount} open, ${closedCount} closed)`);
          taskSummary = {
            total: totalCount,
            todo: openCount, // Treat open as todo
            in_progress: 0,
            completed: closedCount,
          };
        }
      }
      
      // If bugs array is empty but project details show issue counts, use those
      if (bugs.length === 0 && projectDetails?.issues) {
        const openCount = projectDetails.issues.open_count || 0;
        const closedCount = projectDetails.issues.closed_count || 0;
        const totalCount = openCount + closedCount;
        
        if (totalCount > 0) {
          console.log(`[CAD Status] Using project details issue counts as fallback: ${totalCount} total (${openCount} open, ${closedCount} closed)`);
          issueSummary = {
            total: totalCount,
            todo: openCount, // Treat open as todo
            in_progress: 0,
            completed: closedCount,
          };
        }
      }
    }

    // Derive open/closed counts for convenience
    const tasksData = {
      ...taskSummary,
      open: taskSummary.todo + taskSummary.in_progress,
      closed: taskSummary.completed,
    };

    const issuesData = {
      ...issueSummary,
      open: issueSummary.todo + issueSummary.in_progress,
      closed: issueSummary.completed,
    };

    // Format tasks and issues for frontend consumption
    // Include essential fields: id, name/title, status, owner, etc.
    // Ensure all values are strings to avoid type errors in Flutter
    const formattedTasks = tasks.map((task: any) => {
      const id = task.id || task.task_id || task.id_string;
      const name = task.name || task.task_name || task.title || 'Untitled Task';
      
      // Extract status - handle both string and object formats
      let status = 'Unknown';
      if (task.status) {
        if (typeof task.status === 'string') {
          status = task.status;
        } else if (task.status.name) {
          status = task.status.name;
        } else if (task.status.status_name) {
          status = task.status.status_name;
        }
      } else if (task.status_name) {
        status = task.status_name;
      } else if (task.status_details) {
        status = task.status_details;
      }
      
      // Extract owner/assignee from details.owners array
      let owner = 'Unassigned';
      let ownerId = null;
      let ownerEmail = null;
      if (task.details?.owners && Array.isArray(task.details.owners) && task.details.owners.length > 0) {
        const primaryOwner = task.details.owners[0];
        owner = primaryOwner.full_name || primaryOwner.name || 'Unassigned';
        ownerId = primaryOwner.id || primaryOwner.zpuid || null;
        ownerEmail = primaryOwner.email || null;
      } else if (task.owner_name) {
        owner = task.owner_name;
      } else if (task.owner?.name) {
        owner = task.owner.name;
        ownerId = task.owner.id || null;
      } else if (task.assignee) {
        owner = task.assignee;
      }
      
      // Extract dates
      const startDate = task.start_date || task.start_date_format || null;
      const endDate = task.end_date || task.end_date_format || task.due_date || task.target_date || null;
      const createdDate = task.created_date || task.created_time || task.created_time_format || null;
      const createdBy = task.created_by_full_name || task.created_person || task.created_by_email || null;
      
      const tasklistName = task.tasklist_name || task.tasklist?.name || '';
      const priority = task.priority || task.priority_name || '';
      const description = task.description || '';
      const key = task.key || '';

      return {
        id: id != null ? String(id) : '',
        name: String(name),
        status: String(status),
        owner: String(owner),
        owner_id: ownerId != null ? String(ownerId) : null,
        owner_email: ownerEmail || null,
        start_date: startDate != null ? String(startDate) : null,
        due_date: endDate != null ? String(endDate) : null,
        created_date: createdDate != null ? String(createdDate) : null,
        created_by: createdBy || null,
        description: String(description),
        tasklist_name: String(tasklistName),
        priority: String(priority),
        key: String(key),
        // Include raw data for any additional fields needed
        raw: task,
      };
    });

    const formattedIssues = bugs.map((bug: any) => {
      const id = bug.id || bug.bug_id || bug.id_string;
      const name = bug.name || bug.bug_name || bug.title || bug.subject || 'Untitled Issue';
      
      // Extract status - handle both string and object formats
      let status = 'Unknown';
      if (bug.status) {
        if (typeof bug.status === 'string') {
          status = bug.status;
        } else if (bug.status.name) {
          status = bug.status.name;
        } else if (bug.status.status_name) {
          status = bug.status.status_name;
        }
      } else if (bug.status_name) {
        status = bug.status_name;
      } else if (bug.status_details) {
        status = bug.status_details;
      }
      
      // Extract owner/assignee from details.owners array
      let owner = 'Unassigned';
      let ownerId = null;
      let ownerEmail = null;
      if (bug.details?.owners && Array.isArray(bug.details.owners) && bug.details.owners.length > 0) {
        const primaryOwner = bug.details.owners[0];
        owner = primaryOwner.full_name || primaryOwner.name || 'Unassigned';
        ownerId = primaryOwner.id || primaryOwner.zpuid || null;
        ownerEmail = primaryOwner.email || null;
      } else if (bug.owner_name) {
        owner = bug.owner_name;
      } else if (bug.owner?.name) {
        owner = bug.owner.name;
        ownerId = bug.owner.id || null;
      } else if (bug.assignee) {
        owner = bug.assignee;
      }
      
      // Extract dates
      const startDate = bug.start_date || bug.start_date_format || null;
      const endDate = bug.end_date || bug.end_date_format || bug.due_date || bug.target_date || null;
      const createdDate = bug.created_date || bug.created_time || bug.created_time_format || null;
      const createdBy = bug.created_by_full_name || bug.created_person || bug.created_by_email || null;
      
      const priority = bug.priority || bug.priority_name || '';
      const severity = bug.severity || bug.severity_name || '';
      const description = bug.description || '';
      const key = bug.key || '';

      return {
        id: id != null ? String(id) : '',
        name: String(name),
        status: String(status),
        owner: String(owner),
        owner_id: ownerId != null ? String(ownerId) : null,
        owner_email: ownerEmail || null,
        start_date: startDate != null ? String(startDate) : null,
        due_date: endDate != null ? String(endDate) : null,
        created_date: createdDate != null ? String(createdDate) : null,
        created_by: createdBy || null,
        description: String(description),
        priority: String(priority),
        severity: String(severity),
        key: String(key),
        // Include raw data for any additional fields needed
        raw: bug,
      };
    });

    return res.json({
      success: true,
      data: {
        projectId: asiProjectId,
        projectName,
        // Summary data (backward compatible)
        tasks: tasksData,
        issues: issuesData,
        // Full lists - commented out as not needed in UI for now
        // tasksList: formattedTasks,
        // issuesList: formattedIssues,
      },
    });
  } catch (error: any) {
    console.error('Error getting CAD status:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;


