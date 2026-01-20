# Script to run all QMS migrations in one shot
# Migrations: 012, 015, 016, 017, 018

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running QMS Migrations (All in One)" -ForegroundColor Cyan
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

# Define migrations to run in order
$migrations = @(
    @{ Number = "012"; File = "012_create_qms_schema.sql"; Description = "Create QMS Schema (checklists, check_items, etc.)" },
    @{ Number = "015"; File = "015_ensure_qms_columns_exist.sql"; Description = "Ensure QMS Columns Exist" },
    @{ Number = "016"; File = "016_add_checklist_submission_tracking.sql"; Description = "Add Checklist Submission Tracking" },
    @{ Number = "017"; File = "017_fix_qms_audit_log_foreign_keys.sql"; Description = "Fix QMS Audit Log Foreign Keys" },
    @{ Number = "018"; File = "018_update_checklists_comments.sql"; Description = "Update Checklists Comments" }
)

$migrationsPath = Join-Path (Get-Location) "backend\migrations"

if ($useDocker -and $containerName) {
    # Run via Docker
    foreach ($migration in $migrations) {
        $migrationPath = Join-Path $migrationsPath $migration.File
        
        if (-not (Test-Path $migrationPath)) {
            Write-Host "❌ Error: Migration file not found: $($migration.File)" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Running migration $($migration.Number): $($migration.Description)..." -ForegroundColor Yellow
        Write-Host "File: $($migration.File)" -ForegroundColor Gray
        
        Get-Content $migrationPath | docker exec -i $containerName psql -U postgres -d ASI
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Migration $($migration.Number) completed!" -ForegroundColor Green
        } else {
            Write-Host "❌ Error running migration $($migration.Number)" -ForegroundColor Red
            exit 1
        }
    }
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
        
        foreach ($migration in $migrations) {
            $migrationPath = Join-Path $migrationsPath $migration.File
            
            if (-not (Test-Path $migrationPath)) {
                Write-Host "❌ Error: Migration file not found: $($migration.File)" -ForegroundColor Red
                exit 1
            }
            
            Write-Host ""
            Write-Host "Running migration $($migration.Number): $($migration.Description)..." -ForegroundColor Yellow
            Write-Host "File: $($migration.File)" -ForegroundColor Gray
            
            Get-Content $migrationPath | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Migration $($migration.Number) completed!" -ForegroundColor Green
            } else {
                Write-Host "❌ Error running migration $($migration.Number)" -ForegroundColor Red
                exit 1
            }
        }
    } else {
        Write-Host "Error: Could not parse DATABASE_URL from .env file" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ All QMS migrations completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Migrations applied:" -ForegroundColor Yellow
foreach ($migration in $migrations) {
    Write-Host "  ✅ $($migration.Number) - $($migration.Description)" -ForegroundColor White
}

