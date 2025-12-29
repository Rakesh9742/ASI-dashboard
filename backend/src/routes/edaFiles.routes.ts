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
      FROM stages s
      INNER JOIN runs r ON s.run_id = r.id
      INNER JOIN blocks b ON r.block_id = b.id
      INNER JOIN projects p ON b.project_id = p.id
      LEFT JOIN project_domains pd ON p.id = pd.project_id
      LEFT JOIN domains d ON pd.domain_id = d.id
      LEFT JOIN stage_timing_metrics stm ON s.id = stm.stage_id
      LEFT JOIN stage_constraint_metrics scm ON s.id = scm.stage_id
      LEFT JOIN power_ir_em_checks pirem ON s.id = pirem.stage_id
      LEFT JOIN physical_verification pv ON s.id = pv.stage_id
      LEFT JOIN ai_summaries ai ON s.id = ai.stage_id
      WHERE 1=1
    `;

    const params: any[] = [];
    let paramCount = 0;

    // Filter by user role: engineers and customers only see their own runs
    if (userRole === 'engineer' || userRole === 'customer') {
      if (username) {
        paramCount++;
        query += ` AND LOWER(r.user_name) = LOWER($${paramCount})`;
        params.push(username);
        console.log(`Filtering EDA files for ${userRole} - only runs by user: ${username}`);
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

    const result = await pool.query(query, params);

    // Get total count for pagination
    let countQuery = `
      SELECT COUNT(DISTINCT s.id)
      FROM stages s
      INNER JOIN runs r ON s.run_id = r.id
      INNER JOIN blocks b ON r.block_id = b.id
      INNER JOIN projects p ON b.project_id = p.id
      LEFT JOIN project_domains pd ON p.id = pd.project_id
      LEFT JOIN domains d ON pd.domain_id = d.id
      WHERE 1=1
    `;
    const countParams: any[] = [];
    let countParamCount = 0;

    // Apply same user filtering to count query
    if (userRole === 'engineer' || userRole === 'customer') {
      if (username) {
        countParamCount++;
        countQuery += ` AND LOWER(r.user_name) = LOWER($${countParamCount})`;
        countParams.push(username);
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

