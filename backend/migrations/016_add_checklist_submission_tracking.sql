-- ============================================================================
-- ADD CHECKLIST SUBMISSION TRACKING
-- ============================================================================
-- This migration adds columns to track who submitted a checklist and when
-- ============================================================================

-- Add submission tracking columns to checklists table
ALTER TABLE checklists
ADD COLUMN IF NOT EXISTS submitted_by INT REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_by ON checklists(submitted_by);
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_at ON checklists(submitted_at);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

