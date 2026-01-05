# EC2 Production: Add Physical Design Schema

This guide will help you add the missing `blocks` table and Physical Design schema to your EC2 PostgreSQL database.

## Error You're Fixing
```
❌ relation "blocks" does not exist
```

## Quick Fix - Run on EC2

### Option 1: SSH to EC2 and Run Directly (Recommended)

1. **SSH into your EC2 instance:**
   ```bash
   ssh ec2-user@YOUR_EC2_IP
   # or
   ssh ubuntu@YOUR_EC2_IP
   ```

2. **Upload the SQL file to EC2:**
   ```bash
   # From your local machine
   scp backend/migrations/EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql ec2-user@YOUR_EC2_IP:/tmp/
   ```

3. **Run the migration on EC2:**
   ```bash
   # Connect to PostgreSQL and run the migration
   sudo -u postgres psql -d ASI -f /tmp/EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql
   ```

   Or if you need to specify password:
   ```bash
   PGPASSWORD=your_password psql -U postgres -h localhost -d ASI -f /tmp/EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql
   ```

### Option 2: Run from Local Machine

If you have PostgreSQL client installed locally and can connect to EC2:

```bash
# From your local machine (project root)
psql -U postgres -h YOUR_EC2_IP -d ASI -f backend/migrations/EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql
```

You'll be prompted for the PostgreSQL password.

### Option 3: Copy-Paste SQL (If file transfer is difficult)

1. **SSH into EC2:**
   ```bash
   ssh ec2-user@YOUR_EC2_IP
   ```

2. **Connect to PostgreSQL:**
   ```bash
   sudo -u postgres psql -d ASI
   ```

3. **Copy the entire contents of `EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql` and paste into the psql prompt**

4. **Press Enter to execute**

## Verify Migration Success

After running the migration, verify the tables were created:

```sql
-- Connect to database
sudo -u postgres psql -d ASI

-- Check if blocks table exists
\dt blocks

-- List all Physical Design tables
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'blocks', 'runs', 'stages', 'stage_timing_metrics', 
    'stage_constraint_metrics', 'path_groups', 'drv_violations',
    'power_ir_em_checks', 'physical_verification', 'ai_summaries'
  )
ORDER BY table_name;
```

You should see all 10 tables listed.

## What This Migration Creates

The migration creates the following tables:

1. **blocks** - Blocks belong to projects
2. **runs** - Runs (experiments) belong to blocks
3. **stages** - Stages belong to runs
4. **stage_timing_metrics** - Timing metrics for each stage
5. **stage_constraint_metrics** - Constraint metrics for each stage
6. **path_groups** - Setup/hold path groups
7. **drv_violations** - Design rule violations
8. **power_ir_em_checks** - Power, IR, EM checks
9. **physical_verification** - Physical verification results
10. **ai_summaries** - AI-generated summaries for stages

Plus all necessary indexes and triggers.

## Prerequisites

- The `projects` table must exist (created by migration `006_create_projects.sql`)
- The `update_updated_at_column()` function will be created if it doesn't exist

## Troubleshooting

### Error: "projects table does not exist"
Run the projects migration first:
```bash
sudo -u postgres psql -d ASI -f /path/to/006_create_projects.sql
```

### Error: "permission denied"
Make sure you're running as the postgres user or have sudo access:
```bash
sudo -u postgres psql -d ASI -f /tmp/EC2_ADD_PHYSICAL_DESIGN_SCHEMA.sql
```

### Error: "database ASI does not exist"
Create the database first:
```bash
sudo -u postgres createdb ASI
```

## After Migration

Once the migration is complete, restart your backend service:

```bash
# If using systemd
sudo systemctl restart asi-backend

# If using PM2
pm2 restart asi-backend

# If using Docker
docker restart asi_backend
```

The file processing should now work without the "blocks does not exist" error!


