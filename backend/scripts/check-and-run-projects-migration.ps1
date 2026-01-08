# Check and run projects migration
$env:PGPASSWORD = "root"

Write-Host "Checking if projects table exists in 'asi' database..." -ForegroundColor Cyan

# Check if projects table exists
$checkQuery = "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'projects');"
$result = psql -h localhost -U postgres -d asi -t -c $checkQuery 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error connecting to database. Please check:" -ForegroundColor Red
    Write-Host "1. PostgreSQL is running" -ForegroundColor Yellow
    Write-Host "2. Database 'asi' exists" -ForegroundColor Yellow
    Write-Host "3. User 'postgres' has access with password 'root'" -ForegroundColor Yellow
    exit 1
}

$tableExists = $result.Trim()

if ($tableExists -eq "t" -or $tableExists -eq "true") {
    Write-Host "✅ Projects table already exists!" -ForegroundColor Green
    
    # Check if project_domains table exists
    $checkDomainsQuery = "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'project_domains');"
    $domainsResult = psql -h localhost -U postgres -d asi -t -c $checkDomainsQuery 2>&1
    $domainsExists = $domainsResult.Trim()
    
    if ($domainsExists -eq "t" -or $domainsExists -eq "true") {
        Write-Host "✅ project_domains table already exists!" -ForegroundColor Green
        Write-Host "Migration already applied. No action needed." -ForegroundColor Green
    } else {
        Write-Host "⚠️  project_domains table missing. Running migration..." -ForegroundColor Yellow
        psql -h localhost -U postgres -d asi -f "migrations\006_create_projects.sql"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "❌ Migration failed!" -ForegroundColor Red
            exit 1
        }
    }
} else {
    Write-Host "⚠️  Projects table not found. Running migration..." -ForegroundColor Yellow
    $migrationPath = Join-Path $PSScriptRoot "..\migrations\006_create_projects.sql"
    psql -h localhost -U postgres -d asi -f $migrationPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Migration completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Migration failed!" -ForegroundColor Red
        exit 1
    }
}

# Verify tables exist
Write-Host "`nVerifying tables..." -ForegroundColor Cyan
psql -h localhost -U postgres -d asi -c "\d projects"
Write-Host ""
psql -h localhost -U postgres -d asi -c "\d project_domains"

Write-Host "`n✅ Database schema check complete!" -ForegroundColor Green












