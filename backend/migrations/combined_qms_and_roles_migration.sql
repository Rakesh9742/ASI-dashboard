-- ============================================================================
-- COMBINED MIGRATION: QMS SCHEMA AND ROLE UPDATES
-- ============================================================================
-- This script combines multiple migrations:
-- - 012_create_qms_schema.sql
-- - 015_ensure_qms_columns_exist.sql
-- - 016_add_checklist_submission_tracking.sql
-- - 017_fix_qms_audit_log_foreign_keys.sql
-- - 018_update_checklists_comments.sql
-- - 019_create_qms_history.sql
-- - 019_create_user_projects.sql
-- - 020_add_role_to_user_projects.sql
-- - 021_add_management_role.sql
-- - 022_add_cad_engineer_role.sql
-- ============================================================================

-- ============================================================================
-- PART 1: CREATE QMS SCHEMA (from 012_create_qms_schema.sql)
-- ============================================================================

-- Ensure update_updated_at_column function exists (safety check)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 0: ENSURE PREREQUISITE TABLES EXIST (projects, blocks)
-- ============================================================================
-- The blocks table is required for checklists. If it doesn't exist, create it.
-- This is from migration 010_create_physical_design_schema.sql

DO $$
BEGIN
    -- First, ensure projects table exists (required for blocks)
    IF NOT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'projects'
    ) THEN
        RAISE EXCEPTION 'Projects table does not exist. Please run migration 006_create_projects.sql first.';
    END IF;
    
    -- Check if blocks table exists
    IF NOT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'blocks'
    ) THEN
        -- Create blocks table if it doesn't exist
        CREATE TABLE blocks (
            id SERIAL PRIMARY KEY,
            project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            block_name VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE (project_id, block_name)
        );
        
        -- Create indexes for blocks
        CREATE INDEX IF NOT EXISTS idx_blocks_project_id ON blocks(project_id);
        CREATE INDEX IF NOT EXISTS idx_blocks_name ON blocks(block_name);
        CREATE INDEX IF NOT EXISTS idx_blocks_project_name ON blocks(project_id, block_name);
        
        RAISE NOTICE 'Created blocks table (prerequisite for QMS schema)';
    ELSE
        RAISE NOTICE 'Blocks table already exists';
    END IF;
END $$;

-- Create checklists table
CREATE TABLE IF NOT EXISTS checklists (
    id SERIAL PRIMARY KEY,
    block_id INTEGER NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
    milestone_id INTEGER, -- Optional milestone reference (no FK constraint since milestones table may not exist)
    name VARCHAR(255) NOT NULL,
    stage VARCHAR(100),
    status VARCHAR(50) DEFAULT 'draft',
    approver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    approver_role VARCHAR(50),
    submitted_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    submitted_at TIMESTAMP,
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'
);

