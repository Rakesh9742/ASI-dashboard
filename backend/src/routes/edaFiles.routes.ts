import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { pool } from '../config/database';
import { authenticate } from '../middleware/auth.middleware';
import { authenticateApiKey } from '../middleware/apiKey.middleware';
import fileProcessorService from '../services/fileProcessor.service';
import fileWatcherService from '../services/fileWatcher.service';

const router = express.Router();

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
 * Get Zoho project names for a user
 */
async function getUserZohoProjectNames(userId: number): Promise<string[]> {
  try {
    const zohoService = (await import('../services/zoho.service')).default;
    const hasToken = await zohoService.hasValidToken(userId);
    
    if (!hasToken) {
      return [];
    }
    
    const zohoProjects = await zohoService.getProjects(userId);
    return zohoProjects.map((project: any) => project.name?.toLowerCase() || '').filter(Boolean);
  } catch (error: any) {
    console.error('Error fetching Zoho projects for user:', error.message);
    return [];
  }
}

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: (req: express.Request, file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) => {
    const outputFolder = fileProcessorService.getOutputFolder();
    // Ensure folder exists
    if (!fs.existsSync(outputFolder)) {
      fs.mkdirSync(outputFolder, { recursive: true });
    }
    cb(null, outputFolder);
  },
  filename: (req: express.Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
    // Keep original filename, add timestamp to avoid conflicts
    const timestamp = Date.now();
    const ext = path.extname(file.originalname);
    const name = path.basename(file.originalname, ext);
    cb(null, `${name}_${timestamp}${ext}`);
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 100 * 1024 * 1024 // 100MB limit
  },
  fileFilter: (req: express.Request, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ext === '.csv' || ext === '.json') {
      cb(null, true);
    } else {
      cb(new Error('Only CSV and JSON files are allowed'));
    }
  }
});

/**
 * GET /api/eda-files
 * Get all processed EDA output files with optional filters
 */
