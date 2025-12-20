# Add domains table to Docker PostgreSQL database

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Adding Domains Table to Docker Database" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is running
try {
    $null = docker ps 2>&1
} catch {
    Write-Host "Error: Docker is not running!" -ForegroundColor Red
    Write-Host "Please start Docker Desktop first." -ForegroundColor Yellow
    exit 1
}

# Check if container exists
$container = docker ps -a --filter "name=asi_postgres" --format "{{.Names}}"
if (-not $container) {
    Write-Host "Error: Container 'asi_postgres' not found!" -ForegroundColor Red
    Write-Host "Please start the containers with: docker-compose up -d" -ForegroundColor Yellow
    exit 1
}

# Check if container is running
$running = docker ps --filter "name=asi_postgres" --format "{{.Names}}"
if (-not $running) {
    Write-Host "Container exists but is not running. Starting it..." -ForegroundColor Yellow
    docker start asi_postgres
    Start-Sleep -Seconds 3
}

Write-Host "Container is running: $running" -ForegroundColor Green
Write-Host ""

# Get migration file path
$migrationPath = Join-Path (Get-Location) "backend\migrations\004_add_domains_table.sql"

if (-not (Test-Path $migrationPath)) {
    Write-Host "Error: Migration file not found at: $migrationPath" -ForegroundColor Red
    exit 1
}

Write-Host "Running migration..." -ForegroundColor Yellow
Write-Host ""

# Execute migration
Get-Content $migrationPath | docker exec -i asi_postgres psql -U postgres -d ASI

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verifying domains table..." -ForegroundColor Cyan
    docker exec -i asi_postgres psql -U postgres -d ASI -c "SELECT id, code, name, is_active FROM domains ORDER BY id;"
    Write-Host ""
    Write-Host "✅ Domains table is ready!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "❌ Migration failed. Check the error above." -ForegroundColor Red
    exit 1
}

