# Zoho Projects to ASI Integration Guide

## Table of Contents

1. [Overview](#overview)
2. [How Zoho Projects Are Added to ASI](#how-zoho-projects-are-added-to-asi)
3. [Project Mapping Process](#project-mapping-process)
4. [Case Study: Mapping Project K](#case-study-mapping-project-k)
5. [EDA Output File Structure](#eda-output-file-structure)
6. [Troubleshooting](#troubleshooting)

---

## Overview

This document explains the complete workflow for integrating Zoho Projects with the ASI Dashboard system. When a project is created in Zoho Projects, it can be:

1. **Displayed** in the ASI Dashboard (read-only from Zoho)
2. **Mapped** to an existing ASI project
3. **Synced** with project members and roles
4. **Marked as "Mapped"** when EDA output data is available

---

## How Zoho Projects Are Added to ASI

### Automatic Discovery

When a user with Zoho integration enabled accesses the Project Management screen:

1. **Zoho Connection Check**
   - The system checks if the user has a valid Zoho OAuth token
   - If connected, Zoho projects are automatically fetched

2. **Project Fetching**
   - Backend calls Zoho Projects API: `GET /restapi/portal/{portalId}/projects/`
   - Projects are retrieved from all accessible Zoho portals
   - Projects are displayed in the Project Management screen with a "Zoho" badge

3. **Display in UI**
   - Zoho projects appear in the projects list with:
     - Cloud icon (☁️) indicating Zoho source
     - "N/A" for Technology (since it's from Zoho)
     - Zoho-specific metadata (owner, created_by, dates, etc.)

### Project States

A Zoho project can be in one of these states:

1. **Unmapped** - Only exists in Zoho, no ASI project linked
2. **Mapped** - Linked to an ASI project via `zoho_projects_mapping` table
3. **Mapped with EDA Data** - Has EDA output files processed, shows "Mapped" badge

---

## Project Mapping Process

### What is Mapping?

Mapping creates a relationship between a Zoho project and an ASI (local) project. This allows:

- Syncing members from Zoho to the ASI project
- Viewing project data from both sources
- Using ASI project ID for EDA file processing
- Accessing project-specific features in ASI

### Mapping Methods

#### Method 1: Using API Endpoint (Recommended)

**Endpoint:** `POST /api/projects/map-zoho-project`

**Authentication:** Required (Bearer token)

**Authorization:** Requires `admin`, `project_manager`, or `lead` role

**Request Body Options:**

**Option A: Map to Existing ASI Project**
```json
{
  "zohoProjectId": "173458000001992000",
  "asiProjectId": 14,
  "portalId": "60021787257",
  "zohoProjectName": "Project K"
}
```

**Option B: Auto-Create ASI Project**
```json
{
  "zohoProjectId": "173458000001992000",
  "zohoProjectName": "Project K",
  "portalId": "60021787257",
  "createIfNotExists": true
}
```

**Example: Using cURL**
```bash
curl -X POST http://localhost:3000/api/projects/map-zoho-project \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "zohoProjectId": "173458000001992000",
    "zohoProjectName": "Project K",
    "createIfNotExists": true
  }'
```

**Response:**
```json
{
  "success": true,
  "message": "Successfully mapped Zoho project \"Project K\" to ASI project \"Project K\"",
  "mapping": {
    "id": 1,
    "zoho_project_id": "173458000001992000",
    "local_project_id": 14,
    "zoho_project_name": "Project K",
    "created_at": "2026-01-22T12:40:40.723Z",
    "updated_at": "2026-01-22T12:40:40.723Z"
  },
  "createdAsiProjectId": 14
}
```

#### Method 2: Using SQL (Direct Database Access)

**Step 1: Find Project IDs**

```sql
-- Find ASI Project ID
SELECT id, name FROM projects WHERE name = 'Project K';

-- Find Zoho Project ID (from Zoho Projects URL or API response)
-- Usually a long numeric string like: 173458000001992000
```

**Step 2: Create the Mapping**

```sql
-- If ASI project exists
INSERT INTO zoho_projects_mapping 
  (zoho_project_id, local_project_id, zoho_project_name)
VALUES 
  ('173458000001992000', 14, 'Project K')
ON CONFLICT (zoho_project_id)
DO UPDATE SET 
  local_project_id = EXCLUDED.local_project_id,
  zoho_project_name = EXCLUDED.zoho_project_name,
  updated_at = CURRENT_TIMESTAMP;
```

**Step 3: Verify the Mapping**

```sql
SELECT 
  zpm.zoho_project_id,
  zpm.zoho_project_name,
  zpm.local_project_id,
  p.name AS asi_project_name,
  zpm.created_at
FROM zoho_projects_mapping zpm
LEFT JOIN projects p ON p.id = zpm.local_project_id
WHERE zpm.zoho_project_id = '173458000001992000';
```

---

## Case Study: Mapping Project K

This section documents the complete process used to successfully map "Project K" from Zoho to ASI.

### Project K Details

- **Zoho Project ID:** `173458000001992000`
- **Zoho Project Name:** `Project K`
- **Zoho Portal ID:** `60021787257`
- **Status:** `active`
- **Start Date:** `01-22-2026`
- **End Date:** `01-31-2026`
- **Owner:** `Bhavya Sree Sreeramdas`

### Step-by-Step Process

#### Step 1: Create ASI Project

Since Project K didn't exist in ASI, we used the `createIfNotExists` option:

**Using SQL:**
```sql
INSERT INTO projects (name, created_by, created_at, updated_at) 
VALUES ('Project K', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) 
RETURNING id, name;
```

**Result:** ASI Project created with ID `14`

#### Step 2: Create Zoho-to-ASI Mapping

**Using SQL:**
```sql
INSERT INTO zoho_projects_mapping 
  (zoho_project_id, local_project_id, zoho_project_name) 
VALUES 
  ('173458000001992000', 14, 'Project K') 
ON CONFLICT (zoho_project_id) 
DO UPDATE SET 
  local_project_id = EXCLUDED.local_project_id,
  zoho_project_name = EXCLUDED.zoho_project_name,
  updated_at = CURRENT_TIMESTAMP 
RETURNING *;
```

**Result:** Mapping created successfully

#### Step 3: Create EDA Output JSON File

To mark the project as "Mapped" (with EDA data), we created an EDA output JSON file:

**File Location:** `backend/output/project k.physical domain.json`

**File Structure:** See [EDA Output File Structure](#eda-output-file-structure) section below.

#### Step 4: Process the EDA Output File

Since the file watcher wasn't running, we used the External API endpoint:

**Endpoint:** `POST /api/eda-files/external/upload`

**Authentication:** API Key (`X-API-Key` header)

**Request:**
```bash
curl -X POST http://localhost:3000/api/eda-files/external/upload \
  -H "X-API-Key: sitedafilesdata" \
  -F "file=@backend/output/project k.physical domain.json"
```

**Response:**
```json
{
  "success": true,
  "message": "File uploaded and processed successfully",
  "data": {
    "fileId": 37,
    "fileName": "project k.physical domain.json",
    "fileSize": 3143,
    "fileType": "json",
    "filePath": "/app/output/project k.physical domain_1769096803836.json",
    "processedAt": "2026-01-22T15:46:44.690Z"
  }
}
```

#### Step 5: Verify Mapping Status

**Check Database:**
```sql
SELECT 
  p.name as project_name,
  b.block_name,
  COUNT(DISTINCT r.id) as run_count,
  COUNT(DISTINCT s.id) as stage_count
FROM projects p
LEFT JOIN blocks b ON b.project_id = p.id
LEFT JOIN runs r ON r.block_id = b.id
LEFT JOIN stages s ON s.run_id = r.id
WHERE LOWER(p.name) = 'project k'
GROUP BY p.name, b.block_name;
```

**Result:**
```
 project_name | block_name | run_count | stage_count 
--------------+------------+-----------+-------------
 Project K    | Karna      |         1 |           1
```

**Verify Mapping Check:**
```sql
SELECT COUNT(DISTINCT p.id) as mapped_count
FROM projects p
INNER JOIN blocks b ON b.project_id = p.id
INNER JOIN runs r ON r.block_id = b.id
INNER JOIN stages s ON s.run_id = r.id
WHERE LOWER(p.name) = 'project k';
```

**Result:** `mapped_count = 1` ✅

### Final Result

After completing all steps:

- ✅ Project K exists in ASI (ID: 14)
- ✅ Zoho project is mapped to ASI project
- ✅ EDA output data is processed
- ✅ Project shows as "Mapped" in the UI
- ✅ Block "Karna" is available in the project
- ✅ 1 run and 1 stage are recorded

---

## EDA Output File Structure

### File Naming Convention

EDA output files should follow this naming pattern:

```
{project_name}.{domain_name}.json
```

**Examples:**
- `ganga.physical domain.json`
- `project k.physical domain.json`
- `project-k.physical domain.json`

**Note:** The domain name is extracted from the filename and used to link the data to a domain in the database.

### JSON File Structure

The JSON file must contain the following structure:

```json
{
  "project": "Project K",
  "block_name": "Karna",
  "experiment": "run1",
  "rtl_tag": "v1",
  "run_directory": "/proj1/pd/users/testcase/rakesh/proj/flow28nm_dashbrd/karna/v1/run1/dashboard",
  "stages": {
    "syn": {
      "stage": "syn",
      "timestamp": "2026-01-22 08:02:39",
      "project": "Project K",
      "block_name": "Karna",
      "experiment": "run1",
      "rtl_tag": "v1",
      "user_name": "rakesh",
      "run_directory": "/proj1/pd/users/testcase/rakesh/proj/flow28nm_dashbrd/karna/v1/run1/dashboard",
      "stage_directory": "/proj1/pd/users/testcase/rakesh/proj/flow28nm_dashbrd/karna/v1/run1/syn",
      "internal_timing_r2r_wns": 8.527,
      "internal_timing_r2r_tns": 8.0,
      "internal_timing_r2r_nvp": -5.2,
      "interface_timing_i2r_wns": 7.463,
      "interface_timing_i2r_tns": 4.0,
      "interface_timing_i2r_nvp": 4.25,
      "interface_timing_r2o_wns": 7.421,
      "interface_timing_r2o_tns": 0.0,
      "interface_timing_r2o_nvp": -5.6,
      "interface_timing_i2o_wns": "-5.0",
      "interface_timing_i2o_tns": "8.4",
      "interface_timing_i2o_nvp": "3.4",
      "hold_wns": "N/A",
      "hold_tns": "N/A",
      "hold_nvp": "N/A",
      "max_tran_wns": "N/A",
      "max_tran_nvp": 0,
      "max_cap_wns": "N/A",
      "max_cap_nvp": 0,
      "max_fanout_wns": "N/A",
      "max_fanout_nvp": 0,
      "noise_violations": "N/A",
      "min_pulse_width": "N/A",
      "min_period": "N/A",
      "double_switching": "N/A",
      "drc_violations": "N/A",
      "congestion_hotspot": "N/A",
      "area": 6303.15,
      "inst_count": 9846,
      "utilization": "N/A",
      "log_errors": 0,
      "log_warnings": 74,
      "run_status": "continue_with_error",
      "runtime": "00:08:15",
      "memory_usage": "1,045M",
      "ai_summary": "",
      "ir_static": "N/A",
      "ir_dynamic": "N/A",
      "em_power": "N/A",
      "em_signal": "N/A",
      "pv_drc_base": "N/A",
      "pv_drc_metal": "N/A",
      "pv_drc_antenna": "N/A",
      "lvs": "N/A",
      "erc": "N/A",
      "r2g_lec": "N/A",
      "g2g_lec": "N/A",
      "setup_path_groups": {
        "all": {
          "wns": 7.421,
          "tns": 0.0,
          "nvp": 0
        },
        "cg_enable_group_clk": {
          "wns": 8.705,
          "tns": 0.0,
          "nvp": 0
        },
        "in2reg": {
          "wns": 7.463,
          "tns": 0.0,
          "nvp": 0
        },
        "reg2out": {
          "wns": 7.421,
          "tns": 0.0,
          "nvp": 0
        },
        "reg2reg": {
          "wns": 8.527,
          "tns": 0.0,
          "nvp": 0
        }
      },
      "drv_violations": {
        "max_transition": {
          "wns": "N/A",
          "tns": "N/A",
          "nvp": 0
        },
        "max_capacitance": {
          "wns": "N/A",
          "tns": "N/A",
          "nvp": 0
        },
        "max_fanout": {
          "wns": "N/A",
          "tns": "N/A",
          "nvp": 0
        }
      },
      "log_critical": 0
    }
  },
  "last_updated": "2026-01-22 16:22:35"
}
```

### Required Fields

**Top Level:**
- `project` (string) - Project name (must match ASI project name)
- `block_name` (string) - Block name
- `experiment` (string) - Experiment name
- `rtl_tag` (string) - RTL tag version
- `run_directory` (string) - Run directory path
- `stages` (object) - Object containing stage data

**Stage Object:**
- `stage` (string) - Stage name (e.g., "syn", "place", "route")
- `timestamp` (string) - Timestamp in format "YYYY-MM-DD HH:MM:SS"
- `project` (string) - Project name (should match top-level project)
- `block_name` (string) - Block name
- `experiment` (string) - Experiment name
- `rtl_tag` (string) - RTL tag
- `user_name` (string) - User who ran the stage
- `run_directory` (string) - Run directory path
- `stage_directory` (string) - Stage-specific directory path

**Timing Metrics (Optional but recommended):**
- `internal_timing_r2r_wns`, `internal_timing_r2r_tns`, `internal_timing_r2r_nvp`
- `interface_timing_i2r_wns`, `interface_timing_i2r_tns`, `interface_timing_i2r_nvp`
- `interface_timing_r2o_wns`, `interface_timing_r2o_tns`, `interface_timing_r2o_nvp`
- `interface_timing_i2o_wns`, `interface_timing_i2o_tns`, `interface_timing_i2o_nvp`
- `hold_wns`, `hold_tns`, `hold_nvp`

**Constraint Metrics (Optional):**
- `max_tran_wns`, `max_tran_nvp`
- `max_cap_wns`, `max_cap_nvp`
- `max_fanout_wns`, `max_fanout_nvp`
- `drc_violations`, `congestion_hotspot`, `noise_violations`
- `min_pulse_width`, `min_period`, `double_switching`

**Area and Utilization (Optional):**
- `area` (number) - Area in square units
- `inst_count` (number) - Instance count
- `utilization` (string) - Utilization percentage

**Logs (Optional):**
- `log_errors` (number) - Error count
- `log_warnings` (number) - Warning count
- `log_critical` (number) - Critical error count

**Run Status (Required):**
- `run_status` (string) - One of: "pass", "fail", "continue_with_error"

**Runtime and Memory (Optional):**
- `runtime` (string) - Runtime duration (e.g., "00:08:15" or "2h 30m")
- `memory_usage` (string) - Memory usage (e.g., "1,045M" or "8.5GB")

### Processing Flow

1. **File Detection**
   - File is placed in `backend/output/` folder
   - File watcher detects new JSON files (if running)
   - Or file is uploaded via API endpoint

2. **File Parsing**
   - JSON file is parsed
   - Project name is extracted from `project` field
   - Domain name is extracted from filename (e.g., "physical domain" from `project k.physical domain.json`)

3. **Database Operations**
   - Project is found or created (by name)
   - Domain is found or created (by name)
   - Block is found or created (by project_id and block_name)
   - Run is found or created (by block_id, experiment, rtl_tag)
   - Stage is created (by run_id and stage name)
   - Timing metrics, constraint metrics, and other data are saved

4. **Mapping Status**
   - After processing, `checkProjectMapping()` function checks if project has:
     - At least one block
     - At least one run
     - At least one stage
   - If all conditions are met, project is marked as "Mapped"

### Example: Project K JSON File

The complete JSON file for Project K is located at:

**File Path:** `backend/output/project k.physical domain.json`

**Key Details:**
- **Project:** "Project K"
- **Block:** "Karna"
- **Experiment:** "run1"
- **RTL Tag:** "v1"
- **Stage:** "syn"
- **Domain:** "Physical Design" (extracted from filename)

---

## Troubleshooting

### Issue: Zoho Projects Not Showing

**Symptoms:** Zoho projects don't appear in Project Management screen

**Solutions:**
1. Check Zoho OAuth connection: `GET /api/zoho/status`
2. Verify OAuth token is valid and not expired
3. Check backend logs for Zoho API errors
4. Ensure user has access to Zoho Projects portal

### Issue: Mapping Not Working

**Symptoms:** Project mapping API returns error

**Solutions:**
1. Verify user role is `admin`, `project_manager`, or `lead`
2. Check that Zoho project ID is correct (long numeric string)
3. Verify ASI project exists: `SELECT id FROM projects WHERE name = 'Project Name';`
4. Check for duplicate mappings: `SELECT * FROM zoho_projects_mapping WHERE zoho_project_id = '...';`

### Issue: Project Not Showing as "Mapped"

**Symptoms:** Project is mapped but doesn't show "Mapped" badge

**Solutions:**
1. Verify EDA output data exists:
   ```sql
   SELECT COUNT(*) FROM blocks b
   INNER JOIN runs r ON r.block_id = b.id
   INNER JOIN stages s ON s.run_id = r.id
   INNER JOIN projects p ON p.id = b.project_id
   WHERE LOWER(p.name) = 'project name';
   ```
2. Check that project name in JSON file matches ASI project name (case-insensitive)
3. Verify EDA file was processed successfully
4. Check backend logs for file processing errors

### Issue: EDA File Not Processing

**Symptoms:** JSON file is in output folder but not processed

**Solutions:**
1. Check file watcher status: `GET /api/eda-files/watcher/status`
2. Verify file format is valid JSON
3. Check file naming convention matches expected pattern
4. Manually process file via API: `POST /api/eda-files/external/upload`
5. Check backend logs for processing errors

### Issue: File Watcher Not Running

**Symptoms:** File watcher fails to start

**Error:** `Failed to start file watcher: Error [ERR_REQUIRE_ESM]`

**Solution:** This is a known issue with chokidar ES module. Use manual file upload via API:
```bash
curl -X POST http://localhost:3000/api/eda-files/external/upload \
  -H "X-API-Key: sitedafilesdata" \
  -F "file=@path/to/file.json"
```

---

## Quick Reference

### Database Tables

**`zoho_projects_mapping`**
- `id` - Primary key
- `zoho_project_id` - Zoho project ID (VARCHAR, UNIQUE)
- `local_project_id` - ASI project ID (INTEGER, FK to projects.id)
- `zoho_project_name` - Zoho project name
- `created_at` - Timestamp
- `updated_at` - Timestamp

**`projects`**
- `id` - Primary key
- `name` - Project name (must match JSON file project name)

**`blocks`**
- `id` - Primary key
- `project_id` - FK to projects.id
- `block_name` - Block name (from JSON)

**`runs`**
- `id` - Primary key
- `block_id` - FK to blocks.id
- `experiment` - Experiment name (from JSON)
- `rtl_tag` - RTL tag (from JSON)

**`stages`**
- `id` - Primary key
- `run_id` - FK to runs.id
- `stage_name` - Stage name (from JSON stages object)

### API Endpoints

- `GET /api/projects` - List all projects (includes Zoho if `includeZoho=true`)
- `POST /api/projects/map-zoho-project` - Map Zoho project to ASI project
- `POST /api/eda-files/external/upload` - Upload and process EDA output file
- `GET /api/zoho/projects` - List Zoho projects
- `GET /api/zoho/status` - Check Zoho connection status

### File Locations

- **EDA Output Folder:** `backend/output/`
- **Example JSON File:** `backend/output/project k.physical domain.json`
- **Reference JSON File:** `backend/output/ganga.physical domain.json`

---

## Summary

The complete workflow for adding a Zoho project to ASI:

1. **Discovery:** Zoho projects are automatically fetched when user has Zoho integration
2. **Mapping:** Create mapping between Zoho project and ASI project (via API or SQL)
3. **EDA Data:** Create and process EDA output JSON file
4. **Verification:** Project shows as "Mapped" when it has blocks, runs, and stages

**Project K Example:**
- ✅ Zoho project discovered automatically
- ✅ ASI project created (ID: 14)
- ✅ Mapping created via SQL
- ✅ EDA JSON file created and processed
- ✅ Project shows as "Mapped" in UI

---

**Last Updated:** 2026-01-22  
**Document Version:** 1.0

