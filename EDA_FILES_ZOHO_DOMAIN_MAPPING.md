# EDA Files Upload: Zoho Project Domain Mapping & Dashboard Display

## Overview

This document explains how EDA files are uploaded, how domains are extracted and mapped to Zoho projects, and how the dashboard view displays this data.

---

## Flow Diagram

```
EDA File Upload
    ↓
Extract Domain from Filename or File Data
    ↓
Find/Create Domain in domains table
    ↓
Find Project (Check if Zoho project)
    ↓
Link Domain to Project (for local projects only)
    ↓
Validate Block/Experiment against Setup Data
    ↓
Save EDA Data to stages table
    ↓
Dashboard View: Load EDA Files → Group by Project/Domain/Block/Experiment/Stage
```

---

## Step 1: EDA File Upload

### File Upload Endpoint
**Location:** `backend/src/routes/edaFiles.routes.ts`

**Endpoints:**
- `POST /api/eda-files/upload` - Regular upload (authenticated users)
- `POST /api/eda-files/external/upload` - External API upload (API key)

### File Processing
**Location:** `backend/src/services/fileProcessor.service.ts`

When a file is uploaded:
1. File is saved to `backend/output/` directory
2. File is processed based on type (CSV or JSON)
3. Data is extracted and normalized

---

## Step 2: Domain Extraction

### Domain Sources (Priority Order)

#### 1. From Filename
**Location:** `backend/src/services/fileProcessor.service.ts` (line ~1594)

The system tries to extract domain from filename:
- Pattern: `{project}.{domain}.{extension}`
- Example: `saraswathi.physical design.json` → domain = "physical design"
- Example: `project_k.pd.json` → domain = "pd"

```typescript
private extractDomainFromFilename(fileName: string): string | null {
  // Try pattern: project.domain.extension
  const match = fileName.match(/^[^.]+\.([^.]+)\.(csv|json)$/i);
  if (match) {
    return match[1]; // Return domain part
  }
  return null;
}
```

#### 2. From File Data
**Location:** `backend/src/services/fileProcessor.service.ts` (line ~815)

If domain is not in filename, it's extracted from the EDA file data:
- JSON files: `domain_name` field
- CSV files: `domain` column

**Priority:**
1. Filename domain (if extracted)
2. File data domain (if filename domain not found)

---

## Step 3: Domain Creation/Lookup

**Location:** `backend/src/services/fileProcessor.service.ts` (line ~814-852)

### Process:

```typescript
// 1. Normalize domain name
const normalizedDomainName = domainName.trim();
const normalizedForMatching = this.normalizeDomainName(normalizedDomainName);

// 2. Try to find existing domain
domainId = await this.findDomainId(normalizedDomainName);

// 3. If not found, check for similar domain (case-insensitive)
if (!domainId) {
  const similarDomainCheck = await client.query(
    'SELECT id FROM domains WHERE LOWER(TRIM(name)) = $1 AND is_active = true',
    [normalizedForMatching]
  );
  
  if (similarDomainCheck.rows.length > 0) {
    domainId = similarDomainCheck.rows[0].id; // Use existing
  } else {
    // 4. Create new domain
    const domainCode = normalizedDomainName.toUpperCase()
      .replace(/\s+/g, '_')
      .substring(0, 50);
    
    const domainResult = await client.query(
      'INSERT INTO domains (name, code, description, is_active) VALUES ($1, $2, $3, $4) RETURNING id',
      [normalizedDomainName, domainCode, `Domain: ${normalizedDomainName}`, true]
    );
    domainId = domainResult.rows[0].id;
  }
}
```

**Domain Table:**
```sql
CREATE TABLE domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,        -- e.g., "Physical Design"
    code VARCHAR(50) NOT NULL UNIQUE,  -- e.g., "PD" or "PHYSICAL_DESIGN"
    description TEXT,
    is_active BOOLEAN DEFAULT true
);
```

---

## Step 4: Project Detection (Zoho vs Local)

**Location:** `backend/src/services/fileProcessor.service.ts` (line ~854-895)

### Process:

