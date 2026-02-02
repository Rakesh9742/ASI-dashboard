import { pool } from '../config/database';
import fs from 'fs';
import path from 'path';
// @ts-ignore - csv-parser doesn't have types
import csv from 'csv-parser';
// @ts-ignore - xlsx doesn't have types
import * as XLSX from 'xlsx';

interface FilterOptions {
  projects: Array<{ id: number; name: string; domains: Array<{ id: number; name: string; code: string }> }>;
  milestones: Array<{ id: number; name: string; project_id: number }>;
  blocks: Array<{ id: number; block_name: string; project_id: number }>;
}

interface ChecklistData {
  id: number;
  block_id: number;
  milestone_id: number | null;
  name: string;
  status: string;
  engineer_comments: string | null;
  reviewer_comments: string | null;
  check_items?: CheckItemData[];
  created_at: Date;
  updated_at: Date;
}

interface CheckItemData {
  id: number;
  checklist_id: number;
  checklist_status?: string;
  check_name?: string | null;
  name: string;
  description: string | null;
  check_item_type: string | null;
  display_order: number;
  category: string | null;
  sub_category: string | null;
  severity: string | null;
  bronze: string | null;
  silver: string | null;
  gold: string | null;
  info: string | null;
  evidence: string | null;
  version: string | null;
  report_data?: CReportData;
  approval?: CheckItemApproval;
  created_at: Date;
  updated_at: Date;
}

interface CReportData {
  id: number;
  check_item_id: number;
  report_path: string | null;
  description: string | null;
  status: string;
  fix_details: string | null;
  engineer_comments: string | null;
  lead_comments: string | null;
  result_value: string | null;
  signoff_status: string | null;
  signoff_by: number | null;
  signoff_at: Date | null;
  csv_data: any | null;
  created_at: Date;
  updated_at: Date;
}

interface CheckItemApproval {
  id: number;
  check_item_id: number;
  default_approver_id: number | null;
  assigned_approver_id: number | null;
  assigned_by_lead_id: number | null;
  status: string;
  comments: string | null;
  submitted_at: Date | null;
  approved_at: Date | null;
}

class QmsService {
  private getDefaultTemplateFilePath(): string {
    // Template is stored under backend/templates for container accessibility
    const templatePath = path.resolve(__dirname, '..', '..', 'templates', 'Synthesis_QMS.xlsx');
    if (!fs.existsSync(templatePath)) {
      throw new Error(`Default QMS template not found at: ${templatePath}`);
    }
    return templatePath;
  }

  private getDefaultChecklistName(experimentName: string): string {
    const normalizedExperiment = (experimentName || '').trim();
    return normalizedExperiment ? `Synthesis QMS - ${normalizedExperiment}` : 'Synthesis QMS - Default';
  }

  private extractExperimentFromStageDirectory(stageDirectory?: string | null, blockName?: string | null): string | null {
    if (!stageDirectory) return null;
    const parts = stageDirectory.split('/').filter(Boolean);
    if (parts.length < 2) return null;

    if (blockName) {
      const blockIndex = parts.findIndex(part => part === blockName);
      if (blockIndex >= 0 && blockIndex + 1 < parts.length) {
        const experiment = parts[blockIndex + 1];
        if (experiment) return experiment;
      }
    }

    const experiment = parts[parts.length - 2];
    return experiment || null;
  }

  /**
   * Ensure default checklist exists for a block + experiment using the default template.
   */
  async ensureDefaultChecklistForBlockExperiment(
    blockId: number,
    experimentName: string,
    userId: number | null
  ): Promise<void> {
    const templatePath = this.getDefaultTemplateFilePath();
    const checklistName = this.getDefaultChecklistName(experimentName);
    await this.uploadTemplate(blockId, templatePath, userId ?? 0, checklistName, null);
  }

  /**
   * Backfill default checklists for all existing block+experiment pairs.
   */
  async backfillDefaultChecklistsForAllExperiments(userId: number | null): Promise<{ totalPairs: number; processed: number }> {
    const result = await pool.query(
      `SELECT DISTINCT block_id, experiment
       FROM runs
       WHERE experiment IS NOT NULL AND TRIM(experiment) <> ''`
    );
    const pairs = result.rows as Array<{ block_id: number; experiment: string }>;
    let processed = 0;
    for (const pair of pairs) {
      await this.ensureDefaultChecklistForBlockExperiment(pair.block_id, pair.experiment, userId);
      processed++;
    }
    return { totalPairs: pairs.length, processed };
  }

  /**
   * Apply external JSON report to a checklist derived from project/block/experiment.
   * Updates only matching check IDs; reports missing and extra check IDs.
   */
  async applyExternalSynReport(
    reportPath: string,
    userId: number
  ): Promise<{
    checklist_id: number;
    updated: number;
    missing_check_ids: string[];
    extra_check_ids: string[];
  }> {
    if (!fs.existsSync(reportPath)) {
      throw new Error(`Report file not found: ${reportPath}`);
    }
    if (path.extname(reportPath).toLowerCase() !== '.json') {
      throw new Error('Only JSON report files are supported');
    }

    const report = await this.parseJSONFile(reportPath);
    return this.applyExternalSynReportData(report, userId, reportPath);
  }

