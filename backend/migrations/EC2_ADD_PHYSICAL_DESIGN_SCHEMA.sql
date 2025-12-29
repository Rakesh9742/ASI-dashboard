-- ============================================================================
-- EC2 PRODUCTION: ADD PHYSICAL DESIGN SCHEMA
-- ============================================================================
-- This script adds the Physical Design schema tables to your EC2 PostgreSQL database
-- Run this on your EC2 server to fix the "relation 'blocks' does not exist" error
--
-- Usage on EC2:
--   sudo -u postgres psql -d ASI -f EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql
--
-- Or if you have the file locally:
--   psql -U postgres -h YOUR_EC2_IP -d ASI -f EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql
-- ============================================================================

-- ============================================================================
-- STEP 1: CREATE UPDATE FUNCTION (if not exists)
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- ============================================================================
-- STEP 2: VERIFY PREREQUISITES
-- ============================================================================
-- Check if projects table exists (required for blocks)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'projects') THEN
        RAISE EXCEPTION 'ERROR: projects table does not exist. Please run migration 006_create_projects.sql first!';
    END IF;
END $$;

-- ============================================================================
-- STEP 3: CREATE BLOCKS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS blocks (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    block_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (project_id, block_name)
);

-- ============================================================================
-- STEP 4: CREATE RUNS TABLE
-- ============================================================================
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

-- ============================================================================
-- STEP 5: CREATE STAGES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS stages (
    id SERIAL PRIMARY KEY,
    run_id INT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    stage_name VARCHAR(50) NOT NULL,
    timestamp TIMESTAMP,
    stage_directory TEXT,
    run_status VARCHAR(50),
    runtime VARCHAR(20),
    memory_usage VARCHAR(50),
    log_errors INT DEFAULT 0,
    log_warnings INT DEFAULT 0,
    log_critical INT DEFAULT 0,
    area FLOAT,
    inst_count INT,
    utilization FLOAT,
    metal_density_max FLOAT,
    min_pulse_width VARCHAR(50),
    min_period VARCHAR(50),
    double_switching VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (run_id, stage_name)
);

-- ============================================================================
-- STEP 6: CREATE STAGE TIMING METRICS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS stage_timing_metrics (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    internal_r2r_wns FLOAT,
    internal_r2r_tns FLOAT,
    internal_r2r_nvp INT,
    interface_i2r_wns FLOAT,
    interface_i2r_tns FLOAT,
    interface_i2r_nvp INT,
    interface_r2o_wns FLOAT,
    interface_r2o_tns FLOAT,
    interface_r2o_nvp INT,
    interface_i2o_wns FLOAT,
    interface_i2o_tns FLOAT,
    interface_i2o_nvp INT,
    hold_wns FLOAT,
    hold_tns FLOAT,
    hold_nvp INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- ============================================================================
-- STEP 7: CREATE STAGE CONSTRAINT METRICS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS stage_constraint_metrics (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    max_tran_wns FLOAT,
    max_tran_nvp INT,
    max_cap_wns FLOAT,
    max_cap_nvp INT,
    max_fanout_wns FLOAT,
    max_fanout_nvp INT,
    drc_violations INT,
    congestion_hotspot VARCHAR(100),
    noise_violations VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- ============================================================================
-- STEP 8: CREATE PATH GROUPS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS path_groups (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    group_type VARCHAR(10) NOT NULL,
    group_name VARCHAR(100) NOT NULL,
    wns FLOAT,
    tns FLOAT,
    nvp INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id, group_type, group_name)
);

-- ============================================================================
-- STEP 9: CREATE DRV VIOLATIONS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS drv_violations (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    violation_type VARCHAR(50) NOT NULL,
    wns FLOAT,
    tns FLOAT,
    nvp INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id, violation_type)
);

-- ============================================================================
-- STEP 10: CREATE POWER/IR/EM CHECKS TABLE
-- ============================================================================
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

-- ============================================================================
-- STEP 11: CREATE PHYSICAL VERIFICATION TABLE
-- ============================================================================
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

