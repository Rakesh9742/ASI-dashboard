# Project Mapping Guide

## Overview

This guide explains how to map a Zoho project to an ASI (local) project. Mapping allows you to:
- Link Zoho projects with local ASI projects
- Sync members from Zoho to the mapped ASI project
- View project data from both sources in a unified way

## Prerequisites

- Admin, Project Manager, or Lead role
- Zoho project ID
- ASI project ID (local project ID)

## Method 1: Using API Endpoint (Recommended)

### API Endpoint

**POST** `/api/projects/map-zoho-project`

**Authentication:** Required (Bearer token)

**Authorization:** Requires `admin`, `project_manager`, or `lead` role

### Request Body

**Option 1: Map to existing ASI project**
```json
{
  "zohoProjectId": "173458000001945100",
  "asiProjectId": 13,
  "portalId": "60021787257",
  "zohoProjectName": "Project K"
}
```

**Option 2: Auto-create ASI project (if it doesn't exist)**
```json
{
  "zohoProjectId": "173458000001992000",
  "zohoProjectName": "Project K",
  "portalId": "60021787257",
  "createIfNotExists": true
}
```

**Required Fields:**
- `zohoProjectId` (string) - The Zoho project ID

**Conditional Fields:**
- `asiProjectId` (number) - The local ASI project ID (required if `createIfNotExists` is false or not set)
- `createIfNotExists` (boolean) - If true, creates a new ASI project with the same name if `asiProjectId` is not provided

**Optional Fields:**
- `portalId` (string) - Zoho portal ID
- `zohoProjectName` (string) - Zoho project name (for reference, used when creating new ASI project)

### Example: Using cURL

```bash
curl -X POST http://localhost:3000/api/projects/map-zoho-project \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "zohoProjectId": "173458000001945100",
    "asiProjectId": 13,
    "portalId": "60021787257",
    "zohoProjectName": "Project K"
  }'
```

### Example: Using JavaScript/TypeScript

```typescript
const response = await fetch('http://localhost:3000/api/projects/map-zoho-project', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`
  },
  body: JSON.stringify({
    zohoProjectId: '173458000001945100',
    asiProjectId: 13,
    portalId: '60021787257',
    zohoProjectName: 'Project K'
  })
});

const result = await response.json();
console.log(result);
```

### Response

**Success (200):**
```json
{
  "success": true,
  "message": "Successfully mapped Zoho project \"Project K\" to ASI project \"Ganga\"",
  "mapping": {
    "id": 1,
    "zoho_project_id": "173458000001945100",
    "local_project_id": 13,
    "zoho_project_name": "Project K",
    "portal_id": "60021787257",
    "created_at": "2025-01-XX...",
    "updated_at": "2025-01-XX..."
  }
}
```

**Error (400/404/500):**
```json
{
  "error": "Error message here"
}
```

---

## Method 2: Using SQL (Direct Database Access)

If you have direct database access, you can create the mapping directly:

### Step 1: Find Your Project IDs

**Find ASI Project ID:**
```sql
SELECT id, name FROM projects WHERE name LIKE '%K%' OR name LIKE '%k%';
```

**Find Zoho Project ID:**
- Check the Zoho project URL or API response
- Usually a long numeric string like `173458000001945100`

### Step 2: Create the Mapping

```sql
INSERT INTO zoho_projects_mapping 
  (zoho_project_id, local_project_id, zoho_project_name, portal_id)
VALUES 
  ('173458000001945100', 13, 'Project K', '60021787257')
ON CONFLICT (zoho_project_id)
DO UPDATE SET 
  local_project_id = EXCLUDED.local_project_id,
  zoho_project_name = COALESCE(EXCLUDED.zoho_project_name, zoho_projects_mapping.zoho_project_name),
  portal_id = COALESCE(EXCLUDED.portal_id, zoho_projects_mapping.portal_id),
  updated_at = CURRENT_TIMESTAMP;
```

### Step 3: Verify the Mapping

```sql
SELECT 
  zpm.zoho_project_id,
  zpm.zoho_project_name,
  zpm.local_project_id,
  p.name AS asi_project_name,
  zpm.portal_id,
  zpm.created_at
