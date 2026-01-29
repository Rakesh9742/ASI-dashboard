-- Add domain_id to runs so we can track which domain incoming EDA files belong to
-- Domain comes from filename (e.g. project.domain.json) or from file data (domain_name)
ALTER TABLE runs
  ADD COLUMN IF NOT EXISTS domain_id INTEGER REFERENCES domains(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_runs_domain_id ON runs(domain_id) WHERE domain_id IS NOT NULL;

COMMENT ON COLUMN runs.domain_id IS 'Domain this run belongs to (set when EDA file is uploaded; from filename or file domain_name)';
