-- ============================================================================
-- CREATE QMS SCHEMA (CHECKLISTS, CHECK ITEMS, AND RELATED TABLES)
-- ============================================================================
-- This migration creates all tables required for QMS (Quality Management System)
-- including checklists, check_items, c_report_data, check_item_approvals, and qms_audit_log
-- ============================================================================
-- PREREQUISITES: 
-- - blocks table must exist (from migration 010_create_physical_design_schema.sql)
-- - users table must exist (from migration 002_users_and_roles.sql)
-- - update_updated_at_column() function must exist (from migration 002_users_and_roles.sql)
-- ============================================================================

-- Ensure update_updated_at_column function exists (safety check)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_checklists_block_id ON checklists(block_id);
CREATE INDEX IF NOT EXISTS idx_checklists_milestone_id ON checklists(milestone_id);
CREATE INDEX IF NOT EXISTS idx_checklists_status ON checklists(status);
CREATE INDEX IF NOT EXISTS idx_checklists_approver_id ON checklists(approver_id);
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_by ON checklists(submitted_by);
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_at ON checklists(submitted_at);

CREATE INDEX IF NOT EXISTS idx_check_items_checklist_id ON check_items(checklist_id);
CREATE INDEX IF NOT EXISTS idx_check_items_category ON check_items(category);
CREATE INDEX IF NOT EXISTS idx_check_items_sub_category ON check_items(sub_category);
CREATE INDEX IF NOT EXISTS idx_check_items_severity ON check_items(severity);
CREATE INDEX IF NOT EXISTS idx_check_items_version ON check_items(version);

CREATE INDEX IF NOT EXISTS idx_c_report_data_check_item_id ON c_report_data(check_item_id);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_status ON c_report_data(signoff_status);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_by ON c_report_data(signoff_by);

CREATE INDEX IF NOT EXISTS idx_check_item_approvals_check_item_id ON check_item_approvals(check_item_id);
CREATE INDEX IF NOT EXISTS idx_check_item_approvals_status ON check_item_approvals(status);

CREATE INDEX IF NOT EXISTS idx_qms_audit_log_checklist_id ON qms_audit_log(checklist_id);
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_check_item_id ON qms_audit_log(check_item_id);
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_user_id ON qms_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_created_at ON qms_audit_log(created_at);

-- Add triggers to update updated_at timestamp
DROP TRIGGER IF EXISTS update_checklists_updated_at ON checklists;
CREATE TRIGGER update_checklists_updated_at BEFORE UPDATE ON checklists
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_check_items_updated_at ON check_items;
CREATE TRIGGER update_check_items_updated_at BEFORE UPDATE ON check_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_c_report_data_updated_at ON c_report_data;
CREATE TRIGGER update_c_report_data_updated_at BEFORE UPDATE ON c_report_data
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_check_item_approvals_updated_at ON check_item_approvals;
CREATE TRIGGER update_check_item_approvals_updated_at BEFORE UPDATE ON check_item_approvals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

