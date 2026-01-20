-- ============================================================================
-- CREATE COMPLETE PHYSICAL DESIGN SCHEMA FOR PRODUCTION
-- ============================================================================
-- This script creates all Physical Design tables and dependencies
-- Run this in your production database to fix missing table errors
-- ============================================================================

-- 1. Ensure update_updated_at_column function exists (safety check)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2. CREATE BLOCKS TABLE
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
-- 3. CREATE RUNS TABLE
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
-- 4. CREATE STAGES TABLE
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

-- ============================================================================
-- 5. CREATE STAGE TIMING METRICS TABLE
-- ============================================================================
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

-- ============================================================================
-- 6. CREATE STAGE CONSTRAINT METRICS TABLE
-- ============================================================================
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

-- ============================================================================
-- 7. CREATE PATH GROUPS TABLE
-- ============================================================================
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

-- ============================================================================
-- 8. CREATE DRV VIOLATIONS TABLE
-- ============================================================================
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

-- ============================================================================
-- 9. CREATE POWER / IR / EM CHECKS TABLE
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
-- 10. CREATE PHYSICAL VERIFICATION TABLE
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
-- 11. CREATE AI SUMMARIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS ai_summaries (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    summary_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 12. CREATE INDEXES FOR PERFORMANCE
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
-- 13. CREATE TRIGGERS FOR UPDATED_AT
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
-- VERIFICATION
-- ============================================================================
-- Run these queries to verify all tables were created successfully:
-- SELECT table_name FROM information_schema.tables 
-- WHERE table_name IN ('blocks', 'runs', 'stages', 'stage_timing_metrics', 
--                      'stage_constraint_metrics', 'path_groups', 'drv_violations',
--                      'power_ir_em_checks', 'physical_verification', 'ai_summaries')
-- ORDER BY table_name;
-- ============================================================================

