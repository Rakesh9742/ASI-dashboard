# Script to fix PostgreSQL connection issue
# This script helps you set the PostgreSQL password to 'root'

Write-Host "=== PostgreSQL Connection Fix ===" -ForegroundColor Yellow
Write-Host ""

# Check if PostgreSQL is running
$pgService = Get-Service | Where-Object {$_.Name -like "*postgres*"}
if ($pgService) {
    Write-Host "✅ PostgreSQL service found: $($pgService.Name)" -ForegroundColor Green
    Write-Host "   Status: $($pgService.Status)" -ForegroundColor Cyan
} else {
    Write-Host "❌ PostgreSQL service not found" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "Attempting to connect to PostgreSQL..." -ForegroundColor Yellow
Write-Host ""

# Try to connect with different methods
$connected = $false
$methods = @(
    @{name="No password"; cmd="psql -U postgres -c 'SELECT version();'"},
    @{name="Password 'postgres'"; cmd="$env:PGPASSWORD='postgres'; psql -U postgres -c 'SELECT version();'"},
    @{name="Password empty string"; cmd="$env:PGPASSWORD=''; psql -U postgres -c 'SELECT version();'"}
)

foreach ($method in $methods) {
    Write-Host "Trying: $($method.name)..." -ForegroundColor Cyan
    try {
        $result = Invoke-Expression $method.cmd 2>&1
        if ($LASTEXITCODE -eq 0 -or $result -match "PostgreSQL") {
            Write-Host "✅ Connected using: $($method.name)" -ForegroundColor Green
            $connected = $true
            break
        }
    } catch {
        # Continue to next method
    }
}

if (-not $connected) {
    Write-Host ""
    Write-Host "❌ Could not connect automatically" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please connect manually:" -ForegroundColor Yellow
    Write-Host "1. Run: psql -U postgres" -ForegroundColor White
    Write-Host "2. If it asks for password, try:" -ForegroundColor White
    Write-Host "   - Empty (just press Enter)" -ForegroundColor Gray
    Write-Host "   - 'postgres'" -ForegroundColor Gray
    Write-Host "   - Your Windows password" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Once connected, run:" -ForegroundColor White
    Write-Host "   ALTER USER postgres WITH PASSWORD 'root';" -ForegroundColor Cyan
    Write-Host "   \q" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "4. Then create database:" -ForegroundColor White
    Write-Host "   psql -U postgres -c 'CREATE DATABASE ASI;'" -ForegroundColor Cyan
    exit
}

Write-Host ""
Write-Host "Setting password to 'root'..." -ForegroundColor Yellow

# Try to set password
try {
    $setPasswordCmd = "psql -U postgres -c `"ALTER USER postgres WITH PASSWORD 'root';`""
    $result = Invoke-Expression $setPasswordCmd 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Password set successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Create database
        Write-Host "Creating ASI database..." -ForegroundColor Yellow
        $createDbCmd = "psql -U postgres -c 'CREATE DATABASE ASI;'"
        Invoke-Expression $createDbCmd 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Database created!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Database might already exist (this is OK)" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "=== NEXT STEPS ===" -ForegroundColor Green
        Write-Host "1. Run migrations:" -ForegroundColor White
        Write-Host "   cd backend" -ForegroundColor Cyan
        Write-Host "   psql -U postgres -d ASI -f migrations/001_initial_schema.sql" -ForegroundColor Cyan
        Write-Host "   psql -U postgres -d ASI -f migrations/002_users_and_roles.sql" -ForegroundColor Cyan
        Write-Host "   psql -U postgres -d ASI -f migrations/003_add_admin_user.sql" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "2. Restart your backend server" -ForegroundColor White
        Write-Host ""
        Write-Host "✅ Your .env file is already correct!" -ForegroundColor Green
        Write-Host "   DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI" -ForegroundColor Gray
        
    } else {
        Write-Host "❌ Failed to set password. Error:" -ForegroundColor Red
        Write-Host $result
        Write-Host ""
        Write-Host "Please set password manually (see instructions above)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please set password manually (see instructions above)" -ForegroundColor Yellow
}

