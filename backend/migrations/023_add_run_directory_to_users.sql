-- Add run_directory field to users table
-- This field stores the directory path where engineers run their EDA tools
-- Provided by external users via API (e.g., "pd/user/p1/")

ALTER TABLE users 
ADD COLUMN IF NOT EXISTS run_directory VARCHAR(500);

-- Add index for run_directory if needed for queries
CREATE INDEX IF NOT EXISTS idx_users_run_directory ON users(run_directory) WHERE run_directory IS NOT NULL;

-- Add comment to document this field
COMMENT ON COLUMN users.run_directory IS 'Directory path where engineer runs EDA tools (provided by external users via API, e.g., "pd/user/p1/")';

