# Script to run domains migrations on existing database

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running Domains Migrations" -ForegroundColor Cyan
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

# Check if container exists (try both possible names)
$container = docker ps -a --filter "name=asi_postgres" --format "{{.Names}}"
if (-not $container) {
    $container = docker ps -a --filter "name=asidashboard" --format "{{.Names}}"
}

if (-not $container) {
    Write-Host "Error: PostgreSQL container not found!" -ForegroundColor Red
    Write-Host "Please start the containers with: docker-compose up -d" -ForegroundColor Yellow
    Write-Host "Or check if you're using a local PostgreSQL instance instead." -ForegroundColor Yellow
    exit 1
}

# Get the actual container name
$containerName = $container

# Check if container is running
$running = docker ps --filter "name=$containerName" --format "{{.Names}}"
if (-not $running) {
    Write-Host "Container exists but is not running. Starting it..." -ForegroundColor Yellow
    docker start $containerName
    Start-Sleep -Seconds 3
}

Write-Host "Container is running: $running" -ForegroundColor Green
Write-Host ""

# Get migration file paths
$migration1Path = Join-Path (Get-Location) "backend\migrations\004_add_domains_table.sql"
$migration2Path = Join-Path (Get-Location) "backend\migrations\005_add_domain_to_users.sql"

if (-not (Test-Path $migration1Path)) {
    Write-Host "Error: Migration file not found at: $migration1Path" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $migration2Path)) {
    Write-Host "Error: Migration file not found at: $migration2Path" -ForegroundColor Red
    exit 1
}

Write-Host "Running migration 1: Create domains table..." -ForegroundColor Yellow
Get-Content $migration1Path | docker exec -i $containerName psql -U postgres -d ASI

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Domains table created!" -ForegroundColor Green
} else {
    Write-Host "❌ Error creating domains table" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Running migration 2: Add domain_id to users table..." -ForegroundColor Yellow
Get-Content $migration2Path | docker exec -i $containerName psql -U postgres -d ASI

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Domain_id column added to users table!" -ForegroundColor Green
} else {
    Write-Host "❌ Error adding domain_id column" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Verifying domains table..." -ForegroundColor Cyan
docker exec -i $containerName psql -U postgres -d ASI -c "SELECT id, code, name, is_active FROM domains ORDER BY id;"

Write-Host ""
Write-Host "✅ All migrations completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "The domains table is now ready!" -ForegroundColor Yellow

