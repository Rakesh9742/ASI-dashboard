# Script to clear/empty PostgreSQL database
# WARNING: This will delete ALL data and tables from the database!

param(
    [switch]$Docker = $false,
    [switch]$Local = $false,
    [switch]$Confirm = $false
)

Write-Host "=== PostgreSQL Database Clear ===" -ForegroundColor Yellow
Write-Host ""

# Database configuration
$DB_NAME = "asi"
$DB_USER = "postgres"
$DB_PASSWORD = "root"
$DB_HOST = "localhost"
$DB_PORT = "5432"
$DOCKER_CONTAINER = "asi_postgres"

# Safety check
if (-not $Confirm) {
    Write-Host "⚠️  WARNING: This will DELETE ALL DATA from the database!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Database: $DB_NAME" -ForegroundColor Cyan
    Write-Host ""
    $response = Read-Host "Type 'YES' to confirm deletion"
    if ($response -ne "YES") {
        Write-Host "❌ Operation cancelled" -ForegroundColor Yellow
        exit 0
    }
}

# Determine if using Docker or local PostgreSQL
$useDocker = $false

if ($Docker) {
    $useDocker = $true
} elseif ($Local) {
    $useDocker = $false
} else {
    # Auto-detect: Check if Docker container is running
    $containerStatus = docker ps --filter "name=$DOCKER_CONTAINER" --format "{{.Status}}" 2>$null
    if ($containerStatus -and $containerStatus -match "Up") {
        Write-Host "✅ Docker container '$DOCKER_CONTAINER' is running" -ForegroundColor Green
        $useDocker = $true
    } else {
        Write-Host "⚠️  Docker container not found, using local PostgreSQL" -ForegroundColor Yellow
        $useDocker = $false
    }
}

Write-Host ""
Write-Host "Clearing database: $DB_NAME" -ForegroundColor Cyan
Write-Host "Source: $(if ($useDocker) { "Docker Container" } else { "Local PostgreSQL" })" -ForegroundColor Gray
Write-Host ""

# SQL to drop all objects - using a simpler approach
$clearSQL = @"
-- Drop all objects in public schema
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
"@

if ($useDocker) {
    # Clear from Docker container
    Write-Host "Clearing database in Docker container..." -ForegroundColor Yellow
    
    try {
        $env:PGPASSWORD = $DB_PASSWORD
        $clearSQL | docker exec -i $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Database cleared successfully!" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to clear database. Exit code: $LASTEXITCODE" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "❌ Error during database clear: $_" -ForegroundColor Red
        exit 1
    }
} else {
    # Clear from local PostgreSQL
    Write-Host "Clearing database in local PostgreSQL..." -ForegroundColor Yellow
    
    # Check if psql is available
    $psqlPath = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $psqlPath) {
        Write-Host "❌ psql not found in PATH" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure PostgreSQL client tools are installed and in your PATH." -ForegroundColor Yellow
        Write-Host "Or use Docker clear by running: .\clear-database.ps1 -Docker" -ForegroundColor Yellow
        exit 1
    }
    
    try {
        $env:PGPASSWORD = $DB_PASSWORD
        $clearSQL | & psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Database cleared successfully!" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to clear database. Exit code: $LASTEXITCODE" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "❌ Error during database clear: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "=== Database Cleared ===" -ForegroundColor Green
Write-Host ""
Write-Host "The database is now empty and ready for:" -ForegroundColor Yellow
Write-Host "1. Restoring from backup" -ForegroundColor White
Write-Host "2. Running migrations from scratch" -ForegroundColor White
Write-Host ""

