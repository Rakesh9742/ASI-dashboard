# Script to add domains table to Docker PostgreSQL database

Write-Host "Adding domains table to Docker database..." -ForegroundColor Yellow
Write-Host ""

# Check if Docker container is running
$containerRunning = docker ps --filter "name=asi_postgres" --format "{{.Names}}"

if (-not $containerRunning) {
    Write-Host "Error: Docker container 'asi_postgres' is not running!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please start Docker Desktop and run:" -ForegroundColor Yellow
    Write-Host "  docker-compose up -d postgres" -ForegroundColor Cyan
    exit 1
}

Write-Host "Container found: $containerRunning" -ForegroundColor Green
Write-Host ""

# Get the migration file content
$migrationFile = Join-Path $PSScriptRoot "..\migrations\004_add_domains_table.sql"

if (-not (Test-Path $migrationFile)) {
    Write-Host "Error: Migration file not found: $migrationFile" -ForegroundColor Red
    exit 1
}

Write-Host "Running migration: 004_add_domains_table.sql" -ForegroundColor Cyan
Write-Host ""

# Execute the migration
Get-Content $migrationFile | docker exec -i asi_postgres psql -U postgres -d ASI

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Domains table created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verifying domains..." -ForegroundColor Yellow
    docker exec -i asi_postgres psql -U postgres -d ASI -c "SELECT id, code, name FROM domains ORDER BY id;"
} else {
    Write-Host ""
    Write-Host "❌ Error running migration. Check the error message above." -ForegroundColor Red
    exit 1
}

















