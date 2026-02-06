import express, { Request, Response } from 'express';
import { pool } from '../config/database';
import { authenticate, authorize } from '../middleware/auth.middleware';
import zohoService from '../services/zoho.service';
import qmsService from '../services/qms.service';
import fileProcessorService from '../services/fileProcessor.service';

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

// List projects with their domains (optionally include Zoho projects)
router.get('/', authenticate, async (req: Request, res: Response) => {
  try {
    const { includeZoho } = req.query;
    const userId = (req as any).user?.id;
    const userRole = (req as any).user?.role;
    
    // Only fetch Zoho when frontend explicitly requests it (includeZoho=true).
    // Admin sees Zoho only when they have connected Zoho and frontend sends includeZoho=true.
    const effectiveIncludeZoho = includeZoho === 'true' || includeZoho === '1';

    // Log logged-in user info
    console.log(`\n🔵 ========== GET /api/projects ==========`);
    console.log(`🔵 Logged-in user: user_id=${userId}, role=${userRole}`);
    console.log(`🔵 includeZoho=${includeZoho}, effectiveIncludeZoho=${effectiveIncludeZoho}`);

    // Build query based on user role: only show projects where user is in user_projects table.
    // Admin sees all projects (to manage and assign users). Others see only projects they are part of.
    let projectFilter = '';
    let joinClause = '';
    const queryParams: any[] = [];
    
    console.log('Project filtering - User ID:', userId, 'Role:', userRole);
    
    if (userRole === 'customer') {
      // Customers: only projects assigned via user_projects
      joinClause = 'INNER JOIN user_projects up ON p.id = up.project_id';
      projectFilter = 'WHERE up.user_id = $1';
      queryParams.push(userId);
      console.log('Filtering projects for customer - only projects in user_projects:', userId);
    } else if (userRole === 'engineer') {
      // Engineers: only projects where user is in user_projects (not by created_by alone)
      const tableExistsResult = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' 
          AND table_name = 'user_projects'
        );
      `);
      const tableExists = tableExistsResult.rows[0]?.exists || false;
      if (tableExists) {
        joinClause = 'INNER JOIN user_projects up ON p.id = up.project_id';
        projectFilter = 'WHERE up.user_id = $1';
        queryParams.push(userId);
        console.log('Filtering projects for engineer - only projects in user_projects:', userId);
      } else {
        joinClause = '';
        projectFilter = 'WHERE p.created_by = $1 AND p.created_by IS NOT NULL';
        queryParams.push(userId);
        console.log('user_projects table missing - engineer filter by created_by only:', userId);
      }
    } else if (userRole === 'project_manager' || userRole === 'lead' || userRole === 'cad_engineer') {
      // project_manager, lead, cad_engineer: only projects where user is in user_projects
      joinClause = 'INNER JOIN user_projects up ON p.id = up.project_id';
      projectFilter = 'WHERE up.user_id = $1';
      queryParams.push(userId);
      console.log('Filtering projects for', userRole, '- only projects in user_projects:', userId);
    } else {
      // Admin: no filter - see all projects (to manage and assign users to projects)
      console.log('No filter applied - admin sees all projects');
    }

    // SSH username not used for GET /api/projects - skip to avoid slow SSH timeouts for all roles
    const userUsername: string | null = null;

    // Get local projects (admin also gets local projects; when Zoho not connected, admin sees them)
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
          ) as latest_run_status,
          (
            SELECT COALESCE(
              (SELECT s.timestamp
               FROM stages s
               INNER JOIN runs r ON s.run_id = r.id
               INNER JOIN blocks b ON r.block_id = b.id
               WHERE b.project_id = p.id
               ORDER BY s.timestamp DESC NULLS LAST
               LIMIT 1),
              (SELECT r.last_updated
               FROM runs r
               INNER JOIN blocks b ON r.block_id = b.id
               WHERE b.project_id = p.id
               ORDER BY r.last_updated DESC NULLS LAST, r.created_at DESC NULLS LAST
               LIMIT 1)
            )
          ) as last_run_at
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

    // Build local projects — exported_to_linux from projects table only (no other tables)
    const localProjects = result.rows.map((p: any) => {
      let projectStatus = 'IDLE'; // Default when no run status (was RUNNING — caused all projects to show as running)
      if (p.latest_run_status) {
        const statusLower = p.latest_run_status.toLowerCase();
        if (statusLower === 'pass' || statusLower === 'completed' || statusLower === 'done') projectStatus = 'COMPLETED';
        else if (statusLower === 'fail' || statusLower === 'failed' || statusLower === 'error') projectStatus = 'FAILED';
        else if (statusLower === 'running' || statusLower === 'in progress' || statusLower === 'active') projectStatus = 'RUNNING';
      }
      // Exported to Linux: from projects table only (p.exported_to_linux or p.setup_completed)
      const exportedToLinux = p.exported_to_linux === true || p.setup_completed === true;
      return {
        ...p,
        source: 'local',
        status: projectStatus,
        is_mapped: false,
        run_directory: p.user_run_directory || null,
        exported_to_linux: exportedToLinux,
        setup_completed: p.setup_completed === true
      };
    });
    
    // Filter local projects to only include those with technology_node
    const filteredLocalProjects = localProjects.filter((p: any) => {
      const techNode = p.technology_node;
      return techNode && techNode !== null && techNode !== '' && techNode !== 'N/A';
    });

    // If includeZoho is requested (or admin - admin sees only Zoho), fetch from Zoho Projects
    if (effectiveIncludeZoho) {
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
          const zohoProjectRunDirs = new Map<string, { directory: string; directories: string[]; last_run_at?: string | null }>(); // zoho_project_id -> { directory, directories, last_run_at }
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
          console.log('═══ [Zoho projects] Status from projects table when mapped (name | source | exported_to_linux | projectStatus) ═══');

          // Map: local project id -> { status, exported_to_linux } from projects table (single source of truth)
          const localProjectStatusById = new Map<number, { status: string; exported_to_linux: boolean; last_run_at?: string | null }>();
          filteredLocalProjects.forEach((p: any) => {
            localProjectStatusById.set(p.id, {
              status: p.status,
              exported_to_linux: p.exported_to_linux,
              last_run_at: p.last_run_at ?? null
            });
          });

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
              
              // Get run directory and last_run_at from batched data
              let zohoRunDirectory: string | null = null;
              let zohoRunDirectories: string[] = [];
              let lastRunAt: string | null = null;
              
              // Check mapped local project first
              if (asiProjectId && mappedProjectRunDirs.has(asiProjectId)) {
                zohoRunDirectory = mappedProjectRunDirs.get(asiProjectId)!;
                zohoRunDirectories = [zohoRunDirectory];
                const fromLocal = localProjectStatusById.get(asiProjectId);
                if (fromLocal?.last_run_at) lastRunAt = fromLocal.last_run_at;
              } else {
                // Check unmapped Zoho project table
                const projectKey = zp.id.toString();
                const runDirData = zohoProjectRunDirs.get(projectKey) || 
                                 zohoProjectRunDirs.get(projectNameLower);
                if (runDirData) {
                  zohoRunDirectory = runDirData.directory;
                  zohoRunDirectories = runDirData.directories;
                  if (runDirData.last_run_at) lastRunAt = runDirData.last_run_at;
                }
              }
              
              // Status and exported_to_linux: prefer projects table when Zoho project is linked to local (in DB)
              let exportedToLinux: boolean;
              let projectStatus: string;
              const fromProjectsTable = asiProjectId != null ? localProjectStatusById.get(asiProjectId) : null;
              if (fromProjectsTable) {
                exportedToLinux = fromProjectsTable.exported_to_linux;
                projectStatus = fromProjectsTable.status;
                console.log(`  [Zoho project] name=${zp.name} | from projects table (id=${asiProjectId}) | exported_to_linux=${exportedToLinux} | projectStatus=>${projectStatus}`);
              } else {
                // Not in projects table yet: use zoho_project_exports and Zoho API
                exportedToLinux = exportStatuses.get(zp.id.toString()) || false;
                projectStatus = 'IDLE';
                const zohoStatus = (zp.status || zp.custom_status_name || '').toLowerCase();
                if (zohoStatus.includes('completed') || zohoStatus.includes('closed') || zohoStatus.includes('done')) {
                  projectStatus = 'COMPLETED';
                } else if (zohoStatus.includes('failed') || zohoStatus.includes('cancelled') || zohoStatus.includes('error')) {
                  projectStatus = 'FAILED';
                } else if (exportedToLinux) {
                  projectStatus = 'RUNNING';
                } else if (zohoStatus.includes('running') || zohoStatus.includes('in progress')) {
                  projectStatus = 'RUNNING';
                }
                console.log(`  [Zoho project] name=${zp.name} | not in projects table | zohoStatus="${zohoStatus}" | exported_to_linux=${exportedToLinux} | projectStatus=>${projectStatus}`);
              }
              // Use local project last_run_at for mapped projects when not set from run dirs
              if (lastRunAt == null && fromProjectsTable?.last_run_at) lastRunAt = fromProjectsTable.last_run_at;

              // Extract technology_node from Zoho project data
              // Check multiple possible field names and locations
              let technologyNode: string | null = null;
              
              // Check direct fields first (various naming conventions)
              if (zp.technology_node) {
                technologyNode = String(zp.technology_node);
              } else if (zp.technology) {
                technologyNode = String(zp.technology);
              } else if (zp.technologyNode) {
                technologyNode = String(zp.technologyNode);
              } else if (zp['Technology Node']) {
                technologyNode = String(zp['Technology Node']);
              } else if (zp['technology node']) {
                technologyNode = String(zp['technology node']);
              }
              
              // Check custom_fields array if technology_node not found in direct fields
              // Zoho custom fields can be structured in different ways
              if (!technologyNode && zp.custom_fields) {
                if (Array.isArray(zp.custom_fields)) {
                  // Custom fields as array of objects
                  for (const field of zp.custom_fields) {
                    if (field && typeof field === 'object') {
                      // Check field value directly
                      if (field.technology_node || field.technologyNode || field.technology) {
                        technologyNode = String(field.technology_node || field.technologyNode || field.technology);
                        break;
                      }
                      // Check field label/name for "Technology Node" or "Technology"
                      const fieldLabel = (field.label || field.name || field.field_name || '').toLowerCase();
                      if ((fieldLabel.includes('technology') || fieldLabel.includes('node')) && field.value) {
                        technologyNode = String(field.value);
                        break;
                      }
                      // Check if field has a key matching technology node
                      const fieldKeys = Object.keys(field);
                      for (const key of fieldKeys) {
                        if (key.toLowerCase().includes('technology') && field[key]) {
                          technologyNode = String(field[key]);
                          break;
                        }
                      }
                      if (technologyNode) break;
                    }
                  }
                } else if (typeof zp.custom_fields === 'object') {
                  // Custom fields as object with field names as keys
                  const customFieldKeys = Object.keys(zp.custom_fields);
                  for (const key of customFieldKeys) {
                    const keyLower = key.toLowerCase();
                    if ((keyLower.includes('technology') || keyLower.includes('node')) && zp.custom_fields[key]) {
                      technologyNode = String(zp.custom_fields[key]);
                      break;
                    }
                  }
                }
              }
              
              // Check other possible field locations (case-insensitive search in object keys)
              // This handles cases where technology node might be a direct property with different casing
              if (!technologyNode) {
                const zpKeys = Object.keys(zp);
                for (const key of zpKeys) {
                  const keyLower = key.toLowerCase();
                  // Look for keys containing "technology" and optionally "node"
                  if ((keyLower.includes('technology') || (keyLower.includes('tech') && keyLower.includes('node'))) && zp[key]) {
                    technologyNode = String(zp[key]);
                    break;
                  }
                }
              }
              
              return {
                id: `zoho_${zp.id}`,
                name: zp.name,
                client: zp.owner_name || null,
                technology_node: technologyNode,
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
                run_directories: zohoRunDirectories, // All run directories for the logged-in user
                last_run_at: lastRunAt || zp.created_time || null // Latest run timestamp for project card
              };
          });

          console.log(`Showing ${formattedZohoProjects.length} Zoho projects for ${userRole} (mapping status included)`);

          // Filter Zoho projects to only include those with technology_node
          const zohoProjectsWithTechNode = formattedZohoProjects.filter((zp: any) => {
            const techNode = zp.technology_node;
            return techNode && techNode !== null && techNode !== '' && techNode !== 'N/A';
          });

          // Exclude local projects that are mapped to a Zoho project (so same project doesn't appear twice)
          const mappedLocalProjectIds = new Set(projectMappings.values());
          const localOnlyProjects = filteredLocalProjects.filter((p: any) => !mappedLocalProjectIds.has(p.id));

          // Combine: local-only projects + Zoho projects (mapped projects appear only as Zoho)
          const allProjects = [
            ...localOnlyProjects,
            ...zohoProjectsWithTechNode
          ];

          console.log(`Total projects: ${allProjects.length} (${localOnlyProjects.length} local-only, ${zohoProjectsWithTechNode.length} Zoho; ${filteredLocalProjects.length - localOnlyProjects.length} local hidden as mapped)`);

          return res.json({
            local: localOnlyProjects,
            zoho: zohoProjectsWithTechNode,
            all: allProjects,
            counts: {
              local: localOnlyProjects.length,
              zoho: zohoProjectsWithTechNode.length,
              total: allProjects.length
            }
          });
        } else {
          // Zoho not connected — show local projects for everyone (including admin)
          return res.json({
            local: filteredLocalProjects,
            zoho: [],
            all: filteredLocalProjects,
            counts: {
              local: filteredLocalProjects.length,
              zoho: 0,
              total: filteredLocalProjects.length
            },
            message: userRole === 'admin'
              ? 'Zoho not connected. Showing local projects. Connect Zoho to see Zoho projects.'
              : 'Zoho Projects not connected. Use /api/zoho/auth to connect.'
          });
        }
      } catch (zohoError: any) {
        console.error('Error fetching Zoho projects:', zohoError);
        // On Zoho error, show local projects for everyone (including admin)
        return res.json({
          local: filteredLocalProjects,
          zoho: [],
          all: filteredLocalProjects,
          counts: {
            local: filteredLocalProjects.length,
            zoho: 0,
            total: filteredLocalProjects.length
          },
          error: `Failed to fetch Zoho projects: ${zohoError.message}`
        });
      }
    }

    // No Zoho requested: return local projects only (same shape as Zoho response)
    return res.json({
      local: filteredLocalProjects,
      zoho: [],
      all: filteredLocalProjects,
      counts: {
        local: filteredLocalProjects.length,
        zoho: 0,
        total: filteredLocalProjects.length
      }
    });
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
 * GET /api/projects/:projectIdOrName/blocks
 * Get all blocks for a project from DB only. projectIdOrName can be numeric id or project name.
 * Admin and project_manager: ALL blocks. Lead: only blocks in which they are assigned (block_users). Others: only assigned when filterByAssigned=true.
 */
router.get(
  '/:projectIdOrName/blocks',
  authenticate,
  async (req: Request, res: Response) => {
    try {
      const projectIdOrName = String(req.params.projectIdOrName || '').trim();
      const userId = (req as any).user?.id;
      const userRole = (req as any).user?.role;
      const filterByAssigned = req.query.filterByAssigned === 'true' || req.query.filterByAssigned === '1';

      if (!projectIdOrName) {
        return res.status(400).json({ error: 'Invalid project ID or name' });
      }

      let projectId: number | null = null;
      if (projectIdOrName.startsWith('zoho_')) {
        const zohoId = projectIdOrName.replace('zoho_', '');
        const mappingResult = await pool.query(
          'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1 OR zoho_project_id::text = $1',
          [zohoId]
        );
        if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
          projectId = mappingResult.rows[0].local_project_id;
        }
        if (!projectId) {
          return res.json({ success: true, data: [] });
        }
      } else {
        const numericId = parseInt(projectIdOrName, 10);
        if (!Number.isNaN(numericId) && String(numericId) === projectIdOrName) {
          const byIdResult = await pool.query(
            'SELECT id FROM projects WHERE id = $1',
            [numericId]
          );
          if (byIdResult.rows.length > 0) {
            projectId = byIdResult.rows[0].id;
          } else {
            const byName = await pool.query(
              'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
              [projectIdOrName]
            );
            if (byName.rows.length > 0) projectId = byName.rows[0].id;
          }
        } else {
          const byName = await pool.query(
            'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
            [projectIdOrName]
          );
          if (byName.rows.length > 0) projectId = byName.rows[0].id;
        }
      }

      if (projectId == null) {
        return res.status(404).json({ error: 'Project not found' });
      }

      // Check if user has access to this project
      let hasAccess = false;
      if (userRole === 'admin' || userRole === 'project_manager' || userRole === 'lead') {
        hasAccess = true;
      } else {
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
          message: 'You do not have access to this project',
        });
      }

      // Global role = JWT (from users table only). Project-based role = user_projects only.
      const projectRoleRow = await pool.query(
        'SELECT role FROM user_projects WHERE user_id = $1 AND project_id = $2 LIMIT 1',
        [userId, projectId]
      );
      const projectRole = projectRoleRow.rows[0]?.role?.toString().trim() || null;
      const effectiveRole = (projectRole || userRole || '').toString().trim();
      const roleLowerBlocks = effectiveRole.toLowerCase();
      // Lead: always only blocks assigned to them (block_users). Admin and project_manager: all blocks. Others: filtered when filterByAssigned=true.
      const isAdminOrManagerBlocks = roleLowerBlocks === 'admin' || roleLowerBlocks === 'project_manager';
      const isLead = roleLowerBlocks === 'lead';
      const blockUsersExists = await pool.query(
        `SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'block_users')`
      );
      const hasBlockUsersTable = blockUsersExists.rows[0]?.exists === true;
      const useFilteredBlocks = hasBlockUsersTable && (filterByAssigned || isLead) && !isAdminOrManagerBlocks;
      console.log('🔵 [GET /blocks] globalRole:', userRole, '| projectRole:', projectRole, '| effectiveRole:', effectiveRole, '| filterByAssigned:', filterByAssigned, '| useFilteredBlocks (assigned only):', useFilteredBlocks);

      let result: { rows: any[] };
      if (useFilteredBlocks) {
        result = await pool.query(
          `
            SELECT b.id, b.block_name, b.project_id, b.created_at
            FROM blocks b
            INNER JOIN block_users bu ON bu.block_id = b.id AND bu.user_id = $2
            WHERE b.project_id = $1
            ORDER BY b.block_name
          `,
          [projectId, userId]
        );
        console.log('🔵 [GET /blocks] Returning ASSIGNED blocks only. Count:', result.rows.length, '| names:', result.rows.map((r: any) => r.block_name));
      } else {
        result = await pool.query(
          `
            SELECT id, block_name, project_id, created_at
            FROM blocks
            WHERE project_id = $1
            ORDER BY block_name
          `,
          [projectId]
        );
        console.log('🔵 [GET /blocks] Returning ALL blocks. Count:', result.rows.length);
      }

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
 * GET /api/projects/:projectIdOrName/rtl-tags?blockName=X
 * Get RTL tags for the given block. Admin/project_manager/lead see all RTL tags for the block;
 * other users see only RTL tags they created for that block (user_block_rtl_tags).
 */
router.get(
  '/:projectIdOrName/rtl-tags',
  authenticate,
  async (req: Request, res: Response) => {
    try {
      const projectIdOrName = String(req.params.projectIdOrName || '').trim();
      const blockName = String(req.query.blockName || '').trim();
      const userId = (req as any).user?.id;
      const userRole = ((req as any).user?.role ?? '').toString().toLowerCase();
      if (!userId) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      if (!blockName) {
        return res.json({ success: true, rtlTags: [] });
      }
      let projectId: number | null = null;
      if (projectIdOrName.startsWith('zoho_')) {
        const zohoId = projectIdOrName.replace('zoho_', '');
        const mappingResult = await pool.query(
          'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1 OR zoho_project_id::text = $1',
          [zohoId]
        );
        if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
          projectId = mappingResult.rows[0].local_project_id;
        }
      } else {
        const numericId = parseInt(projectIdOrName, 10);
        if (!Number.isNaN(numericId) && String(numericId) === projectIdOrName) {
          const byId = await pool.query('SELECT id FROM projects WHERE id = $1', [numericId]);
          if (byId.rows.length > 0) projectId = byId.rows[0].id;
        }
        if (projectId == null) {
          const byName = await pool.query('SELECT id FROM projects WHERE LOWER(name) = LOWER($1)', [projectIdOrName]);
          if (byName.rows.length > 0) projectId = byName.rows[0].id;
        }
      }
      if (projectId == null) {
        return res.json({ success: true, rtlTags: [] });
      }
      const blockResult = await pool.query(
        'SELECT id FROM blocks WHERE project_id = $1 AND block_name = $2',
        [projectId, blockName]
      );
      if (blockResult.rows.length === 0) {
        return res.json({ success: true, rtlTags: [] });
      }
      const blockId = blockResult.rows[0].id;
      const tableExists = await pool.query(
        `SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_block_rtl_tags')`
      );
      if (tableExists.rows[0]?.exists !== true) {
        return res.json({ success: true, rtlTags: [] });
      }
      // Show all RTL tags if: global role is admin/pm/lead, OR block-level role (block_users) is lead, OR project-level role (user_projects) is lead
      let showAllRtlTags = userRole === 'admin' || userRole === 'project_manager' || userRole === 'lead';
      if (!showAllRtlTags) {
        const blockRoleRow = await pool.query(
          `SELECT role FROM block_users WHERE block_id = $1 AND user_id = $2 LIMIT 1`,
          [blockId, userId]
        );
        const blockRole = (blockRoleRow.rows[0]?.role ?? '').toString().toLowerCase();
        if (blockRole === 'lead' || blockRole === 'admin' || blockRole === 'project_manager') showAllRtlTags = true;
      }
      if (!showAllRtlTags) {
        const projectRoleRow = await pool.query(
          `SELECT role FROM user_projects WHERE project_id = $1 AND user_id = $2 LIMIT 1`,
          [projectId, userId]
        );
        const projectRole = (projectRoleRow.rows[0]?.role ?? '').toString().toLowerCase();
        if (projectRole === 'lead' || projectRole === 'admin' || projectRole === 'project_manager') showAllRtlTags = true;
      }
      const rtlResult = showAllRtlTags
        ? await pool.query(
            `SELECT DISTINCT rtl_tag FROM user_block_rtl_tags WHERE block_id = $1 ORDER BY rtl_tag`,
            [blockId]
          )
        : await pool.query(
            `SELECT rtl_tag FROM user_block_rtl_tags WHERE user_id = $1 AND block_id = $2 ORDER BY rtl_tag`,
            [userId, blockId]
          );
      const rtlTags = (rtlResult.rows as any[]).map((r) => (r.rtl_tag ?? '').toString().trim()).filter(Boolean);
      return res.json({ success: true, rtlTags });
    } catch (error: any) {
      console.error('Error fetching rtl-tags:', error);
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

      // Filter by user role: engineers, cad_engineers, and customers only see their own runs
      if (userRole === 'engineer' || userRole === 'cad_engineer' || userRole === 'customer') {
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
 * Global role = users table only. Project-based role = user_projects only.
 * projectIdentifier can be: project ID (number), project name, or Zoho project ID
 */
router.get('/:projectIdentifier/user-role', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user?.id;
    const { projectIdentifier } = req.params;
    
    if (!userId) {
      return res.status(401).json({ error: 'User not authenticated' });
    }

    // Global role: from users table only
    const userResult = await pool.query(
      'SELECT role FROM users WHERE id = $1',
      [userId]
    );
    
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    const globalRole = userResult.rows[0].role;
    
    // For non-admin: role only from DB (user_projects). Do not use Zoho for role.
    let projectRole: string | null = null;
    let asiProjectId: number | null = null;
    
    if (globalRole === 'admin') {
      // Admin only: optionally resolve role from Zoho for Zoho projects
      try {
        const userEmailResult = await pool.query(
          'SELECT email FROM users WHERE id = $1',
          [userId]
        );
        if (userEmailResult.rows.length > 0) {
          const userEmail = userEmailResult.rows[0].email;
          let zohoProjectId: string | null = null;
          const isLongNumeric = /^\d+$/.test(projectIdentifier);
          const numericValue = isLongNumeric ? parseInt(projectIdentifier, 10) : 0;
          const isZohoProjectId = isLongNumeric && (projectIdentifier.length >= 15 || numericValue > 2147483647);
          if (isZohoProjectId) {
            zohoProjectId = projectIdentifier;
          } else {
            try {
              const zohoProjects = await zohoService.getProjects(userId);
              const matchingProject = zohoProjects.find(
                (p: any) => p.name?.toLowerCase() === projectIdentifier.toLowerCase()
              );
              if (matchingProject) zohoProjectId = matchingProject.id?.toString();
            } catch (_) {}
          }
          if (zohoProjectId) {
            try {
              const zohoMembers = await zohoService.getProjectMembers(userId, zohoProjectId);
              const userMember = zohoMembers.find(
                (m: any) => (m.email || m.Email || m.mail || '').toLowerCase() === userEmail.toLowerCase()
              );
              if (userMember) {
                let zohoRole: any = userMember.project_profile || userMember.project_role || userMember.role_in_project || userMember.role || userMember.Role || userMember.project_role_name || userMember.designation;
                if (zohoRole && typeof zohoRole === 'object') {
                  zohoRole = zohoRole.name || zohoRole.role || zohoRole.designation || zohoRole.value || zohoRole.label || zohoRole.title || zohoRole.id;
                }
                if (zohoRole) {
                  projectRole = zohoService.mapZohoProjectRoleToAppRole(typeof zohoRole === 'string' ? zohoRole : String(zohoRole));
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    
    // Project-based role: from user_projects only (or Zoho for admin on Zoho projects)
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
    
    // Determine effective role: project-specific role if exists, otherwise global role.
    // Exception: when global role is project_manager, keep them as manager (don't elevate to admin
    // if project role is admin), so they get manager experience (dashboard, manager view), not admin/management-only.
    let effectiveRole = projectRole || globalRole;
    if (globalRole === 'project_manager' && projectRole === 'admin') {
      effectiveRole = 'project_manager';
    }
    
    // Determine available view types based on role
    // Admin: all views. Manager: engineer, lead, manager. Lead: engineer, lead. CAD: cad only.
    const availableViewTypes: string[] = [];
    if (effectiveRole === 'management') {
      // Management role only sees management view
      availableViewTypes.push('management');
    } else if (effectiveRole === 'cad_engineer') {
      // CAD can see only CAD view
      availableViewTypes.push('cad');
    } else if (effectiveRole === 'engineer' || effectiveRole === 'customer') {
      availableViewTypes.push('engineer');
    } else if (effectiveRole === 'lead') {
      // Lead can see engineer view and lead view of that project
      availableViewTypes.push('engineer', 'lead');
    } else if (effectiveRole === 'project_manager') {
      // Manager can see only lead view, manager view, and engineer view of that project
      availableViewTypes.push('engineer', 'lead', 'manager');
    } else if (effectiveRole === 'admin') {
      // Admin can see all views
      availableViewTypes.push('engineer', 'lead', 'manager', 'management', 'cad');
    }
    
    // If customer, also add customer view
    if (effectiveRole === 'customer') {
      availableViewTypes.push('customer');
    }
    
    // Special case: If user has admin role from project profile only (global role is not admin),
    // they see only the management view for that project (no block selection, no setup).
    // Exclude project_manager: managers with project role admin stay as manager (dashboard + manager view).
    if (projectRole === 'admin' && globalRole !== 'admin' && globalRole !== 'project_manager') {
      availableViewTypes.length = 0;
      availableViewTypes.push('management');
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

      // Insert or update mapping (zoho_projects_mapping has no portal_id column)
      const result = await pool.query(
        `INSERT INTO zoho_projects_mapping 
         (zoho_project_id, local_project_id, zoho_project_name)
         VALUES ($1, $2, $3)
         ON CONFLICT (zoho_project_id)
         DO UPDATE SET 
           local_project_id = EXCLUDED.local_project_id,
           zoho_project_name = COALESCE(EXCLUDED.zoho_project_name, zoho_projects_mapping.zoho_project_name),
           updated_at = CURRENT_TIMESTAMP
         RETURNING *`,
        [
          zohoProjectId.toString(),
          finalAsiProjectId,
          zohoProjectName || null
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
    
    // Global admin/management, or user with project-role "admin" in at least one project, can access
    if (userRole === 'management' || userRole === 'admin') {
      // Allow
    } else if (userId) {
      const projectAdminCheck = await pool.query(
        'SELECT 1 FROM user_projects WHERE user_id = $1 AND role = $2 LIMIT 1',
        [userId, 'admin']
      );
      if (projectAdminCheck.rows.length === 0) {
        return res.status(403).json({ error: 'Access denied. Management or admin role required.' });
      }
    } else {
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
 * POST /api/projects/mark-setup-completed
 * Mark project setup as completed (e.g. when CAD engineer finishes Export to Linux / createDir.py successfully).
 * Updates projects.setup_completed and setup_completed_at only.
 * Body: { projectId?: string | number, projectName?: string } — resolve by id, zoho mapping, or name.
 */
router.post(
  '/mark-setup-completed',
  authenticate,
  async (req: Request, res: Response) => {
    try {
      const { projectId: rawProjectId, projectName } = req.body;
      const userId = (req as any).user?.id;
      if (!userId) {
        return res.status(401).json({ error: 'Unauthorized' });
      }

      let localProjectId: number | null = null;
      const projectIdStr = rawProjectId != null ? String(rawProjectId).trim() : '';

      // Resolve to local project: by numeric id, by zoho mapping, or by name
      if (projectIdStr && /^\d+$/.test(projectIdStr)) {
        localProjectId = parseInt(projectIdStr, 10);
      } else if (projectIdStr && (projectIdStr.startsWith('zoho_') || !projectIdStr.startsWith('zoho_'))) {
        const zohoId = projectIdStr.replace(/^zoho_/, '');
        const mappingResult = await pool.query(
          'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1 OR zoho_project_id::text = $1',
          [zohoId]
        );
        if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
          localProjectId = mappingResult.rows[0].local_project_id;
        }
      }
      if (!localProjectId && projectName) {
        const byName = await pool.query(
          'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
          [String(projectName).trim()]
        );
        if (byName.rows.length > 0) {
          localProjectId = byName.rows[0].id;
        }
      }

      if (!localProjectId) {
        return res.status(404).json({
          error: 'Project not found',
          message: 'Could not resolve project by id or name.',
        });
      }

      await pool.query(
        `UPDATE projects SET setup_completed = true, setup_completed_at = CURRENT_TIMESTAMP, exported_to_linux = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
        [localProjectId]
      );
      console.log(`✅ Marked setup completed and exported_to_linux for project id ${localProjectId}`);

      return res.json({
        success: true,
        message: 'Project setup marked as completed',
        data: { projectId: localProjectId },
      });
    } catch (error: any) {
      console.error('Error marking setup completed:', error);
      return res.status(500).json({
        error: 'Internal server error',
        message: error.message,
      });
    }
  }
);

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
      const { projectName, blockName, experimentName, runDirectory, zohoProjectId: providedZohoProjectId, username: sshUsername, domainCode, rtlTag: bodyRtlTag } = req.body;
      
      // Debug logging
      console.log('Save run directory request:', {
        projectName,
        blockName,
        experimentName,
        rtlTag: bodyRtlTag,
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

      // Sanitize names (replace spaces with underscores, same as frontend); experiment name: lowercase only
      const sanitizedProjectName = projectName.replace(/\s+/g, '_');
      const sanitizedBlockName = blockName.replace(/\s+/g, '_');
      const sanitizedExperimentName = experimentName.trim().toLowerCase();
      if (!/^[a-z0-9_]+$/.test(sanitizedExperimentName)) {
        return res.status(400).json({
          error: 'Invalid experiment name',
          message: 'Experiment name must contain only lowercase letters, numbers, and underscores',
        });
      }

      // RTL tag: from body (engineer creates/selects during setup); lowercase only; empty string allowed for backward compat
      const rawRtlTag = bodyRtlTag != null ? String(bodyRtlTag).trim() : '';
      const rtlTag = rawRtlTag.toLowerCase();
      if (rawRtlTag.length > 0 && !/^[a-z0-9_]+$/.test(rtlTag)) {
        return res.status(400).json({
          error: 'Invalid RTL tag',
          message: 'RTL tag must contain only lowercase letters, numbers, and underscores',
        });
      }

      // Use the run directory path provided from remote server
      // Format: /CX_RUN_NEW/{project}/pd/users/{username}/{block}/{experimentName} or .../{block}/{rtlTag}/{experimentName} when rtl_tag set
      const actualRunDirectory = runDirectory.trim();

      await client.query('BEGIN');

      // Resolve to local project only: update projects table and runs table only (never zoho_project_run_directories)
      let projectId: number | null = null;
      if (providedZohoProjectId) {
        const mappingResult = await client.query(
          'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1 OR zoho_project_id::text = $1',
          [providedZohoProjectId.toString()]
        );
        if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
          projectId = mappingResult.rows[0].local_project_id;
          console.log('Resolved Zoho project to local project ID:', projectId);
        }
      }
      if (!projectId) {
        const projectResult = await client.query(
          'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
          [projectName]
        );
        if (projectResult.rows.length > 0) {
          projectId = projectResult.rows[0].id;
          console.log('Resolved project by name, ID:', projectId);
        }
      }
      if (!projectId) {
        await client.query('ROLLBACK');
        return res.status(404).json({ 
          error: 'Project not found',
          message: `Project "${projectName}" does not exist.` 
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

      // Record RTL tag for this user+block (for dropdown: engineer-created tags)
      try {
        const tableExists = await client.query(
          `SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_block_rtl_tags')`
        );
        if (tableExists.rows[0]?.exists === true && rtlTag.length > 0) {
          await client.query(
            `INSERT INTO user_block_rtl_tags (user_id, block_id, rtl_tag) VALUES ($1, $2, $3)
             ON CONFLICT (user_id, block_id, rtl_tag) DO NOTHING`,
            [userId, blockId, rtlTag]
          );
        }
      } catch (ubrtErr: any) {
        console.warn('Could not save to user_block_rtl_tags:', ubrtErr?.message);
      }

      // Find or create run (experiment) with rtl_tag from engineer (or empty for backward compat)
      const rtlTagForRun = rtlTag; // use sanitized rtl_tag from body
      // Assign domain from run_directory path (e.g. /CX_PROJ/proj/pd/users/... → domain "pd"); do not take domain from EDA files
      const domainId = await fileProcessorService.getDomainIdFromRunDirectory(actualRunDirectory);
      console.log(`[Experiment Setup] Assigned domain_id=${domainId ?? 'null'} from run_directory: ${actualRunDirectory}`);

      let runResult = await client.query(
        `SELECT id, run_directory FROM runs 
         WHERE block_id = $1 AND experiment = $2 AND COALESCE(rtl_tag, '') = $3`,
        [blockId, sanitizedExperimentName, rtlTagForRun]
      );

      let runId: number;
      const isNewRun = runResult.rows.length === 0;
      if (!isNewRun) {
        runId = runResult.rows[0].id;
        await client.query(
          'UPDATE runs SET run_directory = $1, user_name = $2, rtl_tag = $3, domain_id = $4, updated_at = CURRENT_TIMESTAMP WHERE id = $5',
          [actualRunDirectory, finalUsername, rtlTagForRun, domainId, runId]
        );
      } else {
        const insertRunResult = await client.query(
          'INSERT INTO runs (block_id, experiment, rtl_tag, user_name, run_directory, last_updated, domain_id) VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, $6) RETURNING id',
          [blockId, sanitizedExperimentName, rtlTagForRun, finalUsername, actualRunDirectory, domainId]
        );
        runId = insertRunResult.rows[0].id;
      }

      // Store run_directory in block_users (per block per user; used when engineer completes setup)
      try {
        await client.query(
          `INSERT INTO block_users (block_id, user_id, run_directory)
           VALUES ($1, $2, $3)
           ON CONFLICT (block_id, user_id) DO UPDATE SET run_directory = EXCLUDED.run_directory`,
          [blockId, userId, actualRunDirectory]
        );
        console.log(`✅ Saved run_directory to block_users for block_id=${blockId}, user_id=${userId}`);
      } catch (blockUsersErr: any) {
        // Log but don't fail if block_users table or column doesn't exist yet (migration not run)
        console.warn('Could not save run_directory to block_users:', blockUsersErr?.message);
      }

      // Mark project setup and exported_to_linux in projects table only
      await client.query(
        `UPDATE projects SET setup_completed = true, setup_completed_at = CURRENT_TIMESTAMP, exported_to_linux = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
        [projectId]
      );

      await client.query('COMMIT');

      if (isNewRun) {
        try {
          await qmsService.ensureDefaultChecklistForBlockExperiment(blockId, sanitizedExperimentName, userId);
        } catch (qmsError: any) {
          console.error('Error auto-creating default checklist template:', qmsError?.message || qmsError);
        }
      }

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
 * Get blocks and experiments for a project from DB only (no Zoho).
 * If projectIdOrName is zoho_<id>, resolve to local project via mapping; if no mapping, return [].
 * Admin, project_manager: see ALL blocks and all runs. Lead: only blocks assigned (block_users) and ALL runs in those blocks. Others: only blocks assigned and runs they created.
 */
router.get(
  '/:projectIdOrName/blocks-experiments',
  authenticate,
  async (req: Request, res: Response) => {
    const client = await pool.connect();
    try {
      const projectIdOrName = String(req.params.projectIdOrName || '').trim();
      const userId = (req as any).user?.id;
      const userRole = (req as any).user?.role;

      console.log('🔵 [BACKEND] GET /api/projects/:projectIdOrName/blocks-experiments (DB only)');
      console.log('   Project ID/Name: ', projectIdOrName);
      console.log('   User ID: ', userId);
      console.log('   User Role: ', userRole);

      // Resolve to local project ID only (no Zoho fetch)
      let projectId: number | null = null;
      if (projectIdOrName.startsWith('zoho_')) {
        const zohoId = projectIdOrName.replace('zoho_', '');
        const mappingResult = await client.query(
          'SELECT local_project_id FROM zoho_projects_mapping WHERE zoho_project_id = $1 OR zoho_project_id::text = $1',
          [zohoId]
        );
        if (mappingResult.rows.length > 0 && mappingResult.rows[0].local_project_id) {
          projectId = mappingResult.rows[0].local_project_id;
        }
        if (!projectId) {
          client.release();
          return res.json({ success: true, data: [] });
        }
      } else {
        const parsedId = parseInt(projectIdOrName, 10);
        if (!Number.isNaN(parsedId) && String(parsedId) === projectIdOrName) {
          const byIdResult = await client.query(
            'SELECT id FROM projects WHERE id = $1',
            [parsedId]
          );
          if (byIdResult.rows.length > 0) {
            projectId = byIdResult.rows[0].id;
          } else {
            // If numeric ID doesn't exist, try treating it as a project name
            const projectResult = await client.query(
              'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
              [projectIdOrName]
            );
            if (projectResult.rows.length > 0) projectId = projectResult.rows[0].id;
          }
        } else {
          const projectResult = await client.query(
            'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
            [projectIdOrName]
          );
          if (projectResult.rows.length > 0) projectId = projectResult.rows[0].id;
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
          message: 'You do not have access to this project',
        });
      }

      // Global role = JWT (from users table only). Project-based role = user_projects only.
      const projectRoleRow = await client.query(
        'SELECT role FROM user_projects WHERE user_id = $1 AND project_id = $2 LIMIT 1',
        [userId, projectId]
      );
      const projectRole = projectRoleRow.rows[0]?.role?.toString().trim() || null;
      const effectiveRole = (projectRole || userRole || '').toString().trim();
      const roleLower = effectiveRole.toLowerCase();
      const blockUsersExists = await client.query(
        `SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'block_users')`
      );
      const hasBlockUsersTable = blockUsersExists.rows[0]?.exists === true;
      const blockUsersRoleExists = await client.query(
        `SELECT EXISTS (
           SELECT FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'block_users' AND column_name = 'role'
         )`
      );
      const hasBlockUsersRoleColumn = blockUsersRoleExists.rows[0]?.exists === true;
      const blockUserRoleSelect = hasBlockUsersRoleColumn ? 'MAX(bu.role) as block_user_role,' : 'NULL as block_user_role,';

      // Admin and project_manager see all blocks and all runs. Lead sees only assigned blocks but all runs in those blocks.
      const showAll = roleLower === 'admin' || roleLower === 'project_manager';
      console.log('🔵 [blocks-experiments] globalRole:', userRole, '| projectRole:', projectRole, '| effectiveRole:', effectiveRole, '| showAll (see all blocks):', showAll);

      if (showAll) {
        // All blocks and all runs from DB; include block_users.run_directory for current user when present
        const result = await client.query(
          `
            SELECT 
              b.id as block_id,
              b.block_name,
              b.project_id,
              b.created_at as block_created_at,
              MAX(bu.run_directory) as block_user_run_directory,
              ${blockUserRoleSelect}
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
            LEFT JOIN block_users bu ON bu.block_id = b.id AND bu.user_id = $2
            LEFT JOIN runs r ON r.block_id = b.id
            WHERE b.project_id = $1
            GROUP BY b.id, b.block_name, b.project_id, b.created_at
            ORDER BY b.block_name
          `,
          [projectId, userId]
        );
        console.log('🔵 [blocks-experiments] Returning ALL blocks for admin/manager. Count:', result.rows.length, '| block_names:', result.rows.map((r: any) => r.block_name));
        client.release();
        return res.json({ success: true, data: result.rows });
      }

      // Lead: only blocks assigned (block_users), but ALL runs in those blocks. Engineer: only blocks assigned and only runs they created.
      console.log('🔵 [blocks-experiments] hasBlockUsersTable:', hasBlockUsersTable);

      // Lead: only blocks assigned to lead (block_users), all runs in those blocks (any user)
      if (roleLower === 'lead' && hasBlockUsersTable) {
        const result = await client.query(
          `
            SELECT 
              b.id as block_id,
              b.block_name,
              b.project_id,
              b.created_at as block_created_at,
              MAX(bu.run_directory) as block_user_run_directory,
              ${blockUserRoleSelect}
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
            INNER JOIN block_users bu ON bu.block_id = b.id AND bu.user_id = $2
            LEFT JOIN runs r ON r.block_id = b.id
            WHERE b.project_id = $1
            GROUP BY b.id, b.block_name, b.project_id, b.created_at
            ORDER BY b.block_name
          `,
          [projectId, userId]
        );
        const rows = (result.rows as any[]).map((row: any) => ({
          ...row,
          experiments: Array.isArray(row.experiments) ? row.experiments.filter((e: any) => e && e.id != null) : [],
        }));
        console.log('🔵 [blocks-experiments] Returning ASSIGNED blocks for lead (all runs in those blocks). Count:', rows.length, '| block_names:', rows.map((r: any) => r.block_name));
        client.release();
        return res.json({ success: true, data: rows });
      }

      // Current user's run user_name (runs.user_name): prefer ssh_user, else username (for engineer path)
      const userRow = await client.query(
        'SELECT COALESCE(ssh_user, username) AS run_user_name FROM users WHERE id = $1',
        [userId]
      );
      const runUserName: string | null = userRow.rows[0]?.run_user_name?.trim() || null;
      console.log('🔵 [blocks-experiments] runUserName (for filtering runs):', runUserName);

      if (hasBlockUsersTable) {
        // Engineer: only blocks in block_users for this user, only runs where user_name matches.
        if (!runUserName) {
          client.release();
          return res.json({ success: true, data: [] });
        }
        const result = await client.query(
          `
            SELECT 
              b.id as block_id,
              b.block_name,
              b.project_id,
              b.created_at as block_created_at,
              MAX(bu.run_directory) as block_user_run_directory,
              ${blockUserRoleSelect}
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
                ) FILTER (WHERE r.id IS NOT NULL AND r.user_name = $3),
                '[]'
              ) as experiments
            FROM blocks b
            INNER JOIN block_users bu ON bu.block_id = b.id AND bu.user_id = $2
            LEFT JOIN runs r ON r.block_id = b.id AND r.user_name = $3
            WHERE b.project_id = $1
            GROUP BY b.id, b.block_name, b.project_id, b.created_at
            ORDER BY b.block_name
          `,
          [projectId, userId, runUserName]
        );
        // Filter out blocks that have no experiments (agg may still return one row with [])
        const rows = (result.rows as any[]).map((row) => ({
          ...row,
          experiments: Array.isArray(row.experiments) ? row.experiments.filter((e: any) => e && e.id != null) : [],
        }));
        console.log('🔵 [blocks-experiments] Returning ASSIGNED blocks only (block_users). Count:', rows.length, '| block_names:', rows.map((r: any) => r.block_name));
        client.release();
        return res.json({ success: true, data: rows });
      }

      // No block_users table: only blocks that have at least one run by this user (DB only)
      if (!runUserName) {
        client.release();
        return res.json({ success: true, data: [] });
      }
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
              ) FILTER (WHERE r.id IS NOT NULL AND r.user_name = $2),
              '[]'
            ) as experiments
          FROM blocks b
          INNER JOIN runs r ON r.block_id = b.id AND r.user_name = $2
          WHERE b.project_id = $1
          GROUP BY b.id, b.block_name, b.project_id, b.created_at
          ORDER BY b.block_name
        `,
        [projectId, runUserName]
      );
      const rows = (result.rows as any[]).map((row) => ({
        ...row,
        experiments: Array.isArray(row.experiments) ? row.experiments.filter((e: any) => e && e.id != null) : [],
      }));
      console.log('🔵 [blocks-experiments] No block_users table: returning blocks with user runs only. Count:', rows.length, '| block_names:', rows.map((r: any) => r.block_name));
      client.release();
      return res.json({ success: true, data: rows });
    } catch (error: any) {
      if (client) client.release();
      console.error('Error fetching blocks and experiments:', error);
      res.status(500).json({ error: error.message });
    }
  }
);
export default router;





