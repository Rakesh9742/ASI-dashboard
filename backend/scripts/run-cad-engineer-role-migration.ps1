# Script to run CAD Engineer role migration on LOCAL PostgreSQL (not Docker)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running CAD Engineer Role Migration (Local PostgreSQL)" -ForegroundColor Cyan
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
        $migrationPath = Join-Path (Get-Location) "backend\migrations\022_add_cad_engineer_role.sql"
        
        if (-not (Test-Path $migrationPath)) {
            Write-Host "Error: Migration file not found at: $migrationPath" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Running migration: Add CAD Engineer role..." -ForegroundColor Yellow
        Write-Host "File: 022_add_cad_engineer_role.sql" -ForegroundColor Gray
        Write-Host ""
        
        Get-Content $migrationPath | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "❌ Error running migration" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Verifying user_role enum..." -ForegroundColor Cyan
        & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT enumlabel FROM pg_enum WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'user_role') ORDER BY enumlabel;"
        
        Write-Host ""
        Write-Host "✅ CAD Engineer role migration completed and verified!" -ForegroundColor Green
    } else {
        Write-Host "Error: Could not parse DATABASE_URL from .env file" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Error: .env file not found at: $envFile" -ForegroundColor Red
    Write-Host "Please run this script from the project root directory." -ForegroundColor Yellow
    exit 1
}

