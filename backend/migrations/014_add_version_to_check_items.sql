-- ============================================================================
-- ADD VERSION COLUMN TO CHECK ITEMS
-- ============================================================================
-- This migration adds a version column to check_items table with default value 'v1'
-- ============================================================================

-- Add version column to check_items table
ALTER TABLE check_items
ADD COLUMN IF NOT EXISTS version VARCHAR(50) DEFAULT 'v1';

-- Update existing rows to have version 'v1' if null
UPDATE check_items SET version = 'v1' WHERE version IS NULL;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_check_items_version ON check_items(version);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

