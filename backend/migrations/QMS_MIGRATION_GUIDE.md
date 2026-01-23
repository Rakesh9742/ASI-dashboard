# QMS Migration Guide

This guide provides commands to run QMS (Quality Management System) database migrations inside a PostgreSQL container.

## Prerequisites

QMS tables depend on the following tables that must exist first:
- `users` table (from `002_users_and_roles.sql`)
- `projects` table (from `006_create_projects.sql`)
- `blocks` table (from `010_create_physical_design_schema.sql`)

## Migration Order

Run these migrations in the following order:

1. `012_create_qms_schema.sql` - Creates all base QMS tables
2. `015_ensure_qms_columns_exist.sql` - Adds additional columns
3. `016_add_checklist_submission_tracking.sql` - Adds submission tracking
4. `017_fix_qms_audit_log_foreign_keys.sql` - Fixes foreign key constraints
5. `018_update_checklists_comments.sql` - Updates checklists table structure
6. `019_create_qms_history.sql` - Creates history/versioning table

## Commands to Run

### Step 1: Connect to your PostgreSQL container

First, identify your PostgreSQL container name:

```bash
docker ps | grep postgres
```

Then connect to the container (adjust container name if different):

```bash
docker exec -it asi_postgres bash
```

Or directly execute psql commands without entering the container:

```bash
docker exec -i asi_postgres psql -U postgres -d asi
```

### Step 2: Verify Prerequisites

Before running QMS migrations, verify that required tables exist:

```bash
docker exec asi_postgres psql -U postgres -d asi -c "\dt users"
docker exec asi_postgres psql -U postgres -d asi -c "\dt projects"
docker exec asi_postgres psql -U postgres -d asi -c "\dt blocks"
```

If any of these tables don't exist, you need to run their migrations first.

### Step 3: Run QMS Migrations

**Option A: Run migrations one by one (Recommended)**

```bash
# Migration 1: Create QMS schema (base tables)
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/012_create_qms_schema.sql

# Migration 2: Ensure all QMS columns exist
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/015_ensure_qms_columns_exist.sql

# Migration 3: Add checklist submission tracking
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/016_add_checklist_submission_tracking.sql

# Migration 4: Fix QMS audit log foreign keys
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/017_fix_qms_audit_log_foreign_keys.sql

# Migration 5: Update checklists comments
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/018_update_checklists_comments.sql

# Migration 6: Create QMS history table
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/019_create_qms_history.sql
```

**Option B: Run all migrations from inside the container**

If you're already inside the container or prefer to copy files first:

```bash
# Enter the container
docker exec -it asi_postgres bash

# Copy migration files to container (if not mounted)
# You can also mount the migrations directory when starting the container

# Run migrations
psql -U postgres -d asi -f /path/to/012_create_qms_schema.sql
psql -U postgres -d asi -f /path/to/015_ensure_qms_columns_exist.sql
psql -U postgres -d asi -f /path/to/016_add_checklist_submission_tracking.sql
psql -U postgres -d asi -f /path/to/017_fix_qms_audit_log_foreign_keys.sql
psql -U postgres -d asi -f /path/to/018_update_checklists_comments.sql
psql -U postgres -d asi -f /path/to/019_create_qms_history.sql
```

**Option C: Run migrations via docker-compose exec**

If your migrations directory is mounted in docker-compose:

```bash
# Navigate to project root directory
cd /path/to/ASI-dashboard

# Run migrations
docker-compose exec -T postgres psql -U postgres -d asi < backend/migrations/012_create_qms_schema.sql
docker-compose exec -T postgres psql -U postgres -d asi < backend/migrations/015_ensure_qms_columns_exist.sql
docker-compose exec -T postgres psql -U postgres -d asi < backend/migrations/016_add_checklist_submission_tracking.sql
docker-compose exec -T postgres psql -U postgres -d asi < backend/migrations/017_fix_qms_audit_log_foreign_keys.sql
docker-compose exec -T postgres psql -U postgres -d asi < backend/migrations/018_update_checklists_comments.sql
docker-compose exec -T postgres psql -U postgres -d asi < backend/migrations/019_create_qms_history.sql
```

### Step 4: Verify QMS Tables Were Created

After running all migrations, verify that QMS tables exist:

