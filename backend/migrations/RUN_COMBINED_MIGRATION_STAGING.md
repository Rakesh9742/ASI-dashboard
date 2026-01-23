# Running Combined QMS and Roles Migration on Staging Server

This guide explains how to run the `combined_qms_and_roles_migration.sql` script on a staging server with Docker PostgreSQL.

## Prerequisites

1. **Access to staging server** (SSH or direct access)
2. **Docker PostgreSQL container running** (typically named `asi_postgres` or similar)
3. **The migration file** (`combined_qms_and_roles_migration.sql`)

## Step 1: Identify Your Docker PostgreSQL Container

First, find the name of your PostgreSQL container:

```bash
# List running containers
docker ps

# Or list all containers (including stopped)
docker ps -a
```

Look for a container with a PostgreSQL image. Common names:
- `asi_postgres`
- `postgres`
- `asi-dashboard_postgres`
- `asi-dashboard-postgres-1` (if using docker-compose)

**Note the container name** - you'll need it in the next steps.

## Step 2: Copy Migration File to Staging Server

### Option A: If you have SSH access

From your local machine:

```bash
# Copy the migration file to staging server
scp backend/migrations/combined_qms_and_roles_migration.sql user@staging-server:/tmp/

# Or if using a specific key
scp -i ~/.ssh/your-key.pem backend/migrations/combined_qms_and_roles_migration.sql user@staging-server:/tmp/
```

### Option B: If you're already on the staging server

Upload the file via:
- SCP from your local machine
- Git pull (if the file is in your repository)
- Manual copy/paste (for small files)

## Step 3: Verify Database Connection

Test that you can connect to the database:

```bash
# Replace 'asi_postgres' with your actual container name
docker exec -it asi_postgres psql -U postgres -d ASI -c "SELECT version();"
```

If this works, you're ready to proceed. If not, check:
- Container is running: `docker ps`
- Database name is correct (usually `ASI`)
- User credentials are correct (usually `postgres`)

## Step 4: Run the Migration

### Method 1: Using docker exec with file input (Recommended)

```bash
# Replace 'asi_postgres' with your actual container name
# Replace '/tmp/combined_qms_and_roles_migration.sql' with your file path

docker exec -i asi_postgres psql -U postgres -d ASI < /tmp/combined_qms_and_roles_migration.sql
```

**Or if the file is on your local machine and you want to pipe it:**

```bash
# From your local machine (PowerShell on Windows)
Get-Content backend\migrations\combined_qms_and_roles_migration.sql | docker exec -i asi_postgres psql -U postgres -d ASI

# From your local machine (Bash/Linux/Mac)
cat backend/migrations/combined_qms_and_roles_migration.sql | docker exec -i asi_postgres psql -U postgres -d ASI
```

### Method 2: Copy file into container, then run

```bash
# Copy file into container
docker cp /tmp/combined_qms_and_roles_migration.sql asi_postgres:/tmp/

# Execute inside container
docker exec -i asi_postgres psql -U postgres -d ASI -f /tmp/combined_qms_and_roles_migration.sql
```

### Method 3: Interactive execution

```bash
# Enter the container
docker exec -it asi_postgres psql -U postgres -d ASI

# Then inside psql, run:
\i /tmp/combined_qms_and_roles_migration.sql

# Or paste the SQL content directly
```

## Step 5: Verify Migration Success

After running the migration, verify that all tables and roles were created:

```bash
# Connect to database
docker exec -it asi_postgres psql -U postgres -d ASI

# Check QMS tables exist
\dt checklists
\dt check_items
\dt c_report_data
\dt check_item_approvals
\dt qms_audit_log
\dt qms_checklist_versions
\dt user_projects

# Check if management role exists
SELECT enumlabel FROM pg_enum 
WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'user_role')
ORDER BY enumlabel;

# Check if cad_engineer role exists
SELECT enumlabel FROM pg_enum 
WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'user_role')
AND enumlabel = 'cad_engineer';

# Check user_projects table has role column
\d user_projects

# Exit psql
\q
```

