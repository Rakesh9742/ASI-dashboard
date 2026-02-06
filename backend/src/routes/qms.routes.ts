import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { authenticate, authorize } from '../middleware/auth.middleware';
import { authenticateApiKey } from '../middleware/apiKey.middleware';
import qmsService from '../services/qms.service';
import { pool } from '../config/database';

const router = express.Router();

// Configure multer for Excel file uploads
const storage = multer.diskStorage({
  destination: (req: express.Request, file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) => {
    // Use temp directory for uploads (will be deleted after processing)
    const uploadDir = path.join(process.cwd(), 'uploads', 'qms-templates');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req: express.Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
    const timestamp = Date.now();
    const ext = path.extname(file.originalname);
    const name = path.basename(file.originalname, ext);
    cb(null, `qms_template_${timestamp}${ext}`);
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB limit
  },
  fileFilter: (req: express.Request, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ext === '.xlsx' || ext === '.xls') {
      cb(null, true);
    } else {
      cb(new Error('Only Excel files (.xlsx, .xls) are allowed'));
    }
  }
});

// Configure multer for CSV report uploads (external API)
const csvStorage = multer.diskStorage({
  destination: (req: express.Request, file: Express.Multer.File, cb: (error: Error | null, destination: string) => void) => {
    const uploadDir = path.join(process.cwd(), 'uploads', 'qms-reports');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req: express.Request, file: Express.Multer.File, cb: (error: Error | null, filename: string) => void) => {
    const timestamp = Date.now();
    const ext = path.extname(file.originalname).toLowerCase();
    const name = path.basename(file.originalname, ext);
    cb(null, `qms_report_${timestamp}${ext}`);
  }
});

