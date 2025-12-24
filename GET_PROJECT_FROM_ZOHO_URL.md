# Get Project Information from Zoho URL

This guide shows you how to extract project information from a Zoho Projects URL and fetch it via the API.

## Understanding Your Zoho URL

Your URL:
```
https://projects.zoho.in/portal/sumedhadesignsystemspvtltd231#zp/projects/173458000001906091/tasks/custom-view/173458000000067003/list/tasklist-detail/173458000001906123/task-detail/173458000001906133?group_by=tasklist
```

**Breaking it down:**
- **Portal Name:** `sumedhadesignsystemspvtltd231`
- **Project ID:** `173458000001906091` ← This is what you need!
- **Data Center:** `.in` (India)
- The rest is the task detail view path

## API Endpoints to Get Project Information

### 1. Get Single Project Details

**Endpoint:** `GET /api/zoho/projects/:projectId`

**Description:** Returns complete project information including all fields from Zoho.

**Example:**
```bash
curl -X GET "http://localhost:3000/api/zoho/projects/173458000001906091" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

**Response:**
```json
{
  "success": true,
  "project": {
    "id": "173458000001906091",
    "name": "Project Name",
    "description": "Project description",
    "status": "active",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "owner_name": "Owner Name",
    "created_time": "2024-01-01T00:00:00+00:00",
    "source": "zoho",
    "raw": {
      // COMPLETE PROJECT DATA FROM ZOHO
      // All fields you see in Zoho Projects UI
    }
  }
}
```

### 2. Get Project from Combined Endpoint

**Endpoint:** `GET /api/projects?includeZoho=true`

**Description:** Returns all projects (local + Zoho). Find your project by `zoho_project_id`.

**Example:**
```bash
curl -X GET "http://localhost:3000/api/projects?includeZoho=true" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

Then search for project with `zoho_project_id: "173458000001906091"` in the response.

---

## Quick Test Script

### PowerShell Script

Save this as `get-project-from-url.ps1`:

