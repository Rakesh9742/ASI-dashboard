# Script to run user_projects migration on existing database

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running User Projects Migration" -ForegroundColor Cyan
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
$migrationPath = Join-Path (Get-Location) "backend\migrations\019_create_user_projects.sql"

if (-not (Test-Path $migrationPath)) {
    Write-Host "Error: Migration file not found at: $migrationPath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Running migration: Create user_projects table..." -ForegroundColor Yellow

if ($useDocker -and $containerName) {
    # Run via Docker
    Get-Content $migrationPath | docker exec -i $containerName psql -U postgres -d ASI
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ user_projects table created!" -ForegroundColor Green
    } else {
        Write-Host "❌ Error creating user_projects table" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
    Write-Host "Verifying user_projects table..." -ForegroundColor Cyan
    docker exec -i $containerName psql -U postgres -d ASI -c "\d user_projects"
    
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
            Write-Host "✅ user_projects table created!" -ForegroundColor Green
        } else {
            Write-Host "❌ Error creating user_projects table" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Verifying user_projects table..." -ForegroundColor Cyan
        & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "\d user_projects"
    } else {
        Write-Host "Error: Could not parse DATABASE_URL from .env file" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "The user_projects table is now ready for customer-project assignments!" -ForegroundColor Yellow

