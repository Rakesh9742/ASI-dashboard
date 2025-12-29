-- ============================================================================
-- DROP EDA OUTPUT FILES TABLE
-- ============================================================================
-- This migration drops the eda_output_files table and all related objects
-- This is done because the Physical Design (PD) table structure is being redesigned

-- Drop the trigger first
DROP TRIGGER IF EXISTS update_eda_output_files_updated_at ON eda_output_files;

-- Drop all indexes
DROP INDEX IF EXISTS idx_eda_output_files_project_name;
DROP INDEX IF EXISTS idx_eda_output_files_domain_name;
DROP INDEX IF EXISTS idx_eda_output_files_domain_id;
DROP INDEX IF EXISTS idx_eda_output_files_project_id;
DROP INDEX IF EXISTS idx_eda_output_files_file_type;
DROP INDEX IF EXISTS idx_eda_output_files_processing_status;
DROP INDEX IF EXISTS idx_eda_output_files_created_at;

-- Drop the table (CASCADE will drop any dependent objects)
DROP TABLE IF EXISTS eda_output_files CASCADE;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- The eda_output_files table and all related objects have been dropped.
-- You can now create a new table structure for Physical Design data.