  /**
   * Apply external JSON report data to a checklist (report already parsed).
   */
  async applyExternalSynReportData(
    report: any,
    userId: number,
    reportPath: string | null = null
  ): Promise<{
    checklist_id: number;
    updated: number;
    missing_check_ids: string[];
    extra_check_ids: string[];
  }> {
    if (!report || typeof report !== 'object') {
      throw new Error('Invalid JSON report');
    }

    const projectName = report.project || report.project_name || report.projectName;
    const blockName = report.block_name || report.blockName;
    const experimentName =
      report.experiment ||
      report.experiment_name ||
      report.experimentName ||
      this.extractExperimentFromStageDirectory(report.stage_directory || report.stageDirectory, blockName);

    if (!projectName || !blockName || !experimentName) {
      throw new Error('Report must include project, block_name, and experiment (or stage_directory to infer experiment).');
    }

    const checks = report.checks && typeof report.checks === 'object' ? report.checks : null;
    if (!checks) {
      throw new Error('Report is missing "checks" object');
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const projectResult = await client.query(
        'SELECT id FROM projects WHERE LOWER(name) = LOWER($1)',
        [String(projectName).trim()]
      );
      if (projectResult.rows.length === 0) {
        throw new Error(`Project "${projectName}" not found`);
      }
      const projectId = projectResult.rows[0].id;

      const blockResult = await client.query(
        'SELECT id FROM blocks WHERE project_id = $1 AND block_name = $2',
        [projectId, String(blockName).trim()]
      );
      if (blockResult.rows.length === 0) {
        throw new Error(`Block "${blockName}" not found in project "${projectName}"`);
      }
      const blockId = blockResult.rows[0].id;

      const checklistName = this.getDefaultChecklistName(String(experimentName).trim());
      const checklistResult = await client.query(
        'SELECT id, status FROM checklists WHERE block_id = $1 AND name = $2',
        [blockId, checklistName]
      );
      if (checklistResult.rows.length === 0) {
        throw new Error(`Checklist "${checklistName}" not found for block "${blockName}"`);
      }
      const checklistId = checklistResult.rows[0].id;
      const checklistStatus = checklistResult.rows[0].status as string | null;
      if (checklistStatus !== 'rejected') {
        throw new Error(
          `Checklist "${checklistName}" is in "${checklistStatus ?? 'unknown'}" state; external updates are only allowed when status is "rejected".`
        );
      }

      const checklistItems = await client.query(
        'SELECT id, name FROM check_items WHERE checklist_id = $1',
        [checklistId]
      );
      const checklistCheckIds = new Set(checklistItems.rows.map((r: any) => r.name));

      const reportCheckIds = Object.keys(checks);
      const missingCheckIds = [...checklistCheckIds].filter(id => !reportCheckIds.includes(id));
      const extraCheckIds = reportCheckIds.filter(id => !checklistCheckIds.has(id));

      let updated = 0;

      for (const checkId of reportCheckIds) {
        if (!checklistCheckIds.has(checkId)) continue;
        const itemRow = checklistItems.rows.find((r: any) => r.name === checkId);
        if (!itemRow) continue;

        const checkData = checks[checkId] || {};
        const checkName = checkData.check_name || checkData.checkName || null;
        const status = checkData.status || null;
        const message = checkData.message || null;
        const value = checkData.value ?? null;
        const reportPathOverride = checkData.report_path || checkData.reportPath || null;

        await client.query(
          'UPDATE check_items SET check_name = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
          [checkName, itemRow.id]
        );

        const reportDataResult = await client.query(
          'SELECT id FROM c_report_data WHERE check_item_id = $1',
          [itemRow.id]
        );

        if (reportDataResult.rows.length > 0) {
          await client.query(
            `
              UPDATE c_report_data
              SET
                report_path = $1,
                csv_data = $2,
                status = $3,
                result_value = $4,
                engineer_comments = $5,
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $6
            `,
            [
              reportPathOverride || reportPath,
              JSON.stringify(checkData),
              status,
              value?.toString?.() ?? value,
              message,
              itemRow.id
            ]
          );
        } else {
          await client.query(
            `
              INSERT INTO c_report_data
                (check_item_id, report_path, csv_data, status, result_value, engineer_comments)
              VALUES ($1, $2, $3, $4, $5, $6)
            `,
            [
              itemRow.id,
              reportPathOverride || reportPath,
              JSON.stringify(checkData),
              status,
              value?.toString?.() ?? value,
              message
            ]
          );
        }

        await client.query(
          `
            UPDATE check_item_approvals
            SET
              status = 'pending',
              comments = NULL,
              submitted_at = NULL,
              approved_at = NULL,
              updated_at = CURRENT_TIMESTAMP
            WHERE check_item_id = $1
          `,
          [itemRow.id]
        );

        updated++;
      }

      if (updated > 0) {
        const checklistColsResult = await client.query(
          `
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'checklists'
              AND column_name IN ('submitted_by', 'submitted_at', 'approver_id', 'approver_role')
          `
        );
        const checklistCols = new Set(checklistColsResult.rows.map((r: any) => r.column_name));
        const updateFields: string[] = ["status = 'draft'", 'updated_at = CURRENT_TIMESTAMP'];
        if (checklistCols.has('submitted_by')) updateFields.push('submitted_by = NULL');
        if (checklistCols.has('submitted_at')) updateFields.push('submitted_at = NULL');
        if (checklistCols.has('approver_id')) updateFields.push('approver_id = NULL');
        if (checklistCols.has('approver_role')) updateFields.push('approver_role = NULL');

        await client.query(
          `UPDATE checklists SET ${updateFields.join(', ')} WHERE id = $1`,
          [checklistId]
        );
      }

      await client.query('COMMIT');
      return {
        checklist_id: checklistId,
        updated,
        missing_check_ids: missingCheckIds,
        extra_check_ids: extraCheckIds
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
  /**
   * Check if milestones table exists
   */
  private async milestonesTableExists(): Promise<boolean> {
    try {
      const result = await pool.query(`
        SELECT EXISTS (
          SELECT FROM information_schema.tables 
          WHERE table_schema = 'public' 
          AND table_name = 'milestones'
        );
      `);
      return result.rows[0]?.exists || false;
    } catch (error) {
      return false;
    }
  }

  /**
   * Get filter options for QMS (Project → Domain → Milestone → Block)
   */
  async getFilterOptions(userId?: number, userRole?: string): Promise<FilterOptions> {
    try {
      // Get projects with domains
      const queryParams: any[] = [];
      let joinClause = '';
      let whereClause = '';
      
      // Build join and filter based on user role
      if (userRole === 'customer') {
        // Customers see projects assigned via user_projects table
        joinClause = 'INNER JOIN user_projects up ON p.id = up.project_id';
        whereClause = 'WHERE up.user_id = $1';
        queryParams.push(userId);
      } else if (userRole === 'engineer') {
        // Engineers see projects they created OR projects assigned via user_projects
        joinClause = 'LEFT JOIN user_projects up ON p.id = up.project_id';
        whereClause = 'WHERE (p.created_by = $1 AND p.created_by IS NOT NULL) OR up.user_id = $1';
        queryParams.push(userId);
      }
      // Admin, project_manager, and lead see all projects (no filter)
      
      let projectQuery = `
        SELECT 
          p.id,
          p.name,
          COALESCE(
            json_agg(
              jsonb_build_object(
                'id', d.id,
                'name', d.name,
                'code', d.code
              )
            ) FILTER (WHERE d.id IS NOT NULL),
            '[]'
          ) as domains
        FROM projects p
        ${joinClause}
        LEFT JOIN project_domains pd ON pd.project_id = p.id
        LEFT JOIN domains d ON d.id = pd.domain_id AND d.is_active = true
        ${whereClause}
        GROUP BY p.id ORDER BY p.name
      `;

      const projectsResult = await pool.query(projectQuery, queryParams);
      const projects = projectsResult.rows.map((row: any) => {
        let domains = Array.isArray(row.domains) ? row.domains : [];
        // Remove duplicate domains based on id
        const uniqueDomains = domains.filter((domain: any, index: number, self: any[]) =>
          index === self.findIndex((d: any) => d.id === domain.id)
        );
        return {
          id: row.id,
          name: row.name,
          domains: uniqueDomains
        };
      });

      // Get milestones (table may not exist, so handle gracefully)
      let milestones: any[] = [];
      try {
        // Try to query milestones table - if it doesn't exist, catch the error
      let milestoneQuery = 'SELECT id, name, project_id FROM milestones';
        const milestoneParams: any[] = [];
        
        if (userRole === 'customer') {
          // Customers see milestones from projects assigned via user_projects
          milestoneQuery += ` WHERE project_id IN (
            SELECT project_id FROM user_projects WHERE user_id = $1
          )`;
          milestoneParams.push(userId);
        } else if (userRole === 'engineer') {
          // Engineers see milestones from projects they created OR projects assigned via user_projects
          milestoneQuery += ` WHERE project_id IN (
            SELECT id FROM projects WHERE created_by = $1 AND created_by IS NOT NULL
            UNION
            SELECT project_id FROM user_projects WHERE user_id = $1
          )`;
          milestoneParams.push(userId);
      }
        // Admin, project_manager, and lead see all milestones (no filter)
        
      milestoneQuery += ' ORDER BY name';
      
        const milestonesResult = await pool.query(milestoneQuery, milestoneParams);
        milestones = milestonesResult.rows;
      } catch (error: any) {
        // If table doesn't exist (42P01) or any other error, return empty array
        if (error.code === '42P01') {
          console.log('⚠️  Milestones table does not exist, returning empty array');
        } else {
          console.warn('⚠️  Could not fetch milestones:', error.message);
        }
        milestones = [];
      }

      // Get blocks
      // Important: Check project-specific roles from user_projects table
      // A user might have global role 'engineer' but be 'lead' in a specific project
      let blockQuery = `
        SELECT DISTINCT b.id, b.block_name, b.project_id
        FROM blocks b
      `;
      
      const blockQueryParams: any[] = [];
      
      if (userRole === 'customer') {
        // Customers see blocks from projects assigned via user_projects
        blockQuery += ` WHERE b.project_id IN (
          SELECT project_id FROM user_projects WHERE user_id = $1
        )`;
        blockQueryParams.push(userId);
      } else if (userRole === 'engineer' || userRole === 'lead' || userRole === 'project_manager' || userRole === 'admin') {
        // For engineers and elevated roles, check both:
        // 1. Projects they created
        // 2. Projects assigned via user_projects (regardless of role in user_projects)
        // This ensures users with project-specific roles see blocks for those projects
        blockQuery += ` WHERE b.project_id IN (
          SELECT id FROM projects WHERE created_by = $1 AND created_by IS NOT NULL
          UNION
          SELECT project_id FROM user_projects WHERE user_id = $1
        )`;
        blockQueryParams.push(userId);
        
        // Additionally, if user has global elevated role (admin, project_manager, lead),
        // they should see ALL blocks (no filter needed - already handled above)
        // But if their global role is 'engineer' but they have elevated role in a project,
        // the UNION above already includes those projects via user_projects
      }
      // Note: If userRole is admin/project_manager/lead globally, they see all blocks
      // But we still check user_projects to ensure project-specific access works
      
      blockQuery += ' ORDER BY b.block_name';
      
      const blocksResult = await pool.query(
        blockQuery,
        blockQueryParams.length > 0 ? blockQueryParams : []
      );
      const blocks = blocksResult.rows;

      return { projects, milestones, blocks };
    } catch (error: any) {
      console.error('Error getting filter options:', error);
      throw error;
    }
  }

  /**
   * Get all checklists for a block
   *
   * Visibility rules:
   * - Admin / project_manager / lead / engineer: can see all checklists for any block
   *   they have access to (block access is enforced when loading filters/blocks).
   * - Customer: can only see checklists for projects explicitly assigned to them.
   */
  async getChecklistsForBlock(blockId: number, userId?: number, userRole?: string): Promise<ChecklistData[]> {
    try {
      const hasMilestonesTable = await this.milestonesTableExists();
      const milestoneJoin = hasMilestonesTable 
        ? 'LEFT JOIN milestones m ON m.id = cl.milestone_id'
        : '';
      const milestoneSelect = hasMilestonesTable 
        ? 'm.name as milestone_name,'
        : 'NULL as milestone_name,';
      
      // Base WHERE clause: scoped to a single block
      let whereClause = 'WHERE cl.block_id = $1';
      const queryParams: any[] = [blockId];

      // Additional restriction only for customers
      if (userRole === 'customer' && userId) {
        // Customers see checklists for projects assigned to them
        whereClause += ` AND EXISTS (
          SELECT 1
          FROM blocks b
          JOIN user_projects up ON up.project_id = b.project_id
          WHERE b.id = cl.block_id
            AND up.user_id = $2
        )`;
        queryParams.push(userId);
      }
      // Admin, project_manager, and lead see all checklists (no additional filter)
      
      const result = await pool.query(
        `
          SELECT 
            cl.*,
            ${milestoneSelect}
            u_submitted.id as submitted_by_id,
            u_submitted.username as submitted_by_username,
            u_submitted.full_name as submitted_by_name,
            -- Current approver name (prefer pending assignment, else last approved)
            (
              SELECT u.full_name
              FROM check_items ci
              JOIN check_item_approvals cia ON cia.check_item_id = ci.id
              JOIN users u ON u.id = COALESCE(cia.assigned_approver_id, cia.default_approver_id)
              WHERE ci.checklist_id = cl.id
                AND u.id IS NOT NULL
              ORDER BY 
                CASE WHEN cia.status = 'pending' THEN 0 ELSE 1 END, -- pending first
                cia.updated_at DESC NULLS LAST,
                cia.approved_at DESC NULLS LAST
              LIMIT 1
            ) as approver_name,
            -- Current approver role (use project-specific role if available)
            (
              SELECT COALESCE(up.role, u.role::text)
              FROM check_items ci
              JOIN check_item_approvals cia ON cia.check_item_id = ci.id
              JOIN users u ON u.id = COALESCE(cia.assigned_approver_id, cia.default_approver_id)
              LEFT JOIN blocks b_checklist ON b_checklist.id = cl.block_id
              LEFT JOIN user_projects up ON up.user_id = u.id AND up.project_id = b_checklist.project_id
              WHERE ci.checklist_id = cl.id
                AND u.id IS NOT NULL
              ORDER BY 
                CASE WHEN cia.status = 'pending' THEN 0 ELSE 1 END,
                cia.updated_at DESC NULLS LAST,
                cia.approved_at DESC NULLS LAST
              LIMIT 1
            ) as approver_role,
            -- Current assigned approver ID (pending preferred)
            (
              SELECT COALESCE(cia.assigned_approver_id, cia.default_approver_id)
              FROM check_items ci
              JOIN check_item_approvals cia ON cia.check_item_id = ci.id
              WHERE ci.checklist_id = cl.id
                AND (cia.assigned_approver_id IS NOT NULL OR cia.default_approver_id IS NOT NULL)
              ORDER BY 
                CASE WHEN cia.status = 'pending' THEN 0 ELSE 1 END,
                cia.updated_at DESC NULLS LAST,
                cia.approved_at DESC NULLS LAST
              LIMIT 1
            ) as assigned_approver_id,
            -- Get submission date (when checklist was submitted)
            cl.submitted_at,
            -- Count of check items
            (
              SELECT COUNT(*)
              FROM check_items ci
              WHERE ci.checklist_id = cl.id
            ) as total_items,
            -- Count of approved items
            (
              SELECT COUNT(*)
              FROM check_items ci
              JOIN c_report_data crd ON crd.check_item_id = ci.id
              WHERE ci.checklist_id = cl.id
                AND crd.status = 'approved'
            ) as approved_items
          FROM checklists cl
          ${milestoneJoin}
          LEFT JOIN users u_submitted ON u_submitted.id = cl.submitted_by
          ${whereClause}
          ORDER BY cl.created_at ASC
        `,
        queryParams
      );

      return result.rows;
    } catch (error: any) {
      console.error('Error getting checklists:', error);
      throw error;
    }
  }

  /**
   * Update checklist basic details (currently name only)
   */
  async updateChecklist(
    checklistId: number,
    name: string | null,
    userId: number
  ): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        await client.query(
          `
            UPDATE checklists
            SET 
              name = COALESCE($1, name),
              updated_at = CURRENT_TIMESTAMP
            WHERE id = $2
          `,
          [name, checklistId]
        );

        const blockResult = await client.query(
          'SELECT block_id FROM checklists WHERE id = $1',
          [checklistId]
        );
        const blockId = blockResult.rows[0]?.block_id || null;

        await this.logAuditAction(
          client,
          null,
          checklistId,
          blockId,
          userId,
          'checklist_updated',
          { name }
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error updating checklist:', error);
      throw error;
    }
  }

  /**
   * Delete checklist and all related data
   */
  async deleteChecklist(checklistId: number, userId: number): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Get checklist and block info for audit BEFORE any deletions
        const checklistResult = await client.query(
          'SELECT id, name, block_id FROM checklists WHERE id = $1 FOR UPDATE',
          [checklistId]
        );
        
        if (checklistResult.rows.length === 0) {
          throw new Error('Checklist not found');
        }
        
        const checklistInfo = checklistResult.rows[0];
        const blockId = checklistInfo.block_id || null;
        const checklistName = checklistInfo.name;

        // Get all check item ids
        const itemsResult = await client.query(
          'SELECT id FROM check_items WHERE checklist_id = $1',
          [checklistId]
        );
        const checkItemIds = itemsResult.rows.map((r: any) => r.id);

        // CRITICAL: Verify checklist still exists right before logging (double-check after FOR UPDATE lock)
        const verifyChecklist = await client.query(
          'SELECT id FROM checklists WHERE id = $1',
          [checklistId]
        );
        
        // Determine the checklist_id to use for audit log
        // If checklist exists, use it; if not, use NULL (constraint allows NULL)
        const auditChecklistId = verifyChecklist.rows.length > 0 ? checklistId : null;
        
        if (verifyChecklist.rows.length === 0) {
          // Checklist was already deleted - log with NULL checklist_id
          console.warn(`Checklist ${checklistId} was already deleted, logging deletion with NULL checklist_id`);
        }

        // IMPORTANT: Log audit action FIRST, before ANY deletions
        // Use NULL for checklist_id if checklist doesn't exist (avoids foreign key violation)
        // Store the checklist info in action_details for audit trail
        await this.logAuditAction(
          client,
          null,
          auditChecklistId, // Use NULL if checklist doesn't exist, otherwise use checklistId
          blockId,
          userId,
          'checklist_deleted',
          {
            deleted_checklist_id: checklistId,
            deleted_checklist_name: checklistName,
            deleted_check_item_count: checkItemIds.length
          }
        );

        // Delete audit log entries that reference check items (these will be set to NULL by ON DELETE SET NULL constraint)
        // We delete them explicitly to clean up, but the constraint will handle it if we don't
        if (checkItemIds.length > 0) {
          await client.query(
            'DELETE FROM qms_audit_log WHERE check_item_id = ANY($1::int[])',
            [checkItemIds]
          );
        }

        if (checkItemIds.length > 0) {
          // Delete approvals
          await client.query(
            'DELETE FROM check_item_approvals WHERE check_item_id = ANY($1::int[])',
            [checkItemIds]
          );

          // Delete report data
          await client.query(
            'DELETE FROM c_report_data WHERE check_item_id = ANY($1::int[])',
            [checkItemIds]
          );

          // Delete check items
          await client.query(
            'DELETE FROM check_items WHERE id = ANY($1::int[])',
            [checkItemIds]
          );
        }

        // Delete checklist (the audit log entry's checklist_id will be set to NULL by ON DELETE SET NULL constraint)
        await client.query('DELETE FROM checklists WHERE id = $1', [checklistId]);

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error deleting checklist:', error);
      throw error;
    }
  }

