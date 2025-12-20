# Script to run domains migrations on LOCAL PostgreSQL (not Docker)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running Domains Migrations (Local PostgreSQL)" -ForegroundColor Cyan
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
        
        Write-Host "Database: $dbName on $dbHost:$dbPort" -ForegroundColor Green
        Write-Host ""
        
        # Set PGPASSWORD environment variable
        $env:PGPASSWORD = $dbPass
        
        # Get migration file paths
        $migration1Path = Join-Path (Get-Location) "backend\migrations\004_add_domains_table.sql"
        $migration2Path = Join-Path (Get-Location) "backend\migrations\005_add_domain_to_users.sql"
        
        if (-not (Test-Path $migration1Path)) {
            Write-Host "Error: Migration file not found at: $migration1Path" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Running migration 1: Create domains table..." -ForegroundColor Yellow
        Get-Content $migration1Path | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Domains table created!" -ForegroundColor Green
        } else {
            Write-Host "❌ Error creating domains table" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Running migration 2: Add domain_id to users table..." -ForegroundColor Yellow
        Get-Content $migration2Path | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Domain_id column added to users table!" -ForegroundColor Green
        } else {
            Write-Host "❌ Error adding domain_id column" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Verifying domains table..." -ForegroundColor Cyan
        & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT id, code, name, is_active FROM domains ORDER BY id;"
        
        Write-Host ""
        Write-Host "✅ All migrations completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Error: Could not parse DATABASE_URL from .env file" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Error: .env file not found at: $envFile" -ForegroundColor Red
    Write-Host "Please run this script from the project root directory." -ForegroundColor Yellow
    exit 1
}