-- Create check_items table
CREATE TABLE IF NOT EXISTS check_items (
    id SERIAL PRIMARY KEY,
    checklist_id INTEGER NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    check_item_type VARCHAR(100),
    display_order INTEGER DEFAULT 0,
    category VARCHAR(100),
    sub_category VARCHAR(100),
    severity VARCHAR(50),
    bronze VARCHAR(50),
    silver VARCHAR(50),
    gold VARCHAR(50),
    info TEXT,
    evidence TEXT,
    auto_approve BOOLEAN DEFAULT false,
    version VARCHAR(50) DEFAULT 'v1',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create c_report_data table (Check Report Data)
CREATE TABLE IF NOT EXISTS c_report_data (
    id SERIAL PRIMARY KEY,
    check_item_id INTEGER NOT NULL REFERENCES check_items(id) ON DELETE CASCADE,
    report_path TEXT,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    fix_details TEXT,
    engineer_comments TEXT,
    lead_comments TEXT,
    result_value TEXT,
    signoff_status VARCHAR(50),
    signoff_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    signoff_at TIMESTAMP,
    csv_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create check_item_approvals table
CREATE TABLE IF NOT EXISTS check_item_approvals (
    id SERIAL PRIMARY KEY,
    check_item_id INTEGER NOT NULL REFERENCES check_items(id) ON DELETE CASCADE,
    default_approver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    assigned_approver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    assigned_by_lead_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'pending',
    comments TEXT,
    submitted_at TIMESTAMP,
    approved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create qms_audit_log table
CREATE TABLE IF NOT EXISTS qms_audit_log (
    id SERIAL PRIMARY KEY,
    checklist_id INTEGER REFERENCES checklists(id) ON DELETE SET NULL,
    check_item_id INTEGER REFERENCES check_items(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    old_value JSONB,
    new_value JSONB,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance (only if tables exist)
DO $$
BEGIN
    -- Indexes for checklists table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'checklists') THEN
        CREATE INDEX IF NOT EXISTS idx_checklists_block_id ON checklists(block_id);
        CREATE INDEX IF NOT EXISTS idx_checklists_milestone_id ON checklists(milestone_id);
        CREATE INDEX IF NOT EXISTS idx_checklists_status ON checklists(status);
        CREATE INDEX IF NOT EXISTS idx_checklists_approver_id ON checklists(approver_id);
        CREATE INDEX IF NOT EXISTS idx_checklists_submitted_by ON checklists(submitted_by);
        CREATE INDEX IF NOT EXISTS idx_checklists_submitted_at ON checklists(submitted_at);
    END IF;
    
    -- Indexes for check_items table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'check_items') THEN
        CREATE INDEX IF NOT EXISTS idx_check_items_checklist_id ON check_items(checklist_id);
        CREATE INDEX IF NOT EXISTS idx_check_items_category ON check_items(category);
        CREATE INDEX IF NOT EXISTS idx_check_items_sub_category ON check_items(sub_category);
        CREATE INDEX IF NOT EXISTS idx_check_items_severity ON check_items(severity);
        CREATE INDEX IF NOT EXISTS idx_check_items_version ON check_items(version);
    END IF;
    
    -- Indexes for c_report_data table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'c_report_data') THEN
        CREATE INDEX IF NOT EXISTS idx_c_report_data_check_item_id ON c_report_data(check_item_id);
        CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_status ON c_report_data(signoff_status);
        CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_by ON c_report_data(signoff_by);
    END IF;
    
    -- Indexes for check_item_approvals table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'check_item_approvals') THEN
        CREATE INDEX IF NOT EXISTS idx_check_item_approvals_check_item_id ON check_item_approvals(check_item_id);
        CREATE INDEX IF NOT EXISTS idx_check_item_approvals_status ON check_item_approvals(status);
    END IF;
    
    -- Indexes for qms_audit_log table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'qms_audit_log') THEN
        CREATE INDEX IF NOT EXISTS idx_qms_audit_log_checklist_id ON qms_audit_log(checklist_id);
        CREATE INDEX IF NOT EXISTS idx_qms_audit_log_check_item_id ON qms_audit_log(check_item_id);
        CREATE INDEX IF NOT EXISTS idx_qms_audit_log_user_id ON qms_audit_log(user_id);
        CREATE INDEX IF NOT EXISTS idx_qms_audit_log_created_at ON qms_audit_log(created_at);
    END IF;
END $$;

-- Add triggers to update updated_at timestamp (only if tables exist)
DO $$
BEGIN
    -- Triggers for checklists table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'checklists') THEN
        DROP TRIGGER IF EXISTS update_checklists_updated_at ON checklists;
        CREATE TRIGGER update_checklists_updated_at BEFORE UPDATE ON checklists
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    
    -- Triggers for check_items table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'check_items') THEN
        DROP TRIGGER IF EXISTS update_check_items_updated_at ON check_items;
        CREATE TRIGGER update_check_items_updated_at BEFORE UPDATE ON check_items
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    
    -- Triggers for c_report_data table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'c_report_data') THEN
        DROP TRIGGER IF EXISTS update_c_report_data_updated_at ON c_report_data;
        CREATE TRIGGER update_c_report_data_updated_at BEFORE UPDATE ON c_report_data
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    
    -- Triggers for check_item_approvals table
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'check_item_approvals') THEN
        DROP TRIGGER IF EXISTS update_check_item_approvals_updated_at ON check_item_approvals;
        CREATE TRIGGER update_check_item_approvals_updated_at BEFORE UPDATE ON check_item_approvals
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- ============================================================================
-- PART 2: ENSURE ALL QMS COLUMNS EXIST (from 015_ensure_qms_columns_exist.sql)
-- ============================================================================

