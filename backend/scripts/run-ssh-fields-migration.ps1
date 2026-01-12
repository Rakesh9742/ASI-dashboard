# Script to run SSH fields migration on LOCAL PostgreSQL (not Docker)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running SSH Fields Migration (Local PostgreSQL)" -ForegroundColor Cyan
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
        $migrationPath = Join-Path (Get-Location) "backend\migrations\012_add_ssh_fields_to_users.sql"
        
        if (-not (Test-Path $migrationPath)) {
            Write-Host "Error: Migration file not found at: $migrationPath" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Running migration: Add SSH fields to users table..." -ForegroundColor Yellow
        Get-Content $migrationPath | & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ SSH fields added to users table!" -ForegroundColor Green
        } else {
            Write-Host "❌ Error adding SSH fields" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "Verifying SSH fields in users table..." -ForegroundColor Cyan
        & "psql" -h $dbHost -p $dbPort -U $dbUser -d $dbName -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users' AND column_name IN ('ipaddress', 'port', 'ssh_user', 'sshpassword_hash') ORDER BY column_name;"
        
        Write-Host ""
        Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "The following fields have been added to the users table:" -ForegroundColor Cyan
        Write-Host "  - ipaddress (VARCHAR)" -ForegroundColor White
        Write-Host "  - port (INTEGER)" -ForegroundColor White
        Write-Host "  - ssh_user (VARCHAR)" -ForegroundColor White
        Write-Host "  - sshpassword_hash (VARCHAR)" -ForegroundColor White
    } else {
        Write-Host "Error: Could not parse DATABASE_URL from .env file" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Error: .env file not found at: $envFile" -ForegroundColor Red
    Write-Host "Please run this script from the project root directory." -ForegroundColor Yellow
    exit 1
}

