# Quick Fix: Create Domains Table

## Problem
Error: `relation "domains" does not exist`

## Solution (Local PostgreSQL)

Since you're using local PostgreSQL (not Docker), run these SQL commands:

### Step 1: Connect to your database
```bash
psql -h localhost -U postgres -d asi
```

### Step 2: Run this SQL

```sql
-- Create domains table
CREATE TABLE IF NOT EXISTS domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_domains_code ON domains(code);
CREATE INDEX IF NOT EXISTS idx_domains_is_active ON domains(is_active);

-- Insert design domains
INSERT INTO domains (name, code, description, is_active) VALUES
('Design Verification', 'DV', 'Design Verification (DV) domain for verifying chip designs', true),
('Register Transfer Level', 'RTL', 'RTL (Register Transfer Level) design domain', true),
('Design for Testability', 'DFT', 'DFT (Design for Testability) domain for testability features', true),
('Physical Design', 'PHYSICAL', 'Physical design domain for layout and floorplanning', true),
('Analog Layout', 'ANALOG', 'Analog layout domain for analog circuit design', true)
ON CONFLICT (code) DO NOTHING;

-- Create trigger
DROP TRIGGER IF EXISTS update_domains_updated_at ON domains;
CREATE TRIGGER update_domains_updated_at
    BEFORE UPDATE ON domains
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Add domain_id to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS domain_id INTEGER REFERENCES domains(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_domain_id ON users(domain_id);
```

### Step 3: Verify
```sql
SELECT id, code, name FROM domains;
```

You should see 5 domains.

### Step 4: Restart Backend
Restart your Node.js backend server.

## Alternative: Using PowerShell Script
```powershell
.\backend\scripts\run-domains-migration-local.ps1
```

## Alternative: Using pgAdmin or DBeaver
1. Open pgAdmin or DBeaver
2. Connect to your database (localhost:5432, database: asi)
3. Open a SQL query window
4. Copy and paste the SQL from above
5. Execute


