```typescript
// 1. Find project by name
let projectId = await this.findProjectId(projectName);
let isZohoProject = false;
let zohoProjectId: string | null = null;

// 2. Check if it's a Zoho project
const zohoMappingResult = await client.query(
  'SELECT zoho_project_id FROM zoho_projects_mapping WHERE LOWER(zoho_project_name) = LOWER($1) OR local_project_id = $2',
  [projectName, projectId || 0]
);

if (zohoMappingResult.rows.length > 0) {
  isZohoProject = true;
  zohoProjectId = zohoMappingResult.rows[0].zoho_project_id;
} else if (!projectId) {
  // Check if unmapped Zoho project (exists in zoho_project_run_directories)
  const zohoByNameResult = await client.query(
    'SELECT DISTINCT zoho_project_id FROM zoho_project_run_directories WHERE LOWER(zoho_project_name) = LOWER($1) LIMIT 1',
    [projectName]
  );
  
  if (zohoByNameResult.rows.length > 0) {
    isZohoProject = true;
    zohoProjectId = zohoByNameResult.rows[0].zoho_project_id;
  }
}
```

**Result:**
- **Mapped Zoho Project:** Has entry in `zoho_projects_mapping` → `isZohoProject = true`, has `local_project_id`
- **Unmapped Zoho Project:** Exists in `zoho_project_run_directories` but not mapped → `isZohoProject = true`, no `local_project_id`
- **Local Project:** Exists in `projects` table → `isZohoProject = false`

---

## Step 5: Domain-to-Project Linking

**Location:** `backend/src/services/fileProcessor.service.ts` (line ~900-920)

### Important: Only for Local Projects

```typescript
// Link domain to project if domain exists (for dashboard domain distribution)
// Only for local projects (Zoho projects don't use project_domains)
if (domainId && projectId && !isZohoProject) {
  try {
    // Check if link already exists
    const linkCheck = await client.query(
      'SELECT project_id, domain_id FROM project_domains WHERE project_id = $1 AND domain_id = $2',
      [projectId, domainId]
    );
    
    if (linkCheck.rows.length === 0) {
      // Create link between project and domain
      await client.query(
        'INSERT INTO project_domains (project_id, domain_id) VALUES ($1, $2) ON CONFLICT (project_id, domain_id) DO NOTHING',
        [projectId, domainId]
      );
    }
  } catch (error: any) {
    // Skip linking if table doesn't exist
  }
}
```

**Why Zoho Projects Don't Use `project_domains`:**
- Zoho projects may not have a local `project_id` (if unmapped)
- Domain information is stored in EDA files (`eda_output_files.domain_name`)
- Dashboard can query domains directly from EDA files for Zoho projects

---

## Step 6: Block/Experiment Validation

**Location:** `backend/src/services/fileProcessor.service.ts` (line ~928-1100)

### For Zoho Projects:

```typescript
if (isZohoProject && zohoProjectId) {
  // 1. Validate block exists in zoho_project_run_directories
  const zohoBlockResult = await client.query(
    `SELECT DISTINCT block_name, experiment_name 
     FROM zoho_project_run_directories 
     WHERE zoho_project_id = $1 AND block_name = $2`,
    [zohoProjectId, blockName]
  );

  if (zohoBlockResult.rows.length === 0) {
    throw new Error(
      `Block "${blockName}" does not exist for Zoho project "${projectName}". ` +
      `Please run the setup command first.`
    );
  }

  // 2. Validate experiment exists (ignore rtl_tag for validation)
  const zohoRunResult = await client.query(
    `SELECT id FROM zoho_project_run_directories 
     WHERE zoho_project_id = $1 AND block_name = $2 AND experiment_name = $3`,
    [zohoProjectId, blockName, experiment]
  );

  if (zohoRunResult.rows.length === 0) {
    throw new Error(
      `Experiment "${experiment}" does not exist for block "${blockName}" in Zoho project "${projectName}". ` +
      `Please run the setup command first.`
    );
  }

  // 3. Create/update local project, block, run for EDA data storage
  // (This allows storing EDA data even for unmapped Zoho projects)
  if (!projectId) {
    // Create local project for EDA data
    const createProjectResult = await client.query(
      'INSERT INTO projects (name, created_by) VALUES ($1, $2) RETURNING id',
      [projectName, uploadedBy || null]
    );
    projectId = createProjectResult.rows[0].id;
    
    // Create mapping
    await client.query(
      'INSERT INTO zoho_projects_mapping (zoho_project_id, local_project_id, zoho_project_name) VALUES ($1, $2, $3) ON CONFLICT (zoho_project_id) DO NOTHING',
      [zohoProjectId, projectId, projectName]
    );
  }
  
  // Create/update local block and run
  // ... (block and run creation logic)
}
```

