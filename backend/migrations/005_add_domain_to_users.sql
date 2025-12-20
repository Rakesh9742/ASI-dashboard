-- Add domain_id column to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS domain_id INTEGER REFERENCES domains(id) ON DELETE SET NULL;

-- Create index for domain_id
CREATE INDEX IF NOT EXISTS idx_users_domain_id ON users(domain_id);