FROM zoho_projects_mapping zpm
LEFT JOIN projects p ON p.id = zpm.local_project_id
WHERE zpm.zoho_project_id = '173458000001945100';
```

---

## Finding Project IDs

### Finding ASI Project ID

**Option 1: Using SQL**
```sql
SELECT id, name FROM projects ORDER BY name;
```

**Option 2: Using API**
```bash
GET /api/projects
Authorization: Bearer YOUR_TOKEN
```

Look for the project in the response and note its `id`.

### Finding Zoho Project ID

**Option 1: From Zoho Projects URL**
- Open the project in Zoho Projects
- Check the URL: `https://projects.zoho.com/portal/.../projects/{PROJECT_ID}/...`
- The PROJECT_ID is the Zoho project ID

**Option 2: From API Response**
```bash
GET /api/zoho/projects
Authorization: Bearer YOUR_TOKEN
```

Look for the project in the response and note its `id` field.

**Option 3: From Project Management Screen**
- Go to Project Management screen
- Find the Zoho project
- Check the project details - the Zoho project ID is in the `zoho_project_id` field

---

## Example: Mapping "Project K"

Let's say you have:
- **Zoho Project:** "Project K" with ID `173458000001945100`
- **ASI Project:** "Project K" with ID `14` (assuming it exists)

### Using API:

```bash
curl -X POST http://localhost:3000/api/projects/map-zoho-project \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "zohoProjectId": "173458000001945100",
    "asiProjectId": 14,
    "zohoProjectName": "Project K"
  }'
```

### Using SQL:

```sql
INSERT INTO zoho_projects_mapping 
  (zoho_project_id, local_project_id, zoho_project_name)
VALUES 
  ('173458000001945100', 14, 'Project K')
ON CONFLICT (zoho_project_id)
DO UPDATE SET 
  local_project_id = EXCLUDED.local_project_id,
  zoho_project_name = EXCLUDED.zoho_project_name,
  updated_at = CURRENT_TIMESTAMP;
```

---

## Updating an Existing Mapping

If a mapping already exists, you can update it:

### Using API:
Just call the same endpoint with the new `asiProjectId`:

```json
{
  "zohoProjectId": "173458000001945100",
  "asiProjectId": 15,
  "zohoProjectName": "Project K"
}
```

The API will update the existing mapping.

### Using SQL:
The `ON CONFLICT` clause in the SQL will automatically update if the Zoho project ID already exists.

---

## Viewing All Mappings

```sql
SELECT 
  zpm.id,
  zpm.zoho_project_id,
  zpm.zoho_project_name,
  zpm.local_project_id,
  p.name AS asi_project_name,
  zpm.portal_id,
  zpm.created_at,
  zpm.updated_at
FROM zoho_projects_mapping zpm
LEFT JOIN projects p ON p.id = zpm.local_project_id
ORDER BY zpm.created_at DESC;
```

---

## Deleting a Mapping

If you need to remove a mapping:

```sql
DELETE FROM zoho_projects_mapping 
WHERE zoho_project_id = '173458000001945100';
```

**Note:** This will not delete the Zoho or ASI project, only the mapping between them.

---

## Troubleshooting

### Error: "ASI project not found"
- Verify the ASI project ID exists: `SELECT id FROM projects WHERE id = <asiProjectId>;`
- Check that you're using the correct project ID

### Error: "zohoProjectId and asiProjectId are required"
- Make sure both fields are provided in the request
- Check that `zohoProjectId` is a string and `asiProjectId` is a number

### Error: "Only admins can create mappings"
- Verify your user role: `SELECT role FROM users WHERE id = <your_user_id>;`
- You need `admin`, `project_manager`, or `lead` role

### Mapping not showing up
- Refresh the projects list
- Check the mapping was created: `SELECT * FROM zoho_projects_mapping WHERE zoho_project_id = '<id>';`
- Verify the project names match (case-insensitive)

---

## After Mapping

Once mapped:
1. The Zoho project will show as "Mapped" in the Project Management screen
2. You can use "Sync Members from Zoho" to sync project members
3. The ASI project ID will be available in project responses as `asi_project_id`
4. Users can access the project data from both sources

---

## Quick Reference

**Table:** `zoho_projects_mapping`

**Columns:**
- `id` - Auto-increment primary key
- `zoho_project_id` - Zoho project ID (VARCHAR, UNIQUE)
- `local_project_id` - ASI project ID (INTEGER, FK to projects.id)
- `zoho_project_name` - Zoho project name (VARCHAR, optional)
- `portal_id` - Zoho portal ID (VARCHAR, optional)
- `created_at` - Timestamp
- `updated_at` - Timestamp

**API Endpoint:** `POST /api/projects/map-zoho-project`

**Required Role:** `admin`, `project_manager`, or `lead`

---

**Last Updated:** 2025-01-XX