const csvUpload = multer({
  storage: csvStorage,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB limit
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
 * GET /api/qms/filters
 * Get filter options (projects, domains, milestones, blocks)
 */
router.get('/filters', authenticate, async (req, res) => {
  try {
    const userId = (req as any).user?.id;
    const userRole = (req as any).user?.role;
    
    const filters = await qmsService.getFilterOptions(userId, userRole);
    res.json(filters);
  } catch (error: any) {
    console.error('Error getting filter options:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/qms/blocks/:blockId/checklists
 * Get all checklists for a block
 * Query params: experiment, rtl_tag (optional - for filtering by run)
 */
router.get('/blocks/:blockId/checklists', authenticate, async (req, res) => {
  try {
    const blockId = parseInt(req.params.blockId, 10);
    const userId = (req as any).user?.id;
    const userRole = (req as any).user?.role;
    const experiment = req.query.experiment as string | undefined;
    const rtlTag = req.query.rtl_tag as string | undefined;
    
    console.log(`[QMS] GET /blocks/${blockId}/checklists - experiment: ${experiment}, rtl_tag: ${rtlTag}`);
    
    if (isNaN(blockId)) {
      return res.status(400).json({ error: 'Invalid block ID' });
    }

    const checklists = await qmsService.getChecklistsForBlock(
      blockId, 
      userId, 
      userRole,
      experiment,
      rtlTag
    );
    console.log(`[QMS] Returning ${checklists.length} checklists`);
    res.json(checklists);
  } catch (error: any) {
    console.error('Error getting checklists:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/qms/checklists/:checklistId
 * Get checklist with all check items
 */
router.get('/checklists/:checklistId', authenticate, async (req, res) => {
  try {
    const checklistId = parseInt(req.params.checklistId, 10);
    const userId = (req as any).user?.id;
    
    if (isNaN(checklistId)) {
      return res.status(400).json({ error: 'Invalid checklist ID' });
    }

    const checklist = await qmsService.getChecklistWithItems(checklistId, userId);
    
    if (!checklist) {
      return res.status(404).json({ error: 'Checklist not found' });
    }

    res.json(checklist);
  } catch (error: any) {
    console.error('Error getting checklist:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PUT /api/qms/checklists/:checklistId
 * Update checklist (name only for now)
 */
router.put(
  '/checklists/:checklistId',
  authenticate,
  authorize('admin', 'lead'),
  async (req, res) => {
    try {
      const checklistId = parseInt(req.params.checklistId, 10);
      const { name } = req.body;
      const userId = (req as any).user?.id;

      if (isNaN(checklistId)) {
        return res.status(400).json({ error: 'Invalid checklist ID' });
      }

      await qmsService.updateChecklist(checklistId, name ?? null, userId);
      const updatedChecklist = await qmsService.getChecklistWithItems(checklistId, userId);

      res.json({
        message: 'Checklist updated successfully',
        checklist: updatedChecklist
      });
    } catch (error: any) {
      console.error('Error updating checklist:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * DELETE /api/qms/checklists/:checklistId
 * Delete checklist and related data
 */
router.delete(
  '/checklists/:checklistId',
  authenticate,
  authorize('admin', 'lead'),
  async (req, res) => {
    try {
      const checklistId = parseInt(req.params.checklistId, 10);
      const userId = (req as any).user?.id;

      if (isNaN(checklistId)) {
        return res.status(400).json({ error: 'Invalid checklist ID' });
      }

      await qmsService.deleteChecklist(checklistId, userId);
      res.json({ message: 'Checklist deleted successfully' });
    } catch (error: any) {
      console.error('Error deleting checklist:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * GET /api/qms/check-items/:checkItemId
 * Get check item details with report data
 */
router.get('/check-items/:checkItemId', authenticate, async (req, res) => {
  try {
    const checkItemId = parseInt(req.params.checkItemId, 10);
    const userId = (req as any).user?.id;
    
    if (isNaN(checkItemId)) {
      return res.status(400).json({ error: 'Invalid check item ID' });
    }

    const checkItem = await qmsService.getCheckItem(checkItemId, userId);
    
    if (!checkItem) {
      return res.status(404).json({ error: 'Check item not found' });
    }

    res.json(checkItem);
  } catch (error: any) {
    console.error('Error getting check item:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/qms/check-items/:checkItemId/fill-action
 * Execute Fill Action (fetch CSV report)
 */
router.post(
  '/check-items/:checkItemId/fill-action',
  authenticate,
  authorize('engineer', 'admin', 'lead'),
  async (req, res) => {
    try {
      const checkItemId = parseInt(req.params.checkItemId, 10);
      const { report_path } = req.body;
      
      if (isNaN(checkItemId)) {
        return res.status(400).json({ error: 'Invalid check item ID' });
      }

      if (!report_path) {
        return res.status(400).json({ error: 'report_path is required' });
      }

      const userId = (req as any).user?.id;
      const csvData = await qmsService.executeFillAction(checkItemId, report_path, userId);

      res.json({
        message: 'Fill action executed successfully',
        csv_data: csvData,
        rows_count: csvData.length
      });
    } catch (error: any) {
      console.error('Error executing fill action:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * PUT /api/qms/check-items/:checkItemId
 * Update check item (engineer: fix details, comments)
 */
router.put(
  '/check-items/:checkItemId',
  authenticate,
  authorize('engineer', 'admin', 'lead'),
  async (req, res) => {
    try {
      const checkItemId = parseInt(req.params.checkItemId, 10);
      const { fix_details, engineer_comments, description } = req.body;
      const userId = (req as any).user?.id;
      
      if (isNaN(checkItemId)) {
        return res.status(400).json({ error: 'Invalid check item ID' });
      }

      await qmsService.updateCheckItem(
        checkItemId,
        { fix_details, engineer_comments, description },
        userId
      );

      const updatedItem = await qmsService.getCheckItem(checkItemId, userId);
      res.json(updatedItem);
    } catch (error: any) {
      console.error('Error updating check item:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * POST /api/qms/check-items/:checkItemId/submit
 * Submit check item for approval
 */
router.post(
  '/check-items/:checkItemId/submit',
  authenticate,
  authorize('engineer', 'admin', 'lead'),
  async (req, res) => {
    try {
      const checkItemId = parseInt(req.params.checkItemId, 10);
      const userId = (req as any).user?.id;
      
      if (isNaN(checkItemId)) {
        return res.status(400).json({ error: 'Invalid check item ID' });
      }

      await qmsService.submitCheckItemForApproval(checkItemId, userId);

      const updatedItem = await qmsService.getCheckItem(checkItemId, userId);
      res.json({
        message: 'Check item submitted for approval',
        check_item: updatedItem
      });
    } catch (error: any) {
      console.error('Error submitting check item:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * PUT /api/qms/check-items/:checkItemId/approve
 * Approve/Reject check item (approver)
 * Supports: approved (boolean), with_waiver (boolean), comments (string)
 */
router.put(
  '/check-items/:checkItemId/approve',
  authenticate,
  authorize('engineer', 'admin', 'project_manager', 'lead'),
  async (req, res) => {
    try {
      const checkItemId = parseInt(req.params.checkItemId, 10);
      const { approved, with_waiver, comments } = req.body;
      const userId = (req as any).user?.id;
      
      if (isNaN(checkItemId)) {
        return res.status(400).json({ error: 'Invalid check item ID' });
      }

      if (typeof approved !== 'boolean') {
        return res.status(400).json({ error: 'approved must be a boolean' });
      }

      const withWaiver = with_waiver === true;
      await qmsService.approveCheckItem(checkItemId, approved, comments || null, userId, withWaiver);

      const updatedItem = await qmsService.getCheckItem(checkItemId, userId);
      
      let statusMessage = 'rejected';
      if (approved) {
        statusMessage = withWaiver ? 'approved with waiver' : 'approved';
      }
      
      res.json({
        message: `Check item ${statusMessage}`,
        check_item: updatedItem
      });
    } catch (error: any) {
      console.error('Error approving check item:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * PUT /api/qms/check-items/:checkItemId/comments
 * Update engineer or reviewer comments for a check item
 * Engineers can edit engineer_comments, Approvers/Admins can edit reviewer_comments
 */
router.put(
  '/check-items/:checkItemId/comments',
  authenticate,
  async (req, res) => {
    try {
      const checkItemId = parseInt(req.params.checkItemId, 10);
      const { engineer_comments, reviewer_comments } = req.body;
      const userId = (req as any).user?.id;
      const userRole = (req as any).user?.role;
      
      if (isNaN(checkItemId)) {
        return res.status(400).json({ error: 'Invalid check item ID' });
      }

      if (engineer_comments === undefined && reviewer_comments === undefined) {
        return res.status(400).json({ error: 'At least one comment field must be provided' });
      }

      await qmsService.updateCheckItemComments(
        checkItemId,
        engineer_comments,
        reviewer_comments,
        userId,
        userRole
      );

      const updatedItem = await qmsService.getCheckItem(checkItemId, userId);
      res.json({
        message: 'Comments updated successfully',
        check_item: updatedItem
      });
    } catch (error: any) {
      console.error('Error updating comments:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * PUT /api/qms/check-items/:checkItemId/assign-approver
 * Change approver (lead only)
 */
router.put(
  '/check-items/:checkItemId/assign-approver',
  authenticate,
  authorize('admin', 'lead'),
  async (req, res) => {
    try {
      const checkItemId = parseInt(req.params.checkItemId, 10);
      const { approver_id } = req.body;
      const userId = (req as any).user?.id;
      
      if (isNaN(checkItemId)) {
        return res.status(400).json({ error: 'Invalid check item ID' });
      }

      if (!approver_id || isNaN(parseInt(approver_id, 10))) {
        return res.status(400).json({ error: 'Valid approver_id is required' });
      }

      await qmsService.assignApprover(checkItemId, parseInt(approver_id, 10), userId);

      const updatedItem = await qmsService.getCheckItem(checkItemId, userId);
      res.json({
        message: 'Approver assigned successfully',
        check_item: updatedItem
      });
    } catch (error: any) {
      console.error('Error assigning approver:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * GET /api/qms/check-items/:checkItemId/history
 * Get audit trail for check item
 */
router.get('/check-items/:checkItemId/history', authenticate, async (req, res) => {
  try {
    const checkItemId = parseInt(req.params.checkItemId, 10);
    
    if (isNaN(checkItemId)) {
      return res.status(400).json({ error: 'Invalid check item ID' });
    }

    const history = await qmsService.getCheckItemHistory(checkItemId);
    res.json(history);
  } catch (error: any) {
    console.error('Error getting check item history:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/qms/checklists/:checklistId/submit
 * Submit entire checklist
 */
router.post(
  '/checklists/:checklistId/submit',
  authenticate,
  authorize('engineer', 'admin', 'lead'),
  async (req, res) => {
    try {
      const checklistId = parseInt(req.params.checklistId, 10);
      const userId = (req as any).user?.id;
      const { engineer_comments } = req.body || {};
      
      if (isNaN(checklistId)) {
        return res.status(400).json({ error: 'Invalid checklist ID' });
      }

      await qmsService.submitChecklist(checklistId, userId, engineer_comments || null);

      const updatedChecklist = await qmsService.getChecklistWithItems(checklistId, userId);
      res.json({
        message: 'Checklist submitted successfully',
        checklist: updatedChecklist
      });
    } catch (error: any) {
      console.error('Error submitting checklist:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * PUT /api/qms/checklists/:checklistId/assign-approver
 * Assign approver to all check items in a checklist (lead only)
 */
router.put(
  '/checklists/:checklistId/assign-approver',
  authenticate,
  authorize('admin', 'lead'),
  async (req, res) => {
    try {
      const checklistId = parseInt(req.params.checklistId, 10);
      const { approver_id } = req.body;
      const userId = (req as any).user?.id;
      
      if (isNaN(checklistId)) {
        return res.status(400).json({ error: 'Invalid checklist ID' });
      }

      if (!approver_id || isNaN(parseInt(approver_id, 10))) {
        return res.status(400).json({ error: 'Valid approver_id is required' });
      }

      await qmsService.assignApproverToChecklist(checklistId, parseInt(approver_id, 10), userId);

      const updatedChecklist = await qmsService.getChecklistWithItems(checklistId, userId);
      res.json({
        message: 'Approver assigned successfully',
        checklist: updatedChecklist
      });
    } catch (error: any) {
      console.error('Error assigning approver to checklist:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * POST /api/qms/check-items/batch-approve-reject
 * Batch approve or reject multiple check items
 * Supports: check_item_ids (array), approved (boolean), with_waiver (boolean), comments (string)
 */
router.post(
  '/check-items/batch-approve-reject',
  authenticate,
  authorize('engineer', 'admin', 'project_manager', 'lead'),
  async (req, res) => {
    try {
      const { check_item_ids, approved, with_waiver, comments } = req.body;
      const userId = (req as any).user?.id;
      
      if (!Array.isArray(check_item_ids) || check_item_ids.length === 0) {
        return res.status(400).json({ error: 'check_item_ids must be a non-empty array' });
      }

      if (typeof approved !== 'boolean') {
        return res.status(400).json({ error: 'approved must be a boolean' });
      }

      const withWaiver = with_waiver === true;
      await qmsService.batchApproveRejectCheckItems(
        check_item_ids.map((id: any) => parseInt(id, 10)),
        approved,
        userId,
        comments || null,
        withWaiver
      );

      let statusMessage = 'rejected';
      if (approved) {
        statusMessage = withWaiver ? 'approved with waiver' : 'approved';
      }

      res.json({
        message: `${check_item_ids.length} check item(s) ${statusMessage} successfully`
      });
    } catch (error: any) {
      console.error('Error batch approving/rejecting check items:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * GET /api/qms/checklists/:checklistId/approvers
 * Get list of available approvers for a checklist (excluding submitting engineer)
 */
router.get(
  '/checklists/:checklistId/approvers',
  authenticate,
  authorize('admin', 'lead'),
  async (req, res) => {
    try {
      const checklistId = parseInt(req.params.checklistId, 10);
      
      if (isNaN(checklistId)) {
        return res.status(400).json({ error: 'Invalid checklist ID' });
      }

      // Get submitting engineer ID
      const checklistResult = await pool.query(
        'SELECT submitted_by FROM checklists WHERE id = $1',
        [checklistId]
      );

      const submittedBy = checklistResult.rows[0]?.submitted_by || undefined;

      const approvers = await qmsService.getApproversForChecklist(checklistId, submittedBy);
      res.json(approvers);
    } catch (error: any) {
      console.error('Error getting approvers for checklist:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * GET /api/qms/blocks/:blockId/status
 * Get block submission status
 */
router.get('/blocks/:blockId/status', authenticate, async (req, res) => {
  try {
    const blockId = parseInt(req.params.blockId, 10);
    
    if (isNaN(blockId)) {
      return res.status(400).json({ error: 'Invalid block ID' });
    }

    const status = await qmsService.getBlockStatus(blockId);
    res.json(status);
  } catch (error: any) {
    console.error('Error getting block status:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/qms/blocks/:blockId/upload-template
 * Upload Excel template and create checklists and check items
 */
router.post(
  '/blocks/:blockId/upload-template',
  authenticate,
  authorize('admin', 'project_manager', 'lead'),
  upload.single('template'),
  async (req, res) => {
    try {
      const blockId = parseInt(req.params.blockId, 10);
      const userId = (req as any).user?.id;
      
      if (isNaN(blockId)) {
        return res.status(400).json({ error: 'Invalid block ID' });
      }

      if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
      }

      const { checklist_name, milestone_id } = req.body;

      const result = await qmsService.uploadTemplate(
        blockId,
        req.file.path,
        userId,
        checklist_name || null,
        milestone_id ? parseInt(milestone_id, 10) : null
      );

      // Replace default template with the latest uploaded file
      try {
        const templateDir = path.resolve(__dirname, '..', '..', 'templates');
        const templatePath = path.join(templateDir, 'Synthesis_QMS.xlsx');
        const backupPath = path.join(templateDir, `Synthesis_QMS_backup_${Date.now()}.xlsx`);

        if (!fs.existsSync(templateDir)) {
          fs.mkdirSync(templateDir, { recursive: true });
        }

        if (fs.existsSync(templatePath)) {
          fs.copyFileSync(templatePath, backupPath);
        }

        fs.copyFileSync(req.file.path, templatePath);
      } catch (replaceError) {
        console.warn('Failed to replace default template:', replaceError);
      }

      // Clean up uploaded file
      try {
        fs.unlinkSync(req.file.path);
      } catch (unlinkError) {
        console.warn('Failed to delete uploaded file:', unlinkError);
      }

      res.json({
        message: 'Template uploaded and processed successfully',
        ...result
      });
    } catch (error: any) {
      // Clean up uploaded file on error
      if (req.file && fs.existsSync(req.file.path)) {
        try {
          fs.unlinkSync(req.file.path);
        } catch (unlinkError) {
          console.warn('Failed to delete uploaded file on error:', unlinkError);
        }
      }
      console.error('Error uploading template:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * POST /api/qms/checklists/backfill-default-template
 * Backfill default checklist template for all existing block+experiment pairs.
 */
router.post(
  '/checklists/backfill-default-template',
  authenticate,
  authorize('admin', 'project_manager', 'lead'),
  async (req, res) => {
    try {
      const userId = (req as any).user?.id || null;
      const result = await qmsService.backfillDefaultChecklistsForAllExperiments(userId);
      res.json({
        success: true,
        message: 'Default checklists backfilled',
        ...result,
      });
    } catch (error: any) {
      console.error('Error backfilling default checklists:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * POST /api/qms/external/checklists/:checklistId/items/upload-report
 * External API endpoint for uploading JSON reports to a checklist
 * Requires API key authentication via X-API-Key header
 * Accepts JSON file upload or JSON body (report content)
 */
router.post(
  '/external/checklists/:checklistId/items/upload-report',
  authenticateApiKey,
  async (req, res) => {
    res.status(410).json({
      error: 'Endpoint moved',
      message: 'Use /api/qms/external-checklists/upload-report with JSON file or JSON body.'
    });
  }
);

/**
 * POST /api/qms/external-checklists/upload-report
 * External API endpoint for uploading JSON reports without checklist id in URL
 * Requires API key authentication via X-API-Key header
 * Accepts JSON file upload or JSON body
 */
router.post(
  '/external-checklists/upload-report',
  authenticateApiKey,
  csvUpload.single('file'),
  async (req, res) => {
    try {
      const file = (req as any).file as Express.Multer.File | undefined;
      const { report_path, report, report_json } = req.body || {};
      let reportData: any = null;
      let reportSourcePath: string | null = null;

      if (file) {
        const ext = path.extname(file.originalname).toLowerCase();
        if (ext !== '.json') {
          try {
            fs.unlinkSync(file.path);
          } catch (e) {
            // ignore
          }
          return res.status(400).json({
            error: 'Invalid report file type',
            message: 'Only JSON report files are supported',
            received: ext
          });
        }

        const fileContent = fs.readFileSync(file.path, 'utf8');
        reportData = JSON.parse(fileContent);
        reportSourcePath = file.path;
      } else if (report_path) {
        if (!fs.existsSync(report_path)) {
          return res.status(400).json({
            error: 'Report file not found',
            message: `The file at ${report_path} does not exist on the server`
          });
        }
        if (!report_path.toLowerCase().endsWith('.json')) {
          return res.status(400).json({
            error: 'Invalid report file type',
            message: 'Only JSON report files are supported'
          });
        }
        const fileContent = fs.readFileSync(report_path, 'utf8');
        reportData = JSON.parse(fileContent);
        reportSourcePath = report_path;
      } else if (report || report_json) {
        reportData = report || report_json;
      } else if (req.body && Object.keys(req.body).length > 0) {
        reportData = req.body;
      } else {
        return res.status(400).json({
          error: 'Report content is required',
          message: 'Provide a JSON file (multipart form field "file") or JSON body'
        });
      }

      if (typeof reportData === 'string') {
        reportData = JSON.parse(reportData);
      }

      const systemUserId = 1;
      const result = await qmsService.applyExternalSynReportData(reportData, systemUserId, reportSourcePath);
      console.log(
        `✅ [QMS EXTERNAL] checklist_id=${result.checklist_id} updated=${result.updated} ` +
        `missing_check_ids=${result.missing_check_ids.join(', ')} ` +
        `extra_check_ids=${result.extra_check_ids.join(', ')}`
      );

      res.json({
        success: true,
        message: 'Report uploaded and processed successfully',
        report_path: reportSourcePath,
        processed_at: new Date().toISOString(),
        ...result
      });
    } catch (error: any) {
      console.error('Error uploading report:', error);
      res.status(500).json({ error: error.message });
    } finally {
      const file = (req as any).file as Express.Multer.File | undefined;
      if (file && fs.existsSync(file.path)) {
        try {
          fs.unlinkSync(file.path);
        } catch (e) {
          // ignore cleanup errors
        }
      }
    }
  }
);

/**
 * GET /api/qms/checklists/:checklistId/history
 * Get version history of a checklist
 */
router.get('/checklists/:checklistId/history', authenticate, async (req, res) => {
  try {
    const checklistId = parseInt(req.params.checklistId, 10);
    
    if (isNaN(checklistId)) {
      return res.status(400).json({ error: 'Invalid checklist ID' });
    }

    const history = await qmsService.getChecklistHistory(checklistId);
    res.json(history);
  } catch (error: any) {
    console.error('Error getting checklist history:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/qms/versions/:versionId
 * Get a specific checklist version snapshot
 */
router.get('/versions/:versionId', authenticate, async (req, res) => {
  try {
    const versionId = parseInt(req.params.versionId, 10);
    
    if (isNaN(versionId)) {
      return res.status(400).json({ error: 'Invalid version ID' });
    }

    const version = await qmsService.getChecklistVersion(versionId);
    
    if (!version) {
      return res.status(404).json({ error: 'Version not found' });
    }

    res.json(version);
  } catch (error: any) {
    console.error('Error getting checklist version:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/qms/templates/upload-default
 * Upload and replace the default QMS template file (Admin only)
 */
router.post(
  '/templates/upload-default',
  authenticate,
  authorize('admin'),
  upload.single('template'),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
      }

      const ext = path.extname(req.file.originalname).toLowerCase();
      if (ext !== '.xlsx' && ext !== '.xls') {
        // Clean up uploaded file
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Only Excel files (.xlsx, .xls) are allowed' });
      }

      // Define paths
      const templateDir = path.resolve(__dirname, '..', '..', 'templates');
      const templatePath = path.join(templateDir, 'Synthesis_QMS.xlsx');
      const backupPath = path.join(templateDir, `Synthesis_QMS_backup_${Date.now()}.xlsx`);

      // Ensure templates directory exists
      if (!fs.existsSync(templateDir)) {
        fs.mkdirSync(templateDir, { recursive: true });
      }

      // Backup existing template if it exists
      if (fs.existsSync(templatePath)) {
        fs.copyFileSync(templatePath, backupPath);
        console.log(`Backed up existing template to: ${backupPath}`);
      }

      // Move uploaded file to replace the template
      fs.copyFileSync(req.file.path, templatePath);
      
      // Clean up the uploaded temp file
      fs.unlinkSync(req.file.path);

      res.json({
        message: 'Default template replaced successfully',
        template_path: 'templates/Synthesis_QMS.xlsx',
        backup_path: path.basename(backupPath),
        original_filename: req.file.originalname
      });
    } catch (error: any) {
      // Clean up uploaded file on error
      if (req.file && fs.existsSync(req.file.path)) {
        try {
          fs.unlinkSync(req.file.path);
        } catch (unlinkError) {
          console.warn('Failed to delete uploaded file on error:', unlinkError);
        }
      }
      console.error('Error replacing default template:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

/**
 * GET /api/qms/templates/backups
 * Get list of template backup files (Admin only)
 */
router.get(
  '/templates/backups',
  authenticate,
  authorize('admin'),
  async (req, res) => {
    try {
      const templateDir = path.resolve(__dirname, '..', '..', 'templates');
      
      if (!fs.existsSync(templateDir)) {
        return res.json({ backups: [] });
      }

      // Read directory and filter backup files
      const files = fs.readdirSync(templateDir);
      const backups = files
        .filter(file => file.startsWith('Synthesis_QMS_backup_') && file.endsWith('.xlsx'))
        .map(file => {
          const stats = fs.statSync(path.join(templateDir, file));
          return {
            filename: file,
            size: stats.size,
            created_at: stats.birthtime,
            modified_at: stats.mtime
          };
        })
        .sort((a, b) => b.created_at.getTime() - a.created_at.getTime()); // Most recent first

      res.json({ backups });
    } catch (error: any) {
      console.error('Error listing template backups:', error);
      res.status(500).json({ error: error.message });
    }
  }
);

export default router;

