# Script to create the Physical Design schema tables
# This creates the new table structure for Physical Design data

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Creating Physical Design Schema" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Read database connection from .env
$envFile = Join-Path (Get-Location) "backend\.env"
if (Test-Path $envFile) {
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
        
        # Get migration file path
        $migrationPath = Join-Path (Get-Location) "backend\migrations\010_create_physical_design_schema.sql"
        
        if (-not (Test-Path $migrationPath)) {
            Write-Host "Error: Migration file not found at: $migrationPath" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Running migration: Create Physical Design schema..." -ForegroundColor Yellow
        Get-Content $migrationPath | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Physical Design schema created successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Verifying tables..." -ForegroundColor Cyan
            & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('blocks', 'runs', 'stages', 'stage_timing_metrics', 'stage_constraint_metrics', 'path_groups', 'drv_violations', 'power_ir_em_checks', 'physical_verification', 'ai_summaries') ORDER BY table_name;"
            Write-Host ""
            Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Schema Hierarchy:" -ForegroundColor Cyan
            Write-Host "  projects (linked to domains via project_domains)" -ForegroundColor White
            Write-Host "    └── blocks" -ForegroundColor White
            Write-Host "        └── runs" -ForegroundColor White
            Write-Host "            └── stages" -ForegroundColor White
            Write-Host "                ├── stage_timing_metrics" -ForegroundColor White
            Write-Host "                ├── stage_constraint_metrics" -ForegroundColor White
            Write-Host "                ├── path_groups" -ForegroundColor White
            Write-Host "                ├── drv_violations" -ForegroundColor White
            Write-Host "                ├── power_ir_em_checks" -ForegroundColor White
            Write-Host "                ├── physical_verification" -ForegroundColor White
            Write-Host "                └── ai_summaries" -ForegroundColor White
        } else {
            Write-Host "❌ Error creating Physical Design schema" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Error: Could not parse DATABASE_URL from .env file" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Error: .env file not found at: $envFile" -ForegroundColor Red
    Write-Host "Please run this script from the project root directory." -ForegroundColor Yellow
    exit 1
}




















