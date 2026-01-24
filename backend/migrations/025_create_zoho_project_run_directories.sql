-- Create table to store run directories for Zoho projects (unmapped projects)
-- This allows storing run directories for Zoho projects that haven't been mapped to local projects yet

CREATE TABLE IF NOT EXISTS zoho_project_run_directories (
    id SERIAL PRIMARY KEY,
    zoho_project_id VARCHAR(255) NOT NULL,
    zoho_project_name VARCHAR(255),
    user_name VARCHAR(100) NOT NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    block_name VARCHAR(255) NOT NULL,
    experiment_name VARCHAR(100) NOT NULL,
    run_directory TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (zoho_project_id, user_name, block_name, experiment_name)
);

CREATE INDEX IF NOT EXISTS idx_zoho_project_run_dirs_zoho_id ON zoho_project_run_directories(zoho_project_id);
CREATE INDEX IF NOT EXISTS idx_zoho_project_run_dirs_user_name ON zoho_project_run_directories(user_name);
CREATE INDEX IF NOT EXISTS idx_zoho_project_run_dirs_user_id ON zoho_project_run_directories(user_id);

-- Keep updated_at fresh
DROP TRIGGER IF EXISTS update_zoho_project_run_dirs_updated_at ON zoho_project_run_directories;
CREATE TRIGGER update_zoho_project_run_dirs_updated_at
    BEFORE UPDATE ON zoho_project_run_directories
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE zoho_project_run_directories IS 'Stores run directory paths for Zoho projects that are not yet mapped to local projects';
COMMENT ON COLUMN zoho_project_run_directories.zoho_project_id IS 'Zoho project ID from Zoho Projects API';
COMMENT ON COLUMN zoho_project_run_directories.run_directory IS 'Full path to the run directory on remote server (e.g., /CX_RUN_NEW/project/pd/users/username/block/experiment)';

