-- ============================================================================
-- ADD COMMENT COLUMNS TO check_items TABLE
-- ============================================================================
-- This migration adds three comment columns to check_items table:
-- 1. comments - Filled ONLY from external JSON uploads, not editable in UI
-- 2. engineer_comments - Editable by engineer who submitted checklist (or admin/lead)
-- 3. reviewer_comments - Editable by approver/admin/lead when checklist is in submitted_for_approval status
-- ============================================================================

-- Add comments column (from external JSON only)
ALTER TABLE check_items ADD COLUMN IF NOT EXISTS comments TEXT;
COMMENT ON COLUMN check_items.comments IS 'Comments from external JSON report uploads. Not editable via UI - only updated by external API.';

-- Add engineer_comments column (editable by engineer)
ALTER TABLE check_items ADD COLUMN IF NOT EXISTS engineer_comments TEXT;
COMMENT ON COLUMN check_items.engineer_comments IS 'Comments from engineer/submitter. Editable by engineer who submitted the checklist, or admin/lead.';

-- Add reviewer_comments column (editable by approver when checklist is submitted_for_approval)
ALTER TABLE check_items ADD COLUMN IF NOT EXISTS reviewer_comments TEXT;
COMMENT ON COLUMN check_items.reviewer_comments IS 'Comments from approver/reviewer. Editable by assigned approver, admin, or lead when checklist is in submitted_for_approval status.';

-- Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_check_items_engineer_comments 
  ON check_items(checklist_id) WHERE engineer_comments IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_check_items_reviewer_comments 
  ON check_items(checklist_id) WHERE reviewer_comments IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_check_items_comments 
  ON check_items(checklist_id) WHERE comments IS NOT NULL;