**Key Points:**
- Block and experiment **must exist** in `zoho_project_run_directories` (from setup)
- If validation passes, local `blocks` and `runs` records are created/updated for EDA data storage
- EDA file's `rtl_tag` is used (may differ from setup's empty `rtl_tag`)

---

## Step 7: Save EDA Data

**Location:** `backend/src/services/fileProcessor.service.ts` (line ~1100+)

### Data Storage:

1. **EDA File Metadata:** Saved to `eda_output_files` table
   - `project_name`, `domain_name`, `block_name`, `experiment`, `rtl_tag`, `stage`, etc.

2. **Stage Data:** Saved to `stages` table
   - Linked to `runs.id` (via `run_id`)
   - Contains all metrics (timing, power, area, etc.)

3. **Domain Information:**
   - Stored in `eda_output_files.domain_name` (for all projects)
   - Also linked via `project_domains` (for local projects only)

---

## Step 8: Dashboard View Display

**Location:** `frontend/lib/screens/view_screen.dart`

### Loading Domains for Project

**Method:** `_loadDomainsForProject()` (line ~946)

```dart
Future<void> _loadDomainsForProject(String projectName) async {
  // Load EDA files to find domains for this project
  final filesResponse = await _apiService.getEdaFiles(
    token: token,
    limit: 1000,
  );

  final files = filesResponse['files'] ?? [];
  final domainSet = <String>{};

  for (var file in files) {
    final projectNameFromFile = file['project_name'] ?? 'Unknown';
    final domainName = file['domain_name'] ?? '';
    if (projectNameFromFile == projectName && domainName.isNotEmpty) {
      domainSet.add(domainName);
    }
  }

  final availableDomains = domainSet.toList()..sort();
  // Set available domains for dropdown
}
```

**How it works:**
1. Fetches all EDA files (filtered by user permissions)
2. Extracts unique `domain_name` values for the selected project
3. Displays domains in dropdown

**For Zoho Projects:**
- Domains come directly from `eda_output_files.domain_name`
- No need to query `project_domains` table

**For Local Projects:**
- Domains can come from:
  1. `eda_output_files.domain_name` (from uploaded files)
  2. `project_domains` table (from setup command)

---

### Loading EDA Data for Display

**Method:** `_loadInitialData()` (line ~262)

```dart
Future<void> _loadInitialData() async {
  // Load EDA files with backend filtering by project and domain
  final filesResponse = await _apiService.getEdaFiles(
    token: token,
    projectName: _selectedProject,
    domainName: _selectedDomain,
    limit: 500,
  );

  final files = filesResponse['files'] ?? [];

  // Group files by project -> block -> rtl_tag -> experiment -> stages
  final Map<String, dynamic> grouped = {};

  for (var file in filteredFiles) {
    final projectName = file['project_name'] ?? 'Unknown';
    final blockName = file['block_name'] ?? 'Unknown';
    final rtlTag = file['rtl_tag'] ?? 'Unknown';
    final experiment = file['experiment'] ?? 'Unknown';
    
    // Build hierarchical structure
    if (!grouped.containsKey(projectName)) {
      grouped[projectName] = {};
    }
    if (!grouped[projectName].containsKey(blockName)) {
      grouped[projectName][blockName] = {};
    }
    // ... (continue nesting: rtl_tag -> experiment -> stages)
    
    // Add stage data with all metrics
    final stage = file['stage'] ?? 'unknown';
    run['stages'][stage] = {
      'stage': stage,
      'timestamp': file['timestamp'],
      // Timing metrics
      'internal_timing_r2r_wns': file['internal_timing_r2r_wns'],
      // ... (all other metrics)
    };
  }
}
```

**Data Structure:**
```
grouped = {
  "project_name": {
    "block_name": {
      "rtl_tag": {
        "experiment": {
          "run_directory": "/path/to/run",
          "last_updated": "2024-01-15T10:30:00",
          "stages": {
            "syn": { /* stage metrics */ },
            "place": { /* stage metrics */ },
            "route": { /* stage metrics */ }
          }
        }
      }
    }
  }
}
```

