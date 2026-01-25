# EDA File Upload Process - Complete Flow

## Overview

This document explains what happens when EDA (Electronic Design Automation) files are uploaded and how all fields are added to the database.

---

## 📤 Step 1: File Upload

### Endpoints:
- **Internal**: `POST /api/eda-files/upload` (authenticated users)
- **External API**: `POST /api/eda-files/external/upload` (API key authentication)

### What Happens:
1. File is received and saved to `backend/output/` directory
2. File type is validated (only CSV or JSON allowed)
3. File is processed asynchronously

**File Location**: `backend/src/routes/edaFiles.routes.ts` (line ~674-750)

---

## 🔄 Step 2: File Processing

**Location**: `backend/src/services/fileProcessor.service.ts` → `processFile()` method

### Process:
1. **Extract file metadata**:
   - File name, path, size, type (CSV/JSON)

2. **Extract domain from filename** (if available):
   - Pattern: `{project}.{domain}.{extension}`
   - Example: `saraswathi.pd.json` → domain = "pd"
   - Example: `project_k.physical design.json` → domain = "physical design"

3. **Parse file content**:
   - CSV: Parse rows and columns
   - JSON: Parse JSON structure
   - Extract all stage data (each row = one stage)

---

## 🗄️ Step 3: Database Operations

**Location**: `backend/src/services/fileProcessor.service.ts` → `saveToNewSchema()` method

### 3.1 Domain Processing

**What it does:**
- Finds or creates domain in `domains` table
- Domain name comes from filename (priority) or file data (fallback)

**Database Operations:**
```sql
-- 1. Try to find existing domain by name
SELECT id FROM domains WHERE name = 'Physical Design' AND is_active = true

-- 2. If not found, create new domain
INSERT INTO domains (name, code, description, is_active) 
VALUES ('Physical Design', 'PHYSICAL_DESIGN', 'Domain: Physical Design', true)
RETURNING id
```

**Fields Added to `domains` table:**
- `name` - Domain name (e.g., "Physical Design")
- `code` - Domain code (auto-generated, e.g., "PHYSICAL_DESIGN")
- `description` - Auto-generated description
- `is_active` - Set to `true`

---

### 3.2 Project Detection

**What it does:**
- Finds project by name from file data
- Determines if it's a Zoho project or local project

**Database Operations:**
```sql
-- 1. Check if local project exists
SELECT id FROM projects WHERE LOWER(name) = LOWER('saraswathi')

-- 2. Check if Zoho project (mapped)
SELECT zoho_project_id FROM zoho_projects_mapping 
WHERE LOWER(zoho_project_name) = LOWER('saraswathi')

-- 3. Check if unmapped Zoho project
SELECT DISTINCT zoho_project_id FROM zoho_project_run_directories 
WHERE LOWER(zoho_project_name) = LOWER('saraswathi')
```

**Result:**
- **Local Project**: `projectId` found, `isZohoProject = false`
- **Mapped Zoho Project**: `zohoProjectId` found, `isZohoProject = true`, has `local_project_id`
- **Unmapped Zoho Project**: `zohoProjectId` found, `isZohoProject = true`, no `local_project_id`

**If project doesn't exist (local projects only):**
```sql
-- Create project automatically
INSERT INTO projects (name, created_by) 
VALUES ('saraswathi', 15)
RETURNING id
```

**Fields Added to `projects` table (if created):**
- `name` - Project name from file data
- `created_by` - User ID who uploaded the file

---

### 3.3 Domain-to-Project Linking (Local Projects Only)