```powershell
param(
    [string]$ZohoUrl = "",
    [string]$BaseUrl = "http://localhost:3000",
    [string]$Username = "",
    [string]$Password = ""
)

# Extract project ID from URL
if ([string]::IsNullOrEmpty($ZohoUrl)) {
    $ZohoUrl = Read-Host "Enter Zoho Projects URL"
}

# Extract project ID using regex
if ($ZohoUrl -match '/projects/(\d+)') {
    $projectId = $matches[1]
    Write-Host "✅ Extracted Project ID: $projectId" -ForegroundColor Green
} else {
    Write-Host "❌ Could not extract project ID from URL" -ForegroundColor Red
    exit 1
}

# Login
if ([string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password)) {
    $Username = Read-Host "Enter username"
    $Password = Read-Host "Enter password" -AsSecureString
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    )
}

Write-Host "🔐 Logging in..." -ForegroundColor Yellow
try {
    $loginBody = @{
        username = $Username
        password = $Password
    } | ConvertTo-Json

    $loginResponse = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" `
        -Method Post `
        -ContentType "application/json" `
        -Body $loginBody

    $token = $loginResponse.token
    Write-Host "✅ Login successful!" -ForegroundColor Green
} catch {
    Write-Host "❌ Login failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get project details
Write-Host "📊 Fetching project details for ID: $projectId..." -ForegroundColor Yellow
try {
    $headers = @{
        "Authorization" = "Bearer $token"
    }

    $projectResponse = Invoke-RestMethod -Uri "$BaseUrl/api/zoho/projects/$projectId" `
        -Method Get `
        -Headers $headers

    Write-Host "✅ Project found!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Project Information:" -ForegroundColor Cyan
    Write-Host "   ID: $($projectResponse.project.id)" -ForegroundColor White
    Write-Host "   Name: $($projectResponse.project.name)" -ForegroundColor White
    Write-Host "   Status: $($projectResponse.project.status)" -ForegroundColor White
    Write-Host "   Owner: $($projectResponse.project.owner_name)" -ForegroundColor White
    Write-Host "   Start Date: $($projectResponse.project.start_date)" -ForegroundColor White
    Write-Host "   End Date: $($projectResponse.project.end_date)" -ForegroundColor White
    Write-Host ""

    # Save complete response
    $outputFile = "project-$projectId-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $projectResponse | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "💾 Complete project data saved to: $outputFile" -ForegroundColor Green
    Write-Host ""

    # Show all fields in raw data
    Write-Host "📄 All Fields in Raw Zoho Response:" -ForegroundColor Cyan
    $rawFields = $projectResponse.project.raw.PSObject.Properties.Name
    foreach ($field in $rawFields) {
        $value = $projectResponse.project.raw.$field
        $valueType = if ($value -is [System.Array]) { 
            "Array[$($value.Count)]" 
        } elseif ($value -is [System.Collections.Hashtable] -or $value -is [PSCustomObject]) { 
            "Object" 
        } else { 
            $value.GetType().Name 
        }
        Write-Host "   - $field : $valueType" -ForegroundColor Gray
    }
    Write-Host ""

    # Show complete raw data
    Write-Host "📄 Complete Raw Project Data:" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Gray
    $projectResponse.project.raw | ConvertTo-Json -Depth 10 | Write-Host
    Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Gray

} catch {
    Write-Host "❌ Error fetching project: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "   Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    exit 1
}
```

**Usage:**
```powershell
.\get-project-from-url.ps1 -ZohoUrl "https://projects.zoho.in/portal/sumedhadesignsystemspvtltd231#zp/projects/173458000001906091/tasks/..."
```

---

## Manual Steps

### Step 1: Extract Project ID from URL

From your URL:
```
https://projects.zoho.in/portal/sumedhadesignsystemspvtltd231#zp/projects/173458000001906091/...
```

**Project ID:** `173458000001906091`

### Step 2: Get Authentication Token

```bash
curl -X POST "http://localhost:3000/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username": "your_username", "password": "your_password"}'
```

Copy the `token` from the response.

### Step 3: Get Project Details

```bash
curl -X GET "http://localhost:3000/api/zoho/projects/173458000001906091" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  | jq '.'
```

This will return the complete project information with all fields in the `raw` object.

---

## What You'll Get

The API response includes:

1. **Standard Project Fields:**
   - `id`, `name`, `description`
   - `status`, `start_date`, `end_date`
   - `owner_name`, `created_time`
   - `priority`, `completion_percentage`
   - `work_hours`, `billing_type`
   - `team_name`, `tags`
   - And many more...

2. **Complete Raw Data:**
   - The `raw` field contains **ALL** fields returned by Zoho Projects API
   - This includes custom fields, task counts, milestones, etc.
   - Everything you see in the Zoho Projects UI

---

## Example: Your Specific Project

For your project ID `173458000001906091`:

```bash
# 1. Login
TOKEN=$(curl -s -X POST "http://localhost:3000/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"your_username","password":"your_password"}' \
  | jq -r '.token')

# 2. Get project
curl -X GET "http://localhost:3000/api/zoho/projects/173458000001906091" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.project.raw' > project-173458000001906091.json

# 3. View all field names
cat project-173458000001906091.json | jq 'keys'
```

---

## Notes

- **Portal ID:** If you need to specify a portal, add `?portalId=YOUR_PORTAL_ID` to the URL
- **Data Center:** Your URL shows `.in` (India), make sure your `ZOHO_API_URL` in `.env` matches:
  - India: `https://projectsapi.zoho.in`
  - US: `https://projectsapi.zoho.com`
  - EU: `https://projectsapi.zoho.eu`
- **Tasks:** The current API doesn't fetch tasks. The project response includes task counts but not the actual task list.

---

## Next Steps

If you need to fetch **tasks** for this project, you would need to:
1. Add a new endpoint: `GET /api/zoho/projects/:projectId/tasks`
2. Call Zoho Projects API: `/restapi/portal/{portalId}/projects/{projectId}/tasks/`

Let me know if you want me to implement task fetching!




