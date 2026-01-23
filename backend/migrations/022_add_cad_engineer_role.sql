-- Add 'cad_engineer' role to user_role enum
-- This role is intended for CAD engineers with a dedicated CAD view

DO $$ 
BEGIN
    -- Add 'cad_engineer' to the enum if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumlabel = 'cad_engineer' 
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'user_role')
    ) THEN
        ALTER TYPE user_role ADD VALUE 'cad_engineer';
    END IF;
END $$;

-- Update comment on user_role to document cad_engineer
COMMENT ON TYPE user_role IS 'User roles: admin (full access), project_manager (project management), lead (technical lead), engineer (standard user), customer (read-only), management (project status overview only), cad_engineer (CAD-specific view for tasks/issues and export tools)';


