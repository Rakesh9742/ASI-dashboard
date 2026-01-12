# QMS Migration Quick Reference

This document lists all QMS-related migrations that need to be run on the staging/production database.

## QMS Migration Files (Run in Order)

### 1. **012_create_qms_schema.sql** ⭐ REQUIRED
   - Creates the base QMS tables:
     - `checklists` - Main checklist table
     - `check_items` - Individual check items within checklists
     - `c_report_data` - Check report data for each check item
     - `check_item_approvals` - Approval tracking for check items
     - `qms_audit_log` - Audit log for QMS actions
   - Creates all indexes and triggers
   - **Status**: Base schema - MUST be run first

### 2. **013_add_check_item_details.sql**
   - Adds detailed columns to `check_items` table:
     - `category`, `sub_category`, `severity`
     - `bronze`, `silver`, `gold` (quality levels)
     - `info`, `evidence`, `auto_approve`, `metadata`
   - Adds columns to `c_report_data`:
     - `result_value`, `signoff_status`, `signoff_by`, `signoff_at`
   - Creates indexes for performance

### 3. **014_add_version_to_check_items.sql**
   - Adds `version` column to `check_items` table
   - Sets default value to 'v1'
   - Creates index on version column

### 4. **015_ensure_qms_columns_exist.sql**
   - Idempotent migration - ensures all QMS columns exist
   - Safe to run multiple times
   - Adds any missing columns from previous migrations
   - Adds additional columns to `c_report_data`:
     - `description`, `fix_details`, `engineer_comments`, `lead_comments`

### 5. **016_add_checklist_submission_tracking.sql**
   - Adds submission tracking to `checklists`:
     - `submitted_by` - User who submitted the checklist
     - `submitted_at` - Timestamp when submitted
   - Creates indexes for performance

### 6. **017_fix_qms_audit_log_foreign_keys.sql**
   - Fixes foreign key constraints on `qms_audit_log`
   - Changes to `ON DELETE SET NULL` to preserve audit logs
   - Allows audit log entries to remain even after checklist/check_item deletion

## Quick Migration Commands

### Run All QMS Migrations (Staging/Production)

```bash
# Connect to database
sudo -u postgres psql -d ASI

# Or with password
PGPASSWORD=your_password psql -U asi_user -d ASI -h localhost
```
docker exec -it asi_postgres psql -U postgres -d ASI

**Run each migration in order:**

```sql
-- Base QMS Schema (MUST RUN FIRST)
\i backend/migrations/012_create_qms_schema.sql

-- Additional QMS Features
\i backend/migrations/013_add_check_item_details.sql
\i backend/migrations/014_add_version_to_check_items.sql
\i backend/migrations/015_ensure_qms_columns_exist.sql
\i backend/migrations/016_add_checklist_submission_tracking.sql
\i backend/migrations/017_fix_qms_audit_log_foreign_keys.sql
```

**Or from command line:**

```bash
cd /path/to/ASI-dashboard

# Run migrations sequentially
sudo -u postgres psql -d ASI -f backend/migrations/012_create_qms_schema.sql
sudo -u postgres psql -d ASI -f backend/migrations/013_add_check_item_details.sql
sudo -u postgres psql -d ASI -f backend/migrations/014_add_version_to_check_items.sql
sudo -u postgres psql -d ASI -f backend/migrations/015_ensure_qms_columns_exist.sql
sudo -u postgres psql -d ASI -f backend/migrations/016_add_checklist_submission_tracking.sql
sudo -u postgres psql -d ASI -f backend/migrations/017_fix_qms_audit_log_foreign_keys.sql

# Run all QMS migrations in order
docker exec -i asi_postgres psql -U postgres -d ASI < 012_create_qms_schema.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 013_add_check_item_details.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 014_add_version_to_check_items.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 015_ensure_qms_columns_exist.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 016_add_checklist_submission_tracking.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 017_fix_qms_audit_log_foreign_keys.sql
```

## Verify QMS Tables

### Check if tables exist:

```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'checklists', 
    'check_items', 
    'c_report_data', 
    'check_item_approvals', 
    'qms_audit_log'
  )
ORDER BY table_name;
```

**Expected result:** 5 tables

### Check table structure:

```sql
-- Checklists table
\d checklists

-- Check items table
\d check_items

-- C Report Data table
\d c_report_data

-- Check Item Approvals table
\d check_item_approvals

-- QMS Audit Log table
\d qms_audit_log
```

### Check table row counts:

```sql
SELECT 
    'checklists' as table_name, COUNT(*) as row_count FROM checklists
UNION ALL
SELECT 
    'check_items', COUNT(*) FROM check_items
UNION ALL
SELECT 
    'c_report_data', COUNT(*) FROM c_report_data
UNION ALL
SELECT 
    'check_item_approvals', COUNT(*) FROM check_item_approvals
UNION ALL
SELECT 
    'qms_audit_log', COUNT(*) FROM qms_audit_log;
```

## Dependencies

### Required Pre-existing Tables:
- `blocks` - Created by migration `010_create_physical_design_schema.sql`
- `milestones` - Created by migration `006_create_projects.sql`
- `users` - Created by migration `002_users_and_roles.sql`
- `projects` - Created by migration `006_create_projects.sql`

### Required Functions:
- `update_updated_at_column()` - Created by migration `001_initial_schema.sql` or `complete_schema.sql`

## Rollback (If Needed)

**⚠️ WARNING**: Rollback will delete all QMS data!

```sql
-- Drop QMS tables in reverse order
DROP TABLE IF EXISTS qms_audit_log CASCADE;
DROP TABLE IF EXISTS check_item_approvals CASCADE;
DROP TABLE IF EXISTS c_report_data CASCADE;
DROP TABLE IF EXISTS check_items CASCADE;
DROP TABLE IF EXISTS checklists CASCADE;
```

## Common Issues

### Issue: "relation blocks does not exist"
**Solution**: Run migration `010_create_physical_design_schema.sql` first

### Issue: "relation milestones does not exist"
**Solution**: Run migration `006_create_projects.sql` first

### Issue: "function update_updated_at_column() does not exist"
**Solution**: Run migration `001_initial_schema.sql` or `complete_schema.sql` first

### Issue: "column already exists" warnings
**Status**: This is OK - migrations use `IF NOT EXISTS` clauses, so they're idempotent

## Testing After Migration

1. **Test table creation:**
   ```sql
   SELECT COUNT(*) FROM information_schema.tables 
   WHERE table_name IN ('checklists', 'check_items', 'c_report_data', 'check_item_approvals', 'qms_audit_log');
   -- Should return 5
   ```

2. **Test insert (basic):**
   ```sql
   -- This requires existing blocks and milestones
   INSERT INTO checklists (block_id, name, status) 
   VALUES (1, 'Test Checklist', 'draft') 
   RETURNING id;
   ```

3. **Check indexes:**
   ```sql
   SELECT indexname FROM pg_indexes 
   WHERE tablename IN ('checklists', 'check_items', 'c_report_data') 
   ORDER BY tablename, indexname;
   ```

## Migration Checklist

Before deploying to production:

- [ ] All prerequisite tables exist (`blocks`, `milestones`, `users`, `projects`)
- [ ] Database backup created
- [ ] Migration `012_create_qms_schema.sql` runs successfully
- [ ] All subsequent QMS migrations run successfully
- [ ] All 5 QMS tables are created
- [ ] Indexes are created correctly
- [ ] Test data can be inserted (optional)
- [ ] Backend application connects successfully
- [ ] QMS endpoints are accessible via API

## Summary

**Total QMS Migrations**: 6 files
**Order**: Must run 012 → 013 → 014 → 015 → 016 → 017
**Key Tables**: checklists, check_items, c_report_data, check_item_approvals, qms_audit_log
**Dependencies**: blocks, milestones, users, projects tables must exist first

 curl.exe -X POST "http://13.204.252.101:3000/api/qms/external/checklists/2/items/upload-report" -H "X-API-Key: sitedafilesdata" -F "check_id=SYN-TL-001" -F "report_path=/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_top/bronze_v1/run2/dashboard/Synthesis_QMS.csv" -F "file=@C:\Users\ganga\OneDrive\Desktop\ASI-Dashboard\ASI-dashboard\Synthesis_QMS_test.csv"


{"success":true,"message":"Report uploaded and processed successfully","data":{"check_item_id":52,"check_id":"SYN-TL-001","report_path":"/app/uploads/qms-reports/qms_report_1767867836725.csv","rows_count":6,"processed_at":"2026-01-08T10:23:56.781Z"}}

docker exec -i asi_postgres psql -U postgres -d ASI < 012_create_qms_schema.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 013_add_check_item_details.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 014_add_version_to_check_items.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 015_ensure_qms_columns_exist.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 016_add_checklist_submission_tracking.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 017_fix_qms_audit_log_foreign_keys.sql
docker exec -i asi_postgres psql -U postgres -d ASI < 018_update_checklists_comments.sql