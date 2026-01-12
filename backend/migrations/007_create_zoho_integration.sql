-- Zoho Projects Integration
-- Stores OAuth tokens for Zoho Projects API access

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

CREATE INDEX IF NOT EXISTS idx_zoho_tokens_user_id ON zoho_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_zoho_tokens_expires_at ON zoho_tokens(expires_at);

-- Keep updated_at fresh
DROP TRIGGER IF EXISTS update_zoho_tokens_updated_at ON zoho_tokens;
CREATE TRIGGER update_zoho_tokens_updated_at
    BEFORE UPDATE ON zoho_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

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

CREATE INDEX IF NOT EXISTS idx_zoho_projects_mapping_local_id ON zoho_projects_mapping(local_project_id);
CREATE INDEX IF NOT EXISTS idx_zoho_projects_mapping_zoho_id ON zoho_projects_mapping(zoho_project_id);

DROP TRIGGER IF EXISTS update_zoho_projects_mapping_updated_at ON zoho_projects_mapping;
CREATE TRIGGER update_zoho_projects_mapping_updated_at
    BEFORE UPDATE ON zoho_projects_mapping
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();












