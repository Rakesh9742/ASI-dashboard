-- ============================================================================
-- CREATE PHYSICAL DESIGN SCHEMA
-- ============================================================================
-- This migration creates the new Physical Design (PD) table structure
-- All tables are linked to projects, which are linked to domains via project_domains
-- Based on the JSON structure from EDA output files

-- ============================================================================
-- 1. BLOCKS
-- ============================================================================
-- Blocks belong to projects (which are linked to domains)
CREATE TABLE IF NOT EXISTS blocks (
    id SERIAL PRIMARY KEY,
    project_id INT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    block_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (project_id, block_name)
);

-- ============================================================================
-- 2. RUNS (EXPERIMENTS)
-- ============================================================================
-- Runs belong to blocks (which belong to projects)
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
-- 3. STAGES
-- ============================================================================
-- Stages belong to runs (which belong to blocks, which belong to projects)
CREATE TABLE IF NOT EXISTS stages (
    id SERIAL PRIMARY KEY,
    run_id INT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    stage_name VARCHAR(50) NOT NULL,           -- syn, init, floorplan, place, cts, postcts, route, postroute
    timestamp TIMESTAMP,
    stage_directory TEXT,
    run_status VARCHAR(50),                   -- pass / fail / continue_with_error
    runtime VARCHAR(20),
    memory_usage VARCHAR(50),
    log_errors INT DEFAULT 0,
    log_warnings INT DEFAULT 0,
    log_critical INT DEFAULT 0,
    area FLOAT,
    inst_count INT,
    utilization FLOAT,
    metal_density_max FLOAT,                  -- Some stages have this (e.g., route, postroute)
    min_pulse_width VARCHAR(50),              -- Can be "N/A" or value
    min_period VARCHAR(50),                    -- Can be "N/A" or value
    double_switching VARCHAR(50),             -- Can be "N/A" or value
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (run_id, stage_name)
);

-- ============================================================================
-- 4. STAGE TIMING METRICS
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
-- 5. STAGE CONSTRAINT METRICS
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
-- 6. PATH GROUPS (SETUP / HOLD)
-- ============================================================================
CREATE TABLE IF NOT EXISTS path_groups (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    group_type VARCHAR(10) NOT NULL,          -- setup / hold
    group_name VARCHAR(100) NOT NULL,         -- reg2reg, in2reg, reg2out, in2out, all, ClockGate, cg_enable_group_clk
    wns FLOAT,
    tns FLOAT,
    nvp INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id, group_type, group_name)
);

-- ============================================================================
-- 7. DRV VIOLATIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS drv_violations (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    violation_type VARCHAR(50) NOT NULL,     -- max_transition, min_transition, max_capacitance, min_capacitance, max_fanout, min_fanout
    wns FLOAT,
    tns FLOAT,
    nvp INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id, violation_type)
);

-- ============================================================================
-- 8. POWER / IR / EM CHECKS
-- ============================================================================
CREATE TABLE IF NOT EXISTS power_ir_em_checks (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    ir_static VARCHAR(50),                    -- Can be "N/A" or value
    ir_dynamic VARCHAR(50),                   -- Can be "N/A" or value
    em_power VARCHAR(50),                     -- Can be "N/A" or value
    em_signal VARCHAR(50),                    -- Can be "N/A" or value
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- ============================================================================
-- 9. PHYSICAL VERIFICATION
-- ============================================================================
CREATE TABLE IF NOT EXISTS physical_verification (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    pv_drc_base VARCHAR(50),                  -- Can be "N/A" or value
    pv_drc_metal VARCHAR(50),                  -- Can be "N/A" or value
    pv_drc_antenna VARCHAR(50),                -- Can be "N/A" or value
    lvs VARCHAR(50),                          -- Can be "N/A" or value
    erc VARCHAR(50),                          -- Can be "N/A" or value
    r2g_lec VARCHAR(50),                      -- Can be "N/A" or value
    g2g_lec VARCHAR(50),                      -- Can be "N/A" or value
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (stage_id)
);

-- ============================================================================
-- 10. AI SUMMARIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS ai_summaries (
    id SERIAL PRIMARY KEY,
    stage_id INT NOT NULL REFERENCES stages(id) ON DELETE CASCADE,
    summary_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
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
-- TRIGGERS FOR UPDATED_AT
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