  /**
   * Get checklist with all check items
   */
  async getChecklistWithItems(checklistId: number): Promise<ChecklistData | null> {
    try {
      const hasMilestonesTable = await this.milestonesTableExists();
      const milestoneJoin = hasMilestonesTable 
        ? 'LEFT JOIN milestones m ON m.id = cl.milestone_id'
        : '';
      const milestoneSelect = hasMilestonesTable 
        ? 'm.name as milestone_name,'
        : 'NULL as milestone_name,';
      
      const checklistResult = await pool.query(
        `
          SELECT 
            cl.*,
            ${milestoneSelect}
            b.block_name,
            u_submitted.id as submitted_by_id,
            u_submitted.username as submitted_by_username,
            u_submitted.full_name as submitted_by_name
          FROM checklists cl
          ${milestoneJoin}
          LEFT JOIN blocks b ON b.id = cl.block_id
          LEFT JOIN users u_submitted ON u_submitted.id = cl.submitted_by
          WHERE cl.id = $1
        `,
        [checklistId]
      );

      if (checklistResult.rows.length === 0) {
        return null;
      }

      const checklist = checklistResult.rows[0];

      // Check which columns exist in c_report_data table
      // TODO: These columns need to be added via migration 013_add_check_item_details.sql:
      // - description
      // - fix_details
      // - engineer_comments
      // - lead_comments
      // - result_value
      // - signoff_status
      // - signoff_by
      // - signoff_at
      const columnCheck = await pool.query(`
        SELECT column_name
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'c_report_data'
      `);
      const existingColumns = new Set(columnCheck.rows.map((r: any) => r.column_name));
      const hasDescription = existingColumns.has('description');
      const hasFixDetails = existingColumns.has('fix_details');
      const hasEngineerComments = existingColumns.has('engineer_comments');
      const hasLeadComments = existingColumns.has('lead_comments');
      const hasResultValue = existingColumns.has('result_value');
      const hasSignoffStatus = existingColumns.has('signoff_status');
      const hasSignoffBy = existingColumns.has('signoff_by');
      const hasSignoffAt = existingColumns.has('signoff_at');

      // Get check items with report data and approvals
      const itemsResult = await pool.query(
        `
          SELECT 
            ci.*,
            crd.id as report_data_id,
            crd.report_path,
            ${hasDescription ? 'crd.description as report_description,' : 'NULL as report_description,'}
            crd.status as report_status,
            ${hasFixDetails ? 'crd.fix_details,' : 'NULL as fix_details,'}
            ${hasEngineerComments ? 'crd.engineer_comments,' : 'NULL as engineer_comments,'}
            ${hasLeadComments ? 'crd.lead_comments,' : 'NULL as lead_comments,'}
            ${hasResultValue ? 'crd.result_value,' : 'NULL as result_value,'}
            ${hasSignoffStatus ? 'crd.signoff_status,' : 'NULL as signoff_status,'}
            ${hasSignoffBy ? 'crd.signoff_by,' : 'NULL as signoff_by,'}
            ${hasSignoffAt ? 'crd.signoff_at,' : 'NULL as signoff_at,'}
            crd.csv_data,
            crd.created_at as report_created_at,
            crd.updated_at as report_updated_at,
            cia.id as approval_id,
            cia.default_approver_id,
            cia.assigned_approver_id,
            cia.assigned_by_lead_id,
            cia.status as approval_status,
            cia.comments as approval_comments,
            cia.submitted_at,
            cia.approved_at,
            ua.username as assigned_approver_username,
            ua.full_name as assigned_approver_name,
            ud.username as default_approver_username,
            ud.full_name as default_approver_name,
            ${hasSignoffBy ? 'us.username as signoff_by_username,' : 'NULL as signoff_by_username,'}
            ${hasSignoffBy ? 'us.full_name as signoff_by_name' : 'NULL as signoff_by_name'}
          FROM check_items ci
          LEFT JOIN c_report_data crd ON crd.check_item_id = ci.id
          LEFT JOIN check_item_approvals cia ON cia.check_item_id = ci.id
          LEFT JOIN users ua ON ua.id = cia.assigned_approver_id
          LEFT JOIN users ud ON ud.id = cia.default_approver_id
          ${hasSignoffBy ? 'LEFT JOIN users us ON us.id = crd.signoff_by' : ''}
          WHERE ci.checklist_id = $1
          ORDER BY ci.display_order ASC, ci.id ASC
        `,
        [checklistId]
      );

      const checkItems: CheckItemData[] = itemsResult.rows.map((row: any) => ({
        id: row.id,
        checklist_id: row.checklist_id,
        check_name: row.check_name ?? null,
        name: row.name,
        description: row.description,
        check_item_type: row.check_item_type,
        display_order: row.display_order,
        category: row.category,
        sub_category: row.sub_category,
        severity: row.severity,
        bronze: row.bronze,
        silver: row.silver,
        gold: row.gold,
        info: row.info,
        evidence: row.evidence,
        version: row.version || 'v1',
        report_data: row.report_data_id ? {
          id: row.report_data_id,
          check_item_id: row.id,
          report_path: row.report_path,
          description: row.report_description,
          status: row.report_status,
          fix_details: row.fix_details,
          engineer_comments: row.engineer_comments,
          lead_comments: row.lead_comments,
          result_value: row.result_value,
          signoff_status: row.signoff_status,
          signoff_by: row.signoff_by,
          signoff_at: row.signoff_at,
          csv_data: row.csv_data,
          created_at: row.report_created_at,
          updated_at: row.report_updated_at
        } : undefined,
        approval: row.approval_id ? {
          id: row.approval_id,
          check_item_id: row.id,
          default_approver_id: row.default_approver_id,
          assigned_approver_id: row.assigned_approver_id,
          assigned_by_lead_id: row.assigned_by_lead_id,
          status: row.approval_status,
          comments: row.approval_comments,
          submitted_at: row.submitted_at,
          approved_at: row.approved_at,
          assigned_approver_name: row.assigned_approver_name,
          assigned_approver_username: row.assigned_approver_username,
          default_approver_name: row.default_approver_name,
          default_approver_username: row.default_approver_username
        } : undefined,
        created_at: row.created_at,
        updated_at: row.updated_at
      }));

      return {
        ...checklist,
        check_items: checkItems
      };
    } catch (error: any) {
      console.error('Error getting checklist with items:', error);
      throw error;
    }
  }

