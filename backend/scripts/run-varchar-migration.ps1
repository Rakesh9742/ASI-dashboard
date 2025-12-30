# Script to convert Physical Design schema fields to VARCHAR
# This migration converts all numeric fields (INT, FLOAT) to VARCHAR(50)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Convert PD Schema Fields to VARCHAR" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Database connection details from .env
$dbHost = "localhost"
$dbPort = "5432"
$dbUser = "postgres"
$dbName = "asi"
$dbPassword = "root"

# Get the migration file path (go up one level from scripts folder)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Split-Path -Parent $scriptDir
$migrationPath = Join-Path $backendDir "migrations\011_convert_pd_fields_to_varchar.sql"

if (-not (Test-Path $migrationPath)) {
    Write-Host "❌ Migration file not found: $migrationPath" -ForegroundColor Red
    exit 1
}

Write-Host "Migration file: $migrationPath" -ForegroundColor Yellow
Write-Host ""

# Set PGPASSWORD environment variable
$env:PGPASSWORD = $dbPassword

Write-Host "Running migration: Convert PD fields to VARCHAR..." -ForegroundColor Yellow
Write-Host ""

# Run the migration
& "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -f $migrationPath

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "All numeric fields in Physical Design schema have been converted to VARCHAR(50)" -ForegroundColor Cyan
    Write-Host "This allows storing any value including decimals, 'N/A', and other text values" -ForegroundColor Cyan
    Write-Host ""
    
    # Verify the changes
    Write-Host "Verifying changes..." -ForegroundColor Yellow
    & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "
        SELECT 
            table_name,
            column_name,
            data_type
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name IN ('stage_timing_metrics', 'stage_constraint_metrics', 'stages', 'path_groups', 'drv_violations')
        AND column_name IN ('internal_r2r_nvp', 'hold_nvp', 'max_tran_nvp', 'wns', 'tns', 'nvp', 'log_errors', 'area', 'inst_count')
        ORDER BY table_name, column_name;
    "
} else {
    Write-Host ""
    Write-Host "❌ Error running migration" -ForegroundColor Red
    exit 1
}

# Clear the password from environment
$env:PGPASSWORD = $null

Write-Host ""
Write-Host "✅ Done!" -ForegroundColor Green