---

## Dashboard Display Flow

### 1. Project Selection
- User selects project from dropdown
- System calls `_updateProject(projectName)`

### 2. Domain Loading
- System calls `_loadDomainsForProject(projectName)`
- Fetches EDA files and extracts unique domains
- Displays domains in dropdown

### 3. Domain Selection
- User selects domain
- System calls `_loadInitialData()`

### 4. Data Grouping
- EDA files are grouped by: Project → Block → RTL Tag → Experiment → Stages
- Each stage contains all metrics (timing, power, area, etc.)

### 5. Display
- Hierarchical tree view:
  - Project
    - Block
      - RTL Tag
        - Experiment
          - Stages (syn, place, route, etc.)
            - Metrics (WNS, TNS, Power, Area, etc.)

---

## Key Differences: Zoho vs Local Projects

| Aspect | Zoho Projects | Local Projects |
|--------|---------------|----------------|
| **Domain Source** | `eda_output_files.domain_name` | `eda_output_files.domain_name` OR `project_domains` |
| **Domain Linking** | Not stored in `project_domains` | Stored in `project_domains` table |
| **Project ID** | May not have local `project_id` (if unmapped) | Always has `project_id` |
| **Block Validation** | Against `zoho_project_run_directories` | Against `blocks` table |
| **Experiment Validation** | Against `zoho_project_run_directories` | Against `runs` table |
| **EDA Data Storage** | Creates local `blocks`/`runs` if needed | Uses existing `blocks`/`runs` |

---

## Example Flow: Zoho Project EDA Upload

### Scenario: Upload EDA file for Zoho project "saraswathi"

1. **File Upload:**
   - File: `saraswathi.physical design.json`
   - Domain extracted: "physical design"

2. **Domain Processing:**
   - Find/create domain: "Physical Design" (code: "PHYSICAL_DESIGN")
   - Domain ID: 1

3. **Project Detection:**
   - Project name: "saraswathi"
   - Check `zoho_projects_mapping` → Found Zoho project ID: "12345"
   - `isZohoProject = true`, `zohoProjectId = "12345"`

4. **Domain Linking:**
   - **Skipped** (Zoho project doesn't use `project_domains`)

5. **Block Validation:**
   - Block: "block3"
   - Check `zoho_project_run_directories` → Found ✅
   - Validation passes

6. **Experiment Validation:**
   - Experiment: "testingfor_server"
   - Check `zoho_project_run_directories` → Found ✅
   - Validation passes

7. **Data Storage:**
   - Save to `eda_output_files` with:
     - `project_name`: "saraswathi"
     - `domain_name`: "Physical Design"
     - `block_name`: "block3"
     - `experiment`: "testingfor_server"
     - `rtl_tag`: "bronze_v1" (from EDA file)
   - Save stage data to `stages` table

8. **Dashboard Display:**
   - User selects project "saraswathi"
   - System loads EDA files → finds domain "Physical Design"
   - User selects domain "Physical Design"
   - System displays:
     - Block: block3
       - RTL Tag: bronze_v1
         - Experiment: testingfor_server
           - Stages: syn, place, route, etc.

---

## Summary

1. **Domain Extraction:**
   - From filename (priority) or file data
   - Creates/finds domain in `domains` table

2. **Project Detection:**
   - Checks if Zoho project (mapped or unmapped)
   - Determines `isZohoProject` flag

3. **Domain Linking:**
   - **Local projects:** Linked via `project_domains` table
   - **Zoho projects:** Not linked (domains come from EDA files)

4. **Validation:**
   - Block/experiment must exist in setup data
   - For Zoho: validates against `zoho_project_run_directories`
   - For Local: validates against `blocks`/`runs` tables

5. **Data Storage:**
   - EDA metadata → `eda_output_files` table
   - Stage metrics → `stages` table
   - Domain info stored in `eda_output_files.domain_name`

6. **Dashboard Display:**
   - Loads domains from EDA files (for all projects)
   - Groups data hierarchically: Project → Block → RTL Tag → Experiment → Stages
   - Displays all metrics per stage

---

**Last Updated:** 2024-01-15  
**Document Version:** 1.0

