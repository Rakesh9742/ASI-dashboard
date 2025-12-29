# Script to drop the eda_output_files table (Physical Design table)
# This drops the table and all related objects (indexes, triggers)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Dropping EDA Output Files Table" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  WARNING: This will DELETE the eda_output_files table and all its data!" -ForegroundColor Yellow
Write-Host ""

# Check if running in non-interactive mode
$nonInteractive = [Environment]::GetCommandLineArgs() -contains "-NonInteractive" -or $Host.Name -eq "Default Host"
if (-not $nonInteractive) {
    $confirm = Read-Host "Are you sure you want to proceed? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Running in non-interactive mode. Proceeding with table deletion..." -ForegroundColor Yellow
}

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
        $migrationPath = Join-Path (Get-Location) "backend\migrations\009_drop_eda_output_files.sql"
        
        if (-not (Test-Path $migrationPath)) {
            Write-Host "Error: Migration file not found at: $migrationPath" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Running migration: Drop eda_output_files table..." -ForegroundColor Yellow
        Get-Content $migrationPath | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ eda_output_files table dropped successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Verifying table deletion..." -ForegroundColor Cyan
            & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'eda_output_files');"
            Write-Host ""
            Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "You can now create a new table structure for Physical Design data." -ForegroundColor Cyan
        } else {
            Write-Host "❌ Error dropping eda_output_files table" -ForegroundColor Red
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

