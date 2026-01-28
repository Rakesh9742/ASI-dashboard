# Domain Mapping to Project During Setup

## Overview

This document explains how the domain is mapped to the project during the setup command execution and how it's saved to the database.

---

## Flow Diagram

```
User Runs Setup Command
    ↓
Frontend: Setup Dialog
    ↓
User Selects Domain (from dropdown)
    ↓
Setup Command Executed: setup -proj {project} -domain {domainCode} -block {block} -exp {experiment}
    ↓
Frontend: Calls saveRunDirectory API with domainCode
    ↓
Backend: /api/projects/save-run-directory endpoint
    ↓
1. Find/Create Project
2. Link Domain to Project (using domainCode)
3. Create/Update Block
4. Create/Update Run (Experiment)
```

---

## Step-by-Step Process

### 1. Frontend: User Selects Domain

**File:** `frontend/lib/screens/projects_screen.dart`

When the user opens the setup dialog, they see a dropdown of available domains:

```dart
// Domain Selection Dropdown
DropdownButtonFormField<String>(
  value: _selectedDomainCode,
  decoration: InputDecoration(
    labelText: 'Domain',
    // ...
  ),
  items: widget.domains.map((domain) {
    final code = domain['code']?.toString() ?? '';
    final name = domain['name']?.toString() ?? code;
    return DropdownMenuItem(
      value: code,
      child: Text('$name ($code)'),
    );
  }).toList(),
  onChanged: (value) {
    setState(() {
      _selectedDomainCode = value;
    });
  },
)
```

**Domain Source:**
- For Zoho projects: Domains are fetched from Zoho tasklists (project plan)
- For local projects: Domains come from `project['domains']` array

**Domain Code Examples:**
- `pd` - Physical Design
- `dv` - Design Verification
- `rtl` - RTL
- `dft` - DFT
- `al` - Analog

---

### 2. Frontend: Setup Command Execution

**File:** `frontend/lib/screens/projects_screen.dart` (line ~2658)

When user clicks "Run Setup", the command is built:

```dart
final domainCode = _selectedDomainCode!; // e.g., "pd"
final command = 'setup -proj $sanitizedProjectName -domain $domainCode -block $sanitizedBlockName -exp $experimentName';
```

**Example Command:**
```bash
setup -proj saraswathi -domain pd -block block3 -exp testingfor_server
```

---

### 3. Frontend: Save Run Directory with Domain Code

**File:** `frontend/lib/screens/projects_screen.dart` (line ~2780)

After the setup command succeeds, the frontend calls the API to save the run directory:

```dart
await widget.apiService.saveRunDirectory(
  projectName: projectName,
  blockName: blockName,
  experimentName: experimentName,
  runDirectory: actualRunDirectory,
  username: actualUsername,
  zohoProjectId: widget.zohoProjectId,
  domainCode: domainCode, // ← Domain code is passed here
  token: token,
);
```

---

### 4. Backend: Receive Domain Code

**File:** `backend/src/routes/project.routes.ts` (line ~1907)

The backend receives the `domainCode` in the request body:

```typescript
const { 
  projectName, 
  blockName, 
  experimentName, 
  runDirectory, 
  zohoProjectId, 
  username: sshUsername, 
  domainCode  // ← Domain code from frontend
} = req.body;
```

---

### 5. Backend: Find Project

**File:** `backend/src/routes/project.routes.ts` (line ~1960-2050)

The backend first finds or creates the project:

```typescript
// For Zoho projects: Check if mapped to local project
// For local projects: Find by name
let projectId: number | null = null;
// ... project lookup logic ...
```

---

### 6. Backend: Link Domain to Project

**File:** `backend/src/routes/project.routes.ts` (line ~2133-2157)

**This is the key step where domain is mapped to project:**

```typescript
// Link domain to project if domain code is provided (for setup command)
if (domainCode && projectId) {
  try {
    // Step 1: Find domain by code
    const domainResult = await client.query(
      'SELECT id FROM domains WHERE code = $1 AND is_active = true',
      [domainCode.toUpperCase()] // e.g., "PD"
    );

    if (domainResult.rows.length > 0) {
      const domainId = domainResult.rows[0].id;
      
      // Step 2: Link domain to project (if not already linked)
      await client.query(
        'INSERT INTO project_domains (project_id, domain_id) VALUES ($1, $2) ON CONFLICT (project_id, domain_id) DO NOTHING',
        [projectId, domainId]
      );
      
      console.log(`✅ Linked domain ${domainCode} to project ${projectName} (ID: ${projectId})`);
    } else {
      console.log(`⚠️ Domain with code ${domainCode} not found, skipping domain linking`);
    }
  } catch (error: any) {
    // Log error but don't fail the entire operation
    console.error('Error linking domain to project:', error.message);
  }
}
```

