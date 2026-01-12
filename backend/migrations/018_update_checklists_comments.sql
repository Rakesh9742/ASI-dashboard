-- ============================================================================
-- UPDATE CHECKLISTS TABLE - REMOVE STAGE, ADD COMMENTS COLUMNS
-- ============================================================================
-- This migration:
-- 1. Removes the 'stage' column from checklists table
-- 2. Adds 'engineer_comments' column to store submit-for-approval comments
-- 3. Adds 'reviewer_comments' column to store approver/reject comments
-- ============================================================================

-- Add engineer_comments column (for submit-for-approval comments)
ALTER TABLE checklists 
ADD COLUMN IF NOT EXISTS engineer_comments TEXT;

-- Add reviewer_comments column (for approver/reject comments)
ALTER TABLE checklists 
ADD COLUMN IF NOT EXISTS reviewer_comments TEXT;

-- Remove stage column (if it exists)
ALTER TABLE checklists 
DROP COLUMN IF EXISTS stage;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

