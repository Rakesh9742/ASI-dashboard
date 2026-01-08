-- ============================================================================
-- FIX QMS AUDIT LOG FOREIGN KEY CONSTRAINTS
-- ============================================================================
-- This migration modifies the foreign key constraints on qms_audit_log
-- to allow NULL values and handle deletions properly
-- ============================================================================

-- First, check if the table exists and get constraint names
DO $$
DECLARE
    constraint_name_checklist TEXT;
    constraint_name_checkitem TEXT;
BEGIN
    -- Drop existing foreign key constraint for checklist_id if it exists
    SELECT conname INTO constraint_name_checklist
    FROM pg_constraint
    WHERE conrelid = 'qms_audit_log'::regclass
    AND confrelid = 'checklists'::regclass
    AND conname LIKE '%checklist_id%';
    
    IF constraint_name_checklist IS NOT NULL THEN
        EXECUTE format('ALTER TABLE qms_audit_log DROP CONSTRAINT IF EXISTS %I', constraint_name_checklist);
    END IF;
    
    -- Drop existing foreign key constraint for check_item_id if it exists
    SELECT conname INTO constraint_name_checkitem
    FROM pg_constraint
    WHERE conrelid = 'qms_audit_log'::regclass
    AND confrelid = 'check_items'::regclass
    AND conname LIKE '%check_item_id%';
    
    IF constraint_name_checkitem IS NOT NULL THEN
        EXECUTE format('ALTER TABLE qms_audit_log DROP CONSTRAINT IF EXISTS %I', constraint_name_checkitem);
    END IF;
END $$;

-- Recreate foreign key constraints with ON DELETE SET NULL to allow NULL values
-- This allows audit log entries to remain even after checklist/check_item is deleted

-- Add foreign key for checklist_id with ON DELETE SET NULL
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'qms_audit_log') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'qms_audit_log' AND column_name = 'checklist_id') THEN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint 
                WHERE conrelid = 'qms_audit_log'::regclass 
                AND confrelid = 'checklists'::regclass
                AND contype = 'f'
            ) THEN
                ALTER TABLE qms_audit_log
                ADD CONSTRAINT qms_audit_log_checklist_id_fkey
                FOREIGN KEY (checklist_id) REFERENCES checklists(id) ON DELETE SET NULL;
            END IF;
        END IF;
        
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'qms_audit_log' AND column_name = 'check_item_id') THEN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint 
                WHERE conrelid = 'qms_audit_log'::regclass 
                AND confrelid = 'check_items'::regclass
                AND contype = 'f'
            ) THEN
                ALTER TABLE qms_audit_log
                ADD CONSTRAINT qms_audit_log_check_item_id_fkey
                FOREIGN KEY (check_item_id) REFERENCES check_items(id) ON DELETE SET NULL;
            END IF;
        END IF;
    END IF;
END $$;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

