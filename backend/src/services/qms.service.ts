import { pool } from '../config/database';
import fs from 'fs';
import path from 'path';
// @ts-ignore - csv-parser doesn't have types
import csv from 'csv-parser';
// @ts-ignore - xlsx doesn't have types
const XLSX = require('xlsx');
// @ts-ignore - xlsx doesn't have types
import XLSX from 'xlsx';

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
  stage: string | null;
  status: string;
  check_items?: CheckItemData[];
  created_at: Date;
  updated_at: Date;
}

interface CheckItemData {
  id: number;
  checklist_id: number;
  checklist_status?: string;
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
  auto_approve: boolean;
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
        LEFT JOIN project_domains pd ON pd.project_id = p.id
        LEFT JOIN domains d ON d.id = pd.domain_id AND d.is_active = true
      `;

      const queryParams: any[] = [];
      
      // Filter projects based on user role
      if (userRole === 'engineer' || userRole === 'customer') {
        projectQuery += ' WHERE p.created_by = $1 AND p.created_by IS NOT NULL';
        queryParams.push(userId);
      }
      
      projectQuery += ' GROUP BY p.id ORDER BY p.name';

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
        // Check if milestones table exists
        const tableCheck = await pool.query(`
          SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = 'milestones'
          );
        `);
        
        if (tableCheck.rows[0]?.exists) {
          let milestoneQuery = 'SELECT id, name, project_id FROM milestones';
          if (userRole === 'engineer' || userRole === 'customer') {
            milestoneQuery += ' WHERE project_id IN (SELECT id FROM projects WHERE created_by = $1)';
          }
          milestoneQuery += ' ORDER BY name';
          
          const milestonesResult = await pool.query(
            milestoneQuery,
            userRole === 'engineer' || userRole === 'customer' ? [userId] : []
          );
          milestones = milestonesResult.rows;
        } else {
          console.log('⚠️  Milestones table does not exist, returning empty array');
        }
      } catch (error: any) {
        // If table doesn't exist or query fails, return empty array
        console.warn('⚠️  Could not fetch milestones (table may not exist):', error.message);
        milestones = [];
      }

      // Get blocks
      let blockQuery = `
        SELECT DISTINCT b.id, b.block_name, b.project_id
        FROM blocks b
      `;
      if (userRole === 'engineer' || userRole === 'customer') {
        blockQuery += ' WHERE b.project_id IN (SELECT id FROM projects WHERE created_by = $1)';
      }
      blockQuery += ' ORDER BY b.block_name';
      
      const blocksResult = await pool.query(
        blockQuery,
        userRole === 'engineer' || userRole === 'customer' ? [userId] : []
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
   */
  async getChecklistsForBlock(blockId: number): Promise<ChecklistData[]> {
    try {
      const hasMilestonesTable = await this.milestonesTableExists();
      const milestoneJoin = hasMilestonesTable 
        ? 'LEFT JOIN milestones m ON m.id = cl.milestone_id'
        : '';
      const milestoneSelect = hasMilestonesTable 
        ? 'm.name as milestone_name,'
        : 'NULL as milestone_name,';
      
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
            -- Current approver role
            (
              SELECT u.role
              FROM check_items ci
              JOIN check_item_approvals cia ON cia.check_item_id = ci.id
              JOIN users u ON u.id = COALESCE(cia.assigned_approver_id, cia.default_approver_id)
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
          WHERE cl.block_id = $1
          ORDER BY cl.created_at ASC
        `,
        [blockId]
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
            u_submitted.id as submitted_by_id,
            u_submitted.username as submitted_by_username,
            u_submitted.full_name as submitted_by_name
          FROM checklists cl
          ${milestoneJoin}
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
        auto_approve: row.auto_approve || false,
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
        auto_approve: row.auto_approve || false,
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
  async executeFillAction(checkItemId: number, reportPath: string, userId: number): Promise<any> {
    try {
      // Validate file exists
      if (!fs.existsSync(reportPath)) {
        throw new Error(`Report file not found: ${reportPath}`);
      }

      // Parse CSV file
      const csvData = await this.parseCSVFile(reportPath);

      // Update or create report data
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Check if report data exists
        const existingResult = await client.query(
          'SELECT id FROM c_report_data WHERE check_item_id = $1',
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
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $3
            `,
            [reportPath, JSON.stringify(csvData), checkItemId]
          );
        } else {
          // Create new
          await client.query(
            `
              INSERT INTO c_report_data 
                (check_item_id, report_path, csv_data, status)
              VALUES ($1, $2, $3, 'in_review')
            `,
            [checkItemId, reportPath, JSON.stringify(csvData)]
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
          'fill_action',
          { report_path: reportPath, rows_count: csvData.length }
        );

        await client.query('COMMIT');
        return csvData;
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
          await client.query(
            `
              UPDATE check_item_approvals 
              SET status = 'pending', submitted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
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

        // Verify user is the assigned approver
        if (approverId !== userId) {
          throw new Error('You are not the assigned approver for this check item.');
        }

        // Update approval status
        const newStatus = approved ? 'approved' : 'not_approved';
        await client.query(
          `
            UPDATE check_item_approvals 
            SET 
              status = $1,
              comments = $2,
              approved_at = CASE WHEN $1 = 'approved' THEN CURRENT_TIMESTAMP ELSE NULL END,
              updated_at = CURRENT_TIMESTAMP
            WHERE check_item_id = $3
          `,
          [newStatus, comments, checkItemId]
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

        // Check if all items in checklist are now approved/rejected
        const allItemsResult = await client.query(
          `
            SELECT cia.status
            FROM check_items ci
            JOIN check_item_approvals cia ON cia.check_item_id = ci.id
            WHERE ci.checklist_id = $1
          `,
          [checklistId]
        );

        if (allItemsResult.rows.length > 0) {
          const allApproved = allItemsResult.rows.every((row: any) => row.status === 'approved');
          const anyRejected = allItemsResult.rows.some((row: any) => row.status === 'not_approved');

          // Get checklist status
          const checklistStatusResult = await client.query(
            'SELECT status FROM checklists WHERE id = $1',
            [checklistId]
          );
          const currentStatus = checklistStatusResult.rows[0]?.status;

          // Only update checklist status if it's in submitted_for_approval state
          if (currentStatus === 'submitted_for_approval') {
            if (allApproved) {
              // All items approved - checklist is submitted
              await client.query(
                'UPDATE checklists SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
                ['submitted', checklistId]
              );
              await this.logAuditAction(
                client,
                null,
                checklistId,
                blockId,
                userId,
                'checklist_approved',
                {}
              );
            } else if (anyRejected) {
              // Any item rejected - checklist goes back to draft
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
                'checklist_rejected',
                {}
              );
            }
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
        await client.query(
          `
            UPDATE checklists 
            SET 
              status = 'submitted_for_approval',
              submitted_by = $1,
              submitted_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
            WHERE id = $2
          `,
          [userId, checklistId]
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
            await client.query(
              `
                UPDATE check_item_approvals 
                SET 
                  default_approver_id = $1,
                  status = 'pending',
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
          // and save engineer comments if provided
          await client.query(
            `
              UPDATE c_report_data 
              SET 
                status = 'submitted',
                engineer_comments = COALESCE($2, engineer_comments),
                updated_at = CURRENT_TIMESTAMP
              WHERE check_item_id = $1
            `,
            [checkItemId, engineerComments ?? null]
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
      let query = `
        SELECT u.id, u.username, u.full_name, u.role, u.email
        FROM users u
        WHERE u.role IN ('lead', 'engineer', 'admin')
          AND u.is_active = true
      `;
      const params: any[] = [];

      if (excludeUserId) {
        query += ` AND u.id != $1`;
        params.push(excludeUserId);
      }

      query += ` ORDER BY u.role, u.full_name ASC`;

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
        const statusValue = approved ? 'approved' : 'not_approved';
        for (const checkItemId of checkItemIds) {
          if (isAdmin) {
            // Admin can approve all items regardless of assignment
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
              [statusValue, comments, checkItemId, approved]
            );
          } else {
            // Regular approver can only approve items they're assigned to
            await client.query(
              `
                UPDATE check_item_approvals 
                SET 
                  status = $1,
                  comments = $2,
                  approved_at = CASE WHEN $5 THEN CURRENT_TIMESTAMP ELSE NULL END,
                  updated_at = CURRENT_TIMESTAMP
                WHERE check_item_id = $3
                  AND (assigned_approver_id = $4 OR default_approver_id = $4)
              `,
              [statusValue, comments, checkItemId, userId, approved]
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
        // If approved, set to 'submitted'; if rejected, set back to 'draft'
        const newChecklistStatus = approved ? 'submitted' : 'draft';
        await client.query(
          `
            UPDATE checklists 
            SET status = $1, updated_at = CURRENT_TIMESTAMP
            WHERE id = $2
          `,
          [newChecklistStatus, checklistId]
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
      const allSubmitted = checklists.every((cl: any) => cl.checklist_status === 'submitted');

      return {
        block_id: blockId,
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
    milestoneId: number | null,
    stage: string | null
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
        console.log('Excel columns found:', Object.keys(data[0]));
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
        const hasAutoApprove = existingColumns.has('auto_approve');
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
              'UPDATE checklists SET milestone_id = $1, stage = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3',
              [milestoneId, stage, checklistId]
            );
          } else {
            // Create new checklist
            const insertResult = await client.query(
              'INSERT INTO checklists (block_id, milestone_id, name, stage, status) VALUES ($1, $2, $3, $4, $5) RETURNING id',
              [blockId, milestoneId, checklistName, stage, 'draft']
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
            // Based on user's Excel: Check ID, Category, Sub-Category, Check Description, Severity, Bronze, Silver, Gold, Info, Evidence, Report path, Result/Value, Status, Comments, Reviewer comments, Signoff, Auto
            // Try exact matches first, then variations
            const checkItemName = getValue(row, 'Check ID', 'CheckID', 'Check_Id', 'check_id', 'Check Id', 'CHECK ID') || `Check Item ${i + 1}`;
            const category = getValue(row, 'Category', 'category', 'CATEGORY');
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
            const autoValue = getValue(row, 'Auto', 'auto', 'AUTO', 'Auto Approve', 'AutoApprove');
            const autoApprove = autoValue === true || 
                               autoValue === 'Yes' || 
                               autoValue === 'Y' || 
                               autoValue === 'TRUE' ||
                               autoValue === 'true' ||
                               autoValue === 'yes' ||
                               autoValue === 'y' ||
                               false;

            // Debug logging for first row
            if (i === 0) {
              console.log('========================================');
              console.log('✅ EXTRACTED VALUES FOR FIRST ROW');
              console.log('========================================');
              console.log('  Check ID:', checkItemName, checkItemName === `Check Item ${i + 1}` ? '⚠️ (USING DEFAULT)' : '✓');
              console.log('  Category:', category || '❌ NULL');
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
              console.log('  Auto Approve:', autoApprove, '| Auto Value:', autoValue);
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
              if (hasAutoApprove) {
                updateQuery += `auto_approve = $${paramIndex}, `;
                updateParams.push(autoApprove);
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
              if (hasAutoApprove) {
                insertColumns += ', auto_approve';
                insertValues += `, $${paramIndex}`;
                insertParams.push(autoApprove);
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

    await client.query(
      `
        INSERT INTO qms_audit_log 
          (check_item_id, checklist_id, block_id, user_id, action_type, action_details)
        VALUES ($1, $2, $3, $4, $5, $6)
      `,
      [checkItemId, checklistId, blockId, userId, actionType, JSON.stringify(actionDetails)]
    );
  }
}

export default new QmsService();

