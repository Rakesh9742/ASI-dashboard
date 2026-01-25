# Setup to EDA File Validation Flow

## Overview

This document describes the complete data flow from setup command execution through EDA file processing, ensuring data integrity by validating EDA files against preconfigured setup data.

---

## Phase 1: Setup Command Execution

### 1.1 User Runs Setup Command

**Command Format:**
```bash
setup -proj {projectName} -domain {domainCode} -block {blockName} -exp {experimentName}
```

**Example:**
```bash
setup -proj saraswathi -domain pd -block block3 -exp testingfor_server
```

### 1.2 Data Captured During Setup

The system captures and stores the following information:

| Field | Source | Storage Location |
|-------|--------|------------------|
| **Project Name** | Command parameter (`-proj`) | `projects` table |
| **Domain Code** | Command parameter (`-domain`) | `domains` table → linked via `project_domains` |
| **Block Name** | Command parameter (`-block`) | `blocks` table |
| **Experiment Name** | Command parameter (`-exp`) | `runs` table |
| **Run Directory** | Fetched from remote server | `runs.run_directory` |
| **Username** | From SSH session (`whoami`) | `runs.user_name` |

### 1.3 Database Storage (Backend: `save-run-directory` endpoint)

**Step 1: Find or Create Project**
```sql
SELECT id FROM projects WHERE LOWER(name) = LOWER($1)
-- If not found, project must exist (error if missing)
```

**Step 2: Link Domain to Project**
```sql
-- Find domain by code
SELECT id FROM domains WHERE code = $1 AND is_active = true

-- Link domain to project
INSERT INTO project_domains (project_id, domain_id) 
VALUES ($1, $2) 
ON CONFLICT (project_id, domain_id) DO NOTHING
```

**Step 3: Create or Find Block**
```sql
-- Check if block exists
SELECT id FROM blocks WHERE project_id = $1 AND block_name = $2

-- If not exists, create it
INSERT INTO blocks (project_id, block_name) 
VALUES ($1, $2) 
RETURNING id
```

**Step 4: Create or Find Run (Experiment)**
```sql
-- Check if run exists (with empty rtl_tag from setup)
SELECT id FROM runs 
WHERE block_id = $1 
  AND experiment = $2 
  AND COALESCE(rtl_tag, '') = ''

-- If not exists, create it
INSERT INTO runs (block_id, experiment, rtl_tag, user_name, run_directory, last_updated) 
VALUES ($1, $2, '', $3, $4, CURRENT_TIMESTAMP) 
RETURNING id
```

### 1.4 Setup Data Summary

After successful setup, the following records exist in the database:

```
projects table:
  - id: 123
  - name: "saraswathi"

project_domains table:
  - project_id: 123
  - domain_id: 4 (PD domain)

blocks table:
  - id: 456
  - project_id: 123
  - block_name: "block3"

runs table:
  - id: 789
  - block_id: 456
  - experiment: "testingfor_server"
  - rtl_tag: "" (empty from setup)
  - user_name: "bhavya"
  - run_directory: "/CX_RUN_NEW/saraswathi/pd/users/bhavya/block3/testingfor_server"
```

---

## Phase 2: EDA File Processing

### 2.1 EDA File Upload/Detection

EDA files can be uploaded via:
- File watcher (automatic detection in `backend/output/` folder)
- Manual upload via API endpoint
- External API upload

### 2.2 Data Extraction from EDA Files

**From Filename:**
- Domain name extracted from filename pattern: `{project}.{domain}.json` or `{project}_{domain}.json`
- Example: `saraswathi.physical domain.json` → domain = "physical domain"

**From File Content (CSV or JSON):**

| Field | CSV Column Names | JSON Field Names |
|-------|------------------|------------------|
| **Project Name** | `project`, `project_name`, `Project`, `Project Name` | `project`, `project_name` |
| **Domain Name** | `domain`, `domain_name`, `Domain`, `PD` | `domain`, `domain_name` |
| **Block Name** | `block_name`, `block`, `Block Name` | `block_name`, `block` |
| **Experiment** | `experiment`, `Experiment` | `experiment` |
| **RTL Tag** | `rtl_tag`, `RTL Tag`, `rtl tag` | `rtl_tag` |

