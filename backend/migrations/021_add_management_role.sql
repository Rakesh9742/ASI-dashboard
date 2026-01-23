-- Add 'management' role to user_role enum
-- This role has access to all projects and can see management view only

-- First, check if management role already exists
DO $$ 
BEGIN
    -- Add 'management' to the enum if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumlabel = 'management' 
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'user_role')
    ) THEN
        ALTER TYPE user_role ADD VALUE 'management';
    END IF;
END $$;

-- Add comment explaining the management role
COMMENT ON TYPE user_role IS 'User roles: admin (full access), project_manager (project management), lead (technical lead), engineer (standard user), customer (read-only), management (project status overview only)';