```bash
docker exec asi_postgres psql -U postgres -d asi -c "\dt checklists"
docker exec asi_postgres psql -U postgres -d asi -c "\dt check_items"
docker exec asi_postgres psql -U postgres -d asi -c "\dt c_report_data"
docker exec asi_postgres psql -U postgres -d asi -c "\dt check_item_approvals"
docker exec asi_postgres psql -U postgres -d asi -c "\dt qms_audit_log"
docker exec asi_postgres psql -U postgres -d asi -c "\dt qms_checklist_versions"
```

Or list all QMS-related tables:

```bash
docker exec asi_postgres psql -U postgres -d asi -c "\dt *qms*"
docker exec asi_postgres psql -U postgres -d asi -c "\dt check*"
```

### Step 5: Verify Table Structure

Check the structure of key tables:

```bash
# Check checklists table structure
docker exec asi_postgres psql -U postgres -d asi -c "\d checklists"

# Check check_items table structure
docker exec asi_postgres psql -U postgres -d asi -c "\d check_items"

# Check c_report_data table structure
docker exec asi_postgres psql -U postgres -d asi -c "\d c_report_data"
```

## Troubleshooting

### Error: relation "blocks" does not exist
**Solution:** Run the physical design schema migration first:
```bash
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/010_create_physical_design_schema.sql
```

### Error: relation "users" does not exist
**Solution:** Run the users and roles migration first:
```bash
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/002_users_and_roles.sql
```

### Error: relation "projects" does not exist
**Solution:** Run the projects migration first:
```bash
docker exec -i asi_postgres psql -U postgres -d asi < backend/migrations/006_create_projects.sql
```

### Error: duplicate column / column already exists
**Solution:** This is normal - migrations use `IF NOT EXISTS` and `ADD COLUMN IF NOT EXISTS` clauses, so they're idempotent and safe to run multiple times. The error can be ignored.

### Container name differs
If your PostgreSQL container has a different name, replace `asi_postgres` with your container name in all commands above.

### Database name differs
If your database name is not `asi`, replace `-d asi` with your database name (e.g., `-d your_db_name`) in all commands above.

## Quick Migration Script

If you want to run all QMS migrations at once, create a script:

```bash
#!/bin/bash
# save as: run_qms_migrations.sh

DB_NAME="asi"
CONTAINER_NAME="asi_postgres"
MIGRATIONS_DIR="backend/migrations"

echo "Running QMS migrations..."

docker exec -i $CONTAINER_NAME psql -U postgres -d $DB_NAME < $MIGRATIONS_DIR/012_create_qms_schema.sql
docker exec -i $CONTAINER_NAME psql -U postgres -d $DB_NAME < $MIGRATIONS_DIR/015_ensure_qms_columns_exist.sql
docker exec -i $CONTAINER_NAME psql -U postgres -d $DB_NAME < $MIGRATIONS_DIR/016_add_checklist_submission_tracking.sql
docker exec -i $CONTAINER_NAME psql -U postgres -d $DB_NAME < $MIGRATIONS_DIR/017_fix_qms_audit_log_foreign_keys.sql
docker exec -i $CONTAINER_NAME psql -U postgres -d $DB_NAME < $MIGRATIONS_DIR/018_update_checklists_comments.sql
docker exec -i $CONTAINER_NAME psql -U postgres -d $DB_NAME < $MIGRATIONS_DIR/019_create_qms_history.sql

echo "QMS migrations completed!"
echo "Verifying tables..."
docker exec $CONTAINER_NAME psql -U postgres -d $DB_NAME -c "\dt check*"
docker exec $CONTAINER_NAME psql -U postgres -d $DB_NAME -c "\dt qms*"
```

Make it executable and run:
```bash
chmod +x run_qms_migrations.sh
./run_qms_migrations.sh
```

## What Tables Are Created?

After running all migrations, you'll have these QMS tables:

1. **checklists** - Main checklist definitions linked to blocks
2. **check_items** - Individual check items within checklists
3. **c_report_data** - Report data associated with check items
4. **check_item_approvals** - Approval workflow for check items
5. **qms_audit_log** - Audit trail for QMS actions
6. **qms_checklist_versions** - Version history for rejected checklists

All tables include proper indexes and foreign key constraints for data integrity.

