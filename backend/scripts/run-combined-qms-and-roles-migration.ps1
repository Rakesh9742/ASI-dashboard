# Script to run the combined QMS and Roles migration
# This script runs all migrations in one combined file:
# - 012_create_qms_schema.sql
# - 015_ensure_qms_columns_exist.sql
# - 016_add_checklist_submission_tracking.sql
# - 017_fix_qms_audit_log_foreign_keys.sql
# - 018_update_checklists_comments.sql
# - 019_create_qms_history.sql
# - 019_create_user_projects.sql
# - 020_add_role_to_user_projects.sql
# - 021_add_management_role.sql
# - 022_add_cad_engineer_role.sql

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running Combined QMS and Roles Migration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is available
$useDocker = $false
$containerName = $null

try {
    $null = docker ps 2>&1
    $useDocker = $true
    
    # Check if container exists (try both possible names)
    $container = docker ps -a --filter "name=asi_postgres" --format "{{.Names}}"
    if (-not $container) {
        $container = docker ps -a --filter "name=asidashboard" --format "{{.Names}}"
    }
    
    if ($container) {
        $containerName = $container
        $running = docker ps --filter "name=$containerName" --format "{{.Names}}"
        if (-not $running) {
            Write-Host "Container exists but is not running. Starting it..." -ForegroundColor Yellow
            docker start $containerName
            Start-Sleep -Seconds 3
        }
        Write-Host "Using Docker container: $containerName" -ForegroundColor Green
    } else {
        $useDocker = $false
        Write-Host "Docker is available but container not found. Using local PostgreSQL..." -ForegroundColor Yellow
    }
} catch {
    $useDocker = $false
    Write-Host "Docker not available. Using local PostgreSQL..." -ForegroundColor Yellow
}

# Get migration file path
$migrationPath = Join-Path (Get-Location) "backend\migrations\combined_qms_and_roles_migration.sql"

if (-not (Test-Path $migrationPath)) {
    Write-Host "Error: Migration file not found at: $migrationPath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Running combined migration..." -ForegroundColor Yellow
Write-Host "File: combined_qms_and_roles_migration.sql" -ForegroundColor Gray
Write-Host ""

if ($useDocker -and $containerName) {
    # Run via Docker
    Get-Content $migrationPath | docker exec -i $containerName psql -U postgres -d ASI
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Combined migration completed!" -ForegroundColor Green
    } else {
        Write-Host "❌ Error running combined migration" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
    Write-Host "Verifying tables..." -ForegroundColor Cyan
    docker exec -i $containerName psql -U postgres -d ASI -c "\dt checklists"
    docker exec -i $containerName psql -U postgres -d ASI -c "\dt user_projects"
    
} else {
    # Run via local PostgreSQL
    $envFile = Join-Path (Get-Location) "backend\.env"
    if (-not (Test-Path $envFile)) {
        Write-Host "Error: .env file not found at: $envFile" -ForegroundColor Red
        Write-Host "Please create .env file with DATABASE_URL or use Docker." -ForegroundColor Yellow
        exit 1
    }
    
    $envContent = Get-Content $envFile
    $dbUrl = ($envContent | Where-Object { $_ -match "DATABASE_URL" }) -replace "DATABASE_URL=", ""
    
    if ($dbUrl -match "postgresql://([^:]+):([^@]+)@([^:]+):(\d+)/(.+)") {
        $dbUser = $matches[1]
        $dbPass = $matches[2]
        $dbHost = $matches[3]
        $dbPort = $matches[4]
        $dbName = $matches[5]
        
        Write-Host "Database: $dbName on ${dbHost}:${dbPort}" -ForegroundColor Green
        Write-Host ""
        
        # Set PGPASSWORD environment variable
        $env:PGPASSWORD = $dbPass
        
        Get-Content $migrationPath | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Combined migration completed!" -ForegroundColor Green
        } else {
            Write-Host "❌ Error running combined migration" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Verifying tables..." -ForegroundColor Cyan
        & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "\dt checklists"
        & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "\dt user_projects"
    } else {
        Write-Host "Error: Could not parse DATABASE_URL from .env file" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ Combined migration completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Migrations applied:" -ForegroundColor Yellow
Write-Host "  ✅ 012 - Create QMS Schema (checklists, check_items, etc.)" -ForegroundColor White
Write-Host "  ✅ 015 - Ensure QMS Columns Exist" -ForegroundColor White
Write-Host "  ✅ 016 - Add Checklist Submission Tracking" -ForegroundColor White
Write-Host "  ✅ 017 - Fix QMS Audit Log Foreign Keys" -ForegroundColor White
Write-Host "  ✅ 018 - Update Checklists Comments" -ForegroundColor White
Write-Host "  ✅ 019 - Create QMS History Table" -ForegroundColor White
Write-Host "  ✅ 019 - Create User Projects Table" -ForegroundColor White
Write-Host "  ✅ 020 - Add Role to User Projects" -ForegroundColor White
Write-Host "  ✅ 021 - Add Management Role" -ForegroundColor White
Write-Host "  ✅ 022 - Add CAD Engineer Role" -ForegroundColor White
Write-Host ""