**What it does:**
- Links domain to project in `project_domains` table
- **Only for local projects** (Zoho projects don't use this table)

**Database Operations:**
```sql
-- Check if link already exists
SELECT project_id, domain_id FROM project_domains 
WHERE project_id = 1 AND domain_id = 2

-- If not exists, create link
INSERT INTO project_domains (project_id, domain_id) 
VALUES (1, 2)
ON CONFLICT (project_id, domain_id) DO NOTHING
```

**Fields Added to `project_domains` table:**
- `project_id` - Reference to projects table
- `domain_id` - Reference to domains table
- `created_at` - Timestamp (auto)

**Note**: This linking happens automatically during EDA upload for local projects, but the primary domain linking should be done during setup by CAD engineer.

---

### 3.4 Block Validation & Creation

**What it does:**
- Validates that block exists (must be created during setup first)
- For Zoho projects: Creates local block if needed for EDA data storage

**For Local Projects:**
```sql
-- Validate block exists
SELECT id FROM blocks WHERE project_id = 1 AND block_name = 'block3'

-- If not found: ERROR (setup must be run first)
```

**For Zoho Projects:**
```sql
-- 1. Validate block exists in Zoho setup
SELECT DISTINCT block_name FROM zoho_project_run_directories 
WHERE zoho_project_id = '12345' AND block_name = 'block3'

-- 2. Create local block for EDA data storage
INSERT INTO blocks (project_id, block_name) 
VALUES (1, 'block3')
RETURNING id
```

**Fields Added to `blocks` table (Zoho projects only):**
- `project_id` - Reference to local project
- `block_name` - Block name from file data

---

### 3.5 Run (Experiment) Validation & Creation

**What it does:**
- Validates that experiment exists (must be created during setup first)
- For Zoho projects: Creates local run if needed

**For Local Projects:**
```sql
-- Validate run exists
SELECT id FROM runs 
WHERE block_id = 1 AND experiment = 'test_block3' AND COALESCE(rtl_tag, '') = ''

-- If not found: ERROR (setup must be run first)
```

**For Zoho Projects:**
```sql
-- 1. Validate experiment exists in Zoho setup
SELECT id FROM zoho_project_run_directories 
WHERE zoho_project_id = '12345' AND block_name = 'block3' AND experiment_name = 'test_block3'

-- 2. Create or find local run for EDA data storage
SELECT id FROM runs WHERE block_id = 1 AND experiment = 'test_block3'

-- If not found, create:
INSERT INTO runs (block_id, experiment, rtl_tag, user_name, run_directory, last_updated) 
VALUES (1, 'test_block3', 'v1', 'bhavya', '/CX_RUN_NEW/...', CURRENT_TIMESTAMP)
RETURNING id
```

**Fields Added to `runs` table (Zoho projects or updates):**
- `block_id` - Reference to blocks table
- `experiment` - Experiment name from file data
- `rtl_tag` - RTL tag from file data (if provided)
- `user_name` - User name from file data
- `run_directory` - Run directory path from file data
- `last_updated` - Timestamp from file data or current time

---

### 3.6 Stage Data Storage

**What it does:**
- Saves each stage (row) from the file as a separate record
- Each stage contains metrics, timing, constraints, etc.

**Database Operations:**
```sql
-- Insert or update stage
INSERT INTO stages (
  run_id, stage_name, timestamp, stage_directory, run_status, runtime, memory_usage,
  log_errors, log_warnings, log_critical, area, inst_count, utilization,
  metal_density_max, min_pulse_width, min_period, double_switching
) VALUES (
  1, 'syn', '2024-01-15 10:30:00', '/path/to/stage', 'pass', '2h 30m', '8GB',
  '0', '5', '0', '1000000', '50000', '75%', '0.85', '0.5ns', '1.0ns', '0'
)
ON CONFLICT (run_id, stage_name) DO UPDATE SET
  timestamp = EXCLUDED.timestamp,
  run_status = EXCLUDED.run_status,
  -- ... update all fields
RETURNING id
```

**Fields Added to `stages` table:**
- `run_id` - Reference to runs table
- `stage_name` - Stage name (e.g., "syn", "place", "route")
- `timestamp` - Run end time from file
- `stage_directory` - Directory path for this stage
- `run_status` - Status (pass/fail/continue_with_error)
- `runtime` - Runtime duration
- `memory_usage` - Memory used
- `log_errors` - Number of errors
- `log_warnings` - Number of warnings
- `log_critical` - Number of critical issues
- `area` - Area metric
- `inst_count` - Instance count
- `utilization` - Utilization percentage
- `metal_density_max` - Maximum metal density
- `min_pulse_width` - Minimum pulse width
- `min_period` - Minimum period
- `double_switching` - Double switching value

---

### 3.7 Additional Metrics Storage

For each stage, additional related data is saved:

#### A. Timing Metrics
**Table**: `timing_metrics`

**Fields:**
- `stage_id` - Reference to stages table
- `internal_timing` - Internal timing value
- `interface_timing` - Interface timing value
- `max_tran_wns_nvp` - Max transition WNS/NVP
- `max_cap_wns_nvp` - Max capacitance WNS/NVP
- `noise` - Noise value

#### B. Constraint Metrics
**Table**: `constraint_metrics`

**Fields:**
- `stage_id` - Reference to stages table
- `mpw_min_period_double_switching` - MPW min period double switching

#### C. Path Groups
**Table**: `path_groups`

**Fields:**
- `stage_id` - Reference to stages table
- `path_group_name` - Name of path group
- `wns` - Worst Negative Slack
- `tns` - Total Negative Slack
- `fep` - Falling Edge Path
- `rep` - Rising Edge Path

#### D. DRV Violations
**Table**: `drv_violations`

**Fields:**
- `stage_id` - Reference to stages table
- `violation_type` - Type of violation
- `count` - Number of violations
- `worst_value` - Worst violation value

#### E. Power/IR/EM Checks
**Table**: `power_ir_em_checks`

**Fields:**
- `stage_id` - Reference to stages table
- `ir_static` - IR static value
- `em_power_signal` - EM power signal value
- `pv_drc_base_metal_antenna` - PV DRC base metal antenna

#### F. Physical Verification
**Table**: `physical_verification`

**Fields:**
- `stage_id` - Reference to stages table
- `lvs` - LVS status
- `lec` - LEC status

#### G. AI Summary
**Table**: `ai_summaries`

**Fields:**
- `stage_id` - Reference to stages table
- `summary_text` - AI-generated summary text

---

## 📊 Complete Database Schema Flow

```
EDA File Upload
    ↓
┌─────────────────────────────────────────┐
│ 1. domains table                       │
│    - Find or create domain             │
│    - Fields: name, code, description   │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 2. projects table                       │
│    - Find or create project            │
│    - Fields: name, created_by          │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 3. project_domains table (local only)  │
│    - Link domain to project             │
│    - Fields: project_id, domain_id     │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 4. blocks table                         │
│    - Validate or create block           │
│    - Fields: project_id, block_name    │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 5. runs table                           │
│    - Validate or create run             │
│    - Fields: block_id, experiment, etc. │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 6. stages table                        │
│    - Create/update stage records        │
│    - One record per stage in file       │
│    - Fields: run_id, stage_name, etc.  │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 7. Related Metrics Tables               │
│    - timing_metrics                    │
│    - constraint_metrics                 │
│    - path_groups                        │
│    - drv_violations                     │
│    - power_ir_em_checks                 │
│    - physical_verification              │
│    - ai_summaries                       │
└─────────────────────────────────────────┘
```

---

## 🔍 Key Points

### 1. **Validation Requirements**
- Block and experiment **must exist** from setup command first
- For local projects: Must exist in `blocks` and `runs` tables
- For Zoho projects: Must exist in `zoho_project_run_directories` table

### 2. **Automatic Creation**
- **Domain**: Created automatically if not found
- **Project**: Created automatically for local projects if not found
- **Domain-Project Link**: Created automatically for local projects
- **Block/Run**: Created automatically for Zoho projects (for EDA data storage)

### 3. **Zoho Projects Special Handling**
- Zoho projects may not have local `project_id` (if unmapped)
- Local project/block/run records are created automatically for EDA data storage
- Domain linking is skipped for Zoho projects (domains come from EDA files)

### 4. **Stage Data**
- Each row in the file = one stage record
- Multiple stages can be in one file
- Stages are saved with `ON CONFLICT DO UPDATE` (updates if exists)

### 5. **Transaction Safety**
- All database operations happen in a single transaction
- If any step fails, entire operation is rolled back
- File is still saved on disk even if processing fails

---

## 📝 Example Flow

### Scenario: Upload `saraswathi.pd.json` file

1. **File Upload**: File saved to `backend/output/saraswathi.pd_1234567890.json`

2. **Domain Processing**:
   - Extract domain "pd" from filename
   - Find domain: `SELECT id FROM domains WHERE code = 'PD'`
   - Domain ID: 1

3. **Project Processing**:
   - Extract project "saraswathi" from file data
   - Find project: `SELECT id FROM projects WHERE name = 'saraswathi'`
   - Project ID: 1

4. **Domain-Project Linking**:
   - Link: `INSERT INTO project_domains (project_id, domain_id) VALUES (1, 1)`

5. **Block Validation**:
   - Extract block "block3" from file data
   - Validate: `SELECT id FROM blocks WHERE project_id = 1 AND block_name = 'block3'`
   - Block ID: 1

6. **Run Validation**:
   - Extract experiment "test_block3" from file data
   - Validate: `SELECT id FROM runs WHERE block_id = 1 AND experiment = 'test_block3'`
   - Run ID: 1

7. **Stage Storage**:
   - File contains 3 stages: "syn", "place", "route"
   - Create 3 records in `stages` table
   - Create related metrics in timing_metrics, path_groups, etc.

**Result**: All EDA data is now stored in the database and visible in the dashboard!

---

## 🚨 Error Handling

### Common Errors:

1. **"Block does not exist"**
   - **Cause**: Setup command was not run first
   - **Solution**: Run setup command: `setup -proj {project} -domain {domain} -block {block} -exp {experiment}`

2. **"Experiment does not exist"**
   - **Cause**: Setup command was not run first
   - **Solution**: Run setup command with the correct experiment name

3. **"Project not found"**
   - **Cause**: Project doesn't exist (for local projects)
   - **Solution**: Project will be created automatically, or ensure project exists

4. **"File parsing failed"**
   - **Cause**: Invalid file format
   - **Solution**: Check file format (CSV/JSON) and structure

---

## 📚 Related Files

- **Upload Endpoint**: `backend/src/routes/edaFiles.routes.ts`
- **File Processing**: `backend/src/services/fileProcessor.service.ts`
- **Database Schema**: `backend/migrations/008_create_eda_output_files.sql`
- **Documentation**: `EDA_FILES_ZOHO_DOMAIN_MAPPING.md`

