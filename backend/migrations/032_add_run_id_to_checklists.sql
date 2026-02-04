-- ============================================================================
-- ADD run_id TO checklists TABLE FOR PROPER HIERARCHY
-- ============================================================================
-- This migration adds run_id column to checklists table to properly link
-- checklists to specific runs (block + experiment + rtl_tag)
-- Allows proper filtering: Block → RTL tag → Experiment → Checklists
-- ============================================================================

-- Add run_id column (nullable for backward compatibility with existing checklists)
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS run_id INTEGER REFERENCES runs(id) ON DELETE CASCADE;

-- Create index for efficient lookups
CREATE INDEX IF NOT EXISTS idx_checklists_run_id ON checklists(run_id);

-- Add comment to explain the column
COMMENT ON COLUMN checklists.run_id IS 'Links checklist to specific run (block + experiment + rtl_tag). Nullable for backward compatibility with block-only checklists.';

-- For existing checklists with names like "Synthesis QMS - exp2", try to link them to runs
-- This is a best-effort migration for existing data
DO $$
DECLARE
    checklist_record RECORD;
    exp_name TEXT;
    matching_run_id INTEGER;
BEGIN
    -- Loop through checklists that don't have run_id set
    FOR checklist_record IN 
        SELECT id, block_id, name 
        FROM checklists 
        WHERE run_id IS NULL
    LOOP
        -- Try to extract experiment name from checklist name (e.g., "Synthesis QMS - exp2" -> "exp2")
        IF checklist_record.name ~ '- (exp\d+|[a-zA-Z0-9_]+)$' THEN
            -- Extract the last segment after " - "
            exp_name := TRIM(SUBSTRING(checklist_record.name FROM '- ([^-]+)$'));
            
            -- Try to find matching run
            SELECT id INTO matching_run_id
            FROM runs
            WHERE block_id = checklist_record.block_id
              AND experiment = exp_name
            LIMIT 1;
            
            -- If found, update checklist
            IF matching_run_id IS NOT NULL THEN
                UPDATE checklists
                SET run_id = matching_run_id
                WHERE id = checklist_record.id;
                
                RAISE NOTICE 'Linked checklist % (%) to run %', checklist_record.id, checklist_record.name, matching_run_id;
            END IF;
        END IF;
    END LOOP;
END $$;