  /**
   * Get check item details with report data
   */
  async getCheckItem(checkItemId: number): Promise<CheckItemData | null> {
    try {
      // Check which columns exist in c_report_data table
      // TODO: These columns need to be added via migration 013_add_check_item_details.sql:
      // - description
      // - fix_details
      // - engineer_comments
      // - lead_comments
      // - result_value
      // - signoff_status
      // - signoff_by
      // - signoff_at
      const columnCheck = await pool.query(`
        SELECT column_name
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'c_report_data'
      `);
      const existingColumns = new Set(columnCheck.rows.map((r: any) => r.column_name));
      const hasDescription = existingColumns.has('description');
      const hasFixDetails = existingColumns.has('fix_details');
      const hasEngineerComments = existingColumns.has('engineer_comments');
      const hasLeadComments = existingColumns.has('lead_comments');
      const hasResultValue = existingColumns.has('result_value');
      const hasSignoffStatus = existingColumns.has('signoff_status');
      const hasSignoffBy = existingColumns.has('signoff_by');
      const hasSignoffAt = existingColumns.has('signoff_at');

      const result = await pool.query(
        `
          SELECT 
            ci.*,
            cl.status as checklist_status,
            crd.id as report_data_id,
            crd.report_path,
            ${hasDescription ? 'crd.description as report_description,' : 'NULL as report_description,'}
            crd.status as report_status,
            ${hasFixDetails ? 'crd.fix_details,' : 'NULL as fix_details,'}
            ${hasEngineerComments ? 'crd.engineer_comments,' : 'NULL as engineer_comments,'}
            ${hasLeadComments ? 'crd.lead_comments,' : 'NULL as lead_comments,'}
            ${hasResultValue ? 'crd.result_value,' : 'NULL as result_value,'}
            ${hasSignoffStatus ? 'crd.signoff_status,' : 'NULL as signoff_status,'}
            ${hasSignoffBy ? 'crd.signoff_by,' : 'NULL as signoff_by,'}
            ${hasSignoffAt ? 'crd.signoff_at,' : 'NULL as signoff_at,'}
            crd.csv_data,
            crd.created_at as report_created_at,
            crd.updated_at as report_updated_at,
            cia.id as approval_id,
            cia.default_approver_id,
            cia.assigned_approver_id,
            cia.assigned_by_lead_id,
            cia.status as approval_status,
            cia.comments as approval_comments,
            cia.submitted_at,
            cia.approved_at,
            ua.username as assigned_approver_username,
            ua.full_name as assigned_approver_name,
            ud.username as default_approver_username,
            ud.full_name as default_approver_name,
            ${hasSignoffBy ? 'us.username as signoff_by_username,' : 'NULL as signoff_by_username,'}
            ${hasSignoffBy ? 'us.full_name as signoff_by_name' : 'NULL as signoff_by_name'}
          FROM check_items ci
          LEFT JOIN checklists cl ON cl.id = ci.checklist_id
          LEFT JOIN c_report_data crd ON crd.check_item_id = ci.id
          LEFT JOIN check_item_approvals cia ON cia.check_item_id = ci.id
          LEFT JOIN users ua ON ua.id = cia.assigned_approver_id
          LEFT JOIN users ud ON ud.id = cia.default_approver_id
          ${hasSignoffBy ? 'LEFT JOIN users us ON us.id = crd.signoff_by' : ''}
          WHERE ci.id = $1
        `,
        [checkItemId]
      );

      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        id: row.id,
        checklist_id: row.checklist_id,
        checklist_status: row.checklist_status || 'draft',
        check_name: row.check_name ?? null,
        name: row.name,
        description: row.description,
        check_item_type: row.check_item_type,
        display_order: row.display_order,
        category: row.category,
        sub_category: row.sub_category,
        severity: row.severity,
        bronze: row.bronze,
        silver: row.silver,
        gold: row.gold,
        info: row.info,
        evidence: row.evidence,
        version: row.version || 'v1',
        report_data: row.report_data_id ? {
          id: row.report_data_id,
          check_item_id: row.id,
          report_path: row.report_path,
          description: row.report_description,
          status: row.report_status,
          fix_details: row.fix_details,
          engineer_comments: row.engineer_comments,
          lead_comments: row.lead_comments,
          result_value: row.result_value,
          signoff_status: row.signoff_status,
          signoff_by: row.signoff_by,
          signoff_at: row.signoff_at,
          csv_data: row.csv_data,
          created_at: row.report_created_at,
          updated_at: row.report_updated_at
        } : undefined,
        approval: row.approval_id ? {
          id: row.approval_id,
          check_item_id: row.id,
          default_approver_id: row.default_approver_id,
          assigned_approver_id: row.assigned_approver_id,
          assigned_by_lead_id: row.assigned_by_lead_id,
          status: row.approval_status,
          comments: row.approval_comments,
          submitted_at: row.submitted_at,
          approved_at: row.approved_at,
          // assigned_approver_name: row.assigned_approver_name,
          // assigned_approver_username: row.assigned_approver_username,
          // default_approver_name: row.default_approver_name,
          // default_approver_username: row.default_approver_username
        } : undefined,
        created_at: row.created_at,
        updated_at: row.updated_at
      };
    } catch (error: any) {
      console.error('Error getting check item:', error);
      throw error;
    }
  }

  /**
   * Execute Fill Action - fetch and parse CSV report
   */
  /**
   * Execute Fill Action - fetch and parse CSV/JSON report
   */
  async executeFillAction(
    checkItemId: number, 
    reportPath: string, 
    userId: number,
    additionalData?: {
      signoff_status?: string | null;
      result_value?: string | null;
      engineer_comments?: string | null;
      external_update?: boolean;
    }
  ): Promise<any> {
    try {
      // Validate file exists
      if (!fs.existsSync(reportPath)) {
        throw new Error(`Report file not found: ${reportPath}`);
      }

      // Parse file based on extension
      const ext = path.extname(reportPath).toLowerCase();
      let reportData: any[];
      
      if (ext === '.json') {
        const rawJson = await this.parseJSONFile(reportPath);
        
        // If it's an object (hash), extract metadata
        if (!Array.isArray(rawJson) && typeof rawJson === 'object' && rawJson !== null) {
          if (!additionalData) additionalData = {};
          
          const jsonSignoff = rawJson.signoff || rawJson.signoff_status;
          const jsonResultValue = rawJson.result || rawJson.result_value;
          const jsonComments = rawJson.comments || rawJson.engineer_comments;
          const jsonRepoPath = rawJson.report_path || rawJson.repo_path;

          if (jsonSignoff) additionalData.signoff_status = jsonSignoff;
          if (jsonResultValue) additionalData.result_value = jsonResultValue;
          if (jsonComments) additionalData.engineer_comments = jsonComments;
          if (jsonRepoPath) reportPath = jsonRepoPath;

          // Data rows might be in 'data', 'items', 'rows' or it's the object itself
          const possibleData = rawJson.data || rawJson.items || rawJson.rows;
          if (Array.isArray(possibleData)) {
            reportData = possibleData;
          } else if (possibleData && typeof possibleData === 'object') {
            reportData = [possibleData];
          } else {
            // If no clear data array/object, use the whole thing as one row if it's not the metadata itself
            reportData = [rawJson];
          }
        } else {
          reportData = Array.isArray(rawJson) ? rawJson : [rawJson];
        }
      } else {
        // Default to CSV for backward compatibility or explicit .csv
        reportData = await this.parseCSVFile(reportPath);
      }

      // Update or create report data
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check if report data exists
        const existingResult = await client.query(
          'SELECT id, status FROM c_report_data WHERE check_item_id = $1',
          [checkItemId]
        );

        if (existingResult.rows.length > 0) {
          // Update existing
          await client.query(
            `
              UPDATE c_report_data 
              SET 
                report_path = $1,
                csv_data = $2,
                status = CASE WHEN status = 'pending' THEN 'in_review' ELSE status END,
                signoff_status = COALESCE($4, signoff_status),
                result_value = COALESCE($5, result_value),
                engineer_comments = COALESCE($6, engineer_comments),
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $3
            `,
            [
              reportPath, 
              JSON.stringify(reportData), 
              checkItemId,
              additionalData?.signoff_status ?? null,
              additionalData?.result_value ?? null,
              additionalData?.engineer_comments ?? null
            ]
          );
        } else {
          // Create new
          await client.query(
            `
              INSERT INTO c_report_data 
                (check_item_id, report_path, csv_data, status, signoff_status, result_value, engineer_comments)
              VALUES ($1, $2, $3, 'in_review', $4, $5, $6)
            `,
            [
              checkItemId, 
              reportPath, 
              JSON.stringify(reportData),
              additionalData?.signoff_status ?? null,
              additionalData?.result_value ?? null,
              additionalData?.engineer_comments ?? null
            ]
          );
        }

        if (additionalData?.external_update) {
          // Reset check item approval status on external update
          await client.query(
            `
              UPDATE check_item_approvals 
              SET 
                status = 'pending',
                comments = NULL,
                submitted_at = NULL,
                approved_at = NULL,
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $1
            `,
            [checkItemId]
          );
        }

        // Get checklist and block info
        const checklistResult = await client.query(
          'SELECT checklist_id FROM check_items WHERE id = $1',
          [checkItemId]
        );
        const checklistId = checklistResult.rows[0]?.checklist_id;
        
        if (checklistId) {
          const checklistInfo = await client.query(
            'SELECT block_id, status FROM checklists WHERE id = $1',
          [checklistId]
        );
          const blockId = checklistInfo.rows[0]?.block_id;
          const checklistStatus = checklistInfo.rows[0]?.status;

          // External update should always reset checklist to draft to force re-submission
          if (additionalData?.external_update && checklistStatus !== 'draft') {
          const checklistColsResult = await client.query(
            `
              SELECT column_name
              FROM information_schema.columns
              WHERE table_schema = 'public'
                AND table_name = 'checklists'
            `
          );
          const checklistCols = new Set(checklistColsResult.rows.map((r: any) => r.column_name));
          const updateFields: string[] = ['status = $1', 'updated_at = CURRENT_TIMESTAMP'];
          const params: any[] = ['draft', checklistId];
          let paramIndex = 2;
          if (checklistCols.has('submitted_by')) {
            updateFields.push(`submitted_by = NULL`);
          }
          if (checklistCols.has('submitted_at')) {
            updateFields.push(`submitted_at = NULL`);
          }
          if (checklistCols.has('approver_id')) {
            updateFields.push(`approver_id = NULL`);
          }
          if (checklistCols.has('approver_role')) {
            updateFields.push(`approver_role = NULL`);
          }
          await client.query(
            `UPDATE checklists SET ${updateFields.join(', ')} WHERE id = $${paramIndex}`,
            params
          );
            
            await this.logAuditAction(
              client,
              null,
              checklistId,
              blockId,
              userId,
              'checklist_reset',
              { reason: 'External report update triggered status reset to draft' }
            );
          } else if (checklistStatus === 'rejected') {
            // If the checklist was rejected, move it back to draft
            await client.query(
              'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
              ['draft', checklistId]
            );
            await this.logAuditAction(
              client,
              null,
              checklistId,
              blockId,
              userId,
              'checklist_recovered',
              { reason: 'External report update triggered status reset from rejected to draft' }
            );
          }

          // Log audit action for fill_action
        await this.logAuditAction(
          client,
          checkItemId,
          checklistId,
          blockId,
          userId,
          'fill_action',
            {
              report_path: reportPath, 
              rows_count: reportData.length,
              external_update: additionalData?.external_update === true
            }
        );
        }

        await client.query('COMMIT');
        return reportData;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error executing fill action:', error);
      throw error;
    }
  }

  /**
   * External report upload for a checklist (JSON only).
   * Updates all matching check items and resets checklist to draft.
   */
  async applyExternalReportForChecklist(
    checklistId: number,
    reportPath: string,
    userId: number
  ): Promise<{ updated: number; missing_check_ids: string[]; skipped_rows: number }> {
    if (!fs.existsSync(reportPath)) {
      throw new Error(`Report file not found: ${reportPath}`);
    }
    if (path.extname(reportPath).toLowerCase() !== '.json') {
      throw new Error('Only JSON report files are supported for external uploads');
    }

    const rawJson = await this.parseJSONFile(reportPath);
    let rows: any[] = [];
    if (Array.isArray(rawJson)) {
      rows = rawJson;
    } else if (rawJson && typeof rawJson === 'object') {
      const possibleData = rawJson.data || rawJson.items || rawJson.rows;
      if (Array.isArray(possibleData)) {
        rows = possibleData;
      } else if (possibleData && typeof possibleData === 'object') {
        rows = [possibleData];
      } else {
        rows = [rawJson];
      }
    }

    if (rows.length === 0) {
      throw new Error('No rows found in JSON report');
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const checklistInfo = await client.query(
        'SELECT block_id, status FROM checklists WHERE id = $1',
        [checklistId]
      );
      const blockId = checklistInfo.rows[0]?.block_id || null;

      const missingCheckIds: string[] = [];
      let skippedRows = 0;
      let updated = 0;

      for (const row of rows) {
        if (!row || typeof row !== 'object') {
          skippedRows++;
          continue;
        }

        const checkId =
          row.check_id ||
          row.checkId ||
          row['Check ID'] ||
          row['check id'] ||
          row['CHECK ID'];

        if (!checkId || String(checkId).trim() === '') {
          skippedRows++;
          continue;
        }

        const checkItemResult = await client.query(
          'SELECT id FROM check_items WHERE checklist_id = $1 AND name = $2',
          [checklistId, String(checkId).trim()]
        );

        if (checkItemResult.rows.length === 0) {
          missingCheckIds.push(String(checkId).trim());
          continue;
        }

        const checkItemId = checkItemResult.rows[0].id;
        const rowReportPath = row.report_path || row.repo_path || reportPath;
        const signoffStatus = row.signoff || row.signoff_status || null;
        const resultValue = row.result || row.result_value || null;
        const comments = row.comments || row.engineer_comments || null;

        const existingResult = await client.query(
          'SELECT id FROM c_report_data WHERE check_item_id = $1',
          [checkItemId]
        );

        if (existingResult.rows.length > 0) {
          await client.query(
            `
              UPDATE c_report_data
              SET
                report_path = $1,
                csv_data = $2,
                status = 'in_review',
                signoff_status = COALESCE($4, signoff_status),
                result_value = COALESCE($5, result_value),
                engineer_comments = COALESCE($6, engineer_comments),
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $3
            `,
            [
              rowReportPath,
              JSON.stringify(row),
              checkItemId,
              signoffStatus,
              resultValue,
              comments
            ]
          );
        } else {
          await client.query(
            `
              INSERT INTO c_report_data
                (check_item_id, report_path, csv_data, status, signoff_status, result_value, engineer_comments)
              VALUES ($1, $2, $3, 'in_review', $4, $5, $6)
            `,
            [checkItemId, rowReportPath, JSON.stringify(row), signoffStatus, resultValue, comments]
          );
        }

        await client.query(
          `
            UPDATE check_item_approvals
            SET
              status = 'pending',
              comments = NULL,
              submitted_at = NULL,
              approved_at = NULL,
              updated_at = CURRENT_TIMESTAMP
            WHERE check_item_id = $1
          `,
          [checkItemId]
        );

        await this.logAuditAction(
          client,
          checkItemId,
          checklistId,
          blockId,
          userId,
          'external_report_update',
          { report_path: rowReportPath }
        );

        updated++;
      }

      if (updated > 0) {
      const checklistColsResult = await client.query(
        `
          SELECT column_name
          FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'checklists'
        `
      );
      const checklistCols = new Set(checklistColsResult.rows.map((r: any) => r.column_name));
      const updateFields: string[] = ['status = $1', 'updated_at = CURRENT_TIMESTAMP'];
      const params: any[] = ['draft', checklistId];
      let paramIndex = 2;
      if (checklistCols.has('submitted_by')) {
        updateFields.push(`submitted_by = NULL`);
      }
      if (checklistCols.has('submitted_at')) {
        updateFields.push(`submitted_at = NULL`);
      }
      if (checklistCols.has('approver_id')) {
        updateFields.push(`approver_id = NULL`);
      }
      if (checklistCols.has('approver_role')) {
        updateFields.push(`approver_role = NULL`);
      }
      await client.query(
        `UPDATE checklists SET ${updateFields.join(', ')} WHERE id = $${paramIndex}`,
        params
      );

        await this.logAuditAction(
          client,
          null,
          checklistId,
          blockId,
          userId,
          'checklist_reset',
          { reason: 'External report upload reset checklist to draft' }
        );
      }

      await client.query('COMMIT');
      return { updated, missing_check_ids: missingCheckIds, skipped_rows: skippedRows };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Parse JSON file and return data
   */
  private async parseJSONFile(filePath: string): Promise<any> {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(content);
    } catch (error: any) {
      console.error('Error parsing JSON file:', error);
      throw new Error(`Failed to parse JSON report: ${error.message}`);
    }
  }

  /**
   * Parse CSV file and return array of objects
   */
  private async parseCSVFile(filePath: string): Promise<any[]> {
    return new Promise((resolve, reject) => {
      const results: any[] = [];
      
      fs.createReadStream(filePath, { encoding: 'utf8' })
        .pipe(csv({
          headers: true,
          mapHeaders: ({ header }: { header: string }) => header.trim(),
          quote: '"',
          escape: '"'
        }))
        .on('data', (data: any) => {
          results.push(data);
        })
        .on('end', () => {
          resolve(results);
        })
        .on('error', (error: Error) => {
          reject(error);
        });
    });
  }

  /**
   * Update check item (engineer: fix details, comments)
   */
  async updateCheckItem(
    checkItemId: number,
    updates: {
      fix_details?: string;
      engineer_comments?: string;
      description?: string;
    },
    userId: number
  ): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Get current report data
        const reportResult = await client.query(
          'SELECT id, status FROM c_report_data WHERE check_item_id = $1',
          [checkItemId]
        );

        if (reportResult.rows.length === 0) {
          throw new Error('Report data not found. Please run Fill Action first.');
        }

        const reportDataId = reportResult.rows[0].id;
        const currentStatus = reportResult.rows[0].status;

        // Update report data
        const updateFields: string[] = [];
        const updateValues: any[] = [];
        let paramCount = 1;

        if (updates.fix_details !== undefined) {
          updateFields.push(`fix_details = $${paramCount++}`);
          updateValues.push(updates.fix_details);
        }
        if (updates.engineer_comments !== undefined) {
          updateFields.push(`engineer_comments = $${paramCount++}`);
          updateValues.push(updates.engineer_comments);
        }
        if (updates.description !== undefined) {
          updateFields.push(`description = $${paramCount++}`);
          updateValues.push(updates.description);
        }

        if (updateFields.length > 0) {
          updateFields.push(`updated_at = CURRENT_TIMESTAMP`);
          updateValues.push(checkItemId);

          await client.query(
            `UPDATE c_report_data SET ${updateFields.join(', ')} WHERE check_item_id = $${paramCount}`,
            updateValues
          );
        }

        // Log audit action
        const checklistResult = await client.query(
          'SELECT checklist_id FROM check_items WHERE id = $1',
          [checkItemId]
        );
        const checklistId = checklistResult.rows[0]?.checklist_id;
        
        const blockResult = await client.query(
          'SELECT block_id FROM checklists WHERE id = $1',
          [checklistId]
        );
        const blockId = blockResult.rows[0]?.block_id;

        await this.logAuditAction(
          client,
          checkItemId,
          checklistId,
          blockId,
          userId,
          'comment_added',
          { updates }
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error updating check item:', error);
      throw error;
    }
  }

  /**
   * Submit check item for approval
   */
  async submitCheckItemForApproval(checkItemId: number, userId: number): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check if report data exists
        const reportResult = await client.query(
          'SELECT id, status FROM c_report_data WHERE check_item_id = $1',
          [checkItemId]
        );

        if (reportResult.rows.length === 0) {
          throw new Error('Report data not found. Please run Fill Action first.');
        }

        const currentStatus = reportResult.rows[0].status;
        if (currentStatus === 'submitted' || currentStatus === 'approved') {
          throw new Error(`Check item is already ${currentStatus}`);
        }

        // Update status to submitted
        await client.query(
          `
            UPDATE c_report_data 
            SET status = 'submitted', updated_at = CURRENT_TIMESTAMP
            WHERE check_item_id = $1
          `,
          [checkItemId]
        );

        // Create or update approval record
        const approvalResult = await client.query(
          'SELECT id FROM check_item_approvals WHERE check_item_id = $1',
          [checkItemId]
        );

        if (approvalResult.rows.length === 0) {
          // Get default approver from check item or checklist
          const checkItemResult = await client.query(
            `
              SELECT ci.checklist_id, cl.block_id
              FROM check_items ci
              JOIN checklists cl ON cl.id = ci.checklist_id
              WHERE ci.id = $1
            `,
            [checkItemId]
          );
          
          const checklistId = checkItemResult.rows[0]?.checklist_id;
          const blockId = checkItemResult.rows[0]?.block_id;

          // For now, default approver can be set later by lead
          await client.query(
            `
              INSERT INTO check_item_approvals 
                (check_item_id, status, submitted_at)
              VALUES ($1, 'pending', CURRENT_TIMESTAMP)
            `,
            [checkItemId]
          );
        } else {
          // Only reset status to 'pending' if the item was previously rejected or already pending
          // Preserve 'approved' status for items that were already approved
          await client.query(
            `
              UPDATE check_item_approvals 
              SET 
                status = CASE 
                  WHEN status = 'approved' THEN 'approved'
                  ELSE 'pending'
                END,
                submitted_at = CURRENT_TIMESTAMP, 
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $1
            `,
            [checkItemId]
          );
        }

        // Log audit action
        const checklistResult = await client.query(
          'SELECT checklist_id FROM check_items WHERE id = $1',
          [checkItemId]
        );
        const checklistId = checklistResult.rows[0]?.checklist_id;
        
        const blockResult = await client.query(
          'SELECT block_id FROM checklists WHERE id = $1',
          [checklistId]
        );
        const blockId = blockResult.rows[0]?.block_id;

        await this.logAuditAction(
          client,
          checkItemId,
          checklistId,
          blockId,
          userId,
          'submitted',
          {}
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error submitting check item:', error);
      throw error;
    }
  }

  /**
   * Approve or reject check item
   */
  async approveCheckItem(
    checkItemId: number,
    approved: boolean,
    comments: string | null,
    userId: number
  ): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check if user is admin, project_manager, or lead (they can approve any item)
        const userCheck = await client.query(
          'SELECT role FROM users WHERE id = $1',
          [userId]
        );
        const userRole = userCheck.rows[0]?.role;
        const isAdminOrPMOrLead = userRole === 'admin' || userRole === 'project_manager' || userRole === 'lead';

        // Check approval record
        const approvalResult = await client.query(
          'SELECT id, assigned_approver_id, default_approver_id FROM check_item_approvals WHERE check_item_id = $1',
          [checkItemId]
        );

        if (approvalResult.rows.length === 0) {
          throw new Error('Approval record not found. Item must be submitted first.');
        }

        const approval = approvalResult.rows[0];
        const approverId = approval.assigned_approver_id || approval.default_approver_id;

        // Verify user is the assigned approver (unless admin, project_manager, or lead)
        // Also allow if no approver is assigned (null approverId)
        if (!isAdminOrPMOrLead && approverId != null && approverId !== userId) {
          throw new Error('You are not the assigned approver for this check item.');
        }

        // Update approval status
        const newStatus = approved ? 'approved' : 'not_approved';
        // Use separate query parameter for the CASE comparison to avoid type inference issues
        await client.query(
          `
            UPDATE check_item_approvals 
            SET 
              status = $1,
              comments = $2,
              approved_at = CASE WHEN $4 THEN CURRENT_TIMESTAMP ELSE NULL END,
              updated_at = CURRENT_TIMESTAMP
            WHERE check_item_id = $3
          `,
          [newStatus, comments || null, checkItemId, approved]
        );

        // Update report data status
        const reportStatus = approved ? 'approved' : 'not_approved';
        await client.query(
          `
            UPDATE c_report_data 
            SET status = $1, updated_at = CURRENT_TIMESTAMP
            WHERE check_item_id = $2
          `,
          [reportStatus, checkItemId]
        );

        // Log audit action
        const checklistResult = await client.query(
          'SELECT checklist_id FROM check_items WHERE id = $1',
          [checkItemId]
        );
        const checklistId = checklistResult.rows[0]?.checklist_id;
        
        const blockResult = await client.query(
          'SELECT block_id FROM checklists WHERE id = $1',
          [checklistId]
        );
        const blockId = blockResult.rows[0]?.block_id;

        await this.logAuditAction(
          client,
          checkItemId,
          checklistId,
          blockId,
          userId,
          approved ? 'approved' : 'rejected',
          { comments }
        );

        // Check if all items in checklist are now approved
        // Get ALL check items in the checklist (not just submitted ones)
        const allItemsResult = await client.query(
          `
            SELECT 
              ci.id,
              COALESCE(cia.status, 'pending') as approval_status,
              COALESCE(crd.status, 'pending') as report_status
            FROM check_items ci
            LEFT JOIN check_item_approvals cia ON cia.check_item_id = ci.id
            LEFT JOIN c_report_data crd ON crd.check_item_id = ci.id
            WHERE ci.checklist_id = $1
          `,
          [checklistId]
        );

        // Get total count of ALL check items in the checklist
        const totalItems = allItemsResult.rows.length;

          // Get checklist status
          const checklistStatusResult = await client.query(
            'SELECT status FROM checklists WHERE id = $1',
            [checklistId]
          );
          const currentStatus = checklistStatusResult.rows[0]?.status;

        // Check if all items are approved (only check when checklist is submitted_for_approval)
        if (currentStatus === 'submitted_for_approval' && totalItems > 0) {
          // Count approved items - an item is approved if both approval_status and report_status are 'approved'
          let approvedCount = 0;
          let rejectedCount = 0;

          allItemsResult.rows.forEach((row: any) => {
            const approvalStatus = row.approval_status;
            const reportStatus = row.report_status;
            
            // Item is approved if both approval and report status are 'approved'
            if (approvalStatus === 'approved' && reportStatus === 'approved') {
              approvedCount++;
            } else if (approvalStatus === 'not_approved' || reportStatus === 'not_approved') {
              rejectedCount++;
            }
          });

          // Auto-approve checklist if ALL items are approved
          if (approvedCount === totalItems && rejectedCount === 0) {
            // Check if approved_at column exists before updating
            const hasApprovedAtColumn = await client.query(
              `SELECT column_name FROM information_schema.columns 
               WHERE table_name = 'checklists' AND column_name = 'approved_at'`
            );
            
            if (hasApprovedAtColumn.rows.length > 0) {
              await client.query(
                'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP, approved_at = CURRENT_TIMESTAMP WHERE id = $2',
                ['approved', checklistId]
              );
            } else {
              await client.query(
                'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
                ['approved', checklistId]
              );
            }
              await this.logAuditAction(
                client,
                null,
                checklistId,
                blockId,
                userId,
                'checklist_approved',
              { reason: 'All check items approved - checklist auto-approved' }
              );
          } else if (rejectedCount > 0) {
            // Any item rejected - checklist is rejected
              await client.query(
                'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
              ['rejected', checklistId]
              );
            // Create a snapshot of the checklist state for history
            if (checklistId) {
              await this.createChecklistSnapshot(client, checklistId, userId, comments);
            }
              await this.logAuditAction(
                client,
                null,
                checklistId,
                blockId,
                userId,
                'checklist_rejected',
              { reason: 'One or more check items were rejected' }
              );
          }
        }

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error approving check item:', error);
      throw error;
    }
  }

  /**
   * Approve all check items in a checklist at once
   * Only available when checklist is in 'submitted_for_approval' status
   */
  async approveAllCheckItems(
    checklistId: number,
    userId: number,
    comments?: string | null
  ): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check if user is admin, project_manager, or lead
        const userCheck = await client.query(
          'SELECT role FROM users WHERE id = $1',
          [userId]
        );
        const userRole = userCheck.rows[0]?.role;
        const isAdminOrPMOrLead = userRole === 'admin' || userRole === 'project_manager' || userRole === 'lead';

        if (!isAdminOrPMOrLead) {
          throw new Error('Only admin, project manager, or lead can approve all items.');
        }

        // Verify checklist exists and is in submitted_for_approval status
        const checklistResult = await client.query(
          'SELECT id, status, block_id FROM checklists WHERE id = $1',
          [checklistId]
        );

        if (checklistResult.rows.length === 0) {
          throw new Error('Checklist not found');
        }

        const checklist = checklistResult.rows[0];
        if (checklist.status !== 'submitted_for_approval') {
          throw new Error('Checklist must be in submitted_for_approval status to approve all items.');
        }

        const blockId = checklist.block_id;

        // Get all check items with approval records (pending or submitted items)
        const checkItemsResult = await client.query(
          `
            SELECT ci.id, cia.id as approval_id, cia.assigned_approver_id, cia.default_approver_id
            FROM check_items ci
            INNER JOIN check_item_approvals cia ON cia.check_item_id = ci.id
            WHERE ci.checklist_id = $1
              AND cia.status IN ('pending', 'submitted')
          `,
          [checklistId]
        );

        if (checkItemsResult.rows.length === 0) {
          throw new Error('No pending check items found to approve.');
        }

        const checkItemIds = checkItemsResult.rows.map((row: any) => row.id);

        // Approve all check items
        for (const checkItemId of checkItemIds) {
          // Update approval status
          // Only update comments if provided (not null/undefined), otherwise keep existing
          await client.query(
            `
              UPDATE check_item_approvals 
              SET 
                status = 'approved',
                comments = COALESCE($1, comments),
                approved_at = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $2
            `,
            [comments || null, checkItemId]
          );

          // Update report data status
          await client.query(
            `
              UPDATE c_report_data 
              SET status = 'approved', updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $1
            `,
            [checkItemId]
          );

          // Log audit action for each item
          await this.logAuditAction(
            client,
            checkItemId,
            checklistId,
            blockId,
            userId,
            'approved',
            { comments, bulk_approved: true }
          );
        }

        // Update checklist status to approved
        await client.query(
          'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
          ['approved', checklistId]
        );

        // Log audit action for checklist
        await this.logAuditAction(
          client,
          null,
          checklistId,
          blockId,
          userId,
          'checklist_approved',
          { reason: 'All check items were bulk approved', comments, item_count: checkItemIds.length }
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error approving all check items:', error);
      throw error;
    }
  }

  /**
   * Batch approve or reject multiple check items
   */
  async batchApproveRejectCheckItems(
    checkItemIds: number[],
    approved: boolean,
    userId: number,
    comments?: string | null
  ): Promise<void> {
    if (checkItemIds.length === 0) {
      throw new Error('No check items provided');
    }

    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check user role
        const userCheck = await client.query(
          'SELECT role FROM users WHERE id = $1',
          [userId]
        );
        const userRole = userCheck.rows[0]?.role;
        const isAdminOrPMOrLead =
          userRole === 'admin' || userRole === 'project_manager' || userRole === 'lead';

        const status = approved ? 'approved' : 'not_approved';
        const reportStatus = approved ? 'approved' : 'not_approved';
        let checklistId: number | null = null;
        let blockId: number | null = null;

        // Process each check item
        for (const checkItemId of checkItemIds) {
          // Get checklist and block info
          const itemResult = await client.query(
            `
              SELECT 
                ci.checklist_id, 
                cl.block_id, 
                cl.status as checklist_status,
                cl.submitted_by
              FROM check_items ci
              JOIN checklists cl ON cl.id = ci.checklist_id
              WHERE ci.id = $1
            `,
            [checkItemId]
          );

          if (itemResult.rows.length === 0) {
            throw new Error(`Check item ${checkItemId} not found`);
          }

          const item = itemResult.rows[0];
          if (!checklistId) {
            checklistId = item.checklist_id;
            blockId = item.block_id;
          }

          // Check if checklist is in submitted_for_approval status
          if (item.checklist_status !== 'submitted_for_approval') {
            throw new Error(`Check item ${checkItemId} belongs to a checklist that is not in submitted_for_approval status.`);
          }

          // Check approval record
          const approvalResult = await client.query(
            'SELECT id, status, assigned_approver_id, default_approver_id FROM check_item_approvals WHERE check_item_id = $1',
            [checkItemId]
          );

          if (approvalResult.rows.length === 0) {
            throw new Error(`Approval record not found for check item ${checkItemId}. Item must be submitted first.`);
          }

          const approvalRecord = approvalResult.rows[0];
          const currentStatus = approvalRecord.status;

          // Only allow approving/rejecting pending or submitted items
          if (currentStatus !== 'pending' && currentStatus !== 'submitted') {
            throw new Error(
              `Check item ${checkItemId} is already ${currentStatus}. Cannot change status.`
            );
          }

          // Permission checks:
          // - Admin / PM / Lead can act on any items
          // - Engineer can only act if they are the assigned/default approver
          // - Submitting engineer cannot approve their own checklist
          const approverId =
            approvalRecord.assigned_approver_id ?? approvalRecord.default_approver_id;

          if (!isAdminOrPMOrLead) {
            // For engineers: must be the assigned approver
            if (approverId != null && approverId !== userId) {
              throw new Error(
                'You are not the assigned approver for one or more selected check items.'
              );
            }

            // Prevent submitting engineer from approving their own checklist
            if (item.submitted_by && item.submitted_by === userId) {
              throw new Error(
                'Submitting engineer cannot approve their own checklist.'
              );
            }
          }

          // Update approval status
          await client.query(
            `
              UPDATE check_item_approvals 
              SET 
                status = $1,
                comments = $2,
                approved_at = CASE WHEN $4 THEN CURRENT_TIMESTAMP ELSE NULL END,
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $3
            `,
            [status, comments || null, checkItemId, approved]
          );

          // Update report data status
          await client.query(
            `
              UPDATE c_report_data 
              SET status = $1, updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $2
            `,
            [reportStatus, checkItemId]
          );

          // Log audit action for each item
          await this.logAuditAction(
            client,
            checkItemId,
            checklistId,
            blockId,
            userId,
            approved ? 'approved' : 'rejected',
            { comments, batch_action: true }
          );
        }

        // Check if all items in checklist are now approved/rejected
        const allItemsResult = await client.query(
          `
            SELECT cia.status
            FROM check_items ci
            INNER JOIN check_item_approvals cia ON cia.check_item_id = ci.id
            WHERE ci.checklist_id = $1
          `,
          [checklistId]
        );

        const totalItems = allItemsResult.rows.length;
        let approvedCount = 0;
        let rejectedCount = 0;
        let pendingCount = 0;

        allItemsResult.rows.forEach((row: any) => {
          const itemStatus = row.status;
          if (itemStatus === 'approved') {
            approvedCount++;
          } else if (itemStatus === 'not_approved') {
            rejectedCount++;
          } else {
            pendingCount++;
          }
        });

        // Update checklist status if any item is rejected OR all items are approved
        const allReviewed = pendingCount === 0 && (approvedCount + rejectedCount) === totalItems;

        if (rejectedCount > 0) {
          // Any item rejected - checklist is rejected
          // Only update if not already rejected (to avoid redundant snapshots/audit logs if this was ever called twice)
          const currentChecklistStatus = await client.query('SELECT status FROM checklists WHERE id = $1', [checklistId]);
          if (currentChecklistStatus.rows[0]?.status === 'submitted_for_approval') {
            await client.query(
              'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
              ['rejected', checklistId]
            );
            
            // Create a snapshot of the checklist state for history
            if (checklistId) {
              await this.createChecklistSnapshot(client, checklistId, userId, comments || null);
            }
            await this.logAuditAction(
              client,
              null,
              checklistId,
              blockId,
              userId,
              'checklist_rejected',
              { reason: 'One or more check items were rejected', item_count: checkItemIds.length }
            );
          }
        } else if (allReviewed && approvedCount === totalItems) {
          // All items approved - checklist is approved
          await client.query(
            'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
            ['approved', checklistId]
          );
          await this.logAuditAction(
            client,
            null,
            checklistId,
            blockId,
            userId,
            'checklist_approved',
            { reason: 'All check items were approved', item_count: checkItemIds.length }
          );
        }

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error batch approving/rejecting check items:', error);
      throw error;
    }
  }

  /**
   * Assign approver to check item (lead only)
   */
  async assignApprover(
    checkItemId: number,
    approverId: number,
    userId: number
  ): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Get checklist info to check who submitted
        const checklistResult = await client.query(
          `
            SELECT cl.id, cl.submitted_by
            FROM check_items ci
            JOIN checklists cl ON cl.id = ci.checklist_id
            WHERE ci.id = $1
          `,
          [checkItemId]
        );

        if (checklistResult.rows.length === 0) {
          throw new Error('Check item not found');
        }

        const checklistId = checklistResult.rows[0].id;
        const submittedBy = checklistResult.rows[0].submitted_by;

        // Prevent assigning the submitting engineer as approver
        if (submittedBy && approverId === submittedBy) {
          throw new Error('Cannot assign the submitting engineer as approver');
        }

        // Check if approval record exists
        const approvalResult = await client.query(
          'SELECT id FROM check_item_approvals WHERE check_item_id = $1',
          [checkItemId]
        );

        if (approvalResult.rows.length === 0) {
          // Create approval record
          await client.query(
            `
              INSERT INTO check_item_approvals 
                (check_item_id, assigned_approver_id, assigned_by_lead_id, status)
              VALUES ($1, $2, $3, 'pending')
            `,
            [checkItemId, approverId, userId]
          );
        } else {
          // Update approval record
          await client.query(
            `
              UPDATE check_item_approvals 
              SET 
                assigned_approver_id = $1,
                assigned_by_lead_id = $2,
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $3
            `,
            [approverId, userId, checkItemId]
          );
        }

        // Log audit action
        const blockResult = await client.query(
          'SELECT block_id FROM checklists WHERE id = $1',
          [checklistId]
        );
        const blockId = blockResult.rows[0]?.block_id;

        await this.logAuditAction(
          client,
          checkItemId,
          checklistId,
          blockId,
          userId,
          'approver_assigned',
          { approver_id: approverId }
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error assigning approver:', error);
      throw error;
    }
  }

  /**
   * Assign approver to all check items in a checklist (lead only)
   */
  async assignApproverToChecklist(
    checklistId: number,
    approverId: number,
    userId: number
  ): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Get checklist info to check who submitted
        const checklistResult = await client.query(
          'SELECT submitted_by, block_id FROM checklists WHERE id = $1',
          [checklistId]
        );

        if (checklistResult.rows.length === 0) {
          throw new Error('Checklist not found');
        }

        const submittedBy = checklistResult.rows[0].submitted_by;
        const blockId = checklistResult.rows[0].block_id;

        // Prevent assigning the submitting engineer as approver
        if (submittedBy && approverId === submittedBy) {
          throw new Error('Cannot assign the submitting engineer as approver');
        }

        // Get all check items in the checklist
        const itemsResult = await client.query(
          'SELECT id FROM check_items WHERE checklist_id = $1',
          [checklistId]
        );

        // Assign approver to all check items
        for (const item of itemsResult.rows) {
          const checkItemId = item.id;
          
          const existingApproval = await client.query(
            'SELECT id FROM check_item_approvals WHERE check_item_id = $1',
            [checkItemId]
          );

          if (existingApproval.rows.length > 0) {
            // Update existing approval
            await client.query(
              `
                UPDATE check_item_approvals 
                SET assigned_approver_id = $1,
                    assigned_by_lead_id = $2,
                    updated_at = CURRENT_TIMESTAMP
                WHERE check_item_id = $3
              `,
              [approverId, userId, checkItemId]
            );
          } else {
            // Create new approval record
            await client.query(
              `
                INSERT INTO check_item_approvals 
                  (check_item_id, assigned_approver_id, assigned_by_lead_id, status)
                VALUES ($1, $2, $3, 'pending')
              `,
              [checkItemId, approverId, userId]
            );
          }
        }

        // Log audit action
        await this.logAuditAction(
          client,
          null,
          checklistId,
          blockId,
          userId,
          'checklist_approver_assigned',
          { approver_id: approverId }
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error assigning approver to checklist:', error);
      throw error;
    }
  }

  /**
   * Get audit trail for check item
   */
  async getCheckItemHistory(checkItemId: number): Promise<any[]> {
    try {
      const result = await pool.query(
        `
          SELECT 
            al.*,
            u.username,
            u.full_name,
            u.role
          FROM qms_audit_log al
          JOIN users u ON u.id = al.user_id
          WHERE al.check_item_id = $1
          ORDER BY al.created_at DESC
        `,
        [checkItemId]
      );

      return result.rows;
    } catch (error: any) {
      console.error('Error getting check item history:', error);
      throw error;
    }
  }

  /**
   * Submit entire checklist for approval
   * Sets status to 'submitted_for_approval', tracks submission, and assigns project lead as approver
   */
  async submitChecklist(checklistId: number, userId: number, engineerComments?: string | null): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Get block_id to find project lead
        const blockResult = await client.query(
          'SELECT block_id FROM checklists WHERE id = $1',
          [checklistId]
        );
        const blockId = blockResult.rows[0]?.block_id;

        if (!blockId) {
          throw new Error('Checklist not found or has no associated block.');
        }

        // Get project lead for this block
        const projectLeadId = await this.getProjectLeadForBlock(blockId);

        // Update checklist status to 'submitted_for_approval' and track submission
        // Store engineer_comments in checklists table
        await client.query(
          `
            UPDATE checklists 
            SET 
              status = 'submitted_for_approval',
              submitted_by = $1,
              submitted_at = CURRENT_TIMESTAMP,
              engineer_comments = COALESCE($3, engineer_comments),
              updated_at = CURRENT_TIMESTAMP
            WHERE id = $2
          `,
          [userId, checklistId, engineerComments ?? null]
        );

        // Get all check items in this checklist
        const checkItemsResult = await client.query(
          'SELECT id FROM check_items WHERE checklist_id = $1',
          [checklistId]
        );

        const checkItemIds = checkItemsResult.rows.map((row: any) => row.id);

        // Assign project lead as default approver for all check items
        // Also mark all check items as submitted and store engineer comments if provided
        for (const checkItemId of checkItemIds) {
          // Check if approval record exists
          const approvalCheck = await client.query(
            'SELECT id FROM check_item_approvals WHERE check_item_id = $1',
            [checkItemId]
          );

          if (approvalCheck.rows.length > 0) {
            // Update existing approval record
            // Preserve 'approved' status for items already approved
            // Only reset rejected/pending items to 'pending'
            await client.query(
              `
                UPDATE check_item_approvals 
                SET 
                  default_approver_id = $1,
                  status = CASE 
                    WHEN status = 'approved' THEN 'approved'
                    ELSE 'pending'
                  END,
                  submitted_at = CURRENT_TIMESTAMP,
                  updated_at = CURRENT_TIMESTAMP
                WHERE check_item_id = $2
              `,
              [projectLeadId, checkItemId]
            );
          } else {
            // Create new approval record
            await client.query(
              `
                INSERT INTO check_item_approvals 
                  (check_item_id, default_approver_id, status, submitted_at)
                VALUES ($1, $2, 'pending', CURRENT_TIMESTAMP)
              `,
              [checkItemId, projectLeadId]
            );
          }

          // Mark check item report data as submitted if it exists
          // Note: engineer_comments are now stored in checklists table, not c_report_data
          await client.query(
            `
              UPDATE c_report_data 
              SET 
                status = 'submitted',
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $1
            `,
            [checkItemId]
          );
        }

        // Log audit action
        await this.logAuditAction(
          client,
          null,
          checklistId,
          blockId,
          userId,
          'checklist_submitted_for_approval',
          { project_lead_id: projectLeadId }
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error submitting checklist:', error);
      throw error;
    }
  }

  /**
   * Get project lead for a block
   * Returns the first active user in the project's domain with role 'lead' (preferred) or 'admin'
   */
  async getProjectLeadForBlock(blockId: number): Promise<number | null> {
    try {
      const result = await pool.query(
        `
          SELECT u.id
          FROM blocks b
          JOIN projects p ON p.id = b.project_id
          JOIN project_domains pd ON pd.project_id = p.id
          JOIN domains d ON d.id = pd.domain_id
          JOIN users u ON u.domain_id = d.id
          WHERE b.id = $1
            AND u.role IN ('lead', 'admin')
            AND u.is_active = true
          ORDER BY 
            CASE WHEN u.role = 'lead' THEN 0 ELSE 1 END,
            u.id ASC
          LIMIT 1
        `,
        [blockId]
      );

      if (result.rows.length > 0) {
        return result.rows[0].id;
      }

      // Fallback: any active lead/admin in the system
      const globalResult = await pool.query(
        `
          SELECT id
          FROM users
          WHERE role IN ('lead', 'admin')
            AND is_active = true
          ORDER BY 
            CASE WHEN role = 'lead' THEN 0 ELSE 1 END,
            id ASC
          LIMIT 1
        `
      );

      return globalResult.rows.length > 0 ? globalResult.rows[0].id : null;
    } catch (error: any) {
      console.error('Error getting project lead for block:', error);
      throw error;
    }
  }

  /**
   * Get available approvers for a checklist
   * Returns users with roles: 'lead', 'engineer', 'admin'
   * Excludes the submitting engineer if provided
   */
  async getApproversForChecklist(checklistId: number, excludeUserId?: number): Promise<any[]> {
    try {
      // First, get the block_id from the checklist
      const checklistResult = await pool.query(
        'SELECT block_id FROM checklists WHERE id = $1',
        [checklistId]
      );

      if (checklistResult.rows.length === 0) {
        throw new Error('Checklist not found');
      }

      const blockId = checklistResult.rows[0].block_id;

      // Get the project_id from the block
      const blockResult = await pool.query(
        'SELECT project_id FROM blocks WHERE id = $1',
        [blockId]
      );

      if (blockResult.rows.length === 0) {
        throw new Error('Block not found');
      }

      const projectId = blockResult.rows[0].project_id;

      // Build query to get users assigned to this project
      // Include users who:
      // 1. Are assigned to the project via user_projects table, OR
      // 2. Created the project (created_by), OR
      // 3. Are admin (admins can approve any project)
      // Use project-specific role (up.role) if available, otherwise use global role (u.role)
      // Cast both to text to handle type mismatch (up.role is VARCHAR, u.role is ENUM)
      let query = `
        SELECT DISTINCT 
          u.id, 
          u.username, 
          u.full_name, 
          COALESCE(up.role, u.role::text) as role,
          u.email
        FROM users u
        LEFT JOIN user_projects up ON u.id = up.user_id AND up.project_id = $1
        LEFT JOIN projects p ON p.id = $1 AND p.created_by = u.id
        WHERE u.is_active = true
          AND (
            up.user_id IS NOT NULL
            OR p.created_by = u.id
            OR u.role = 'admin'
          )
          AND (
            COALESCE(up.role, u.role::text) IN ('lead', 'engineer', 'admin', 'project_manager')
          )
      `;
      const params: any[] = [projectId];

      if (excludeUserId) {
        query += ` AND u.id != $2`;
        params.push(excludeUserId);
      }

      query += ` ORDER BY COALESCE(up.role, u.role::text), u.full_name ASC`;

      const result = await pool.query(query, params);
      return result.rows;
    } catch (error: any) {
      console.error('Error getting approvers for checklist:', error);
      throw error;
    }
  }

  /**
   * Approve or reject an entire checklist
   * Updates checklist status and all associated check items
   */
  async approveChecklist(
    checklistId: number,
    approved: boolean,
    comments: string | null,
    userId: number
  ): Promise<void> {
    try {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check if user is admin
        const userCheck = await client.query(
          'SELECT role FROM users WHERE id = $1',
          [userId]
        );
        const userRole = userCheck.rows[0]?.role;
        const isAdmin = userRole === 'admin';

        // Verify user is assigned approver for at least one check item in this checklist (unless admin)
        if (!isAdmin) {
          const approverCheck = await client.query(
            `
              SELECT COUNT(*) as count
              FROM check_item_approvals cia
              JOIN check_items ci ON ci.id = cia.check_item_id
              WHERE ci.checklist_id = $1
                AND (cia.assigned_approver_id = $2 OR cia.default_approver_id = $2)
            `,
            [checklistId, userId]
          );

          if (parseInt(approverCheck.rows[0].count, 10) === 0) {
            throw new Error('You are not the assigned approver for any check items in this checklist.');
          }
        }

        // Get all check items in this checklist
        const checkItemsResult = await client.query(
          'SELECT id FROM check_items WHERE checklist_id = $1',
          [checklistId]
        );

        const checkItemIds = checkItemsResult.rows.map((row: any) => row.id);

        // Update all check item approvals
        // Note: reviewer_comments are now stored in checklists table, not check_item_approvals
        const statusValue = approved ? 'approved' : 'not_approved';
        for (const checkItemId of checkItemIds) {
          if (isAdmin) {
            // Admin can approve all items regardless of assignment
            await client.query(
              `
                UPDATE check_item_approvals 
                SET 
                  status = $1,
                  approved_at = CASE WHEN $3 THEN CURRENT_TIMESTAMP ELSE NULL END,
                  updated_at = CURRENT_TIMESTAMP
                WHERE check_item_id = $2
              `,
              [statusValue, checkItemId, approved]
            );
          } else {
            // Regular approver can only approve items they're assigned to
            await client.query(
              `
                UPDATE check_item_approvals 
                SET 
                  status = $1,
                  approved_at = CASE WHEN $4 THEN CURRENT_TIMESTAMP ELSE NULL END,
                  updated_at = CURRENT_TIMESTAMP
                WHERE check_item_id = $2
                  AND (assigned_approver_id = $3 OR default_approver_id = $3)
              `,
              [statusValue, checkItemId, userId, approved]
            );
          }

          // Update c_report_data status
          await client.query(
            `
              UPDATE c_report_data 
              SET 
                status = $1,
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $2
            `,
            [approved ? 'approved' : 'not_approved', checkItemId]
          );
        }

        // Update checklist status
        // If approved, set to 'approved'; if rejected, set back to 'draft'
        // Store reviewer_comments in checklists table
        const newChecklistStatus = approved ? 'approved' : 'draft';
        await client.query(
          `
            UPDATE checklists 
            SET 
              status = $1, 
              reviewer_comments = COALESCE($3, reviewer_comments),
              updated_at = CURRENT_TIMESTAMP
            WHERE id = $2
          `,
          [newChecklistStatus, checklistId, comments]
        );

        // Get block_id for audit log
        const blockResult = await client.query(
          'SELECT block_id FROM checklists WHERE id = $1',
          [checklistId]
        );
        const blockId = blockResult.rows[0]?.block_id;

        // Log audit action
        await this.logAuditAction(
          client,
          null,
          checklistId,
          blockId,
          userId,
          approved ? 'checklist_approved' : 'checklist_rejected',
          { comments }
        );

        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error approving checklist:', error);
      throw error;
    }
  }

  /**
   * Get block submission status
   */
  async getBlockStatus(blockId: number): Promise<any> {
    try {
      const result = await pool.query(
        `
          SELECT 
            cl.id as checklist_id,
            cl.name as checklist_name,
            cl.status as checklist_status,
            COUNT(ci.id) as total_items,
            COUNT(CASE WHEN crd.status = 'approved' THEN 1 END) as approved_items,
            COUNT(CASE WHEN crd.status = 'not_approved' THEN 1 END) as rejected_items,
            COUNT(CASE WHEN crd.status = 'submitted' THEN 1 END) as submitted_items
          FROM checklists cl
          LEFT JOIN check_items ci ON ci.checklist_id = cl.id
          LEFT JOIN c_report_data crd ON crd.check_item_id = ci.id
          WHERE cl.block_id = $1
          GROUP BY cl.id, cl.name, cl.status
          ORDER BY cl.created_at ASC
        `,
        [blockId]
      );

      const checklists = result.rows;
      const hasChecklists = checklists.length > 0;
      const allApproved = hasChecklists && checklists.every((cl: any) => cl.checklist_status === 'approved');
      const allSubmitted = hasChecklists && checklists.every((cl: any) =>
        cl.checklist_status === 'submitted_for_approval' || cl.checklist_status === 'approved'
      );

      return {
        block_id: blockId,
        all_checklists_approved: allApproved,
        all_checklists_submitted: allSubmitted,
        checklists: checklists
      };
    } catch (error: any) {
      console.error('Error getting block status:', error);
      throw error;
    }
  }

  /**
   * Upload Excel template and create checklists and check items
   */
  async uploadTemplate(
    blockId: number,
    filePath: string,
    userId: number,
    checklistName: string | null,
    milestoneId: number | null
  ): Promise<any> {
    try {
      // Read Excel file
      const workbook = XLSX.readFile(filePath);
      const sheetName = workbook.SheetNames[0]; // Use first sheet
      const worksheet = workbook.Sheets[sheetName];
      
      // Convert to JSON - handle merged header rows
      // First, parse normally to check for __EMPTY columns (indicates merged header)
      let data = XLSX.utils.sheet_to_json(worksheet, { 
        defval: null,
        raw: false,
        blankrows: false
      });
      
      // Check if we have __EMPTY columns (merged header scenario)
      let hasMergedHeader = false;
      if (data.length > 0 && data[0]) {
        const firstRow = data[0] as any;
        const hasEmptyColumns = Object.keys(firstRow).some(key => key.startsWith('__EMPTY'));
        
        if (hasEmptyColumns) {
          hasMergedHeader = true;
          console.log('📋 Detected merged header row - extracting headers from __EMPTY columns');
          
          // The first row contains the actual column headers in __EMPTY columns
          const headerRow = firstRow;
          const headerMap: { [key: string]: string } = {};
          
          // Map __EMPTY columns to their header names
          Object.keys(headerRow).forEach(key => {
            if (key.startsWith('__EMPTY')) {
              const headerName = headerRow[key];
              if (headerName && typeof headerName === 'string' && headerName.trim()) {
                headerMap[key] = headerName.trim();
              }
            }
          });
          
          console.log('📋 Header mapping:', headerMap);
          
          // Remap all data rows to use proper column names
          data = data.slice(1).map((row: any) => {
            const newRow: any = {};
            Object.keys(row).forEach((key: string) => {
              if (key.startsWith('__EMPTY') && headerMap[key]) {
                // Map __EMPTY column to its header name
                const headerName = headerMap[key];
                const value = row[key];
                if (value !== null && value !== undefined && value !== '') {
                  newRow[headerName] = value;
                }
              } else if (!key.startsWith('__EMPTY') && key !== 'Tool Logs & Warnings') {
                // Keep non-__EMPTY columns (but skip merged header cell)
                const value = row[key];
                if (value !== null && value !== undefined && value !== '') {
                  newRow[key] = value;
                }
              }
            });
            return newRow;
          }).filter((row: any) => Object.keys(row).length > 0); // Remove empty rows
        }
      }
      
      if (!Array.isArray(data) || data.length === 0) {
        throw new Error('Excel file is empty or invalid');
      }

      // Debug: Log first row to see actual column names
      if (data.length > 0) {
        console.log('========================================');
        console.log('📊 EXCEL UPLOAD DEBUG - Column Analysis');
        console.log('========================================');
        console.log('Has merged header:', hasMergedHeader);
        console.log('Total data rows:', data.length);
        console.log('Excel columns found:', Object.keys(data[0] as any));
        console.log('First row sample:', JSON.stringify(data[0], null, 2));
        console.log('First row raw object:', data[0]);
        console.log('========================================');
      }

      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check which columns exist in check_items table
        const columnCheck = await client.query(`
          SELECT column_name
          FROM information_schema.columns 
          WHERE table_schema = 'public' 
          AND table_name = 'check_items'
        `);
        const existingColumns = new Set(columnCheck.rows.map((r: any) => r.column_name));
        const hasCategory = existingColumns.has('category');
        const hasSubCategory = existingColumns.has('sub_category');
        const hasSeverity = existingColumns.has('severity');
        const hasBronze = existingColumns.has('bronze');
        const hasSilver = existingColumns.has('silver');
        const hasGold = existingColumns.has('gold');
        const hasInfo = existingColumns.has('info');
        const hasEvidence = existingColumns.has('evidence');
        const hasCheckName = existingColumns.has('check_name');
        const hasVersion = existingColumns.has('version');

        // Helper function to get value with multiple possible column names
        // Also handles case-insensitive matching and trimmed keys
        const getValue = (row: any, ...keys: string[]): any => {
          const rowKeys = Object.keys(row);
          
          // First try exact matches (case-sensitive)
          for (const key of keys) {
            if (row.hasOwnProperty(key) && row[key] !== undefined && row[key] !== null && String(row[key]).trim() !== '') {
              const value = String(row[key]).trim();
              return value === '' ? null : value;
            }
          }
          
          // Then try case-insensitive and trimmed matches
          for (const key of keys) {
            // Normalize the search key: trim, lowercase, normalize spaces
            const normalizedKey = key.trim().toLowerCase().replace(/\s+/g, ' ');
            
            for (const rowKey of rowKeys) {
              // Normalize the row key: trim, lowercase, normalize spaces
              const normalizedRowKey = rowKey.trim().toLowerCase().replace(/\s+/g, ' ');
              
              // Try exact normalized match
              if (normalizedRowKey === normalizedKey) {
                const value = row[rowKey];
                if (value !== undefined && value !== null && String(value).trim() !== '') {
                  const trimmedValue = String(value).trim();
                  return trimmedValue === '' ? null : trimmedValue;
                }
              }
              
              // Try match without special characters (for "Sub-Category" vs "Sub Category")
              const keyWithoutSpecial = normalizedKey.replace(/[-_\/]/g, ' ').replace(/\s+/g, ' ').trim();
              const rowKeyWithoutSpecial = normalizedRowKey.replace(/[-_\/]/g, ' ').replace(/\s+/g, ' ').trim();
              if (rowKeyWithoutSpecial === keyWithoutSpecial && rowKeyWithoutSpecial !== '') {
                const value = row[rowKey];
                if (value !== undefined && value !== null && String(value).trim() !== '') {
                  const trimmedValue = String(value).trim();
                  return trimmedValue === '' ? null : trimmedValue;
                }
              }
            }
          }
          return null;
        };

        // Group rows by checklist (if Checklist column exists, otherwise use provided name or default)
        const checklistMap = new Map<string, any[]>();
        // If checklist name is provided, use it; otherwise check Excel for Checklist column, or use default
        const defaultChecklistName = checklistName || 'Default Checklist';
        
        for (const row of data) {
          // If checklist_name is provided, use it for all rows; otherwise check Excel column
          const rowChecklistName = checklistName 
            ? checklistName 
            : (getValue(row, 'Checklist', 'CheckList', 'CL') || defaultChecklistName);
          if (!checklistMap.has(rowChecklistName)) {
            checklistMap.set(rowChecklistName, []);
          }
          checklistMap.get(rowChecklistName)!.push(row);
        }

        let totalCreatedItems = 0;
        let totalUpdatedItems = 0;
        const createdChecklists: string[] = [];

        // Process each checklist group
        for (const [checklistName, rows] of checklistMap.entries()) {
          // Check if checklist already exists
          let checklistResult = await client.query(
            'SELECT id FROM checklists WHERE block_id = $1 AND name = $2',
            [blockId, checklistName]
          );

          let checklistId: number;
          if (checklistResult.rows.length > 0) {
            checklistId = checklistResult.rows[0].id;
            // Update existing checklist
            await client.query(
              'UPDATE checklists SET milestone_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
              [milestoneId, checklistId]
            );
          } else {
            // Create new checklist
            const insertResult = await client.query(
              'INSERT INTO checklists (block_id, milestone_id, name, status) VALUES ($1, $2, $3, $4) RETURNING id',
              [blockId, milestoneId, checklistName, 'draft']
            );
            checklistId = insertResult.rows[0].id;
            createdChecklists.push(checklistName);
          }

          // Process each row as a check item
          let createdItems = 0;
          let updatedItems = 0;

          for (let i = 0; i < rows.length; i++) {
            const row = rows[i];

            // Debug: Log all available keys in the row for first row
            if (i === 0) {
              console.log('========================================');
              console.log('🔍 PROCESSING FIRST ROW - Detailed Analysis');
              console.log('========================================');
              console.log('All keys in first row:', Object.keys(row));
              console.log('First row full data:', JSON.stringify(row, null, 2));
              console.log('Sample key-value pairs:');
              Object.keys(row).forEach(key => {
                console.log(`  "${key}": "${row[key]}" (type: ${typeof row[key]})`);
              });
              console.log('========================================');
            }

            // Map Excel columns to database fields - try EXACT column names from Excel sheet first
            // Based on Excel: Check ID, Category, Sub-Category, Check Description, Severity, Bronze, Silver, Gold, Info, Evidence, Report path, Result/Value, Status, Comments, Reviewer comments, Signoff
            // Try exact matches first, then variations
            const checkItemName = getValue(row, 'Check ID', 'CheckID', 'Check_Id', 'check_id', 'Check Id', 'CHECK ID') || `Check Item ${i + 1}`;
            const category = getValue(row, 'Category', 'category', 'CATEGORY');
            const checkName = getValue(row, 'Check Name', 'check_name', 'check name', 'CheckName');
            const subCategory = getValue(row, 'Sub-Category', 'Sub Category', 'SubCategory', 'sub_category', 'sub-category', 'SUB_CATEGORY', 'Sub_Category', 'SUB-CATEGORY');
            const description = getValue(row, 'Check Description', 'CheckDescription', 'check_description', 'Description', 'description', 'Check_Description', 'CHECK DESCRIPTION');
            const severity = getValue(row, 'Severity', 'severity', 'SEVERITY');
            const bronze = getValue(row, 'Bronze', 'bronze', 'BRONZE');
            const silver = getValue(row, 'Silver', 'silver', 'SILVER');
            const gold = getValue(row, 'Gold', 'gold', 'GOLD');
            const info = getValue(row, 'Info', 'info', 'INFO', 'Information', 'information');
            const evidence = getValue(row, 'Evidence', 'evidence', 'EVIDENCE');
            const reportPath = getValue(row, 'Report path', 'Report Path', 'ReportPath', 'report_path', 'Report_path', 'Report_Path', 'REPORT PATH');
            const resultValue = getValue(row, 'Result/Value', 'Result/Value', 'Result Value', 'ResultValue', 'result_value', 'Result_Value', 'RESULT/VALUE', 'Result/Value');
            const status = getValue(row, 'Status', 'status', 'STATUS');
            const comments = getValue(row, 'Comments', 'comments', 'COMMENTS', 'Comment', 'comment');
            const reviewerComments = getValue(row, 'Reviewer comments', 'Reviewer Comments', 'ReviewerComments', 'reviewer_comments', 'Reviewer Comments', 'Reviewer_Comments', 'REVIEWER COMMENTS');
            const signoff = getValue(row, 'Signoff', 'SignOff', 'Sign Off', 'signoff', 'SIGNOFF', 'Sign-off', 'Sign_off');
            // Debug logging for first row
            if (i === 0) {
              console.log('========================================');
              console.log('✅ EXTRACTED VALUES FOR FIRST ROW');
              console.log('========================================');
              console.log('  Check ID:', checkItemName, checkItemName === `Check Item ${i + 1}` ? '⚠️ (USING DEFAULT)' : '✓');
              console.log('  Category:', category || '❌ NULL');
              console.log('  Check Name:', checkName || '❌ NULL');
              console.log('  Sub-Category:', subCategory || '❌ NULL');
              console.log('  Description:', description || '❌ NULL');
              console.log('  Severity:', severity || '❌ NULL');
              console.log('  Bronze:', bronze || '❌ NULL');
              console.log('  Silver:', silver || '❌ NULL');
              console.log('  Gold:', gold || '❌ NULL');
              console.log('  Info:', info || '❌ NULL');
              console.log('  Evidence:', evidence || '❌ NULL');
              console.log('  Report Path:', reportPath || '❌ NULL');
              console.log('  Result/Value:', resultValue || '❌ NULL');
              console.log('  Status:', status || '❌ NULL');
              console.log('  Comments:', comments || '❌ NULL');
              console.log('  Reviewer Comments:', reviewerComments || '❌ NULL');
              console.log('  Signoff:', signoff || '❌ NULL');
              console.log('========================================');
            }

            // Check if check item already exists (by name in this checklist)
            const existingItem = await client.query(
              'SELECT id FROM check_items WHERE checklist_id = $1 AND name = $2',
              [checklistId, checkItemName]
            );

            let checkItemId: number;
            if (existingItem.rows.length > 0) {
              // Update existing check item
              checkItemId = existingItem.rows[0].id;
              
              let updateQuery = 'UPDATE check_items SET ';
              const updateParams: any[] = [];
              let paramIndex = 1;

              if (hasCategory && category !== null) {
                updateQuery += `category = $${paramIndex}, `;
                updateParams.push(category);
                paramIndex++;
              }
              if (hasCheckName && checkName !== null) {
                updateQuery += `check_name = $${paramIndex}, `;
                updateParams.push(checkName);
                paramIndex++;
              }
              if (hasSubCategory && subCategory !== null) {
                updateQuery += `sub_category = $${paramIndex}, `;
                updateParams.push(subCategory);
                paramIndex++;
              }
              if (description !== null) {
                updateQuery += `description = $${paramIndex}, `;
                updateParams.push(description);
                paramIndex++;
              }
              if (hasSeverity && severity !== null) {
                updateQuery += `severity = $${paramIndex}, `;
                updateParams.push(severity);
                paramIndex++;
              }
              if (hasBronze && bronze !== null) {
                updateQuery += `bronze = $${paramIndex}, `;
                updateParams.push(bronze);
                paramIndex++;
              }
              if (hasSilver && silver !== null) {
                updateQuery += `silver = $${paramIndex}, `;
                updateParams.push(silver);
                paramIndex++;
              }
              if (hasGold && gold !== null) {
                updateQuery += `gold = $${paramIndex}, `;
                updateParams.push(gold);
                paramIndex++;
              }
              if (hasInfo && info !== null) {
                updateQuery += `info = $${paramIndex}, `;
                updateParams.push(info);
                paramIndex++;
              }
              if (hasEvidence && evidence !== null) {
                updateQuery += `evidence = $${paramIndex}, `;
                updateParams.push(evidence);
                paramIndex++;
              }
              updateQuery += `updated_at = CURRENT_TIMESTAMP WHERE id = $${paramIndex}`;
              updateParams.push(checkItemId);

              await client.query(updateQuery, updateParams);
              updatedItems++;
              totalUpdatedItems++;
            } else {
              // Create new check item
              let insertColumns = 'checklist_id, name, description';
              let insertValues = '$1, $2, $3';
              const insertParams: any[] = [checklistId, checkItemName, description];
              let paramIndex = 4;

              if (hasCategory && category !== null) {
                insertColumns += ', category';
                insertValues += `, $${paramIndex}`;
                insertParams.push(category);
                paramIndex++;
              }
              if (hasCheckName && checkName !== null) {
                insertColumns += ', check_name';
                insertValues += `, $${paramIndex}`;
                insertParams.push(checkName);
                paramIndex++;
              }
              if (hasSubCategory && subCategory !== null) {
                insertColumns += ', sub_category';
                insertValues += `, $${paramIndex}`;
                insertParams.push(subCategory);
                paramIndex++;
              }
              if (hasSeverity && severity !== null) {
                insertColumns += ', severity';
                insertValues += `, $${paramIndex}`;
                insertParams.push(severity);
                paramIndex++;
              }
              if (hasBronze && bronze !== null) {
                insertColumns += ', bronze';
                insertValues += `, $${paramIndex}`;
                insertParams.push(bronze);
                paramIndex++;
              }
              if (hasSilver && silver !== null) {
                insertColumns += ', silver';
                insertValues += `, $${paramIndex}`;
                insertParams.push(silver);
                paramIndex++;
              }
              if (hasGold && gold !== null) {
                insertColumns += ', gold';
                insertValues += `, $${paramIndex}`;
                insertParams.push(gold);
                paramIndex++;
              }
              if (hasInfo && info !== null) {
                insertColumns += ', info';
                insertValues += `, $${paramIndex}`;
                insertParams.push(info);
                paramIndex++;
              }
              if (hasEvidence && evidence !== null) {
                insertColumns += ', evidence';
                insertValues += `, $${paramIndex}`;
                insertParams.push(evidence);
                paramIndex++;
              }
              insertColumns += ', display_order';
              insertValues += `, $${paramIndex}`;
              insertParams.push(i + 1);
              paramIndex++;
              
              if (hasVersion) {
                insertColumns += ', version';
                insertValues += `, $${paramIndex}`;
                insertParams.push('v1');
              }

              const itemResult = await client.query(
                `INSERT INTO check_items (${insertColumns}) VALUES (${insertValues}) RETURNING id`,
                insertParams
              );
              checkItemId = itemResult.rows[0].id;
              createdItems++;
              totalCreatedItems++;
            }

            // Create or update report data (always create/update if any report data exists)
            if (reportPath || resultValue || status || comments || reviewerComments || signoff) {
              const existingReport = await client.query(
                'SELECT id FROM c_report_data WHERE check_item_id = $1',
                [checkItemId]
              );

              // Determine status: use Excel Status if provided, otherwise default to 'pending'
              const reportStatus = status || 'pending';

              if (existingReport.rows.length > 0) {
                // Check which columns exist before updating
                const columnCheck = await client.query(`
                  SELECT column_name
                  FROM information_schema.columns 
                  WHERE table_schema = 'public' 
                  AND table_name = 'c_report_data'
                `);
                const existingColumns = new Set(columnCheck.rows.map((r: any) => r.column_name));
                
                let updateQuery = 'UPDATE c_report_data SET ';
                const updateParams: any[] = [];
                let paramIndex = 1;

                if (reportPath !== null) {
                  updateQuery += `report_path = $${paramIndex}, `;
                  updateParams.push(reportPath);
                  paramIndex++;
                }
                if (resultValue !== null && existingColumns.has('result_value')) {
                  updateQuery += `result_value = $${paramIndex}, `;
                  updateParams.push(resultValue);
                  paramIndex++;
                }
                if (existingColumns.has('status')) {
                  updateQuery += `status = $${paramIndex}, `;
                  updateParams.push(reportStatus);
                  paramIndex++;
                }
                if (comments !== null && existingColumns.has('engineer_comments')) {
                  updateQuery += `engineer_comments = $${paramIndex}, `;
                  updateParams.push(comments);
                  paramIndex++;
                }
                if (reviewerComments !== null && existingColumns.has('lead_comments')) {
                  updateQuery += `lead_comments = $${paramIndex}, `;
                  updateParams.push(reviewerComments);
                  paramIndex++;
                }
                if (signoff !== null && existingColumns.has('signoff_status')) {
                  updateQuery += `signoff_status = $${paramIndex}, `;
                  updateParams.push(signoff);
                  paramIndex++;
                }
                
                updateQuery += `updated_at = CURRENT_TIMESTAMP WHERE check_item_id = $${paramIndex}`;
                updateParams.push(checkItemId);

                await client.query(updateQuery, updateParams);
              } else {
                // Check which columns exist before inserting
                const columnCheck = await client.query(`
                  SELECT column_name
                  FROM information_schema.columns 
                  WHERE table_schema = 'public' 
                  AND table_name = 'c_report_data'
                `);
                const existingColumns = new Set(columnCheck.rows.map((r: any) => r.column_name));

                let insertColumns = 'check_item_id, report_path';
                let insertValues = '$1, $2';
                const insertParams: any[] = [checkItemId, reportPath || null];
                let paramIndex = 3;

                if (existingColumns.has('result_value')) {
                  insertColumns += ', result_value';
                  insertValues += `, $${paramIndex}`;
                  insertParams.push(resultValue || null);
                  paramIndex++;
                }
                if (existingColumns.has('status')) {
                  insertColumns += ', status';
                  insertValues += `, $${paramIndex}`;
                  insertParams.push(reportStatus);
                  paramIndex++;
                }
                if (existingColumns.has('engineer_comments')) {
                  insertColumns += ', engineer_comments';
                  insertValues += `, $${paramIndex}`;
                  insertParams.push(comments || null);
                  paramIndex++;
                }
                if (existingColumns.has('lead_comments')) {
                  insertColumns += ', lead_comments';
                  insertValues += `, $${paramIndex}`;
                  insertParams.push(reviewerComments || null);
                  paramIndex++;
                }
                if (existingColumns.has('signoff_status')) {
                  insertColumns += ', signoff_status';
                  insertValues += `, $${paramIndex}`;
                  insertParams.push(signoff || null);
                  paramIndex++;
                }

                await client.query(
                  `INSERT INTO c_report_data (${insertColumns}) VALUES (${insertValues})`,
                  insertParams
                );
              }
            }
          }
        }

        // Log audit action for each checklist
        for (const checklistName of createdChecklists) {
          const checklistResult = await client.query(
            'SELECT id FROM checklists WHERE block_id = $1 AND name = $2',
            [blockId, checklistName]
          );
          if (checklistResult.rows.length > 0) {
            await this.logAuditAction(
              client,
              null,
              checklistResult.rows[0].id,
              blockId,
              userId,
              'template_uploaded',
              { 
                file_path: filePath,
                checklist_name: checklistName
              }
            );
          }
        }

        await client.query('COMMIT');

        return {
          checklists_created: createdChecklists.length,
          checklists_names: createdChecklists,
          items_created: totalCreatedItems,
          items_updated: totalUpdatedItems,
          total_rows: data.length
        };
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    } catch (error: any) {
      console.error('Error uploading template:', error);
      throw error;
    }
  }

  /**
   * Log audit action (internal helper)
   */
  private async logAuditAction(
    client: any,
    checkItemId: number | null,
    checklistId: number | null,
    blockId: number | null,
    userId: number | null,
    actionType: string,
    actionDetails: any
  ): Promise<void> {
    if (!userId) return; // Skip if no user ID provided

    // Determine entity_type based on what IDs are provided and include in actionDetails
    let entityType = 'checklist';
    if (checkItemId) {
      entityType = 'check_item';
    } else if (checklistId) {
      entityType = 'checklist';
    }

    // Store block_id and entity_type in actionDetails
    const detailsWithBlock = { 
      ...actionDetails, 
      entity_type: entityType,
      ...(blockId ? { block_id: blockId } : {})
    };

    await client.query(
      `
        INSERT INTO qms_audit_log 
          (check_item_id, checklist_id, block_id, user_id, action_type, action_details, entity_type)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
      `,
      [
        checkItemId, 
        checklistId, 
        blockId,
        userId, 
        actionType,
        JSON.stringify(detailsWithBlock),
        entityType
      ]
    );
  }
  /**
   * Create a snapshot of a checklist state (usually on rejection)
   */
  private async createChecklistSnapshot(
    client: any,
    checklistId: number,
    userId: number,
    comments: string | null
  ): Promise<void> {
    try {
      // 1. Fetch current checklist data
      const hasMilestonesTable = await this.milestonesTableExists();
      const milestoneJoin = hasMilestonesTable 
        ? 'LEFT JOIN milestones m ON m.id = cl.milestone_id'
        : '';
      const milestoneSelect = hasMilestonesTable 
        ? 'm.name as milestone_name,'
        : 'NULL as milestone_name,';

      const checklistResult = await client.query(
        `
          SELECT 
            cl.*, 
            b.block_name,
            ${milestoneSelect}
            u_submitted.full_name as submitted_by_name,
            u_approver.full_name as approver_name,
            COALESCE(up_approver.role, u_approver.role::text) as approver_role
          FROM checklists cl 
          LEFT JOIN blocks b ON b.id = cl.block_id 
          ${milestoneJoin}
          LEFT JOIN users u_submitted ON u_submitted.id = cl.submitted_by
          LEFT JOIN users u_approver ON u_approver.id = $2
          LEFT JOIN user_projects up_approver ON up_approver.user_id = u_approver.id AND up_approver.project_id = b.project_id
          WHERE cl.id = $1
        `,
        [checklistId, userId]
      );
      
      if (checklistResult.rows.length === 0) return;
      const checklist = checklistResult.rows[0];
      
      // 2. Fetch all check items with report data and approvals
      const itemsResult = await client.query(
        `
          SELECT 
            ci.*,
            crd.report_path, 
            crd.status as report_status, 
            crd.description as report_description,
            crd.fix_details, 
            crd.engineer_comments, 
            crd.lead_comments, 
            crd.result_value,
            crd.signoff_status, 
            crd.signoff_by, 
            crd.signoff_at,
            us.full_name as signoff_by_name,
            crd.csv_data,
            cia.status as approval_status, 
            cia.comments as approval_comments,
            cia.submitted_at as approval_submitted_at, 
            cia.approved_at as approval_approved_at
          FROM check_items ci
          LEFT JOIN c_report_data crd ON crd.check_item_id = ci.id
          LEFT JOIN check_item_approvals cia ON cia.check_item_id = ci.id
          LEFT JOIN users us ON us.id = crd.signoff_by
          WHERE ci.checklist_id = $1
          ORDER BY ci.display_order ASC
        `,
        [checklistId]
      );
      
      const snapshot = {
        ...checklist,
        check_items: itemsResult.rows
      };
      
      // 3. Get latest version number
      const versionResult = await client.query(
        'SELECT COALESCE(MAX(version_number), 0) + 1 as next_version FROM qms_checklist_versions WHERE checklist_id = $1',
        [checklistId]
      );
      const nextVersion = versionResult.rows[0].next_version;
      
      // 4. Insert snapshot
      await client.query(
        `
          INSERT INTO qms_checklist_versions 
          (checklist_id, version_number, checklist_snapshot, rejected_by, rejection_comments)
          VALUES ($1, $2, $3, $4, $5)
        `,
        [checklistId, nextVersion, JSON.stringify(snapshot), userId, comments]
      );
      
      console.log(`Created QMS history snapshot for checklist ${checklistId}, version ${nextVersion}`);
    } catch (error) {
      console.error('Error creating checklist snapshot:', error);
      // In Postgres, a failed query poisons the transaction, so we must rethrow
      // so the main transaction can be rolled back properly.
      throw error;
    }
  }

  /**
   * Get checklist version history (snapshots)
   */
  async getChecklistHistory(checklistId: number): Promise<any[]> {
    try {
      const result = await pool.query(
        `
          SELECT 
            cv.id, 
            cv.checklist_id, 
            cv.version_number, 
            cv.created_at, 
            cv.rejection_comments,
            u.full_name as rejected_by_name,
            u.username as rejected_by_username
          FROM qms_checklist_versions cv
          LEFT JOIN users u ON u.id = cv.rejected_by
          WHERE cv.checklist_id = $1
          ORDER BY cv.version_number DESC
        `,
        [checklistId]
    );
      return result.rows;
    } catch (error) {
      console.error('Error getting checklist history:', error);
      throw error;
    }
  }

  /**
   * Get a specific snapshot version of a checklist
   */
  async getChecklistVersion(versionId: number): Promise<any> {
    try {
      const result = await pool.query(
        'SELECT * FROM qms_checklist_versions WHERE id = $1',
        [versionId]
      );
      
      if (result.rows.length === 0) return null;
      
      const version = result.rows[0];
      // Note: checklist_snapshot is already a JSONB object from Postgres
      return version;
    } catch (error) {
      console.error('Error getting checklist version:', error);
      throw error;
    }
  }
}

export const qmsService = new QmsService();
export default qmsService;
