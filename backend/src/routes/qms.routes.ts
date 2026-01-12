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
    if (ext === '.csv') {
      cb(null, true);
    } else {
      cb(new Error('Only CSV files are allowed'));
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
 */
router.get('/blocks/:blockId/checklists', authenticate, async (req, res) => {
  try {
    const blockId = parseInt(req.params.blockId, 10);
    
    if (isNaN(blockId)) {
      return res.status(400).json({ error: 'Invalid block ID' });
    }

    const checklists = await qmsService.getChecklistsForBlock(blockId);
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
    
    if (isNaN(checklistId)) {
      return res.status(400).json({ error: 'Invalid checklist ID' });
    }

    const checklist = await qmsService.getChecklistWithItems(checklistId);
    
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
      const updatedChecklist = await qmsService.getChecklistWithItems(checklistId);

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
    
    if (isNaN(checkItemId)) {
      return res.status(400).json({ error: 'Invalid check item ID' });
    }

    const checkItem = await qmsService.getCheckItem(checkItemId);
    
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

      const updatedItem = await qmsService.getCheckItem(checkItemId);
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

      const updatedItem = await qmsService.getCheckItem(checkItemId);
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
 */
router.put(
  '/check-items/:checkItemId/approve',
  authenticate,
  authorize('admin', 'project_manager', 'lead'),
  async (req, res) => {
    try {
      const checkItemId = parseInt(req.params.checkItemId, 10);
      const { approved, comments } = req.body;
      const userId = (req as any).user?.id;
      
      if (isNaN(checkItemId)) {
        return res.status(400).json({ error: 'Invalid check item ID' });
      }

      if (typeof approved !== 'boolean') {
        return res.status(400).json({ error: 'approved must be a boolean' });
      }

      await qmsService.approveCheckItem(checkItemId, approved, comments || null, userId);

      const updatedItem = await qmsService.getCheckItem(checkItemId);
      res.json({
        message: `Check item ${approved ? 'approved' : 'rejected'}`,
        check_item: updatedItem
      });
    } catch (error: any) {
      console.error('Error approving check item:', error);
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

      const updatedItem = await qmsService.getCheckItem(checkItemId);
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

      const updatedChecklist = await qmsService.getChecklistWithItems(checklistId);
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

      const updatedChecklist = await qmsService.getChecklistWithItems(checklistId);
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
 */
router.post(
  '/check-items/batch-approve-reject',
  authenticate,
  authorize('admin', 'project_manager', 'lead'),
  async (req, res) => {
    try {
      const { check_item_ids, approved, comments } = req.body;
      const userId = (req as any).user?.id;
      
      if (!Array.isArray(check_item_ids) || check_item_ids.length === 0) {
        return res.status(400).json({ error: 'check_item_ids must be a non-empty array' });
      }

      if (typeof approved !== 'boolean') {
        return res.status(400).json({ error: 'approved must be a boolean' });
      }

      await qmsService.batchApproveRejectCheckItems(
        check_item_ids.map((id: any) => parseInt(id, 10)),
        approved,
        userId,
        comments || null
      );

      res.json({
        message: `${check_item_ids.length} check item(s) ${approved ? 'approved' : 'rejected'} successfully`
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
 * POST /api/qms/external/checklists/:checklistId/items/upload-report
 * External API endpoint for uploading CSV reports to check items
 * Requires API key authentication via X-API-Key header
 * Accepts file upload or report_path
 */
router.post(
  '/external/checklists/:checklistId/items/upload-report',
  authenticateApiKey,
  csvUpload.single('file'),
  async (req, res) => {
    try {
      const checklistId = parseInt(req.params.checklistId, 10);
      const { check_id, report_path } = req.body;
      const file = (req as any).file as Express.Multer.File;
      
      if (isNaN(checklistId)) {
        return res.status(400).json({ error: 'Invalid checklist ID' });
      }

      if (!check_id) {
        return res.status(400).json({ error: 'check_id is required' });
      }

      // Get check item by check_id (name) and checklist_id
      const checkItemResult = await pool.query(
        'SELECT id FROM check_items WHERE checklist_id = $1 AND name = $2',
        [checklistId, check_id]
      );

      if (checkItemResult.rows.length === 0) {
        return res.status(404).json({ 
          error: 'Check item not found',
          message: `No check item found with check_id "${check_id}" in checklist ${checklistId}`
        });
      }

      const checkItemId = checkItemResult.rows[0].id;
      
      // Determine report path: use uploaded file path or provided report_path
      let finalReportPath: string;
      if (file) {
        // Use uploaded file path
        finalReportPath = file.path;
      } else if (report_path) {
        // Use provided report_path (must exist on server)
        if (!fs.existsSync(report_path)) {
          return res.status(400).json({ 
            error: 'Report file not found',
            message: `The file at ${report_path} does not exist on the server`
          });
        }
        finalReportPath = report_path;
      } else {
        return res.status(400).json({ 
          error: 'No file or report_path provided',
          message: 'Either upload a file using the "file" field or provide "report_path" in form data'
        });
      }

      // Execute fill action (processes CSV and updates check item)
      // Note: We need a system user ID for audit logging. Use 1 (admin) or create a system user
      const systemUserId = 1; // Default to admin user for external API calls
      
      const csvData = await qmsService.executeFillAction(checkItemId, finalReportPath, systemUserId);

      // Clean up uploaded file if it was uploaded (not using existing path)
      if (file && fs.existsSync(file.path)) {
        try {
          fs.unlinkSync(file.path);
        } catch (unlinkError) {
          console.warn('Failed to delete uploaded file:', unlinkError);
        }
      }

      res.json({
        success: true,
        message: 'Report uploaded and processed successfully',
        data: {
          check_item_id: checkItemId,
          check_id: check_id,
          report_path: finalReportPath,
          rows_count: csvData.length,
          processed_at: new Date().toISOString()
        }
      });
    } catch (error: any) {
      // Clean up uploaded file on error
      if ((req as any).file && fs.existsSync((req as any).file.path)) {
        try {
          fs.unlinkSync((req as any).file.path);
        } catch (unlinkError) {
          console.warn('Failed to delete uploaded file on error:', unlinkError);
        }
      }
      console.error('Error uploading report via external API:', error);
      res.status(500).json({ 
        success: false,
        error: error.message || 'An error occurred while processing the report'
      });
    }
  }
);

export default router;

