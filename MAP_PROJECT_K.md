# Quick Guide: Map "Project K" from Zoho

## Your Project Information

- **Zoho Project ID:** `173458000001992000`
- **Zoho Project Name:** `Project K`
- **Portal ID:** (Check from your Zoho project data or use the one from Ganga project: `60021787257`)

## Solution: Auto-Create ASI Project and Map

Since you don't have an ASI project ID yet, you can use the API to automatically create one:

### Using cURL

```bash
curl -X POST http://localhost:3000/api/projects/map-zoho-project \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "zohoProjectId": "173458000001992000",
    "zohoProjectName": "Project K",
    "portalId": "60021787257",
    "createIfNotExists": true
  }'
```

### Using PowerShell

```powershell
$token = "YOUR_JWT_TOKEN"
$body = @{
    zohoProjectId = "173458000001992000"
    zohoProjectName = "Project K"
    portalId = "60021787257"
    createIfNotExists = $true
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "http://localhost:3000/api/projects/map-zoho-project" `
    -Method POST `
    -Headers @{
        "Content-Type" = "application/json"
        "Authorization" = "Bearer $token"
    } `
    -Body $body

$response | ConvertTo-Json
```

### Response

```json
{
  "success": true,
  "message": "Successfully mapped Zoho project \"Project K\" to ASI project \"Project K\"",
  "mapping": {
    "id": 1,
    "zoho_project_id": "173458000001992000",
    "local_project_id": 14,
    "zoho_project_name": "Project K",
    "portal_id": "60021787257",
    "created_at": "2025-01-XX...",
    "updated_at": "2025-01-XX..."
  },
  "asiProjectId": 14,
  "asiProjectName": "Project K",
  "created": true
}
```

**Note:** The `created: true` field indicates that a new ASI project was created.

## Alternative: Map to Existing ASI Project

If you want to map "Project K" to an existing ASI project instead, first find the project ID:

```sql
SELECT id, name FROM projects ORDER BY name;
```

Then use:

```json
{
  "zohoProjectId": "173458000001992000",
  "asiProjectId": 13,
  "zohoProjectName": "Project K",
  "portalId": "60021787257"
}
```

## Using SQL Directly

If you prefer SQL, first create the ASI project (if needed):

```sql
-- Create ASI project (if it doesn't exist)
INSERT INTO projects (name, created_by, created_at, updated_at)
VALUES ('Project K', YOUR_USER_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING
RETURNING id;
```

Then create the mapping:

```sql
-- Get the ASI project ID (assuming it was just created or exists)
SELECT id FROM projects WHERE name = 'Project K';

-- Create the mapping (replace 14 with the actual ASI project ID)
INSERT INTO zoho_projects_mapping 
  (zoho_project_id, local_project_id, zoho_project_name, portal_id)
VALUES 
  ('173458000001992000', 14, 'Project K', '60021787257')
ON CONFLICT (zoho_project_id)
DO UPDATE SET 
  local_project_id = EXCLUDED.local_project_id,
  zoho_project_name = EXCLUDED.zoho_project_name,
  portal_id = EXCLUDED.portal_id,
  updated_at = CURRENT_TIMESTAMP;
```

## Verify the Mapping

After mapping, verify it was created:

```sql
SELECT 
  zpm.zoho_project_id,
  zpm.zoho_project_name,
  zpm.local_project_id,
  p.name AS asi_project_name,
  zpm.portal_id
FROM zoho_projects_mapping zpm
LEFT JOIN projects p ON p.id = zpm.local_project_id
WHERE zpm.zoho_project_id = '173458000001992000';
```

## Next Steps

After mapping:
1. ✅ The project will show as "Mapped" in the Project Management screen
2. ✅ You can use "Sync Members from Zoho" to sync project members
3. ✅ The ASI project ID will be available in API responses

---

**Quick Command (if you have your JWT token):**

Replace `YOUR_JWT_TOKEN` with your actual token and run:

```bash
curl -X POST http://localhost:3000/api/projects/map-zoho-project \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"zohoProjectId":"173458000001992000","zohoProjectName":"Project K","portalId":"60021787257","createIfNotExists":true}'
```