### 2.3 Validation Process (Backend: `saveToNewSchema` method)

**Step 1: Extract and Normalize Data**
```typescript
// Extract from file content
const projectName = firstRow.project_name;  // From file content
const domainName = filenameDomain || firstRow.domain_name;  // Filename takes priority
const blockName = firstRow.block_name;  // From file content
const experiment = firstRow.experiment;  // From file content
const rtlTag = firstRow.rtl_tag || '';  // From file content (default empty)
```

**Step 2: Find Project**
```sql
SELECT id FROM projects WHERE LOWER(name) = LOWER($1)
-- If not found, create project (but this should rarely happen)
```

**Step 3: Validate Block Exists (CRITICAL VALIDATION)**
```sql
SELECT id FROM blocks 
WHERE project_id = $1 AND block_name = $2
```

**Validation Result:**
- ✅ **If block exists**: Continue to next step
- ❌ **If block does NOT exist**: 
  ```typescript
  throw new Error(
    `Block "${blockName}" does not exist for project "${projectName}". ` +
    `Please run the setup command first with: setup -proj ${projectName} -domain <domain> -block ${blockName} -exp <experiment>`
  );
  ```

**Step 4: Validate Experiment Exists (CRITICAL VALIDATION)**
```sql
SELECT id FROM runs 
WHERE block_id = $1 
  AND experiment = $2 
  AND COALESCE(rtl_tag, '') = $3
```

**Validation Result:**
- ✅ **If experiment exists**: Continue to process EDA data
- ❌ **If experiment does NOT exist**: 
  ```typescript
  throw new Error(
    `Experiment "${experiment}" does not exist for block "${blockName}" in project "${projectName}". ` +
    `Please run the setup command first with: setup -proj ${projectName} -domain <domain> -block ${blockName} -exp ${experiment}`
  );
  ```

**Step 5: Process and Save EDA Data**

Only if both validations pass:
- Save stage data to `stages` table
- Save timing metrics to `stage_timing_metrics` table
- Save constraint metrics to `stage_constraint_metrics` table
- Save path groups to `path_groups` table
- Save DRV violations to `drv_violations` table
- Save power/IR/EM checks to `power_ir_em_checks` table
- Save physical verification to `physical_verification` table
- Save AI summaries to `ai_summaries` table

---

## Phase 3: Data Matching Rules

### 3.1 Matching Criteria

For EDA files to be processed, they must match setup data on:

1. **Project Name** (case-insensitive)
   - EDA file: `"saraswathi"` or `"Saraswathi"`
   - Setup: `"saraswathi"`
   - ✅ Match

2. **Block Name** (exact match, case-sensitive)
   - EDA file: `"block3"`
   - Setup: `"block3"`
   - ✅ Match
   - ❌ `"Block3"` or `"block_3"` would NOT match

3. **Experiment Name** (exact match, case-sensitive)
   - EDA file: `"testingfor_server"`
   - Setup: `"testingfor_server"`
   - ✅ Match
   - ❌ `"TestingFor_Server"` would NOT match

4. **RTL Tag** (handled specially)
   - Setup creates run with `rtl_tag = ''` (empty string)
   - EDA file may have `rtl_tag = ''` or specific version like `"v1.0"`
   - System matches using: `COALESCE(rtl_tag, '') = $3`
   - This allows matching empty rtl_tag from setup with empty rtl_tag from EDA file

### 3.2 Domain Validation

**Note:** Currently, domain is linked during setup but not strictly validated during EDA processing. The domain from the EDA file is used to link to the project if not already linked, but it doesn't block processing if it doesn't match.

**Future Enhancement:** Could add strict domain validation if needed.

---

## Phase 4: Error Handling

### 4.1 Setup Not Run First

**Error Message:**
```
Block "block3" does not exist for project "saraswathi". 
Please run the setup command first with: setup -proj saraswathi -domain <domain> -block block3 -exp <experiment>
```

