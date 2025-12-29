-- ============================================================================
-- CREATE EDA OUTPUT FILES TABLE
-- ============================================================================
-- This table stores files received from EDA tools via VNC server
-- Files are processed to extract project name and domain name
-- Physical Design (PD) specific columns are included

CREATE TABLE IF NOT EXISTS eda_output_files (
    id SERIAL PRIMARY KEY,
    file_name VARCHAR(500) NOT NULL,
    file_path TEXT NOT NULL,
    file_type VARCHAR(50) NOT NULL, -- 'csv' or 'json'
    file_size BIGINT, -- File size in bytes
    project_name VARCHAR(255),
    domain_name VARCHAR(255),
    domain_id INTEGER REFERENCES domains(id) ON DELETE SET NULL,
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    
    -- Physical Design (PD) specific columns
    block_name VARCHAR(255),
    experiment VARCHAR(255),
    rtl_tag VARCHAR(255),
    user_name VARCHAR(255),
    run_directory VARCHAR(255),
    run_end_time TIMESTAMP,
    stage VARCHAR(255),
    internal_timing VARCHAR(255),
    interface_timing VARCHAR(255),
    max_tran_wns_nvp VARCHAR(255),
    max_cap_wns_nvp VARCHAR(255),
    noise VARCHAR(255),
    mpw_min_period_double_switching VARCHAR(255)    ,
    congestion_drc_metrics VARCHAR(255),
    area VARCHAR(255),
    inst_count VARCHAR(100),
    utilization VARCHAR(255),
    logs_errors_warnings VARCHAR(255),
    run_status VARCHAR(100), -- 'pass', 'fail', 'continue_with_error'
    runtime VARCHAR(255),
    ai_based_overall_summary VARCHAR(255),
    ir_static VARCHAR(255),
    em_power_signal VARCHAR(255),
    pv_drc_base_metal_antenna VARCHAR(255),
    lvs VARCHAR(255),
    lec VARCHAR(255),
    
    -- Raw file data stored as JSONB for flexibility
    raw_data JSONB,
    
    -- Processing status
    processing_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'
    processing_error TEXT,
    
    -- Metadata
    uploaded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_eda_output_files_project_name ON eda_output_files(project_name);
CREATE INDEX IF NOT EXISTS idx_eda_output_files_domain_name ON eda_output_files(domain_name);
CREATE INDEX IF NOT EXISTS idx_eda_output_files_domain_id ON eda_output_files(domain_id);
CREATE INDEX IF NOT EXISTS idx_eda_output_files_project_id ON eda_output_files(project_id);
CREATE INDEX IF NOT EXISTS idx_eda_output_files_file_type ON eda_output_files(file_type);
CREATE INDEX IF NOT EXISTS idx_eda_output_files_processing_status ON eda_output_files(processing_status);
CREATE INDEX IF NOT EXISTS idx_eda_output_files_created_at ON eda_output_files(created_at);

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_eda_output_files_updated_at ON eda_output_files;
CREATE TRIGGER update_eda_output_files_updated_at
    BEFORE UPDATE ON eda_output_files
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

