-- Add project setup completed flag to projects table
-- Project setup (Setup experiment / Export to Linux) is now tracked on the project itself
ALTER TABLE projects
ADD COLUMN IF NOT EXISTS setup_completed BOOLEAN DEFAULT FALSE;

-- Optional: timestamp when setup was completed (for auditing)
ALTER TABLE projects
ADD COLUMN IF NOT EXISTS setup_completed_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_projects_setup_completed 
ON projects(setup_completed) WHERE setup_completed = TRUE;

COMMENT ON COLUMN projects.setup_completed IS 'True when project setup (Setup experiment or Export to Linux) has been completed for this project';
COMMENT ON COLUMN projects.setup_completed_at IS 'Timestamp when project setup was completed';