Expected output:
- All QMS tables should exist
- `user_role` enum should include: `admin`, `project_manager`, `lead`, `engineer`, `customer`, `management`, `cad_engineer`
- `user_projects` table should have a `role` column

## Step 6: Check for Errors

If the migration fails, check the error messages:

```bash
# Run migration with verbose output
docker exec -i asi_postgres psql -U postgres -d ASI -v ON_ERROR_STOP=1 < /tmp/combined_qms_and_roles_migration.sql
```

Common issues and fixes:

### Issue 1: "relation already exists"
**Solution**: The migration uses `CREATE TABLE IF NOT EXISTS`, so this is usually safe to ignore. However, if you see errors about constraints, you may need to drop existing tables first (be careful - this will delete data!).

### Issue 2: "enum value already exists"
**Solution**: The migration checks if enum values exist before adding them, so this should be safe. If you see this error, the role already exists, which is fine.

### Issue 3: "permission denied"
**Solution**: Make sure you're using the correct database user (usually `postgres`). If using a different user, ensure it has CREATE privileges.

### Issue 4: "column already exists"
**Solution**: The migration uses `ADD COLUMN IF NOT EXISTS`, so this should be safe. If you see this, the column already exists, which is fine.

## Step 7: Restart Backend Service (if needed)

After running the migration, restart your backend service to ensure it picks up the new schema:

```bash
# If using Docker
docker restart asi_backend

# If using docker-compose
docker-compose restart backend

# If using systemd
sudo systemctl restart asi-backend

# If using PM2
pm2 restart asi-backend
```

## Complete Example (One-liner)

If you have SSH access and the file is in your local repository:

```bash
# From your local machine (PowerShell)
Get-Content backend\migrations\combined_qms_and_roles_migration.sql | ssh user@staging-server "docker exec -i asi_postgres psql -U postgres -d ASI"

# From your local machine (Bash)
cat backend/migrations/combined_qms_and_roles_migration.sql | ssh user@staging-server "docker exec -i asi_postgres psql -U postgres -d ASI"
```

## What This Migration Does

This combined migration includes:

1. **QMS Schema Creation**:
   - `checklists` table
   - `check_items` table
   - `c_report_data` table
   - `check_item_approvals` table
   - `qms_audit_log` table
   - `qms_checklist_versions` table

2. **User Projects Table**:
   - `user_projects` table with `role` column for project-specific roles

3. **New Roles**:
   - `management` role (for management view access)
   - `cad_engineer` role (for CAD engineer view access)

4. **Indexes and Triggers**: All necessary indexes and update triggers

## Rollback (if needed)

⚠️ **Warning**: This migration creates new tables and adds enum values. Rolling back requires manual steps:

```sql
-- Drop QMS tables (WILL DELETE DATA!)
DROP TABLE IF EXISTS qms_checklist_versions CASCADE;
DROP TABLE IF EXISTS qms_audit_log CASCADE;
DROP TABLE IF EXISTS check_item_approvals CASCADE;
DROP TABLE IF EXISTS c_report_data CASCADE;
DROP TABLE IF EXISTS check_items CASCADE;
DROP TABLE IF EXISTS checklists CASCADE;

-- Note: Enum values cannot be easily removed in PostgreSQL
-- The management and cad_engineer enum values will remain
-- but won't cause issues if not used
```

## Troubleshooting

### Container not found
```bash
# List all containers
docker ps -a

# Start container if stopped
docker start asi_postgres
```

### Database connection refused
```bash
# Check if PostgreSQL is accepting connections
docker exec asi_postgres pg_isready -U postgres
```

### File not found
```bash
# Verify file exists
docker exec asi_postgres ls -la /tmp/combined_qms_and_roles_migration.sql
```

## Support

If you encounter issues:
1. Check Docker logs: `docker logs asi_postgres`
2. Verify database is running: `docker ps`
3. Test connection: `docker exec -it asi_postgres psql -U postgres -d ASI -c "SELECT 1;"`
4. Review error messages carefully - the migration is idempotent (safe to run multiple times)

