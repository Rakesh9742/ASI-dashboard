
-- ============================================================================

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- ============================================================================
-- 2. CREATE TYPES
-- ============================================================================

-- Create user roles enum
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('admin', 'project_manager', 'lead', 'engineer', 'customer');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- 3. CREATE BASE TABLES (chips and designs)
-- ============================================================================

-- Create chips table
CREATE TABLE IF NOT EXISTS chips (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    architecture VARCHAR(100),
    process_node VARCHAR(50),
    status VARCHAR(50) DEFAULT 'design',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create designs table
CREATE TABLE IF NOT EXISTS designs (
    id SERIAL PRIMARY KEY,
    chip_id INTEGER REFERENCES chips(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    design_type VARCHAR(100),
    status VARCHAR(50) DEFAULT 'draft',
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 4. CREATE USERS TABLE
-- ============================================================================

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    role user_role NOT NULL DEFAULT 'engineer',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    ipaddress VARCHAR(255),
    port INTEGER,
    ssh_user VARCHAR(255),
    sshpassword_hash VARCHAR(255)
);

-- ============================================================================
-- 5. ADD USER REFERENCES TO CHIPS AND DESIGNS
-- ============================================================================

-- Add created_by and updated_by columns to chips table
ALTER TABLE chips 
ADD COLUMN IF NOT EXISTS created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

-- Add created_by and updated_by columns to designs table
ALTER TABLE designs 
ADD COLUMN IF NOT EXISTS created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

-- ============================================================================
-- 6. CREATE DOMAINS TABLE
-- ============================================================================

-- Create domains table for design domains
CREATE TABLE IF NOT EXISTS domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 7. ADD DOMAIN TO USERS
-- ============================================================================

-- Add domain_id column to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS domain_id INTEGER REFERENCES domains(id) ON DELETE SET NULL;

-- ============================================================================
-- 8. CREATE PROJECTS TABLES
-- ============================================================================

-- Projects core table
CREATE TABLE IF NOT EXISTS projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    client VARCHAR(255),
    technology_node VARCHAR(100),
    start_date DATE,
    target_date DATE,
    plan TEXT,
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Link projects to one or more domains
CREATE TABLE IF NOT EXISTS project_domains (
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    domain_id INTEGER REFERENCES domains(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (project_id, domain_id)
);

-- Link users to projects (for customer role)
CREATE TABLE IF NOT EXISTS user_projects (
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, project_id)
);

-- ============================================================================
-- 9. CREATE PHYSICAL DESIGN SCHEMA
-- ============================================================================

-- Blocks belong to projects
CREATE TABLE IF NOT EXISTS blocks (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    block_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (project_id, block_name)
);

-- Runs belong to blocks
CREATE TABLE IF NOT EXISTS runs (
    id SERIAL PRIMARY KEY,
    block_id INT NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
    experiment VARCHAR(100),
    rtl_tag VARCHAR(100),
    user_name VARCHAR(100),
    run_directory TEXT,
    last_updated TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (block_id, experiment, rtl_tag)
);

-- Stages belong to runs
CREATE TABLE IF NOT EXISTS stages (
    id SERIAL PRIMARY KEY,
    run_id INT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    stage_name VARCHAR(50) NOT NULL,
    timestamp TIMESTAMP,
    stage_directory TEXT,
    run_status VARCHAR(50),
    runtime VARCHAR(20),
    memory_usage VARCHAR(50),
    log_errors VARCHAR(50) DEFAULT '0',
    log_warnings VARCHAR(50) DEFAULT '0',
    log_critical VARCHAR(50) DEFAULT '0',
    area VARCHAR(50),
    inst_count VARCHAR(50),
    utilization VARCHAR(50),
    metal_density_max VARCHAR(50),
    min_pulse_width VARCHAR(50),
    min_period VARCHAR(50),
    double_switching VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (run_id, stage_name)
);

-- Stage timing metrics
CREATE TABLE IF NOT EXISTS stage_timing_metrics (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    internal_r2r_wns VARCHAR(50),
    internal_r2r_tns VARCHAR(50),
    internal_r2r_nvp VARCHAR(50),
    interface_i2r_wns VARCHAR(50),
    interface_i2r_tns VARCHAR(50),
    interface_i2r_nvp VARCHAR(50),
    interface_r2o_wns VARCHAR(50),
    interface_r2o_tns VARCHAR(50),
    interface_r2o_nvp VARCHAR(50),
    interface_i2o_wns VARCHAR(50),
    interface_i2o_tns VARCHAR(50),
    interface_i2o_nvp VARCHAR(50),
    hold_wns VARCHAR(50),
    hold_tns VARCHAR(50),
    hold_nvp VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- Stage constraint metrics
CREATE TABLE IF NOT EXISTS stage_constraint_metrics (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    max_tran_wns VARCHAR(50),
    max_tran_nvp VARCHAR(50),
    max_cap_wns VARCHAR(50),
    max_cap_nvp VARCHAR(50),
    max_fanout_wns VARCHAR(50),
    max_fanout_nvp VARCHAR(50),
    drc_violations VARCHAR(50),
    congestion_hotspot VARCHAR(100),
    noise_violations VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- Path groups (setup/hold)
CREATE TABLE IF NOT EXISTS path_groups (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    group_type VARCHAR(10) NOT NULL,
    group_name VARCHAR(100) NOT NULL,
    wns VARCHAR(50),
    tns VARCHAR(50),
    nvp VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id, group_type, group_name)
);

-- DRV violations
CREATE TABLE IF NOT EXISTS drv_violations (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    violation_type VARCHAR(50) NOT NULL,
    wns VARCHAR(50),
    tns VARCHAR(50),
    nvp VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id, violation_type)
);

-- Power/IR/EM checks
CREATE TABLE IF NOT EXISTS power_ir_em_checks (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    ir_static VARCHAR(50),
    ir_dynamic VARCHAR(50),
    em_power VARCHAR(50),
    em_signal VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- Physical verification
CREATE TABLE IF NOT EXISTS physical_verification (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    pv_drc_base VARCHAR(50),
    pv_drc_metal VARCHAR(50),
    pv_drc_antenna VARCHAR(50),
    lvs VARCHAR(50),
    erc VARCHAR(50),
    r2g_lec VARCHAR(50),
    g2g_lec VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- AI summaries
CREATE TABLE IF NOT EXISTS ai_summaries (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    summary_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 10. CREATE QMS (QUALITY MANAGEMENT SYSTEM) SCHEMA
-- ============================================================================

-- Checklists table
CREATE TABLE IF NOT EXISTS checklists (
    id SERIAL PRIMARY KEY,
    block_id INTEGER NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
    milestone_id INTEGER,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'draft',
    approver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    approver_role VARCHAR(50),
    submitted_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    submitted_at TIMESTAMP,
    engineer_comments TEXT,
    reviewer_comments TEXT,
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'
);

-- Check items table
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
    check_name VARCHAR(255),
    version VARCHAR(50) DEFAULT 'v1',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Check report data table
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

-- Check item approvals table
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

-- QMS audit log table
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

-- ============================================================================
-- 11. CREATE ZOHO INTEGRATION TABLES
-- ============================================================================

-- Zoho Projects Integration - Stores OAuth tokens for Zoho Projects API access
CREATE TABLE IF NOT EXISTS zoho_tokens (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    token_type VARCHAR(50) DEFAULT 'Bearer',
    expires_in INTEGER,
    expires_at TIMESTAMP,
    scope TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

-- Store Zoho Projects mapping (optional - to sync projects)
CREATE TABLE IF NOT EXISTS zoho_projects_mapping (
    id SERIAL PRIMARY KEY,
    zoho_project_id VARCHAR(255) NOT NULL UNIQUE,
    local_project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    zoho_project_name VARCHAR(255),
    zoho_project_data JSONB,
    synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 10. CREATE INDEXES
-- ============================================================================

-- Indexes for chips
CREATE INDEX IF NOT EXISTS idx_chips_status ON chips(status);
CREATE INDEX IF NOT EXISTS idx_chips_created_by ON chips(created_by);
CREATE INDEX IF NOT EXISTS idx_chips_updated_by ON chips(updated_by);

-- Indexes for designs
CREATE INDEX IF NOT EXISTS idx_designs_chip_id ON designs(chip_id);
CREATE INDEX IF NOT EXISTS idx_designs_status ON designs(status);
CREATE INDEX IF NOT EXISTS idx_designs_created_by ON designs(created_by);
CREATE INDEX IF NOT EXISTS idx_designs_updated_by ON designs(updated_by);

-- Indexes for users
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_domain_id ON users(domain_id);
CREATE INDEX IF NOT EXISTS idx_users_ipaddress ON users(ipaddress) WHERE ipaddress IS NOT NULL;

-- Indexes for domains
CREATE INDEX IF NOT EXISTS idx_domains_code ON domains(code);
CREATE INDEX IF NOT EXISTS idx_domains_is_active ON domains(is_active);

-- Indexes for projects
CREATE INDEX IF NOT EXISTS idx_projects_created_by ON projects(created_by);
CREATE INDEX IF NOT EXISTS idx_project_domains_domain_id ON project_domains(domain_id);

-- Indexes for user_projects
CREATE INDEX IF NOT EXISTS idx_user_projects_user_id ON user_projects(user_id);
CREATE INDEX IF NOT EXISTS idx_user_projects_project_id ON user_projects(project_id);

-- Indexes for blocks
CREATE INDEX IF NOT EXISTS idx_blocks_project_id ON blocks(project_id);
CREATE INDEX IF NOT EXISTS idx_blocks_name ON blocks(block_name);
CREATE INDEX IF NOT EXISTS idx_blocks_project_name ON blocks(project_id, block_name);

-- Indexes for runs
CREATE INDEX IF NOT EXISTS idx_runs_block_id ON runs(block_id);
CREATE INDEX IF NOT EXISTS idx_runs_experiment ON runs(experiment);
CREATE INDEX IF NOT EXISTS idx_runs_rtl_tag ON runs(rtl_tag);
CREATE INDEX IF NOT EXISTS idx_runs_user_name ON runs(user_name);

-- Indexes for stages
CREATE INDEX IF NOT EXISTS idx_stages_run_id ON stages(run_id);
CREATE INDEX IF NOT EXISTS idx_stages_name ON stages(stage_name);
CREATE INDEX IF NOT EXISTS idx_stages_status ON stages(run_status);
CREATE INDEX IF NOT EXISTS idx_stages_timestamp ON stages(timestamp);

-- Indexes for stage_timing_metrics
CREATE INDEX IF NOT EXISTS idx_stage_timing_metrics_stage_id ON stage_timing_metrics(stage_id);

-- Indexes for stage_constraint_metrics
CREATE INDEX IF NOT EXISTS idx_stage_constraint_metrics_stage_id ON stage_constraint_metrics(stage_id);

-- Indexes for path_groups
CREATE INDEX IF NOT EXISTS idx_path_groups_stage_id ON path_groups(stage_id);
CREATE INDEX IF NOT EXISTS idx_path_groups_type ON path_groups(group_type);
CREATE INDEX IF NOT EXISTS idx_path_groups_name ON path_groups(group_name);

-- Indexes for drv_violations
CREATE INDEX IF NOT EXISTS idx_drv_violations_stage_id ON drv_violations(stage_id);
CREATE INDEX IF NOT EXISTS idx_drv_violations_type ON drv_violations(violation_type);

-- Indexes for power_ir_em_checks
CREATE INDEX IF NOT EXISTS idx_power_ir_em_checks_stage_id ON power_ir_em_checks(stage_id);

-- Indexes for physical_verification
CREATE INDEX IF NOT EXISTS idx_physical_verification_stage_id ON physical_verification(stage_id);

-- Indexes for ai_summaries
CREATE INDEX IF NOT EXISTS idx_ai_summaries_stage_id ON ai_summaries(stage_id);

-- Indexes for checklists
CREATE INDEX IF NOT EXISTS idx_checklists_block_id ON checklists(block_id);
CREATE INDEX IF NOT EXISTS idx_checklists_milestone_id ON checklists(milestone_id);
CREATE INDEX IF NOT EXISTS idx_checklists_status ON checklists(status);
CREATE INDEX IF NOT EXISTS idx_checklists_approver_id ON checklists(approver_id);
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_by ON checklists(submitted_by);
CREATE INDEX IF NOT EXISTS idx_checklists_submitted_at ON checklists(submitted_at);

-- Indexes for check_items
CREATE INDEX IF NOT EXISTS idx_check_items_checklist_id ON check_items(checklist_id);
CREATE INDEX IF NOT EXISTS idx_check_items_category ON check_items(category);
CREATE INDEX IF NOT EXISTS idx_check_items_sub_category ON check_items(sub_category);
CREATE INDEX IF NOT EXISTS idx_check_items_severity ON check_items(severity);
CREATE INDEX IF NOT EXISTS idx_check_items_version ON check_items(version);

-- Indexes for c_report_data
CREATE INDEX IF NOT EXISTS idx_c_report_data_check_item_id ON c_report_data(check_item_id);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_status ON c_report_data(signoff_status);
CREATE INDEX IF NOT EXISTS idx_c_report_data_signoff_by ON c_report_data(signoff_by);

-- Indexes for check_item_approvals
CREATE INDEX IF NOT EXISTS idx_check_item_approvals_check_item_id ON check_item_approvals(check_item_id);
CREATE INDEX IF NOT EXISTS idx_check_item_approvals_status ON check_item_approvals(status);

-- Indexes for qms_audit_log
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_checklist_id ON qms_audit_log(checklist_id);
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_check_item_id ON qms_audit_log(check_item_id);
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_user_id ON qms_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_qms_audit_log_created_at ON qms_audit_log(created_at);

-- Indexes for zoho_tokens
CREATE INDEX IF NOT EXISTS idx_zoho_tokens_user_id ON zoho_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_zoho_tokens_expires_at ON zoho_tokens(expires_at);

-- Indexes for zoho_projects_mapping
CREATE INDEX IF NOT EXISTS idx_zoho_projects_mapping_local_id ON zoho_projects_mapping(local_project_id);
CREATE INDEX IF NOT EXISTS idx_zoho_projects_mapping_zoho_id ON zoho_projects_mapping(zoho_project_id);

-- ============================================================================
-- 11. CREATE TRIGGERS
-- ============================================================================

-- Trigger for users updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for chips updated_at
DROP TRIGGER IF EXISTS update_chips_updated_at ON chips;
CREATE TRIGGER update_chips_updated_at
    BEFORE UPDATE ON chips
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for designs updated_at
DROP TRIGGER IF EXISTS update_designs_updated_at ON designs;
CREATE TRIGGER update_designs_updated_at
    BEFORE UPDATE ON designs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for domains updated_at
DROP TRIGGER IF EXISTS update_domains_updated_at ON domains;
CREATE TRIGGER update_domains_updated_at
    BEFORE UPDATE ON domains
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for projects updated_at
DROP TRIGGER IF EXISTS update_projects_updated_at ON projects;
CREATE TRIGGER update_projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for zoho_tokens updated_at
DROP TRIGGER IF EXISTS update_zoho_tokens_updated_at ON zoho_tokens;
CREATE TRIGGER update_zoho_tokens_updated_at
    BEFORE UPDATE ON zoho_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for zoho_projects_mapping updated_at
DROP TRIGGER IF EXISTS update_zoho_projects_mapping_updated_at ON zoho_projects_mapping;
CREATE TRIGGER update_zoho_projects_mapping_updated_at
    BEFORE UPDATE ON zoho_projects_mapping
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for blocks updated_at
DROP TRIGGER IF EXISTS update_blocks_updated_at ON blocks;
CREATE TRIGGER update_blocks_updated_at
    BEFORE UPDATE ON blocks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for runs updated_at
DROP TRIGGER IF EXISTS update_runs_updated_at ON runs;
CREATE TRIGGER update_runs_updated_at
    BEFORE UPDATE ON runs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for stages updated_at
DROP TRIGGER IF EXISTS update_stages_updated_at ON stages;
CREATE TRIGGER update_stages_updated_at
    BEFORE UPDATE ON stages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for ai_summaries updated_at
DROP TRIGGER IF EXISTS update_ai_summaries_updated_at ON ai_summaries;
CREATE TRIGGER update_ai_summaries_updated_at
    BEFORE UPDATE ON ai_summaries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for checklists updated_at
DROP TRIGGER IF EXISTS update_checklists_updated_at ON checklists;
CREATE TRIGGER update_checklists_updated_at
    BEFORE UPDATE ON checklists
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for check_items updated_at
DROP TRIGGER IF EXISTS update_check_items_updated_at ON check_items;
CREATE TRIGGER update_check_items_updated_at
    BEFORE UPDATE ON check_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for c_report_data updated_at
DROP TRIGGER IF EXISTS update_c_report_data_updated_at ON c_report_data;
CREATE TRIGGER update_c_report_data_updated_at
    BEFORE UPDATE ON c_report_data
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for check_item_approvals updated_at
DROP TRIGGER IF EXISTS update_check_item_approvals_updated_at ON check_item_approvals;
CREATE TRIGGER update_check_item_approvals_updated_at
    BEFORE UPDATE ON check_item_approvals
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 12. INSERT INITIAL DATA
-- ============================================================================

-- Insert design domains
INSERT INTO domains (name, code, description, is_active) VALUES
('Design Verification', 'DV', 'Design Verification (DV) domain for verifying chip designs', true),
('Register Transfer Level', 'RTL', 'RTL (Register Transfer Level) design domain', true),
('Design for Testability', 'DFT', 'DFT (Design for Testability) domain for testability features', true),
('Physical Design', 'PHYSICAL', 'Physical design domain for layout and floorplanning', true),
('Analog Layout', 'ANALOG', 'Analog layout domain for analog circuit design', true)
ON CONFLICT (code) DO NOTHING;

-- Add admin user with username admin1, email admin@1.com and password test@1234
-- Password hash for 'test@1234' using bcrypt with salt rounds 10
INSERT INTO users (username, email, password_hash, full_name, role, is_active) VALUES
('admin1', 'admin@1.com', '$2a$10$6fuNS9.c5gNt20SsPmmTPO04289kKQcI1wr1QFiCcMt7McQTZSsQC', 'Admin User', 'admin', true)
ON CONFLICT (username) DO UPDATE SET
  email = EXCLUDED.email,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  is_active = EXCLUDED.is_active;

-- ============================================================================
-- SCHEMA CREATION COMPLETE
-- ============================================================================
-- 
-- Database schema has been created successfully!
-- 
-- This complete schema includes:
--   - Base tables: chips, designs, users, domains, projects
--   - Physical Design tables: blocks, runs, stages, and all related metrics
--   - QMS tables: checklists, check_items, c_report_data, approvals, audit_log
--   - Integration tables: zoho_tokens, zoho_projects_mapping
--   - Junction tables: project_domains, user_projects
-- 
-- Default Admin Credentials:
--   Username: admin1
--   Email: admin@1.com
--   Password: test@1234
-- 
-- Note: Change the admin password immediately after first login!
-- 
-- ============================================================================

