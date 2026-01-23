-- Add role column to user_projects table
-- This allows users to have different roles per project
-- If role is NULL, system will use users.role as fallback

ALTER TABLE user_projects 
ADD COLUMN IF NOT EXISTS role VARCHAR(50);

-- Add comment explaining the column
COMMENT ON COLUMN user_projects.role IS 
  'Project-specific role. If NULL, uses users.role as fallback. Allows same user to have different roles in different projects.';

-- Create index for faster role-based queries
CREATE INDEX IF NOT EXISTS idx_user_projects_role ON user_projects(role);

-- Update existing records: ensure role is NULL (will use users.role as fallback)
-- This maintains backward compatibility
-- No UPDATE needed as new column defaults to NULL


