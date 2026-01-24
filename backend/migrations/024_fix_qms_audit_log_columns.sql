-- ============================================================================
-- FIX QMS AUDIT LOG COLUMNS
-- ============================================================================
-- The qms_audit_log table is missing block_id, action_type, and action_details columns
-- that are used by the QMS service code

-- Add block_id column (nullable, references blocks table)
ALTER TABLE qms_audit_log 
ADD COLUMN IF NOT EXISTS block_id INTEGER REFERENCES blocks(id) ON DELETE SET NULL;

-- Add action_type column (if action_details is being used, we might need both)
-- Check if action column exists - if so, we'll keep it and add action_type as alias
-- If action_type doesn't exist, add it
ALTER TABLE qms_audit_log 
ADD COLUMN IF NOT EXISTS action_type VARCHAR(50);

-- Add action_details column (JSONB to store detailed action information)
ALTER TABLE qms_audit_log 
ADD COLUMN IF NOT EXISTS action_details JSONB;

-- Make action column nullable (since code uses action_type instead)
-- The action column was originally NOT NULL, but the code now uses action_type
ALTER TABLE qms_audit_log 
ALTER COLUMN action DROP NOT NULL;

-- Make entity_type column nullable (code stores it in action_details JSON but should also insert it)
-- We'll update the code to insert entity_type, but make it nullable for now to avoid errors
ALTER TABLE qms_audit_log 
ALTER COLUMN entity_type DROP NOT NULL;

-- If action column exists but action_type doesn't, copy data
-- (action_type can be an alias or we can populate it from action)
DO $$
BEGIN
    -- If action_type is NULL but action has a value, copy it
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'qms_audit_log' AND column_name = 'action') THEN
        UPDATE qms_audit_log 
        SET action_type = action 
        WHERE action_type IS NULL AND action IS NOT NULL;
    END IF;
END $$;

-- Create index for block_id for better query performance
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_block_id ON qms_audit_log(block_id);

-- Create index for action_type
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_action_type ON qms_audit_log(action_type);

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

