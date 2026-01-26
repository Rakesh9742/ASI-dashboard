import express, { Request, Response } from 'express';
import { pool } from '../config/database';
import { authenticate, authorize } from '../middleware/auth.middleware';
import zohoService from '../services/zoho.service';

const router = express.Router();

// Shape helpersF
const fetchProjectWithDomains = async (projectId: number, client: any) => {
  const projectResult = await client.query(
    `
      SELECT 
        p.*,
        COALESCE(
          json_agg(F
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
router.get('/', authenticate, async (req: Request, res: Response) => {
  try {
    const { includeZoho } = req.query;
    const userId = (req as any).user?.id;
    const userRole = (req as any).user?.role;
    
    // Log logged-in user info
    console.log(`\n🔵 ========== GET /api/projects ==========`);
    console.log(`🔵 Logged-in user: user_id=${userId}, role=${userRole}`);
    console.log(`🔵 includeZoho=${includeZoho}`);

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

    // Get SSH username from the current SSH session (whoami command)
    // This is the actual username on the server, not from database
    // Fallback to database username if SSH is not available
    let userUsername: string | null = null;
    if (userId) {
      try {
        const { executeSSHCommand } = await import('../services/ssh.service');
        const whoamiResult = await executeSSHCommand(userId, 'whoami', 1);
        if (whoamiResult.stdout && whoamiResult.stdout.trim()) {
          userUsername = whoamiResult.stdout.trim();
          console.log(`✅ Got SSH username for user ${userId}: ${userUsername}`);
        }
      } catch (e) {
        // If SSH command fails (connection not established, etc.), try to get from database
        console.log(`⚠️ SSH whoami failed for user ${userId}, trying database lookup:`, e);
        try {
          // Get username from database - check zoho_project_run_directories table for THIS user
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
            console.log(`✅ Got username from zoho_project_run_directories table for user ${userId}: ${userUsername}`);
          } else {
            // Try runs table - but runs table doesn't have user_id, so we need to check by user's email/username
            // Get user's email first
            const userResult = await pool.query(
              'SELECT email, username FROM users WHERE id = $1',
              [userId]
            );
            if (userResult.rows.length > 0) {
              const user = userResult.rows[0];
              const possibleUsername = user.username || extractUsernameFromEmail(user.email);
              
              if (possibleUsername) {
                // Try to find run directory with this username
                const userRunResult = await pool.query(
                  `SELECT DISTINCT user_name 
                   FROM runs 
                   WHERE user_name = $1 OR user_name LIKE $1 || '%'
                   ORDER BY last_updated DESC NULLS LAST, created_at DESC
                   LIMIT 1`,
                  [possibleUsername]
                );
                if (userRunResult.rows.length > 0 && userRunResult.rows[0].user_name) {
                  userUsername = userRunResult.rows[0].user_name;
                  console.log(`✅ Got username from runs table for user ${userId}: ${userUsername}`);
                }
              }
            }
          }
        } catch (dbError) {
          console.log(`⚠️ Database lookup also failed:`, dbError);
        }
      }
    }

    // Get local projects with run directory info and latest run status for the current user
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
          ) as domains,
          ${userUsername ? `(
            SELECT r.run_directory 
            FROM runs r
            INNER JOIN blocks b ON r.block_id = b.id
            WHERE b.project_id = p.id
              AND r.run_directory IS NOT NULL
              AND (
                r.user_name = $${queryParams.length + 1}
                OR r.user_name LIKE $${queryParams.length + 1} || '%'
                OR r.user_name LIKE '%' || $${queryParams.length + 1}
              )
            ORDER BY 
              CASE 
                WHEN r.user_name = $${queryParams.length + 1} THEN 1
                WHEN r.user_name LIKE $${queryParams.length + 1} || '%' THEN 2
                ELSE 3
              END,
              r.last_updated DESC NULLS LAST, 
              r.created_at DESC
            LIMIT 1
          ) as user_run_directory` : 'NULL as user_run_directory'},
          (
            SELECT s.run_status
            FROM stages s
            INNER JOIN runs r ON s.run_id = r.id
            INNER JOIN blocks b ON r.block_id = b.id
            WHERE b.project_id = p.id
            ORDER BY s.timestamp DESC
            LIMIT 1
          ) as latest_run_status
        FROM projects p
        ${joinClause}
        LEFT JOIN project_domains pd ON pd.project_id = p.id
        LEFT JOIN domains d ON d.id = pd.domain_id
        ${projectFilter}
        GROUP BY p.id
        ORDER BY p.created_at DESC
      `,
      userUsername ? [...queryParams, userUsername] : queryParams
    );

    // Check mapping status for local projects and derive status from latest run
    const localProjects = await Promise.all(
      result.rows.map(async (p: any) => {
        const isMapped = await checkProjectMapping(p.name);
        
        // Derive status from latest run status
        let projectStatus = 'RUNNING'; // Default to RUNNING
        if (p.latest_run_status) {
          const statusLower = p.latest_run_status.toLowerCase();
          if (statusLower === 'pass' || statusLower === 'completed' || statusLower === 'done') {
            projectStatus = 'COMPLETED';
          } else if (statusLower === 'fail' || statusLower === 'failed' || statusLower === 'error') {
            projectStatus = 'FAILED';
          } else if (statusLower === 'running' || statusLower === 'in progress' || statusLower === 'active') {
            projectStatus = 'RUNNING';
          }
        }
        
        return {
          ...p,
          source: 'local',
          status: projectStatus, // Add normalized status
          is_mapped: isMapped,
          run_directory: p.user_run_directory || null // Include run directory for the user
        };
      })
    );

    // If includeZoho is requested, fetch from Zoho Projects
    if (includeZoho === 'true' || includeZoho === '1') {
      console.log(`\n🔵 ========== FETCHING ZOHO PROJECTS ==========`);
      console.log(`🔵 Logged-in user_id: ${userId}, username: ${userUsername}`);
      console.log(`🔵 includeZoho=${includeZoho}`);
      try {
        const zohoService = (await import('../services/zoho.service')).default;
        const hasToken = await zohoService.hasValidToken(userId);
        
        if (hasToken) {
          const { portalId } = req.query;
          
          // OPTIMIZATION: Fetch portals and projects in parallel if portalId is not provided
          let currentPortalId = portalId as string | undefined;
          let zohoProjects: any[];
          
          if (!currentPortalId) {
            // Fetch portals and projects in parallel
            const [portals, projects] = await Promise.all([
              zohoService.getPortals(userId),
              zohoService.getProjects(userId, undefined)
            ]);
            
            if (portals.length > 0) {
              currentPortalId = portals[0].id;
            }
            zohoProjects = projects;
          } else {
            // Portal ID provided, just fetch projects
            zohoProjects = await zohoService.getProjects(userId, currentPortalId);
          }
          console.log(`🔵 Found ${zohoProjects.length} Zoho projects, now checking run directories...`);

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
          
          // OPTIMIZATION: Batch fetch all data at once instead of per-project queries
          console.log(`🔵 Optimizing: Batch fetching data for ${filteredZohoProjects.length} projects...`);
          
          // Extract all project IDs and names for batch queries
          const zohoProjectIds = filteredZohoProjects.map(zp => zp.id.toString());
          const zohoProjectNames = filteredZohoProjects.map(zp => zp.name);
          const zohoProjectNamesLower = zohoProjectNames.map(name => name.toLowerCase());
          
          // Batch 1: Check project mappings (which projects have EDA output)
          const mappedProjectsSet = new Set<string>();
          try {
            if (zohoProjectNames.length > 0) {
              const mappingCheckResult = await pool.query(
                `SELECT DISTINCT LOWER(p.name) as name
                 FROM projects p
                 INNER JOIN blocks b ON b.project_id = p.id
                 INNER JOIN runs r ON r.block_id = b.id
                 INNER JOIN stages s ON s.run_id = r.id
                 WHERE LOWER(p.name) = ANY($1)`,
                [zohoProjectNamesLower]
              );
              mappingCheckResult.rows.forEach((row: any) => {
                mappedProjectsSet.add(row.name);
              });
                }
              } catch (e) {
            console.error('Error batch checking project mappings:', e);
          }
          
          // Batch 2: Get all mappings from zoho_projects_mapping table
          const projectMappings = new Map<string, number>(); // zoho_project_id -> asi_project_id
          try {
            if (zohoProjectIds.length > 0) {
              const mappingResult = await pool.query(
                'SELECT zoho_project_id, local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = ANY($1)',
                [zohoProjectIds]
              );
              mappingResult.rows.forEach((row: any) => {
                if (row.local_project_id) {
                  projectMappings.set(row.zoho_project_id, row.local_project_id);
                }
              });
                  }
                } catch (e) {
            console.log('Could not batch fetch ASI project IDs from mapping table:', e);
          }
          
          // Batch 3: Get ASI project IDs by name for mapped projects without explicit mapping
          const nameToProjectId = new Map<string, number>(); // project_name_lower -> asi_project_id
          try {
            const unmappedNames = zohoProjectNamesLower.filter(name => 
              mappedProjectsSet.has(name) && !Array.from(projectMappings.values()).some(asiId => {
                // Check if this name is already mapped via zoho_projects_mapping
                return Array.from(projectMappings.entries()).some(([zohoId, asiId]) => {
                  const zp = filteredZohoProjects.find(p => p.id.toString() === zohoId);
                  return zp && zp.name.toLowerCase() === name;
                });
              })
            );
            
            if (unmappedNames.length > 0) {
              const nameMatchResult = await pool.query(
                'SELECT id, LOWER(name) as name_lower FROM projects WHERE LOWER(name) = ANY($1)',
                [unmappedNames]
              );
              nameMatchResult.rows.forEach((row: any) => {
                nameToProjectId.set(row.name_lower, row.id);
              });
                  }
                } catch (e) {
            console.log('Could not batch find ASI projects by name:', e);
          }
          
          // Batch 4: Get all run directories for mapped projects (from runs table)
          const mappedProjectRunDirs = new Map<number, string>(); // asi_project_id -> run_directory
          try {
            const mappedAsiProjectIds = Array.from(new Set(Array.from(projectMappings.values()).concat(
              Array.from(nameToProjectId.values())
            )));
            
            if (mappedAsiProjectIds.length > 0 && userUsername) {
              const runDirResult = await pool.query(
                `SELECT DISTINCT ON (b.project_id) b.project_id, r.run_directory
                 FROM runs r
                 INNER JOIN blocks b ON r.block_id = b.id
                 WHERE b.project_id = ANY($1) 
                   AND (r.user_name = $2 OR r.user_name LIKE $2 || '%' OR r.user_name LIKE '%' || $2)
                 ORDER BY b.project_id, r.last_updated DESC NULLS LAST, r.created_at DESC`,
                [mappedAsiProjectIds, userUsername]
              );
              runDirResult.rows.forEach((row: any) => {
                if (row.run_directory) {
                  mappedProjectRunDirs.set(row.project_id, row.run_directory);
                }
              });
            }
          } catch (e) {
            console.log('Could not batch fetch run directories from runs table:', e);
          }
          
          // Batch 5: Get all run directories from zoho_project_run_directories table
          const zohoProjectRunDirs = new Map<string, { directory: string; directories: string[] }>(); // zoho_project_id -> { directory, directories }
          try {
            if (zohoProjectIds.length > 0 && userId) {
              const zohoRunDirResult = await pool.query(
                `SELECT run_directory, zoho_project_id, zoho_project_name, block_name, experiment_name, user_id, updated_at, created_at
                       FROM zoho_project_run_directories 
                 WHERE (zoho_project_id = ANY($1) OR LOWER(zoho_project_name) = ANY($2))
                   AND user_id = $3
                 ORDER BY zoho_project_id, updated_at DESC, created_at DESC`,
                [zohoProjectIds, zohoProjectNamesLower, userId]
              );
              
              // Group by project
              const projectRunDirsMap = new Map<string, any[]>();
              zohoRunDirResult.rows.forEach((row: any) => {
                const key = row.zoho_project_id || row.zoho_project_name?.toLowerCase();
                if (key) {
                  if (!projectRunDirsMap.has(key)) {
                    projectRunDirsMap.set(key, []);
                  }
                  projectRunDirsMap.get(key)!.push(row);
                }
              });
              
              projectRunDirsMap.forEach((rows, key) => {
                const directories = rows
                  .filter((row: any) => row.run_directory)
                  .map((row: any) => row.run_directory);
                if (directories.length > 0) {
                  zohoProjectRunDirs.set(key, {
                    directory: directories[0],
                    directories: directories
                  });
                }
              });
                  }
                } catch (e) {
            console.log('Could not batch fetch run directories from zoho_project_run_directories table:', e);
              }

          // Batch 6: Get all export statuses
          const exportStatuses = new Map<string, boolean>(); // zoho_project_id -> exportedToLinux
              try {
            if (zohoProjectIds.length > 0) {
                const exportResult = await pool.query(
                `SELECT DISTINCT ON (zoho_project_id) zoho_project_id, exported_to_linux
                 FROM zoho_project_exports 
                 WHERE zoho_project_id = ANY($1)
                   AND (portal_id = $2 OR portal_id IS NULL) 
                 ORDER BY zoho_project_id, 
                     CASE WHEN portal_id = $2 THEN 1 ELSE 2 END,
                   portal_id DESC NULLS LAST, exported_at DESC`,
                [zohoProjectIds, currentPortalId]
              );
              exportResult.rows.forEach((row: any) => {
                exportStatuses.set(row.zoho_project_id, row.exported_to_linux === true);
              });
              
              // For projects without portal-specific export, check for any export
              const projectsWithoutExport = zohoProjectIds.filter(id => !exportStatuses.has(id));
              if (projectsWithoutExport.length > 0) {
                  const exportResultNoPortal = await pool.query(
                  `SELECT DISTINCT ON (zoho_project_id) zoho_project_id, exported_to_linux
                   FROM zoho_project_exports 
                   WHERE zoho_project_id = ANY($1)
                   ORDER BY zoho_project_id, exported_at DESC`,
                  [projectsWithoutExport]
                );
                exportResultNoPortal.rows.forEach((row: any) => {
                  if (!exportStatuses.has(row.zoho_project_id)) {
                    exportStatuses.set(row.zoho_project_id, row.exported_to_linux === true);
                  }
                });
                  }
                }
              } catch (e) {
            console.log('Could not batch fetch export statuses:', e);
          }
          
          console.log(`🔵 Batch fetch complete. Processing ${filteredZohoProjects.length} projects...`);
          
          // Now process each project using the batched data
          const formattedZohoProjects = filteredZohoProjects.map((zp: any) => {
              const projectNameLower = zp.name.toLowerCase();
              const isMapped = mappedProjectsSet.has(projectNameLower);
              
              // Get linked ASI project ID from batched data
              let asiProjectId: number | null = projectMappings.get(zp.id.toString()) || null;
              
              // If no mapping found but project is mapped, try to find ASI project by name
              if (isMapped && asiProjectId == null) {
                asiProjectId = nameToProjectId.get(projectNameLower) || null;
              }
              
              // Get run directory from batched data
              let zohoRunDirectory: string | null = null;
              let zohoRunDirectories: string[] = [];
              
              // Check mapped local project first
              if (asiProjectId && mappedProjectRunDirs.has(asiProjectId)) {
                zohoRunDirectory = mappedProjectRunDirs.get(asiProjectId)!;
                zohoRunDirectories = [zohoRunDirectory];
              } else {
                // Check unmapped Zoho project table
                const projectKey = zp.id.toString();
                const runDirData = zohoProjectRunDirs.get(projectKey) || 
                                 zohoProjectRunDirs.get(projectNameLower);
                if (runDirData) {
                  zohoRunDirectory = runDirData.directory;
                  zohoRunDirectories = runDirData.directories;
                }
              }
              
              // Get export status from batched data
              const exportedToLinux = exportStatuses.get(zp.id.toString()) || false;
              
              // Map Zoho status to standard status format
              let projectStatus = 'RUNNING'; // Default to RUNNING
              const zohoStatus = (zp.status || zp.custom_status_name || '').toLowerCase();
              if (zohoStatus.includes('completed') || zohoStatus.includes('closed') || zohoStatus.includes('done')) {
                projectStatus = 'COMPLETED';
              } else if (zohoStatus.includes('failed') || zohoStatus.includes('cancelled') || zohoStatus.includes('error')) {
                projectStatus = 'FAILED';
              } else if (zohoStatus.includes('running') || zohoStatus.includes('in progress') || zohoStatus.includes('active') || zohoStatus.includes('open')) {
                projectStatus = 'RUNNING';
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
                status: projectStatus, // Add normalized status
                zoho_project_id: zp.id,
                zoho_data: {
                  ...zp,
                  portal_id: currentPortalId, // Store portal ID in zoho_data
                  portal: currentPortalId
                },
                is_mapped: isMapped,
                asi_project_id: asiProjectId, // Add linked ASI project ID
                portal_id: currentPortalId, // Also store at top level for easy access
                exported_to_linux: exportedToLinux, // Add export status flag
                run_directory: zohoRunDirectory, // Latest run directory (for backward compatibility)
                run_directories: zohoRunDirectories // All run directories for the logged-in user
              };
          });

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
router.delete('/:id', authenticate, authorize('admin'), async (req: Request, res: Response) => {
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
router.get('/:id', authenticate, async (req: Request, res: Response) => {
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
  async (req: Request, res: Response) => {
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
  async (req: Request, res: Response) => {
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
  async (req: Request, res: Response) => {
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
  async (req: Request, res: Response) => {
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
router.get('/:projectIdentifier/user-role', authenticate, async (req: Request, res: Response) => {
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
    
    // PRIORITY 1: Check Zoho projects FIRST (before ASI projects)
    // This ensures Zoho projects are shown and roles are determined from Zoho
    let projectRole: string | null = null;
    let asiProjectId: number | null = null;
    
    try {
      // Get user email to match with Zoho members
      const userEmailResult = await pool.query(
        'SELECT email FROM users WHERE id = $1',
        [userId]
      );
      
      if (userEmailResult.rows.length > 0) {
        const userEmail = userEmailResult.rows[0].email;
        
        // Check if projectIdentifier looks like a Zoho project ID (long numeric string)
        // Or try to get Zoho project by name
        let zohoProjectId: string | null = null;
        
        // If it's a long numeric string (Zoho project IDs are typically 15+ digits)
        // PostgreSQL integer max is 2,147,483,647, so anything larger must be a Zoho ID
        const isLongNumeric = /^\d+$/.test(projectIdentifier);
        const numericValue = isLongNumeric ? parseInt(projectIdentifier, 10) : 0;
        const isZohoProjectId = isLongNumeric && (projectIdentifier.length >= 15 || numericValue > 2147483647);
        
        if (isZohoProjectId) {
          zohoProjectId = projectIdentifier;
        } else {
          // Try to find Zoho project by name
          try {
            const zohoProjects = await zohoService.getProjects(userId);
            const matchingProject = zohoProjects.find(
              (p: any) => p.name?.toLowerCase() === projectIdentifier.toLowerCase()
            );
            if (matchingProject) {
              zohoProjectId = matchingProject.id?.toString();
            }
          } catch (zohoError) {
            // Zoho API call failed, continue with fallback
          }
        }
        
        // If we have a Zoho project ID, get members and find user's role
        if (zohoProjectId) {
          try {
            const zohoMembers = await zohoService.getProjectMembers(userId, zohoProjectId);
            const userMember = zohoMembers.find(
              (m: any) => {
                const memberEmail = (m.email || m.Email || m.mail || '').toLowerCase();
                return memberEmail === userEmail.toLowerCase();
              }
            );
            
            if (userMember) {
              // Extract role - PRIORITIZE project-specific role over general role
              // project_profile contains the project-specific role (e.g., "CAD Engineer")
              // role contains the general/default role (e.g., "Employee")
              let zohoRole: any = userMember.project_profile || 
                                 userMember.project_role || 
                                 userMember.role_in_project ||
                                 userMember.role || 
                                 userMember.Role || 
                                 userMember.project_role_name ||
                                 userMember.designation;
              
              // Log the raw role to see its structure
              if (zohoRole && typeof zohoRole === 'object') {
                console.log(`[User Role API] Role is object for user ${userEmail} in project ${zohoProjectId}:`, JSON.stringify(zohoRole));
                // Extract the string value from object
                zohoRole = zohoRole.name || 
                           zohoRole.role || 
                           zohoRole.designation || 
                           zohoRole.value ||
                           zohoRole.label ||
                           zohoRole.title ||
                           zohoRole.id;
              }
              
              if (zohoRole) {
                // Convert to string if it's still not a string
                const roleString = typeof zohoRole === 'string' ? zohoRole : String(zohoRole);
                console.log(`[User Role API] Extracted role from project profile: "${roleString}" for user ${userEmail} in project ${zohoProjectId}`);
                // Map Zoho role to app role (handles both "Admin" and "admin" case-insensitively)
                projectRole = zohoService.mapZohoProjectRoleToAppRole(roleString);
                console.log(`[User Role API] Mapped to app role: "${projectRole}" for user ${userEmail}`);
              }
            }
          } catch (memberError: any) {
            console.error(`[User Role API] Failed to get Zoho members for project ${zohoProjectId}:`, memberError.message);
          }
        }
      }
    } catch (zohoCheckError) {
      // Zoho check failed, continue with fallback to ASI projects
    }
    
    // PRIORITY 2: Only check ASI projects if Zoho check didn't find a role
    // This happens after EDA output files are uploaded and projects are mapped
    if (!projectRole) {
      // Try to find ASI project ID from various identifiers
      
      // Check if projectIdentifier is a number (ASI project ID)
      // PostgreSQL integer max is 2,147,483,647, so only try to parse if it's within that range
      // Zoho project IDs are typically 15+ digits and exceed PostgreSQL integer limit
      const isNumeric = /^\d+$/.test(projectIdentifier);
      if (isNumeric) {
        const numericId = parseInt(projectIdentifier, 10);
        // Only try to use as ASI project ID if it's a valid integer (not too large for PostgreSQL)
        if (!isNaN(numericId) && numericId <= 2147483647) {
          const projectCheck = await pool.query(
            'SELECT id FROM projects WHERE id = $1',
            [numericId]
          );
          if (projectCheck.rows.length > 0) {
            asiProjectId = numericId;
          }
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
      
      // If still not found, try Zoho project ID mapping (for mapped projects)
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
      
      // If we found an ASI project ID, check for project-specific role in user_projects
      if (asiProjectId) {
        const userProjectResult = await pool.query(
          'SELECT role FROM user_projects WHERE user_id = $1 AND project_id = $2',
          [userId, asiProjectId]
        );
        if (userProjectResult.rows.length > 0) {
          projectRole = userProjectResult.rows[0].role;
        }
      }
    }
    
    // Determine effective role: project-specific role if exists, otherwise global role
    const effectiveRole = projectRole || globalRole;
    
    // Determine available view types based on role
    // IMPORTANT: Users with 'admin' role from project profile (Zoho) should have same access as global admins
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
      // Admins (both global and project-specific from Zoho) and PMs can see all views
      // This includes: engineer, lead, manager, management, and CAD views
      availableViewTypes.push('engineer', 'lead', 'manager', 'management', 'cad');
    }
    
    // If customer, also add customer view
    if (effectiveRole === 'customer') {
      availableViewTypes.push('customer');
    }
    
    // Special case: If user has admin role from project profile (even if global role is not admin),
    // ensure they have access to all views like a global admin
    if (projectRole === 'admin' && globalRole !== 'admin') {
      // User is admin in this project but not globally - give them all views
      if (!availableViewTypes.includes('engineer')) availableViewTypes.push('engineer');
      if (!availableViewTypes.includes('lead')) availableViewTypes.push('lead');
      if (!availableViewTypes.includes('manager')) availableViewTypes.push('manager');
      if (!availableViewTypes.includes('management')) availableViewTypes.push('management');
      if (!availableViewTypes.includes('cad')) availableViewTypes.push('cad');
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
  async (req: Request, res: Response) => {
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
router.get('/management/status', authenticate, async (req: Request, res: Response) => {
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
router.get('/:projectIdentifier/cad-status', authenticate, async (req: Request, res: Response) => {
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

    // If project is mapped to Zoho, fetch real data; otherwise return empty data
    if (mappingResult.rows.length > 0) {
      const zohoProjectId = mappingResult.rows[0].zoho_project_id;
      console.log(`[CAD Status] Project ${projectName} (ASI ID: ${asiProjectId}) is mapped to Zoho project ID: ${zohoProjectId}`);

      // Fetch tasks and bugs/issues directly from Zoho
      // Use Promise.allSettled to handle partial failures gracefully
      console.log(`[CAD Status] Fetching tasks and bugs for Zoho project ${zohoProjectId}...`);
      const [tasksResult, bugsResult] = await Promise.allSettled([
        zohoService.getTasks(userId, zohoProjectId.toString()),
        zohoService.getBugs(userId, zohoProjectId.toString()),
      ]);

      // Extract results, using empty arrays if rejected
      if (tasksResult.status === 'fulfilled') {
        tasks = tasksResult.value;
        console.log(`[CAD Status] Successfully fetched ${tasks.length} tasks for project ${projectName}`);
      } else {
        console.error(`[CAD Status] Error fetching tasks for project ${projectName}:`, tasksResult.reason?.message || tasksResult.reason);
        tasks = []; // Use empty array on error
      }

      if (bugsResult.status === 'fulfilled') {
        bugs = bugsResult.value;
        console.log(`[CAD Status] Successfully fetched ${bugs.length} bugs for project ${projectName}`);
      } else {
        console.error(`[CAD Status] Error fetching bugs for project ${projectName}:`, bugsResult.reason?.message || bugsResult.reason);
        bugs = []; // Use empty array on error
      }

      console.log(`[CAD Status] Final result: ${tasks.length} tasks and ${bugs.length} bugs for project ${projectName}`);
    } else {
      console.warn(`[CAD Status] Project ${projectName} (ASI ID: ${asiProjectId}) is NOT mapped to a Zoho project. Returning empty tasks/bugs.`);
      console.warn(`[CAD Status] To map this project, use POST /api/projects/map-zoho-project with zohoProjectId and asiProjectId=${asiProjectId}`);
    }
    // If not mapped, tasks and bugs remain empty arrays (default values)

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

    const taskSummary = summarizeItems(tasks);
    const issueSummary = summarizeItems(bugs);

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
        // Full lists
        tasksList: formattedTasks,
        issuesList: formattedIssues,
      },
    });
  } catch (error: any) {
    console.error('Error getting CAD status:', error);
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
 * POST /api/projects/save-run-directory
 * Save run directory path after setup command execution
 * Body: { projectName, blockName, experimentName, runDirectory, zohoProjectId? }
 * If zohoProjectId is provided and project is not mapped, saves to zoho_project_run_directories table
 * Otherwise, saves to runs table (for mapped or local projects)
 */
router.post(
  '/save-run-directory',
  authenticate,
  async (req: Request, res: Response) => {
    const client = await pool.connect();
    try {
      const { projectName, blockName, experimentName, runDirectory, zohoProjectId: providedZohoProjectId, username: sshUsername, domainCode } = req.body;
      
      // Debug logging
      console.log('Save run directory request:', {
        projectName,
        blockName,
        experimentName,
        domainCode,
        zohoProjectId: providedZohoProjectId,
        hasUsername: !!sshUsername
      });
      const userId = (req as any).user?.id;

      if (!projectName || !blockName || !experimentName) {
        return res.status(400).json({ 
          error: 'Missing required fields',
          message: 'projectName, blockName, and experimentName are required' 
        });
      }

      if (!runDirectory) {
        return res.status(400).json({ 
          error: 'Missing required field',
          message: 'runDirectory is required (should be fetched from remote server)' 
        });
      }

      if (!userId) {
        return res.status(401).json({ error: 'Unauthorized' });
      }

      // Use the username from SSH session (whoami command) - this is the actual username on the server
      if (!sshUsername || sshUsername.trim().length === 0) {
        return res.status(400).json({ 
          error: 'Missing username',
          message: 'Username from SSH session is required (should be obtained from whoami command)' 
        });
      }

      const finalUsername = sshUsername.trim();

      // Sanitize names (replace spaces with underscores, same as frontend)
      const sanitizedProjectName = projectName.replace(/\s+/g, '_');
      const sanitizedBlockName = blockName.replace(/\s+/g, '_');
      const sanitizedExperimentName = experimentName.trim();

      // Use the run directory path provided from remote server
      // Format should be: /CX_RUN_NEW/{projectName}/pd/users/{username}/{blockName}/{experimentName}
      const actualRunDirectory = runDirectory.trim();

      await client.query('BEGIN');

      // Simplified logic: Setup happens before EDA files, so no need to check mappings
      // If zohoProjectId is provided, save directly to zoho_project_run_directories
      // If no zohoProjectId, try to find it as Zoho project by name, then check local projects
      let projectId: number | null = null;
      let isZohoProject = false;
      let zohoProjectId: string | null = providedZohoProjectId || null;
      
      if (zohoProjectId) {
        // Zoho project - save directly to zoho_project_run_directories (no mapping check needed)
        isZohoProject = true;
        console.log('Saving as Zoho project with ID:', zohoProjectId);
      } else {
        // No zohoProjectId provided - try to find Zoho project by name first
        try {
          const zohoProjectResult = await client.query(
            'SELECT zoho_project_id FROM zoho_projects_mapping WHERE LOWER(zoho_project_name) = LOWER($1)',
            [projectName]
          );
          
          if (zohoProjectResult.rows.length > 0) {
            // Found as Zoho project - use it
            zohoProjectId = zohoProjectResult.rows[0].zoho_project_id;
            isZohoProject = true;
            console.log('Found Zoho project by name in mapping table, ID:', zohoProjectId);
          } else {
            // Not found in mapping table - try to find it via Zoho API
            try {
              const zohoProjects = await zohoService.getProjects(userId);
              const matchingProject = zohoProjects.find(
                (p: any) => p.name?.toLowerCase() === projectName.toLowerCase()
              );
              if (matchingProject && matchingProject.id) {
                zohoProjectId = matchingProject.id.toString();
                isZohoProject = true;
                console.log('Found Zoho project by name via API, ID:', zohoProjectId);
              } else {
                // Not found as Zoho project - check if it's a local project
                const projectResult = await client.query(
                  'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
                  [projectName]
                );

                if (projectResult.rows.length > 0) {
                  // Found local project
                  projectId = projectResult.rows[0].id;
                  console.log('Found local project, ID:', projectId);
                } else {
                  // Not found anywhere - return error
                  await client.query('ROLLBACK');
                  return res.status(404).json({ 
                    error: 'Project not found',
                    message: `Project "${projectName}" does not exist. Please ensure the project exists or provide the zohoProjectId if it's a Zoho project.` 
                  });
                }
              }
            } catch (zohoApiError) {
              // Zoho API call failed - check local projects
              console.log('Zoho API lookup failed, checking local projects:', zohoApiError);
              const projectResult = await client.query(
                'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
                [projectName]
              );

              if (projectResult.rows.length > 0) {
                projectId = projectResult.rows[0].id;
                console.log('Found local project, ID:', projectId);
              } else {
                await client.query('ROLLBACK');
                return res.status(404).json({ 
                  error: 'Project not found',
                  message: `Project "${projectName}" does not exist.` 
                });
              }
            }
          }
        } catch (e) {
          // If query fails, try local project lookup
          const projectResult = await client.query(
            'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
            [projectName]
          );

          if (projectResult.rows.length > 0) {
            projectId = projectResult.rows[0].id;
          } else {
            await client.query('ROLLBACK');
            return res.status(404).json({ 
              error: 'Project not found',
              message: `Project "${projectName}" does not exist.` 
            });
          }
        }
      }

      // Handle Zoho project - save directly to zoho_project_run_directories table
      // No mapping check needed since setup happens before EDA files
      if (isZohoProject) {
        if (!zohoProjectId) {
          await client.query('ROLLBACK');
          return res.status(400).json({ 
            error: 'Zoho project ID required',
            message: `Zoho project ID is required for Zoho projects. Please ensure the frontend passes the zohoProjectId.` 
          });
        }
        try {
          // Check if record already exists
          const existingResult = await client.query(
            `SELECT id FROM zoho_project_run_directories 
             WHERE zoho_project_id = $1 AND user_name = $2 AND block_name = $3 AND experiment_name = $4`,
            [zohoProjectId.toString(), finalUsername, blockName, sanitizedExperimentName]
          );

          if (existingResult.rows.length > 0) {
            // Update existing record
            await client.query(
              `UPDATE zoho_project_run_directories 
               SET run_directory = $1, updated_at = CURRENT_TIMESTAMP 
               WHERE id = $2`,
              [actualRunDirectory, existingResult.rows[0].id]
            );
          } else {
            // Insert new record
            await client.query(
              `INSERT INTO zoho_project_run_directories 
               (zoho_project_id, zoho_project_name, user_name, user_id, block_name, experiment_name, run_directory) 
               VALUES ($1, $2, $3, $4, $5, $6, $7)`,
              [zohoProjectId.toString(), projectName, finalUsername, userId, blockName, sanitizedExperimentName, actualRunDirectory]
            );
            console.log(`✅ Inserted run directory for Zoho project:`, {
              zoho_project_id: zohoProjectId.toString(),
              zoho_project_name: projectName,
              user_name: finalUsername,
              run_directory: actualRunDirectory
            });
          }

          await client.query('COMMIT');

          return res.json({
            success: true,
            message: 'Run directory saved successfully for Zoho project',
            data: {
              zohoProjectId: zohoProjectId.toString(),
              projectName,
              blockName,
              experimentName: sanitizedExperimentName,
              runDirectory: actualRunDirectory,
              username: finalUsername,
              isUnmappedZohoProject: true
            }
          });
        } catch (e: any) {
          await client.query('ROLLBACK');
          // If table doesn't exist, fall through to local project handling
          if (e.message && e.message.includes('does not exist')) {
            // Table doesn't exist yet - need to run migration
            return res.status(500).json({ 
              error: 'Database table not found',
              message: 'zoho_project_run_directories table does not exist. Please run migration 025_create_zoho_project_run_directories.sql'
            });
          }
          throw e;
        }
      }

      // Handle mapped or local project - save to runs table (existing logic)
      if (!projectId) {
        await client.query('ROLLBACK');
        return res.status(404).json({ 
          error: 'Project not found',
          message: `Project "${projectName}" does not exist` 
        });
      }

      // Link domain to project if domain code is provided (for setup command)
      if (domainCode && projectId) {
        try {
          // Find domain by code
          const domainResult = await client.query(
            'SELECT id FROM domains WHERE code = $1 AND is_active = true',
            [domainCode.toUpperCase()]
          );

          if (domainResult.rows.length > 0) {
            const domainId = domainResult.rows[0].id;
            // Link domain to project (if not already linked)
            await client.query(
              'INSERT INTO project_domains (project_id, domain_id) VALUES ($1, $2) ON CONFLICT (project_id, domain_id) DO NOTHING',
              [projectId, domainId]
            );
            console.log(`✅ Linked domain ${domainCode} to project ${projectName} (ID: ${projectId})`);
          } else {
            console.log(`⚠️ Domain with code ${domainCode} not found, skipping domain linking`);
          }
        } catch (error: any) {
          // Log error but don't fail the entire operation
          console.error('Error linking domain to project:', error.message);
        }
      }

      // Find or create block
      let blockResult = await client.query(
        'SELECT id FROM blocks WHERE project_id = $1 AND block_name = $2',
        [projectId, blockName]
      );

      let blockId: number;
      if (blockResult.rows.length > 0) {
        blockId = blockResult.rows[0].id;
      } else {
        const insertBlockResult = await client.query(
          'INSERT INTO blocks (project_id, block_name) VALUES ($1, $2) RETURNING id',
          [projectId, blockName]
        );
        blockId = insertBlockResult.rows[0].id;
      }

      // Find or create run (experiment)
      // Note: rtl_tag is required for unique constraint, so we'll use empty string as default
      const rtlTag = ''; // Default empty since it's not provided in setup
      
      // Check for existing run with same block_id, experiment, and rtl_tag (treating NULL as empty string)
      let runResult = await client.query(
        `SELECT id, run_directory FROM runs 
         WHERE block_id = $1 AND experiment = $2 AND COALESCE(rtl_tag, '') = $3`,
        [blockId, sanitizedExperimentName, rtlTag]
      );

      let runId: number;
      if (runResult.rows.length > 0) {
        runId = runResult.rows[0].id;
        // Update run_directory and ensure rtl_tag is set (in case it was NULL)
        await client.query(
          'UPDATE runs SET run_directory = $1, user_name = $2, rtl_tag = $3, updated_at = CURRENT_TIMESTAMP WHERE id = $4',
          [actualRunDirectory, finalUsername, rtlTag, runId]
        );
      } else {
        // Create new run
        const insertRunResult = await client.query(
          'INSERT INTO runs (block_id, experiment, rtl_tag, user_name, run_directory, last_updated) VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP) RETURNING id',
          [blockId, sanitizedExperimentName, rtlTag, finalUsername, actualRunDirectory]
        );
        runId = insertRunResult.rows[0].id;
      }

      await client.query('COMMIT');

      res.json({
        success: true,
        message: 'Run directory saved successfully',
        data: {
          projectId,
          blockId,
          runId,
          runDirectory: actualRunDirectory,
          projectName,
          blockName,
          experimentName: sanitizedExperimentName,
          username: finalUsername
        }
      });
    } catch (error: any) {
      await client.query('ROLLBACK');
      console.error('Error saving run directory:', error);
      res.status(500).json({ 
        error: 'Internal server error',
        message: error.message 
      });
    } finally {
      client.release();
    }
  }
);

/**
 * GET /api/projects/:projectIdOrName/blocks-experiments
 * Get all blocks and their experiments for a specific project
 * Supports both local projects (numeric ID) and Zoho projects (project name or zoho_<id> format)
 * Returns blocks and experiments from both setup data and EDA files
 */
router.get(
  '/:projectIdOrName/blocks-experiments',
  authenticate,
  async (req: Request, res: Response) => {
    const client = await pool.connect();
    try {
      const projectIdOrName = req.params.projectIdOrName;
      const userId = (req as any).user?.id;
      const userRole = (req as any).user?.role;
      
      console.log('🔵 [BACKEND] GET /api/projects/:projectIdOrName/blocks-experiments');
      console.log('   Project ID/Name: ', projectIdOrName);
      console.log('   User ID: ', userId);
      console.log('   User Role: ', userRole);
      
      // Check if this is a Zoho project (format: zoho_<zoho_project_id> or just project name)
      const isZohoProject = projectIdOrName.startsWith('zoho_');
      const zohoProjectId = isZohoProject ? projectIdOrName.replace('zoho_', '') : null;
      
      if (isZohoProject || zohoProjectId) {
        // Handle Zoho project - get from zoho_project_run_directories
        const actualZohoProjectId = zohoProjectId || projectIdOrName;
        
        // Get username from SSH session or database
        let userUsername: string | null = null;
        if (userId) {
          try {
            const { executeSSHCommand } = await import('../services/ssh.service');
            const whoamiResult = await executeSSHCommand(userId, 'whoami', 1);
            if (whoamiResult.stdout && whoamiResult.stdout.trim()) {
              userUsername = whoamiResult.stdout.trim();
            }
          } catch (e) {
            // Try database lookup
            const zohoRunResult = await client.query(
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
          }
        }
        
        // Query zoho_project_run_directories table
        let query = `
          SELECT 
            block_name,
            experiment_name as experiment,
            run_directory,
            user_name,
            created_at,
            updated_at as last_updated
          FROM zoho_project_run_directories
          WHERE zoho_project_id = $1
        `;
        
        const params: any[] = [actualZohoProjectId];
        
        // Filter by user if not admin/manager/lead
        if (userRole === 'engineer' || userRole === 'customer') {
          if (userUsername) {
            query += ` AND user_name = $2`;
            params.push(userUsername);
          } else {
            // If no username, return empty (user-specific data)
            client.release();
            return res.json({
              success: true,
              data: [],
            });
          }
        }
        
        query += ` ORDER BY block_name, experiment_name`;
        
        const result = await client.query(query, params);
        
        // Group by block_name and format as blocks with experiments
        const blocksMap = new Map<string, any>();
        
        for (const row of result.rows) {
          const blockName = row.block_name;
          if (!blocksMap.has(blockName)) {
            blocksMap.set(blockName, {
              block_id: null, // Zoho projects don't have block IDs
              block_name: blockName,
              project_id: null,
              block_created_at: row.created_at,
              experiments: [],
            });
          }
          
          const block = blocksMap.get(blockName)!;
          block.experiments.push({
            id: null, // Zoho projects don't have run IDs
            experiment: row.experiment,
            rtl_tag: null,
            user_name: row.user_name,
            run_directory: row.run_directory,
            last_updated: row.last_updated,
            created_at: row.created_at,
          });
        }
        
        const blocksData = Array.from(blocksMap.values());
        
        client.release();
        return res.json({
          success: true,
          data: blocksData,
        });
      } else {
        // Handle local project - try to parse as ID first, then try as name
        let projectId: number | null = null;
        
        // Try parsing as numeric ID
        const parsedId = parseInt(projectIdOrName, 10);
        if (!isNaN(parsedId)) {
          projectId = parsedId;
        } else {
          // Try finding by name
          const projectResult = await client.query(
            'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
            [projectIdOrName]
          );
          if (projectResult.rows.length > 0) {
            projectId = projectResult.rows[0].id;
          }
        }
        
        if (!projectId) {
          client.release();
          return res.status(404).json({ error: 'Project not found' });
        }
        
        // Check access
        let hasAccess = false;
        if (userRole === 'admin' || userRole === 'project_manager' || userRole === 'lead') {
          hasAccess = true;
        } else {
          const accessCheck = await client.query(
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
          client.release();
          return res.status(403).json({ 
            error: 'Access denied',
            message: 'You do not have access to this project'
          });
        }
        
        // Get blocks with their experiments (runs) from setup data
        const result = await client.query(
          `
            SELECT 
              b.id as block_id,
              b.block_name,
              b.project_id,
              b.created_at as block_created_at,
              COALESCE(
                json_agg(
                  json_build_object(
                    'id', r.id,
                    'experiment', r.experiment,
                    'rtl_tag', r.rtl_tag,
                    'user_name', r.user_name,
                    'run_directory', r.run_directory,
                    'last_updated', r.last_updated,
                    'created_at', r.created_at
                  )
                ) FILTER (WHERE r.id IS NOT NULL),
                '[]'
              ) as experiments
            FROM blocks b
            LEFT JOIN runs r ON r.block_id = b.id
            WHERE b.project_id = $1
            GROUP BY b.id, b.block_name, b.project_id, b.created_at
            ORDER BY b.block_name
          `,
          [projectId]
        );
        
        client.release();
        return res.json({
          success: true,
          data: result.rows,
        });
      }
    } catch (error: any) {
      if (client) client.release();
      console.error('Error fetching blocks and experiments:', error);
      res.status(500).json({ error: error.message });
    }
  }
);
export default router;





