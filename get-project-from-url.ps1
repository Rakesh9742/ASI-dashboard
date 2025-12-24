# PowerShell script to extract project ID from Zoho URL and fetch project details
# Usage: .\get-project-from-url.ps1 -ZohoUrl "https://projects.zoho.in/portal/..."

param(
    [string]$ZohoUrl = "",
    [string]$BaseUrl = "http://localhost:3000",
    [string]$Username = "",
    [string]$Password = ""
)

Write-Host "=== Get Project from Zoho URL ===" -ForegroundColor Cyan
Write-Host ""

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
    Write-Host "   Expected format: .../projects/123456789/..." -ForegroundColor Yellow
    exit 1
}

# Extract portal name (optional, for reference)
if ($ZohoUrl -match '/portal/([^/#]+)') {
    $portalName = $matches[1]
    Write-Host "📋 Portal Name: $portalName" -ForegroundColor Gray
}

Write-Host ""

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
    Write-Host "   Token: $($token.Substring(0, 20))..." -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "❌ Login failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "   Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
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
    if ($projectResponse.project.raw.completion_percentage) {
        Write-Host "   Completion: $($projectResponse.project.raw.completion_percentage)%" -ForegroundColor White
    }
    Write-Host ""

    # Save complete response
    $outputFile = "project-$projectId-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $projectResponse | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "💾 Complete project data saved to: $outputFile" -ForegroundColor Green
    Write-Host ""

    # Show all fields in raw data
    Write-Host "📄 All Fields in Raw Zoho Response:" -ForegroundColor Cyan
    $rawFields = $projectResponse.project.raw.PSObject.Properties.Name | Sort-Object
    $fieldCount = 0
    foreach ($field in $rawFields) {
        $value = $projectResponse.project.raw.$field
        $valueType = if ($value -is [System.Array]) { 
            "Array[$($value.Count)]" 
        } elseif ($value -is [System.Collections.Hashtable] -or $value -is [PSCustomObject]) { 
            "Object" 
        } elseif ($null -eq $value) {
            "null"
        } else { 
            $value.GetType().Name 
        }
        $displayValue = if ($value -is [System.Array] -and $value.Count -gt 0) {
            "[$($value.Count) items]"
        } elseif ($value -is [System.Collections.Hashtable] -or ($value -is [PSCustomObject] -and $value.PSObject.Properties.Count -gt 0)) {
            "[Object]"
        } elseif ($null -eq $value) {
            "null"
        } elseif ($value.ToString().Length -gt 50) {
            $value.ToString().Substring(0, 47) + "..."
        } else {
            $value.ToString()
        }
        Write-Host "   [$fieldCount] $field : $valueType = $displayValue" -ForegroundColor Gray
        $fieldCount++
    }
    Write-Host ""
    Write-Host "   Total fields: $fieldCount" -ForegroundColor Gray
    Write-Host ""

    # Show complete raw data
    Write-Host "📄 Complete Raw Project Data (JSON):" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Gray
    $projectResponse.project.raw | ConvertTo-Json -Depth 10 | Write-Host
    Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Gray

} catch {
    Write-Host "❌ Error fetching project: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "   Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
        try {
            $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
            if ($errorDetails.error) {
                Write-Host "   Error: $($errorDetails.error)" -ForegroundColor Red
            }
        } catch {
            # Not JSON, just show as is
        }
    }
    Write-Host ""
    Write-Host "💡 Troubleshooting:" -ForegroundColor Yellow
    Write-Host "   1. Check if project ID is correct: $projectId" -ForegroundColor Gray
    Write-Host "   2. Verify you have access to this project in Zoho" -ForegroundColor Gray
    Write-Host "   3. Check if Zoho token is valid: GET /api/zoho/status" -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "✅ Done! Check the saved JSON file for complete project data." -ForegroundColor Green