router.get('/', authenticate, async (req, res) => {
  try {
    const {
      project_name,
      domain_name,
      project_id,
      domain_id,
      limit = '50',
      offset = '0'
    } = req.query;

    // Get user info from authentication
    const userId = (req as any).user?.id;
    const userRole = (req as any).user?.role;
    const username = (req as any).user?.username;

    // Get user email to extract username for matching
    let userEmail: string | null = null;
    let extractedUsername: string | null = null;
    let zohoProjectNames: string[] = [];
    
    if (userRole === 'engineer' || userRole === 'customer') {
      try {
        // Get user email from database
        const userResult = await pool.query('SELECT email FROM public.users WHERE id = $1', [userId]);
        if (userResult.rows.length > 0) {
          userEmail = userResult.rows[0].email;
          extractedUsername = extractUsernameFromEmail(userEmail);
          console.log(`User email: ${userEmail}, Extracted username: ${extractedUsername}`);
          
          // Get Zoho project names for this user
          zohoProjectNames = await getUserZohoProjectNames(userId);
          console.log(`Zoho project names for user: ${zohoProjectNames.join(', ')}`);
        }
      } catch (error: any) {
        console.error('Error getting user email or Zoho projects:', error.message);
      }
    }

    // Query new Physical Design schema
    // Join: projects -> blocks -> runs -> stages -> timing_metrics -> constraint_metrics
    // Also get domain from project_domains
    let query = `
      SELECT DISTINCT
        p.name as project_name,
        d.name as domain_name,
        d.id as domain_id,
        p.id as project_id,
        b.block_name,
        r.experiment,
        r.rtl_tag,
        r.user_name,
        r.run_directory,
        r.last_updated as run_end_time,
        s.stage_name as stage,
        s.timestamp,
        s.run_status,
        s.runtime,
        s.memory_usage,
        s.area,
        s.inst_count,
        s.utilization,
        s.log_errors,
        s.log_warnings,
        s.log_critical,
        s.min_pulse_width,
        s.min_period,
        s.double_switching,
        s.created_at,
        -- Timing metrics
        stm.internal_r2r_wns as internal_timing_r2r_wns,
        stm.internal_r2r_tns as internal_timing_r2r_tns,
        stm.internal_r2r_nvp as internal_timing_r2r_nvp,
        stm.interface_i2r_wns as interface_timing_i2r_wns,
        stm.interface_i2r_tns as interface_timing_i2r_tns,
        stm.interface_i2r_nvp as interface_timing_i2r_nvp,
        stm.interface_r2o_wns as interface_timing_r2o_wns,
        stm.interface_r2o_tns as interface_timing_r2o_tns,
        stm.interface_r2o_nvp as interface_timing_r2o_nvp,
        stm.interface_i2o_wns as interface_timing_i2o_wns,
        stm.interface_i2o_tns as interface_timing_i2o_tns,
        stm.interface_i2o_nvp as interface_timing_i2o_nvp,
        stm.hold_wns,
        stm.hold_tns,
        stm.hold_nvp,
        -- Constraint metrics
        scm.max_tran_wns,
        scm.max_tran_nvp,
        scm.max_cap_wns,
        scm.max_cap_nvp,
        scm.max_fanout_wns,
        scm.max_fanout_nvp,
        scm.drc_violations,
        scm.congestion_hotspot,
        scm.noise_violations,
        -- Power/IR/EM
        pirem.ir_static,
        pirem.ir_dynamic,
        pirem.em_power,
        pirem.em_signal,
        -- Physical verification
        pv.pv_drc_base,
        pv.pv_drc_metal,
        pv.pv_drc_antenna,
        pv.lvs,
        pv.erc,
        pv.r2g_lec,
        pv.g2g_lec,
        -- AI Summary
        ai.summary_text as ai_summary,
        s.id as stage_id
      FROM public.stages s
      INNER JOIN public.runs r ON s.run_id = r.id
      INNER JOIN public.blocks b ON r.block_id = b.id
      INNER JOIN public.projects p ON b.project_id = p.id
      LEFT JOIN public.project_domains pd ON p.id = pd.project_id
      LEFT JOIN public.domains d ON pd.domain_id = d.id
      LEFT JOIN public.stage_timing_metrics stm ON s.id = stm.stage_id
      LEFT JOIN public.stage_constraint_metrics scm ON s.id = scm.stage_id
      LEFT JOIN public.power_ir_em_checks pirem ON s.id = pirem.stage_id
      LEFT JOIN public.physical_verification pv ON s.id = pv.stage_id
      LEFT JOIN public.ai_summaries ai ON s.id = ai.stage_id
      WHERE 1=1
    `;

    const params: any[] = [];
    let paramCount = 0;

    // Filter by user role: engineers and customers only see their own runs
    // OR runs where project name matches their Zoho projects
    if (userRole === 'customer') {
      // For customers, show all EDA files for projects assigned to them via user_projects table
      query += ` AND EXISTS (
        SELECT 1 FROM public.user_projects up 
        WHERE up.user_id = $${++paramCount} AND up.project_id = p.id
      )`;
      params.push(userId);
      console.log(`Filtering EDA files for customer - only projects assigned via user_projects: ${userId}`);
    } else if (userRole === 'engineer') {
      // Engineers see runs where user_name matches their username
      if (extractedUsername || username) {
        // Build condition: user_name matches extracted username OR
        // (project_name matches Zoho project AND user_name matches extracted username)
        const conditions: string[] = [];
        
        // Condition 1: Direct username match
        if (extractedUsername) {
          paramCount++;
          conditions.push(`LOWER(r.user_name) = LOWER($${paramCount})`);
          params.push(extractedUsername);
        } else if (username) {
          paramCount++;
          conditions.push(`LOWER(r.user_name) = LOWER($${paramCount})`);
          params.push(username);
        }
        
        // Condition 2: Zoho project match (if user has Zoho projects)
        if (zohoProjectNames.length > 0 && extractedUsername) {
          // Create array of project names for IN clause
          const projectNamePlaceholders: string[] = [];
          zohoProjectNames.forEach((projectName) => {
            paramCount++;
            projectNamePlaceholders.push(`LOWER($${paramCount})`);
            params.push(projectName);
          });
          
          // Match if project name is in Zoho projects AND user_name matches
          paramCount++;
          conditions.push(
            `(LOWER(p.name) IN (${projectNamePlaceholders.join(', ')}) AND LOWER(r.user_name) = LOWER($${paramCount}))`
          );
          params.push(extractedUsername);
        }
        
        if (conditions.length > 0) {
          query += ` AND (${conditions.join(' OR ')})`;
          console.log(`Filtering EDA files for engineer:`);
          console.log(`  - Extracted username: ${extractedUsername}`);
          console.log(`  - Zoho projects: ${zohoProjectNames.length} projects`);
          console.log(`  - Conditions: ${conditions.length} condition(s)`);
        }
      }
    }
    // Admin, project_manager, and lead see all runs (no filter)

    if (project_name) {
      paramCount++;
      query += ` AND LOWER(p.name) LIKE LOWER($${paramCount})`;
      params.push(`%${project_name}%`);
    }

    if (domain_name) {
      paramCount++;
      query += ` AND LOWER(d.name) LIKE LOWER($${paramCount})`;
      params.push(`%${domain_name}%`);
    }

    if (project_id) {
      paramCount++;
      query += ` AND p.id = $${paramCount}`;
      params.push(parseInt(project_id as string));
    }

    if (domain_id) {
      paramCount++;
      query += ` AND d.id = $${paramCount}`;
      params.push(parseInt(domain_id as string));
    }

    query += ` ORDER BY s.created_at DESC LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
    params.push(parseInt(limit as string), parseInt(offset as string));

    // DEBUG: Verify search_path and table existence
    try {
      const debugSearchPath = await pool.query('SHOW search_path');
      console.log('🔍 [DEBUG] DB search_path:', debugSearchPath.rows[0]?.search_path);
      
      const debugTableCheck = await pool.query("SELECT to_regclass('public.stages')");
      console.log('🔍 [DEBUG] Table check (public.stages):', debugTableCheck.rows[0]?.to_regclass);
    } catch (debugError: any) {
      console.error('⚠️ [DEBUG] Debug query failed:', debugError.message);
    }

    const result = await pool.query(query, params);

    // Get total count for pagination
    let countQuery = `
      SELECT COUNT(DISTINCT s.id)
      FROM public.stages s
      INNER JOIN public.runs r ON s.run_id = r.id
      INNER JOIN public.blocks b ON r.block_id = b.id
      INNER JOIN public.projects p ON b.project_id = p.id
      LEFT JOIN public.project_domains pd ON p.id = pd.project_id
      LEFT JOIN public.domains d ON pd.domain_id = d.id
      WHERE 1=1
    `;
    const countParams: any[] = [];
    let countParamCount = 0;

    // Apply same user filtering to count query
    if (userRole === 'engineer' || userRole === 'customer') {
      if (extractedUsername || username) {
        const conditions: string[] = [];
        
        // Condition 1: Direct username match
        if (extractedUsername) {
          countParamCount++;
          conditions.push(`LOWER(r.user_name) = LOWER($${countParamCount})`);
          countParams.push(extractedUsername);
        } else if (username) {
          countParamCount++;
          conditions.push(`LOWER(r.user_name) = LOWER($${countParamCount})`);
          countParams.push(username);
        }
        
        // Condition 2: Zoho project match (if user has Zoho projects)
        if (zohoProjectNames.length > 0 && extractedUsername) {
          const projectNamePlaceholders: string[] = [];
          zohoProjectNames.forEach((projectName) => {
            countParamCount++;
            projectNamePlaceholders.push(`LOWER($${countParamCount})`);
            countParams.push(projectName);
          });
          
          countParamCount++;
          conditions.push(
            `(LOWER(p.name) IN (${projectNamePlaceholders.join(', ')}) AND LOWER(r.user_name) = LOWER($${countParamCount}))`
          );
          countParams.push(extractedUsername);
        }
        
        if (conditions.length > 0) {
          countQuery += ` AND (${conditions.join(' OR ')})`;
        }
      }
    }

    if (project_name) {
      countParamCount++;
      countQuery += ` AND LOWER(p.name) LIKE LOWER($${countParamCount})`;
      countParams.push(`%${project_name}%`);
    }

    if (domain_name) {
      countParamCount++;
      countQuery += ` AND LOWER(d.name) LIKE LOWER($${countParamCount})`;
      countParams.push(`%${domain_name}%`);
    }

    if (project_id) {
      countParamCount++;
      countQuery += ` AND p.id = $${countParamCount}`;
      countParams.push(parseInt(project_id as string));
    }

    if (domain_id) {
      countParamCount++;
      countQuery += ` AND d.id = $${countParamCount}`;
      countParams.push(parseInt(domain_id as string));
    }

    const countResult = await pool.query(countQuery, countParams);
    const total = parseInt(countResult.rows[0].count);

    // Transform results to match expected format
    const files = result.rows.map((row: any) => ({
      project_name: row.project_name,
      domain_name: row.domain_name,
      domain_id: row.domain_id,
      project_id: row.project_id,
      block_name: row.block_name,
      experiment: row.experiment,
      rtl_tag: row.rtl_tag,
      user_name: row.user_name,
      run_directory: row.run_directory,
      run_end_time: row.run_end_time,
      stage: row.stage,
      timestamp: row.timestamp,
      run_status: row.run_status,
      runtime: row.runtime,
      memory_usage: row.memory_usage,
      area: row.area,
      inst_count: row.inst_count,
      utilization: row.utilization,
      log_errors: row.log_errors,
      log_warnings: row.log_warnings,
      log_critical: row.log_critical,
      min_pulse_width: row.min_pulse_width,
      min_period: row.min_period,
      double_switching: row.double_switching,
      // Timing metrics
      internal_timing_r2r_wns: row.internal_timing_r2r_wns,
      internal_timing_r2r_tns: row.internal_timing_r2r_tns,
      internal_timing_r2r_nvp: row.internal_timing_r2r_nvp,
      interface_timing_i2r_wns: row.interface_timing_i2r_wns,
      interface_timing_i2r_tns: row.interface_timing_i2r_tns,
      interface_timing_i2r_nvp: row.interface_timing_i2r_nvp,
      interface_timing_r2o_wns: row.interface_timing_r2o_wns,
      interface_timing_r2o_tns: row.interface_timing_r2o_tns,
      interface_timing_r2o_nvp: row.interface_timing_r2o_nvp,
      interface_timing_i2o_wns: row.interface_timing_i2o_wns,
      interface_timing_i2o_tns: row.interface_timing_i2o_tns,
      interface_timing_i2o_nvp: row.interface_timing_i2o_nvp,
      hold_wns: row.hold_wns,
      hold_tns: row.hold_tns,
      hold_nvp: row.hold_nvp,
      // Constraint metrics
      max_tran_wns: row.max_tran_wns,
      max_tran_nvp: row.max_tran_nvp,
      max_cap_wns: row.max_cap_wns,
      max_cap_nvp: row.max_cap_nvp,
      max_fanout_wns: row.max_fanout_wns,
      max_fanout_nvp: row.max_fanout_nvp,
      drc_violations: row.drc_violations,
      congestion_hotspot: row.congestion_hotspot,
      noise_violations: row.noise_violations,
      // Power/IR/EM
      ir_static: row.ir_static,
      ir_dynamic: row.ir_dynamic,
      em_power: row.em_power,
      em_signal: row.em_signal,
      // Physical verification
      pv_drc_base: row.pv_drc_base,
      pv_drc_metal: row.pv_drc_metal,
      pv_drc_antenna: row.pv_drc_antenna,
      lvs: row.lvs,
      erc: row.erc,
      r2g_lec: row.r2g_lec,
      g2g_lec: row.g2g_lec,
      // AI Summary
      ai_summary: row.ai_summary,
      ai_based_overall_summary: row.ai_summary, // Also include for backward compatibility
      created_at: row.created_at,
      stage_id: row.stage_id
    }));

    res.json({
      files: files,
      pagination: {
        total,
        limit: parseInt(limit as string),
        offset: parseInt(offset as string),
        hasMore: total > parseInt(offset as string) + parseInt(limit as string)
      }
    });
  } catch (error: any) {
    console.error('Error fetching EDA files:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/eda-files/:id
 * Get a specific EDA output file by ID
 */
router.get('/:id', authenticate, async (req, res) => {
  try {
    // TODO: Update to use new Physical Design schema
    return res.status(503).json({
      error: 'Endpoint temporarily unavailable - new schema migration in progress',
      message: 'The eda_output_files table has been replaced. Please update the API to use the new Physical Design schema.'
    });
  } catch (error: any) {
    console.error('Error fetching EDA file:', error);
    if (error.code === '42P01') {
      return res.status(503).json({
        error: 'Database schema migration in progress',
        message: 'The eda_output_files table has been replaced. Please update the API to use the new Physical Design schema.'
      });
    }
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/eda-files/upload
 * Upload a file to the output folder and process it
 */
router.post('/upload', authenticate, upload.single('file'), async (req: express.Request, res) => {
  try {
    // TODO: Update to use new Physical Design schema
    return res.status(503).json({
      error: 'Endpoint temporarily unavailable - new schema migration in progress',
      message: 'File upload is disabled until the new Physical Design schema is implemented.'
    });
  } catch (error: any) {
    console.error('Error uploading file:', error);
    if (error.code === '42P01') {
      return res.status(503).json({
        error: 'Database schema migration in progress',
        message: 'The eda_output_files table has been replaced. Please update the API to use the new Physical Design schema.'
      });
    }
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/eda-files/folder/list
 * List all files in the output folder (for API access from VNC server)
 */
router.get('/folder/list', async (req, res) => {
  try {
    const outputFolder = fileProcessorService.getOutputFolder();
    const files = fs.readdirSync(outputFolder);

    const fileList = files.map(file => {
      const filePath = path.join(outputFolder, file);
      const stats = fs.statSync(filePath);

      return {
        name: file,
        path: filePath,
        size: stats.size,
        modified: stats.mtime,
        type: path.extname(file).toLowerCase().slice(1)
      };
    });

    res.json({
      folder: outputFolder,
      files: fileList,
      count: fileList.length
    });
  } catch (error: any) {
    console.error('Error listing folder:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/eda-files/folder/upload
 * Upload file directly to output folder (for VNC server API access)
 * This endpoint doesn't require authentication for external API access
 */
router.post('/folder/upload', upload.single('file'), async (req: express.Request, res) => {
  try {
    const file = (req as any).file as Express.Multer.File;
    if (!file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const fileName = file.originalname;
    console.log(`File received from VNC server: ${fileName}`);

    // TODO: Update to use new Physical Design schema
    // File is saved but processing is disabled
    res.status(201).json({
      message: 'File received but processing is disabled - new schema migration in progress',
      fileName,
      filePath: file.path,
      note: 'File processing will be enabled after the new Physical Design schema is implemented'
    });
  } catch (error: any) {
    console.error('Error receiving file:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/eda-files/external/upload
 * External API endpoint for developers to push EDA output files
 * Requires API key authentication via X-API-Key header
 * Processes and stores files in the database automatically
 */
router.post('/external/upload', authenticateApiKey, upload.single('file'), async (req: express.Request, res) => {
  try {
    const file = (req as any).file as Express.Multer.File;
    if (!file) {
      return res.status(400).json({ 
        error: 'No file uploaded',
        message: 'Please provide a file in the request. Use multipart/form-data with field name "file".'
      });
    }

    const fileName = file.originalname;
    const filePath = file.path;
    const fileSize = file.size;
    const fileType = path.extname(fileName).toLowerCase().slice(1);

    console.log(`📤 [EXTERNAL API] File received: ${fileName} (${fileSize} bytes, type: ${fileType})`);

    // Validate file type
    if (fileType !== 'csv' && fileType !== 'json') {
      // Delete the uploaded file
      try {
        fs.unlinkSync(filePath);
      } catch (e) {
        // Ignore deletion errors
      }
      return res.status(400).json({
        error: 'Invalid file type',
        message: 'Only CSV and JSON files are allowed',
        received: fileType,
        allowed: ['csv', 'json']
      });
    }

    // Process the file asynchronously
    try {
      const fileId = await fileProcessorService.processFile(filePath);
      
      console.log(`✅ [EXTERNAL API] Successfully processed file: ${fileName} (ID: ${fileId})`);

      res.status(201).json({
        success: true,
        message: 'File uploaded and processed successfully',
        data: {
          fileId,
          fileName,
          fileSize,
          fileType,
          filePath,
          processedAt: new Date().toISOString()
        }
      });
    } catch (processingError: any) {
      console.error(`❌ [EXTERNAL API] Error processing file ${fileName}:`, processingError);
      
      // File is still saved, but processing failed
      res.status(500).json({
        success: false,
        error: 'File processing failed',
        message: processingError.message || 'An error occurred while processing the file',
        data: {
          fileName,
          filePath,
          fileSize,
          fileType,
          uploadedAt: new Date().toISOString()
        }
      });
    }
  } catch (error: any) {
    console.error('❌ [EXTERNAL API] Error receiving file:', error);
    res.status(500).json({ 
      success: false,
      error: 'Upload failed',
      message: error.message || 'An unexpected error occurred'
    });
  }
});

/**
 * POST /api/eda-files/external/replace-stage
 * External API endpoint for developers to delete and replace a specific stage
 * Requires API key authentication via X-API-Key header
 * Accepts file upload (CSV or JSON) and query/form parameters: project, block_name, experiment, rtl_tag, stage_name
 * Processes the uploaded file and replaces the specified stage with data from the file
 */
router.post('/external/replace-stage', authenticateApiKey, upload.single('file'), async (req: express.Request, res) => {
  const client = await pool.connect();
  
  try {
    // Get uploaded file
    const file = (req as any).file as Express.Multer.File;
    if (!file) {
      return res.status(400).json({ 
        error: 'No file uploaded',
        message: 'Please provide a file in the request. Use multipart/form-data with field name "file".'
      });
    }

    // Extract identifiers from query params or form fields
    const projectName = req.body.project || req.query.project;
    const blockName = req.body.block_name || req.query.block_name;
    const experiment = req.body.experiment || req.query.experiment;
    const rtlTag = req.body.rtl_tag || req.query.rtl_tag;
    const stageName = req.body.stage_name || req.query.stage_name;

    // Validate required parameters
    if (!projectName || !blockName || !experiment || !rtlTag || !stageName) {
      // Delete the uploaded file if validation fails
      try {
        fs.unlinkSync(file.path);
      } catch (e) {
        // Ignore deletion errors
      }
      return res.status(400).json({
        error: 'Missing required parameters',
        message: 'Please provide: project, block_name, experiment, rtl_tag, and stage_name',
        required: ['project', 'block_name', 'experiment', 'rtl_tag', 'stage_name'],
        note: 'You can provide these as query parameters or form fields along with the file upload'
      });
    }

    const fileName = file.originalname;
    const filePath = file.path;
    const fileSize = file.size;
    const fileType = path.extname(fileName).toLowerCase().slice(1);

    console.log(`🔄 [EXTERNAL API] Replace stage request: ${projectName}/${blockName}/${experiment}/${rtlTag}/${stageName}`);
    console.log(`📤 [EXTERNAL API] File received: ${fileName} (${fileSize} bytes, type: ${fileType})`);

    // Validate file type
    if (fileType !== 'csv' && fileType !== 'json') {
      // Delete the uploaded file
      try {
        fs.unlinkSync(filePath);
      } catch (e) {
        // Ignore deletion errors
      }
      return res.status(400).json({
        error: 'Invalid file type',
        message: 'Only CSV and JSON files are allowed',
        received: fileType,
        allowed: ['csv', 'json']
      });
    }

    // Process the file to extract stage data
    let processedData: any[];
    try {
      if (fileType === 'csv') {
        processedData = await fileProcessorService.processCSVFile(filePath);
      } else {
        processedData = await fileProcessorService.processJSONFile(filePath);
      }

      if (processedData.length === 0) {
        try {
          fs.unlinkSync(filePath);
        } catch (e) {
          // Ignore deletion errors
        }
        return res.status(400).json({
          error: 'No data found in file',
          message: 'The uploaded file does not contain any valid stage data'
        });
      }

      console.log(`📄 [EXTERNAL API] Processed ${processedData.length} stage(s) from file`);
    } catch (parseError: any) {
      try {
        fs.unlinkSync(filePath);
      } catch (e) {
        // Ignore deletion errors
      }
      return res.status(400).json({
        error: 'File parsing failed',
        message: parseError.message || 'Failed to parse the uploaded file'
      });
    }

    // Find the stage data that matches the requested stage_name
    // The file might contain multiple stages, we need to find the one matching stage_name
    let stageData = processedData.find(row => 
      row.stage && row.stage.toLowerCase() === stageName.toLowerCase()
    );

    // If not found by stage name, use the first row (assuming single stage file)
    if (!stageData && processedData.length === 1) {
      stageData = processedData[0];
      // Override the stage name with the requested one
      stageData.stage = stageName;
      console.log(`📄 [EXTERNAL API] Using first row from file, setting stage to: ${stageName}`);
    }

    if (!stageData) {
      try {
        fs.unlinkSync(filePath);
      } catch (e) {
        // Ignore deletion errors
      }
      return res.status(400).json({
        error: 'Stage not found in file',
        message: `The uploaded file does not contain data for stage "${stageName}"`,
        available_stages: processedData.map(row => row.stage).filter(s => s).join(', ') || 'none'
      });
    }

    // Override identifiers from query/form params to ensure they match
    stageData.project_name = projectName;
    stageData.block_name = blockName;
    stageData.experiment = experiment;
    stageData.rtl_tag = rtlTag;
    stageData.stage = stageName;

    console.log(`📄 [EXTERNAL API] Using stage data for replacement:`, {
      project: stageData.project_name,
      block: stageData.block_name,
      experiment: stageData.experiment,
      rtl_tag: stageData.rtl_tag,
      stage: stageData.stage
    });

    await client.query('BEGIN');

    // 1. Find project
    const projectResult = await client.query(
      'SELECT id FROM public.projects WHERE LOWER(name) = LOWER($1)',
      [projectName]
    );

    if (projectResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        error: 'Project not found',
        message: `Project "${projectName}" does not exist`
      });
    }

    const projectId = projectResult.rows[0].id;

    // 2. Find block
    const blockResult = await client.query(
      'SELECT id FROM public.blocks WHERE project_id = $1 AND LOWER(block_name) = LOWER($2)',
      [projectId, blockName]
    );

    if (blockResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        error: 'Block not found',
        message: `Block "${blockName}" not found in project "${projectName}"`
      });
    }

    const blockId = blockResult.rows[0].id;

    // 3. Find run
    const runResult = await client.query(
      'SELECT id FROM public.runs WHERE block_id = $1 AND experiment = $2 AND rtl_tag = $3',
      [blockId, experiment, rtlTag]
    );

    if (runResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        error: 'Run not found',
        message: `Run with experiment "${experiment}" and rtl_tag "${rtlTag}" not found`
      });
    }

    const runId = runResult.rows[0].id;

    // 4. Find and delete existing stage (CASCADE will delete related records)
    const existingStageResult = await client.query(
      'SELECT id FROM public.stages WHERE run_id = $1 AND stage_name = $2',
      [runId, stageName]
    );

    if (existingStageResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        error: 'Stage not found',
        message: `Stage "${stageName}" not found in the specified run`
      });
    }

    const oldStageId = existingStageResult.rows[0].id;

    // Delete the stage (CASCADE will handle related tables)
    await client.query(
      'DELETE FROM public.stages WHERE id = $1',
      [oldStageId]
    );

    console.log(`🗑️  [EXTERNAL API] Deleted old stage: ${stageName} (ID: ${oldStageId})`);

    // 5. Parse timestamp from stage data
    const timestamp = stageData.run_end_time || stageData.timestamp 
      ? new Date(stageData.run_end_time || stageData.timestamp) 
      : new Date();

    // Helper functions for parsing (same as fileProcessor)
    const parseToString = (value: any): string | null => {
      if (value === null || value === undefined) return null;
      if (value === 'N/A' || value === 'NA') return 'N/A';
      return String(value);
    };

    // 6. Insert new stage
    const stageResult = await client.query(
      `INSERT INTO public.stages (
        run_id, stage_name, timestamp, stage_directory, run_status, runtime, memory_usage,
        log_errors, log_warnings, log_critical, area, inst_count, utilization,
        metal_density_max, min_pulse_width, min_period, double_switching
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
      RETURNING id`,
      [
        runId,
        stageName,
        timestamp,
        stageData.stage_directory || null,
        stageData.run_status || null,
        stageData.runtime || null,
        stageData.memory_usage || null,
        parseToString(stageData.log_errors) || '0',
        parseToString(stageData.log_warnings) || '0',
        parseToString(stageData.log_critical) || '0',
        parseToString(stageData.area),
        parseToString(stageData.inst_count),
        parseToString(stageData.utilization),
        parseToString(stageData.metal_density_max),
        stageData.min_pulse_width || null,
        stageData.min_period || null,
        stageData.double_switching || null,
      ]
    );

    const newStageId = stageResult.rows[0].id;
    console.log(`✅ [EXTERNAL API] Created new stage: ${stageName} (ID: ${newStageId})`);

    // 7. Save timing metrics if provided
    if (stageData.internal_timing_r2r_wns !== undefined || 
        stageData.interface_timing_i2r_wns !== undefined ||
        stageData.hold_wns !== undefined) {
      await client.query(
        `INSERT INTO public.stage_timing_metrics (
          stage_id, internal_r2r_wns, internal_r2r_tns, internal_r2r_nvp,
          interface_i2r_wns, interface_i2r_tns, interface_i2r_nvp,
          interface_r2o_wns, interface_r2o_tns, interface_r2o_nvp,
          interface_i2o_wns, interface_i2o_tns, interface_i2o_nvp,
          hold_wns, hold_tns, hold_nvp
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        ON CONFLICT (stage_id) DO UPDATE SET
          internal_r2r_wns = EXCLUDED.internal_r2r_wns,
          internal_r2r_tns = EXCLUDED.internal_r2r_tns,
          internal_r2r_nvp = EXCLUDED.internal_r2r_nvp,
          interface_i2r_wns = EXCLUDED.interface_i2r_wns,
          interface_i2r_tns = EXCLUDED.interface_i2r_tns,
          interface_i2r_nvp = EXCLUDED.interface_i2r_nvp,
          interface_r2o_wns = EXCLUDED.interface_r2o_wns,
          interface_r2o_tns = EXCLUDED.interface_r2o_tns,
          interface_r2o_nvp = EXCLUDED.interface_r2o_nvp,
          interface_i2o_wns = EXCLUDED.interface_i2o_wns,
          interface_i2o_tns = EXCLUDED.interface_i2o_tns,
          interface_i2o_nvp = EXCLUDED.interface_i2o_nvp,
          hold_wns = EXCLUDED.hold_wns,
          hold_tns = EXCLUDED.hold_tns,
          hold_nvp = EXCLUDED.hold_nvp`,
        [
          newStageId,
          parseToString(stageData.internal_timing_r2r_wns),
          parseToString(stageData.internal_timing_r2r_tns),
          parseToString(stageData.internal_timing_r2r_nvp),
          parseToString(stageData.interface_timing_i2r_wns),
          parseToString(stageData.interface_timing_i2r_tns),
          parseToString(stageData.interface_timing_i2r_nvp),
          parseToString(stageData.interface_timing_r2o_wns),
          parseToString(stageData.interface_timing_r2o_tns),
          parseToString(stageData.interface_timing_r2o_nvp),
          parseToString(stageData.interface_timing_i2o_wns),
          parseToString(stageData.interface_timing_i2o_tns),
          parseToString(stageData.interface_timing_i2o_nvp),
          parseToString(stageData.hold_wns),
          parseToString(stageData.hold_tns),
          parseToString(stageData.hold_nvp),
        ]
      );
    }

    // 8. Save constraint metrics if provided
    if (stageData.max_tran_wns !== undefined || stageData.drc_violations !== undefined) {
      await client.query(
        `INSERT INTO public.stage_constraint_metrics (
          stage_id, max_tran_wns, max_tran_nvp, max_cap_wns, max_cap_nvp,
          max_fanout_wns, max_fanout_nvp, drc_violations, congestion_hotspot, noise_violations
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        ON CONFLICT (stage_id) DO UPDATE SET
          max_tran_wns = EXCLUDED.max_tran_wns,
          max_tran_nvp = EXCLUDED.max_tran_nvp,
          max_cap_wns = EXCLUDED.max_cap_wns,
          max_cap_nvp = EXCLUDED.max_cap_nvp,
          max_fanout_wns = EXCLUDED.max_fanout_wns,
          max_fanout_nvp = EXCLUDED.max_fanout_nvp,
          drc_violations = EXCLUDED.drc_violations,
          congestion_hotspot = EXCLUDED.congestion_hotspot,
          noise_violations = EXCLUDED.noise_violations`,
        [
          newStageId,
          parseToString(stageData.max_tran_wns),
          parseToString(stageData.max_tran_nvp),
          parseToString(stageData.max_cap_wns),
          parseToString(stageData.max_cap_nvp),
          parseToString(stageData.max_fanout_wns),
          parseToString(stageData.max_fanout_nvp),
          parseToString(stageData.drc_violations),
          stageData.congestion_hotspot || null,
          stageData.noise_violations || null,
        ]
      );
    }

    // 9. Save power/IR/EM checks if provided
    if (stageData.ir_static !== undefined || stageData.em_power !== undefined) {
      await client.query(
        `INSERT INTO public.power_ir_em_checks (
          stage_id, ir_static, ir_dynamic, em_power, em_signal
        ) VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (stage_id) DO UPDATE SET
          ir_static = EXCLUDED.ir_static,
          ir_dynamic = EXCLUDED.ir_dynamic,
          em_power = EXCLUDED.em_power,
          em_signal = EXCLUDED.em_signal`,
        [
          newStageId,
          parseToString(stageData.ir_static),
          parseToString(stageData.ir_dynamic),
          parseToString(stageData.em_power),
          parseToString(stageData.em_signal),
        ]
      );
    }

    // 10. Save physical verification if provided
    if (stageData.pv_drc_base !== undefined || stageData.lvs !== undefined) {
      await client.query(
        `INSERT INTO public.physical_verification (
          stage_id, pv_drc_base, pv_drc_metal, pv_drc_antenna, lvs, erc, r2g_lec, g2g_lec
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (stage_id) DO UPDATE SET
          pv_drc_base = EXCLUDED.pv_drc_base,
          pv_drc_metal = EXCLUDED.pv_drc_metal,
          pv_drc_antenna = EXCLUDED.pv_drc_antenna,
          lvs = EXCLUDED.lvs,
          erc = EXCLUDED.erc,
          r2g_lec = EXCLUDED.r2g_lec,
          g2g_lec = EXCLUDED.g2g_lec`,
        [
          newStageId,
          parseToString(stageData.pv_drc_base),
          parseToString(stageData.pv_drc_metal),
          parseToString(stageData.pv_drc_antenna),
          parseToString(stageData.lvs),
          parseToString(stageData.erc),
          parseToString(stageData.r2g_lec),
          parseToString(stageData.g2g_lec),
        ]
      );
    }

    // 11. Save path groups if provided
    if (stageData.setup_path_groups || stageData.hold_path_groups) {
      // Save setup path groups
      if (stageData.setup_path_groups && typeof stageData.setup_path_groups === 'object') {
        for (const [groupName, groupData] of Object.entries(stageData.setup_path_groups)) {
          const group = groupData as any;
          await client.query(
            `INSERT INTO public.path_groups (stage_id, group_type, group_name, wns, tns, nvp)
             VALUES ($1, 'setup', $2, $3, $4, $5)
             ON CONFLICT (stage_id, group_type, group_name) DO UPDATE SET
               wns = EXCLUDED.wns, tns = EXCLUDED.tns, nvp = EXCLUDED.nvp`,
            [
              newStageId,
              groupName,
              parseToString(group.wns),
              parseToString(group.tns),
              parseToString(group.nvp),
            ]
          );
        }
      }

      // Save hold path groups
      if (stageData.hold_path_groups && typeof stageData.hold_path_groups === 'object') {
        for (const [groupName, groupData] of Object.entries(stageData.hold_path_groups)) {
          const group = groupData as any;
          await client.query(
            `INSERT INTO public.path_groups (stage_id, group_type, group_name, wns, tns, nvp)
             VALUES ($1, 'hold', $2, $3, $4, $5)
             ON CONFLICT (stage_id, group_type, group_name) DO UPDATE SET
               wns = EXCLUDED.wns, tns = EXCLUDED.tns, nvp = EXCLUDED.nvp`,
            [
              newStageId,
              groupName,
              parseToString(group.wns),
              parseToString(group.tns),
              parseToString(group.nvp),
            ]
          );
        }
      }
    }

    // 12. Save DRV violations if provided
    if (stageData.drv_violations && typeof stageData.drv_violations === 'object') {
      for (const [violationType, violationData] of Object.entries(stageData.drv_violations)) {
        const violation = violationData as any;
        await client.query(
          `INSERT INTO public.drv_violations (stage_id, violation_type, wns, tns, nvp)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (stage_id, violation_type) DO UPDATE SET
             wns = EXCLUDED.wns, tns = EXCLUDED.tns, nvp = EXCLUDED.nvp`,
          [
            newStageId,
            violationType,
            parseToString(violation.wns),
            parseToString(violation.tns),
            parseToString(violation.nvp),
          ]
        );
      }
    }

    // 13. Save AI summary if provided
    if (stageData.ai_summary || stageData.ai_based_overall_summary) {
      await client.query(
        `INSERT INTO public.ai_summaries (stage_id, summary_text)
         VALUES ($1, $2)
         ON CONFLICT (stage_id) DO UPDATE SET summary_text = EXCLUDED.summary_text`,
        [newStageId, stageData.ai_summary || stageData.ai_based_overall_summary]
      );
    }

    await client.query('COMMIT');
    client.release();

    // Clean up uploaded file
    try {
      fs.unlinkSync(filePath);
      console.log(`🗑️  [EXTERNAL API] Cleaned up uploaded file: ${fileName}`);
    } catch (e) {
      console.warn(`⚠️  [EXTERNAL API] Could not delete uploaded file: ${fileName}`, e);
    }

    console.log(`✅ [EXTERNAL API] Successfully replaced stage: ${stageName}`);

    res.status(200).json({
      success: true,
      message: 'Stage deleted and replaced successfully',
      data: {
        project: projectName,
        block_name: blockName,
        experiment: experiment,
        rtl_tag: rtlTag,
        stage_name: stageName,
        old_stage_id: oldStageId,
        new_stage_id: newStageId,
        file_name: fileName,
        replaced_at: new Date().toISOString()
      }
    });
  } catch (error: any) {
    await client.query('ROLLBACK');
    client.release();
    
    // Clean up uploaded file on error
    const file = (req as any).file as Express.Multer.File;
    if (file) {
      try {
        fs.unlinkSync(file.path);
      } catch (e) {
        // Ignore deletion errors
      }
    }
    
    console.error(`❌ [EXTERNAL API] Error replacing stage:`, error);
    res.status(500).json({
      success: false,
      error: 'Stage replacement failed',
      message: error.message || 'An unexpected error occurred'
    });
  }
});

/**
 * GET /api/eda-files/stats/summary
 * Get summary statistics of processed files
 */
router.get('/stats/summary', authenticate, async (req, res) => {
  try {
    const stats = await pool.query(`
      SELECT 
        COUNT(*) as total_files,
        COUNT(DISTINCT project_name) as unique_projects,
        COUNT(DISTINCT domain_name) as unique_domains,
        COUNT(CASE WHEN processing_status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN processing_status = 'processing' THEN 1 END) as processing,
        COUNT(CASE WHEN processing_status = 'failed' THEN 1 END) as failed,
        COUNT(CASE WHEN processing_status = 'pending' THEN 1 END) as pending,
        SUM(file_size) as total_size
      FROM eda_output_files
    `);

    res.json(stats.rows[0]);
  } catch (error: any) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/eda-files/watcher/status
 * Get file watcher status
 */
router.get('/watcher/status', authenticate, async (req, res) => {
  try {
    const outputFolder = fileProcessorService.getOutputFolder();
    const isActive = fileWatcherService.isActive();

    // Count files in folder
    let fileCount = 0;
    let unprocessedCount = 0;
    try {
      const files = fs.readdirSync(outputFolder);
      fileCount = files.length;

      // TODO: Update to use new Physical Design schema
      // Check how many are unprocessed
      for (const file of files) {
        const filePath = path.join(outputFolder, file);
        const stats = fs.statSync(filePath);
        if (stats.isFile()) {
          const ext = path.extname(file).toLowerCase().slice(1);
          if (ext === 'csv' || ext === 'json') {
            try {
              const result = await pool.query(
                'SELECT id FROM eda_output_files WHERE file_path = $1',
                [filePath]
              );
              if (result.rows.length === 0) {
                unprocessedCount++;
              }
            } catch (e: any) {
              // Table doesn't exist - count all as unprocessed
              if (e.code === '42P01') {
                unprocessedCount++;
              }
            }
          }
        }
      }
    } catch (e) {
      // Folder might not exist or be empty
    }

    res.json({
      watcherActive: isActive,
      outputFolder,
      folderExists: fs.existsSync(outputFolder),
      fileCount,
      unprocessedCount
    });
  } catch (error: any) {
    console.error('Error getting watcher status:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/eda-files/process/:filename
 * Manually trigger processing of a file in the output folder
 */
router.post('/process/:filename', authenticate, async (req, res) => {
  try {
    // TODO: Update to use new Physical Design schema
    return res.status(503).json({
      error: 'Endpoint temporarily unavailable - new schema migration in progress',
      message: 'File processing is disabled until the new Physical Design schema is implemented.'
    });
  } catch (error: any) {
    console.error('Error processing file:', error);
    if (error.code === '42P01') {
      return res.status(503).json({
        error: 'Database schema migration in progress',
        message: 'The eda_output_files table has been replaced. Please update the API to use the new Physical Design schema.'
      });
    }
    res.status(500).json({ error: error.message });
  }
});

/**
 * DELETE /api/eda-files/:id
 * Delete a processed file record (and optionally the file itself)
 * For JSON files with multiple stages, deletes ALL records with the same file_path
 */
router.delete('/:id', authenticate, async (req, res) => {
  try {
    // TODO: Update to use new Physical Design schema
    return res.status(503).json({
      error: 'Endpoint temporarily unavailable - new schema migration in progress',
      message: 'File deletion is disabled until the new Physical Design schema is implemented.'
    });
  } catch (error: any) {
    console.error('Error deleting file:', error);
    if (error.code === '42P01') {
      return res.status(503).json({
        error: 'Database schema migration in progress',
        message: 'The eda_output_files table has been replaced. Please update the API to use the new Physical Design schema.'
      });
    }
    res.status(500).json({ error: error.message });
  }
});

export default router;

