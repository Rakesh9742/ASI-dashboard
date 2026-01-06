-- ============================================================================
-- ADD DETAILED COLUMNS TO CHECK ITEMS AND C REPORT DATA
-- ============================================================================
-- This migration adds all required columns for detailed check item tracking
-- ============================================================================

-- Add columns to check_items table
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
    ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

-- Add columns to c_report_data table
ALTER TABLE c_report_data
ADD COLUMN IF NOT EXISTS result_value TEXT,
    ADD COLUMN IF NOT EXISTS signoff_status VARCHAR(50),
    ADD COLUMN IF NOT EXISTS signoff_by INT REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS signoff_at TIMESTAMP;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_check_items_category ON check_items(category);
CREATE INDEX IF NOT EXISTS idx_check_items_sub_category ON check_items(sub_category);
CREATE INDEX IF NOT EXISTS idx_check_items_severity ON check_items(severity);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_status ON c_report_data(signoff_status);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_by ON c_report_data(signoff_by);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================