**User Action:**
1. Run setup command with correct parameters
2. Verify setup succeeded
3. Retry EDA file upload

### 4.2 Experiment Mismatch

**Error Message:**
```
Experiment "wrong_experiment" does not exist for block "block3" in project "saraswathi". 
Please run the setup command first with: setup -proj saraswathi -domain <domain> -block block3 -exp wrong_experiment
```

**User Action:**
1. Check experiment name in EDA file matches setup
2. Either fix EDA file or run setup with correct experiment name
3. Retry EDA file upload

---

## Phase 5: Dashboard Display

### 5.1 Data Flow to Dashboard

Once EDA data is successfully validated and saved:

1. **Dashboard loads blocks and experiments** from `blocks` and `runs` tables
2. **User selects block and experiment** from dropdowns
3. **System queries stages** for the selected run:
   ```sql
   SELECT * FROM stages s
   JOIN runs r ON s.run_id = r.id
   JOIN blocks b ON r.block_id = b.id
   JOIN projects p ON b.project_id = p.id
   WHERE p.name = $1 
     AND b.block_name = $2 
     AND r.experiment = $3
   ```
4. **Metrics are displayed** from the latest stage data

### 5.2 Data Integrity Guarantee

Because of the validation:
- ✅ Only EDA files matching setup data are processed
- ✅ Dashboard only shows data for blocks/experiments that were set up
- ✅ No orphaned data (blocks/experiments without setup)
- ✅ Clear error messages guide users to fix issues

---

## Summary

### Setup Phase (Pre-Configuration)
1. User runs setup command
2. System captures: project, domain, block, experiment
3. System stores in: `projects`, `project_domains`, `blocks`, `runs` tables
4. Setup data becomes the "source of truth"

### EDA Processing Phase (Validation)
1. EDA file is uploaded/detected
2. System extracts: project, domain, block, experiment from file
3. System validates:
   - ✅ Block exists in `blocks` table for the project
   - ✅ Experiment exists in `runs` table for the block
4. If validation passes: Process and save EDA data
5. If validation fails: Reject with clear error message

### Result
- **Data Integrity**: Only matching EDA files are processed
- **User Guidance**: Clear error messages when validation fails
- **Dashboard Accuracy**: Only shows data for properly configured blocks/experiments

---

## Database Schema Reference

### Key Tables

**`projects`**
- `id` (PK)
- `name` (UNIQUE)

**`project_domains`**
- `project_id` (FK → projects.id)
- `domain_id` (FK → domains.id)
- Composite PK: (project_id, domain_id)

**`blocks`**
- `id` (PK)
- `project_id` (FK → projects.id)
- `block_name`
- UNIQUE: (project_id, block_name)

**`runs`**
- `id` (PK)
- `block_id` (FK → blocks.id)
- `experiment`
- `rtl_tag` (default: empty string from setup)
- `user_name`
- `run_directory`
- UNIQUE: (block_id, experiment, rtl_tag)

**`stages`**
- `id` (PK
- `run_id` (FK → runs.id)
- `stage_name`
- UNIQUE: (run_id, stage_name)

---

## API Endpoints

### Setup Phase
- **POST** `/api/projects/save-run-directory`
  - Body: `{ projectName, blockName, experimentName, runDirectory, username, domainCode, zohoProjectId? }`
  - Creates: blocks, runs, links domain to project

### EDA Processing
- **POST** `/api/eda-files/external/upload` (with API key)
- **POST** `/api/eda-files/upload` (authenticated)
- File watcher automatically processes files in `backend/output/` folder

---

## Testing Checklist

- [ ] Setup command creates block and experiment records
- [ ] Domain is linked to project during setup
- [ ] EDA file with matching project/block/experiment processes successfully
- [ ] EDA file with non-existent block is rejected with clear error
- [ ] EDA file with non-existent experiment is rejected with clear error
- [ ] Dashboard shows only blocks/experiments from setup
- [ ] Metrics display correctly for validated EDA data

