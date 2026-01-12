-- ============================================================================
-- ENSURE ALL QMS COLUMNS EXIST
-- ============================================================================
-- This migration ensures all required columns exist for QMS Excel upload
-- It's idempotent - safe to run multiple times
-- ============================================================================

-- Add columns to check_items table (if they don't exist)
ALTER TABLE check_items
ADD COLUMN IF NOT EXISTS category VARCHAR(100),
ADD COLUMN IF NOT EXISTS sub_category VARCHAR(100),
ADD COLUMN IF NOT EXISTS severity VARCHAR(50),
ADD COLUMN IF NOT EXISTS bronze VARCHAR(50),
ADD COLUMN IF NOT EXISTS silver VARCHAR(50),
ADD COLUMN IF NOT EXISTS gold VARCHAR(50),
ADD COLUMN IF NOT EXISTS info TEXT,
ADD COLUMN IF NOT EXISTS evidence TEXT,
ADD COLUMN IF NOT EXISTS auto_approve BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS version VARCHAR(50) DEFAULT 'v1',
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

-- Add columns to c_report_data table (if they don't exist)
ALTER TABLE c_report_data
ADD COLUMN IF NOT EXISTS result_value TEXT,
ADD COLUMN IF NOT EXISTS signoff_status VARCHAR(50),
ADD COLUMN IF NOT EXISTS signoff_by INT REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS signoff_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS description TEXT,
ADD COLUMN IF NOT EXISTS fix_details TEXT,
ADD COLUMN IF NOT EXISTS engineer_comments TEXT,
ADD COLUMN IF NOT EXISTS lead_comments TEXT;

-- Create indexes for performance (if they don't exist)
CREATE INDEX IF NOT EXISTS idx_check_items_category ON check_items(category);
CREATE INDEX IF NOT EXISTS idx_check_items_sub_category ON check_items(sub_category);
CREATE INDEX IF NOT EXISTS idx_check_items_severity ON check_items(severity);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_status ON c_report_data(signoff_status);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_by ON c_report_data(signoff_by);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