-- Add columns to check_items table (if they don't exist)
ALTER TABLE check_items
ADD COLUMN IF NOT EXISTS category VARCHAR(100),
ADD COLUMN IF NOT EXISTS sub_category VARCHAR(100),
ADD COLUMN IF NOT EXISTS severity VARCHAR(50),
ADD COLUMN IF NOT EXISTS bronze VARCHAR(50),
ADD COLUMN IF NOT EXISTS silver VARCHAR(50),
ADD COLUMN IF NOT EXISTS gold VARCHAR(50),
ADD COLUMN IF NOT EXISTS info TEXT,
ADD COLUMN IF NOT EXISTS evidence TEXT,
ADD COLUMN IF NOT EXISTS auto_approve BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS version VARCHAR(50) DEFAULT 'v1',
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

-- Add columns to c_report_data table (if they don't exist)
ALTER TABLE c_report_data
ADD COLUMN IF NOT EXISTS result_value TEXT,
ADD COLUMN IF NOT EXISTS signoff_status VARCHAR(50),
ADD COLUMN IF NOT EXISTS signoff_by INT REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS signoff_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS description TEXT,
ADD COLUMN IF NOT EXISTS fix_details TEXT,
ADD COLUMN IF NOT EXISTS engineer_comments TEXT,
ADD COLUMN IF NOT EXISTS lead_comments TEXT;

-- Create indexes for performance (if they don't exist)
CREATE INDEX IF NOT EXISTS idx_check_items_category ON check_items(category);
CREATE INDEX IF NOT EXISTS idx_check_items_sub_category ON check_items(sub_category);
CREATE INDEX IF NOT EXISTS idx_check_items_severity ON check_items(severity);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_status ON c_report_data(signoff_status);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_by ON c_report_data(signoff_by);

-- ============================================================================
-- PART 3: ADD CHECKLIST SUBMISSION TRACKING (from 016_add_checklist_submission_tracking.sql)
-- ============================================================================

-- Add submission tracking columns to checklists table
ALTER TABLE checklists
ADD COLUMN IF NOT EXISTS submitted_by INT REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMP;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_by ON checklists(submitted_by);
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_at ON checklists(submitted_at);

-- ============================================================================
-- PART 4: FIX QMS AUDIT LOG FOREIGN KEY CONSTRAINTS (from 017_fix_qms_audit_log_foreign_keys.sql)
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
-- PART 5: UPDATE CHECKLISTS TABLE - REMOVE STAGE, ADD COMMENTS COLUMNS (from 018_update_checklists_comments.sql)
-- ============================================================================

-- Add engineer_comments column (for submit-for-approval comments)
ALTER TABLE checklists 
ADD COLUMN IF NOT EXISTS engineer_comments TEXT;

-- Add reviewer_comments column (for approver/reject comments)
ALTER TABLE checklists 
ADD COLUMN IF NOT EXISTS reviewer_comments TEXT;

-- Remove stage column (if it exists)
ALTER TABLE checklists 
DROP COLUMN IF EXISTS stage;

-- ============================================================================
-- PART 6: CREATE QMS HISTORY TABLE (from 019_create_qms_history.sql)
-- ============================================================================

CREATE TABLE IF NOT EXISTS qms_checklist_versions (
    id SERIAL PRIMARY KEY,
    checklist_id INTEGER NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    checklist_snapshot JSONB NOT NULL,
    rejected_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    rejection_comments TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for performance when fetching history for a checklist
CREATE INDEX IF NOT EXISTS idx_qms_checklist_versions_checklist_id ON qms_checklist_versions(checklist_id);
CREATE INDEX IF NOT EXISTS idx_qms_checklist_versions_created_at ON qms_checklist_versions(created_at);

-- ============================================================================
-- PART 7: CREATE USER PROJECTS TABLE (from 019_create_user_projects.sql)
-- ============================================================================

-- Create user_projects table to link users to projects (for customer role)
CREATE TABLE IF NOT EXISTS user_projects (
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, project_id)
);

-- Create indexes for user_projects
CREATE INDEX IF NOT EXISTS idx_user_projects_user_id ON user_projects(user_id);
CREATE INDEX IF NOT EXISTS idx_user_projects_project_id ON user_projects(project_id);

-- ============================================================================
-- PART 8: ADD ROLE TO USER PROJECTS (from 020_add_role_to_user_projects.sql)
-- ============================================================================

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

-- ============================================================================
-- PART 9: ADD MANAGEMENT ROLE (from 021_add_management_role.sql)
-- ============================================================================

-- Add 'management' role to user_role enum
-- This role has access to all projects and can see management view only

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

-- ============================================================================
-- PART 10: ADD CAD ENGINEER ROLE (from 022_add_cad_engineer_role.sql)
-- ============================================================================

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

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

