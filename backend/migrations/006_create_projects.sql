-- Projects core tables
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

CREATE INDEX IF NOT EXISTS idx_projects_created_by ON projects(created_by);

-- Link projects to one or more domains
CREATE TABLE IF NOT EXISTS project_domains (
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    domain_id INTEGER REFERENCES domains(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (project_id, domain_id)
);

CREATE INDEX IF NOT EXISTS idx_project_domains_domain_id ON project_domains(domain_id);

-- Keep updated_at fresh
DROP TRIGGER IF EXISTS update_projects_updated_at ON projects;
CREATE TRIGGER update_projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


