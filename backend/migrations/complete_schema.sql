
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

-- ============================================================================
-- 9. CREATE ZOHO INTEGRATION TABLES
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
-- Default Admin Credentials:
--   Username: admin1
--   Email: admin@1.com
--   Password: test@1234
-- 
-- Note: Change the admin password immediately after first login!
-- 
-- ============================================================================

