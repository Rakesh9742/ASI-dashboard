import express from 'express';
import { pool } from '../config/database';
import { authenticate, authorize } from '../middleware/auth.middleware';

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
    // Engineers and customers only see projects they created
    // Admin, project_manager, and lead see all projects
    let projectFilter = '';
    const queryParams: any[] = [];
    
    console.log('Project filtering - User ID:', userId, 'Role:', userRole);
    
    if (userRole === 'engineer' || userRole === 'customer') {
      // Engineers and customers only see their own projects (created_by = userId)
      // Also exclude projects with NULL created_by (old projects or admin-created)
      projectFilter = 'WHERE p.created_by = $1 AND p.created_by IS NOT NULL';
      queryParams.push(userId);
      console.log('Filtering projects for engineer/customer - only projects created by user:', userId);
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
          const formattedZohoProjects = await Promise.all(
            filteredZohoProjects.map(async (zp: any) => {
              const isMapped = await checkProjectMapping(zp.name);
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
                zoho_data: zp,
                is_mapped: isMapped
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
      
      if (isNaN(projectId)) {
        return res.status(400).json({ error: 'Invalid project ID' });
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

export default router;