**What happens:**
1. **Find Domain:** Query `domains` table by `code` (e.g., "PD")
2. **Get Domain ID:** Extract the `id` from the domain record
3. **Link to Project:** Insert into `project_domains` table:
   - `project_id`: The project's ID
   - `domain_id`: The domain's ID
   - Uses `ON CONFLICT DO NOTHING` to avoid duplicates

---

## Database Schema

### Tables Involved

#### 1. `domains` Table
```sql
CREATE TABLE domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50) NOT NULL UNIQUE,  -- e.g., "PD", "DV", "RTL"
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Example Data:**
| id | name | code | is_active |
|----|------|------|-----------|
| 1 | Physical Design | PD | true |
| 2 | Design Verification | DV | true |
| 3 | RTL | RTL | true |

#### 2. `projects` Table
```sql
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    -- ... other fields ...
);
```

#### 3. `project_domains` Table (Junction Table)
```sql
CREATE TABLE project_domains (
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    domain_id INTEGER REFERENCES domains(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (project_id, domain_id)  -- Composite primary key prevents duplicates
);
```

**Example Data:**
| project_id | domain_id | created_at |
|------------|-----------|------------|
| 1 | 1 | 2024-01-15 10:30:00 |
| 1 | 2 | 2024-01-15 10:30:00 |

This means:
- Project ID 1 is linked to Domain ID 1 (Physical Design)
- Project ID 1 is also linked to Domain ID 2 (Design Verification)

---

## Important Notes

### 1. Domain Code Lookup
- The domain code is **case-insensitive** (converted to uppercase: `domainCode.toUpperCase()`)
- The domain must exist in the `domains` table with `is_active = true`
- If domain is not found, the linking step is skipped (but setup continues)

### 2. Duplicate Prevention
- Uses `ON CONFLICT (project_id, domain_id) DO NOTHING`
- This means if the domain is already linked to the project, no error occurs
- The composite primary key `(project_id, domain_id)` ensures uniqueness

### 3. Error Handling
- If domain linking fails, it's logged but **does not fail the entire setup operation**
- The setup continues to create/update blocks and runs even if domain linking fails

### 4. Zoho Projects
- For **Zoho projects** (unmapped), the domain linking happens **only if the project is mapped to a local project**
- If it's an unmapped Zoho project, the run directory is saved to `zoho_project_run_directories` table, but domain linking is skipped (since there's no local `project_id`)

---

## Example Flow

### Scenario: User sets up "saraswathi" project with "pd" domain

1. **User selects domain:** "Physical Design (pd)"
2. **Setup command:** `setup -proj saraswathi -domain pd -block block3 -exp testingfor_server`
3. **Frontend sends to backend:**
   ```json
   {
     "projectName": "saraswathi",
     "domainCode": "pd",
     "blockName": "block3",
     "experimentName": "testingfor_server",
     "runDirectory": "/CX_RUN_NEW/saraswathi/pd/users/username/block3/testingfor_server",
     "username": "username"
   }
   ```
4. **Backend processing:**
   - Finds project "saraswathi" → `project_id = 1`
   - Finds domain with code "PD" → `domain_id = 1`
   - Inserts into `project_domains`: `(project_id=1, domain_id=1)`
   - Creates/updates block "block3"
   - Creates/updates run "testingfor_server"
5. **Result:** Project "saraswathi" is now linked to "Physical Design" domain

---

## Querying Project Domains

After setup, you can query which domains are linked to a project:

```sql
SELECT 
    p.name AS project_name,
    d.name AS domain_name,
    d.code AS domain_code
FROM projects p
JOIN project_domains pd ON pd.project_id = p.id
JOIN domains d ON d.id = pd.domain_id
WHERE p.name = 'saraswathi';
```

**Result:**
| project_name | domain_name | domain_code |
|--------------|-------------|-------------|
| saraswathi | Physical Design | PD |

---

## Summary

1. **User selects domain** from dropdown (domain code like "pd")
2. **Setup command** includes domain code: `setup -domain pd ...`
3. **Frontend passes domainCode** to `saveRunDirectory` API
4. **Backend finds domain** by code in `domains` table
5. **Backend links domain to project** by inserting into `project_domains` table
6. **Result:** Project and domain are now linked via the `project_domains` junction table

This allows:
- One project to have multiple domains
- One domain to be used by multiple projects
- Easy querying of which domains belong to which projects