-- ============================================================================
-- STEP 12: CREATE AI SUMMARIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS ai_summaries (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    summary_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- STEP 13: CREATE INDEXES FOR PERFORMANCE
-- ============================================================================

-- Blocks indexes
CREATE INDEX IF NOT EXISTS idx_blocks_project_id ON blocks(project_id);
CREATE INDEX IF NOT EXISTS idx_blocks_name ON blocks(block_name);
CREATE INDEX IF NOT EXISTS idx_blocks_project_name ON blocks(project_id, block_name);

-- Runs indexes
CREATE INDEX IF NOT EXISTS idx_runs_block_id ON runs(block_id);
CREATE INDEX IF NOT EXISTS idx_runs_experiment ON runs(experiment);
CREATE INDEX IF NOT EXISTS idx_runs_rtl_tag ON runs(rtl_tag);
CREATE INDEX IF NOT EXISTS idx_runs_user_name ON runs(user_name);

-- Stages indexes
CREATE INDEX IF NOT EXISTS idx_stages_run_id ON stages(run_id);
CREATE INDEX IF NOT EXISTS idx_stages_name ON stages(stage_name);
CREATE INDEX IF NOT EXISTS idx_stages_status ON stages(run_status);
CREATE INDEX IF NOT EXISTS idx_stages_timestamp ON stages(timestamp);

-- Stage timing metrics indexes
CREATE INDEX IF NOT EXISTS idx_stage_timing_metrics_stage_id ON stage_timing_metrics(stage_id);

-- Stage constraint metrics indexes
CREATE INDEX IF NOT EXISTS idx_stage_constraint_metrics_stage_id ON stage_constraint_metrics(stage_id);

-- Path groups indexes
CREATE INDEX IF NOT EXISTS idx_path_groups_stage_id ON path_groups(stage_id);
CREATE INDEX IF NOT EXISTS idx_path_groups_type ON path_groups(group_type);
CREATE INDEX IF NOT EXISTS idx_path_groups_name ON path_groups(group_name);

-- DRV violations indexes
CREATE INDEX IF NOT EXISTS idx_drv_violations_stage_id ON drv_violations(stage_id);
CREATE INDEX IF NOT EXISTS idx_drv_violations_type ON drv_violations(violation_type);

-- Power/IR/EM checks indexes
CREATE INDEX IF NOT EXISTS idx_power_ir_em_checks_stage_id ON power_ir_em_checks(stage_id);

-- Physical verification indexes
CREATE INDEX IF NOT EXISTS idx_physical_verification_stage_id ON physical_verification(stage_id);

-- AI summaries indexes
CREATE INDEX IF NOT EXISTS idx_ai_summaries_stage_id ON ai_summaries(stage_id);

-- ============================================================================
-- STEP 14: CREATE TRIGGERS FOR UPDATED_AT
-- ============================================================================

-- Blocks trigger
DROP TRIGGER IF EXISTS update_blocks_updated_at ON blocks;
CREATE TRIGGER update_blocks_updated_at
    BEFORE UPDATE ON blocks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Runs trigger
DROP TRIGGER IF EXISTS update_runs_updated_at ON runs;
CREATE TRIGGER update_runs_updated_at
    BEFORE UPDATE ON runs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Stages trigger
DROP TRIGGER IF EXISTS update_stages_updated_at ON stages;
CREATE TRIGGER update_stages_updated_at
    BEFORE UPDATE ON stages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- AI summaries trigger
DROP TRIGGER IF EXISTS update_ai_summaries_updated_at ON ai_summaries;
CREATE TRIGGER update_ai_summaries_updated_at
    BEFORE UPDATE ON ai_summaries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- The Physical Design schema has been created successfully!
-- 
-- Table Hierarchy:
--   projects (linked to domains via project_domains)
--     └── blocks
--         └── runs
--             └── stages
--                 ├── stage_timing_metrics
--                 ├── stage_constraint_metrics
--                 ├── path_groups
--                 ├── drv_violations
--                 ├── power_ir_em_checks
--                 ├── physical_verification
--                 └── ai_summaries
--
-- All tables cascade delete properly to maintain referential integrity.
-- ============================================================================

-- Verify tables were created
SELECT 
    '✅ Migration completed! Created tables:' as status,
    string_agg(table_name, ', ' ORDER BY table_name) as tables
FROM information_schema.tables
WHERE table_schema = 'public' 
  AND table_name IN (
    'blocks', 'runs', 'stages', 'stage_timing_metrics', 
    'stage_constraint_metrics', 'path_groups', 'drv_violations',
    'power_ir_em_checks', 'physical_verification', 'ai_summaries'
  );

