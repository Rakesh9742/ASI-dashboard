-- Export to Linux status on projects table only (single source of truth)
ALTER TABLE projects
ADD COLUMN IF NOT EXISTS exported_to_linux BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN projects.exported_to_linux IS 'True when project has been exported to Linux (Export to Linux / setup completed). Source of truth for UI.';
