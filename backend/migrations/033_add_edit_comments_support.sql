-- ============================================================================
-- ADD SUPPORT FOR EDITING ENGINEER AND REVIEWER COMMENTS
-- ============================================================================
-- This migration adds indexes and comments to clarify comment field usage
-- No schema changes needed - fields already exist in c_report_data and check_item_approvals
-- ============================================================================

-- Add index for faster comment lookups
CREATE INDEX IF NOT EXISTS idx_c_report_data_engineer_comments 
  ON c_report_data(check_item_id) WHERE engineer_comments IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_check_item_approvals_comments 
  ON check_item_approvals(check_item_id) WHERE comments IS NOT NULL;

-- Add comments to clarify field usage
COMMENT ON COLUMN c_report_data.engineer_comments IS 'Comments from engineer/submitter. Editable by engineer who submitted the checklist.';
COMMENT ON COLUMN c_report_data.lead_comments IS 'Historical lead comments field (deprecated in favor of check_item_approvals.comments)';
COMMENT ON COLUMN check_item_approvals.comments IS 'Comments from approver/reviewer. Editable by assigned approver, lead, or admin.';

