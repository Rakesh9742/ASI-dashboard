# Fix: Domains Table Does Not Exist

## Error
```
Error: relation "domains" does not exist
```

## Solution

The `domains` table hasn't been created in your database yet. Run these migrations:

### Step 1: Start Docker Desktop
Make sure Docker Desktop is running.

### Step 2: Check Container is Running
```powershell
docker ps
```
You should see `asi_postgres` container running.

### Step 3: Run Migrations

**Option A: Using PowerShell (from project root)**
```powershell
# Navigate to project root
cd "C:\Users\2020r\ASI dashboard"

# Run migration 1: Create domains table
Get-Content backend\migrations\004_add_domains_table.sql | docker exec -i asi_postgres psql -U postgres -d ASI

# Run migration 2: Add domain_id to users
Get-Content backend\migrations\005_add_domain_to_users.sql | docker exec -i asi_postgres psql -U postgres -d ASI
```

**Option B: Using the script**
```powershell
cd "C:\Users\2020r\ASI dashboard"
.\backend\scripts\run-domains-migration.ps1
```

**Option C: Manual SQL (if Docker not available)**
Connect to your PostgreSQL database and run:
```sql
-- From 004_add_domains_table.sql
CREATE TABLE IF NOT EXISTS domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_domains_code ON domains(code);
CREATE INDEX IF NOT EXISTS idx_domains_is_active ON domains(is_active);

INSERT INTO domains (name, code, description, is_active) VALUES
('Design Verification', 'DV', 'Design Verification (DV) domain for verifying chip designs', true),
('Register Transfer Level', 'RTL', 'RTL (Register Transfer Level) design domain', true),
('Design for Testability', 'DFT', 'DFT (Design for Testability) domain for testability features', true),
('Physical Design', 'PHYSICAL', 'Physical design domain for layout and floorplanning', true),
('Analog Layout', 'ANALOG', 'Analog layout domain for analog circuit design', true)
ON CONFLICT (code) DO NOTHING;

-- From 005_add_domain_to_users.sql
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS domain_id INTEGER REFERENCES domains(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_domain_id ON users(domain_id);
```

### Step 4: Verify
```powershell
docker exec -i asi_postgres psql -U postgres -d ASI -c "SELECT id, code, name FROM domains;"
```

You should see 5 domains:
- DV - Design Verification
- RTL - Register Transfer Level
- DFT - Design for Testability
- PHYSICAL - Physical Design
- ANALOG - Analog Layout

### Step 5: Restart Backend
After running migrations, restart your backend server to clear any cached errors.

## After Fix
- Domain dropdown in Add User dialog will show all domains
- Users can be assigned to domains
- User list will display domain information



























