-- Create table to track Linux export status for Zoho projects
-- This table tracks export status independently of mapping, since export happens first
-- and mapping may not occur if there's no EDA output
CREATE TABLE IF NOT EXISTS zoho_project_exports (
    id SERIAL PRIMARY KEY,
    zoho_project_id VARCHAR(255) NOT NULL,
    portal_id VARCHAR(255),
    zoho_project_name VARCHAR(255),
    exported_to_linux BOOLEAN DEFAULT FALSE,
    exported_at TIMESTAMP,
    exported_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add unique constraint using partial indexes to handle NULL portal_id correctly
-- This ensures one export record per zoho_project_id when portal_id is NULL
-- and one export record per (zoho_project_id, portal_id) when portal_id is set
-- Note: PostgreSQL UNIQUE constraint allows multiple NULLs, so we use partial unique indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_zoho_project_exports_unique_with_portal 
    ON zoho_project_exports(zoho_project_id, portal_id) 
    WHERE portal_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_zoho_project_exports_unique_without_portal 
    ON zoho_project_exports(zoho_project_id) 
    WHERE portal_id IS NULL;

-- Add indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_zoho_project_exports_zoho_id ON zoho_project_exports(zoho_project_id);
CREATE INDEX IF NOT EXISTS idx_zoho_project_exports_portal_id ON zoho_project_exports(portal_id);
CREATE INDEX IF NOT EXISTS idx_zoho_project_exports_exported ON zoho_project_exports(exported_to_linux) WHERE exported_to_linux = TRUE;
CREATE INDEX IF NOT EXISTS idx_zoho_project_exports_exported_by ON zoho_project_exports(exported_by);

-- Keep updated_at fresh
DROP TRIGGER IF EXISTS update_zoho_project_exports_updated_at ON zoho_project_exports;
CREATE TRIGGER update_zoho_project_exports_updated_at
    BEFORE UPDATE ON zoho_project_exports
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Add comment to document this table
COMMENT ON TABLE zoho_project_exports IS 'Tracks Linux export status for Zoho projects independently of mapping. Export happens before mapping, and mapping may not occur if there is no EDA output.';
COMMENT ON COLUMN zoho_project_exports.zoho_project_id IS 'Zoho project ID';
COMMENT ON COLUMN zoho_project_exports.portal_id IS 'Zoho portal ID (optional, but recommended for uniqueness)';
COMMENT ON COLUMN zoho_project_exports.exported_to_linux IS 'Flag indicating whether the Zoho project has been successfully exported to Linux';
COMMENT ON COLUMN zoho_project_exports.exported_at IS 'Timestamp when the project was exported to Linux';
COMMENT ON COLUMN zoho_project_exports.exported_by IS 'User ID who performed the export';

