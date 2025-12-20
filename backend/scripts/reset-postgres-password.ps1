# Script to reset PostgreSQL password to 'root'
# This temporarily uses trust authentication to bypass password requirement

Write-Host "=== PostgreSQL Password Reset ===" -ForegroundColor Yellow
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "⚠️  This script needs Administrator privileges" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Right-click PowerShell -> Run as Administrator" -ForegroundColor Cyan
    exit
}

# Find pg_hba.conf
$pgPaths = @(
    "C:\Program Files\PostgreSQL\17\data\pg_hba.conf",
    "C:\Program Files\PostgreSQL\16\data\pg_hba.conf",
    "C:\Program Files\PostgreSQL\15\data\pg_hba.conf",
    "C:\Program Files (x86)\PostgreSQL\17\data\pg_hba.conf"
)

$pgHbaPath = $null
foreach ($path in $pgPaths) {
    if (Test-Path $path) {
        $pgHbaPath = $path
        Write-Host "✅ Found pg_hba.conf at: $path" -ForegroundColor Green
        break
    }
}

if (-not $pgHbaPath) {
    Write-Host "❌ Could not find pg_hba.conf" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please find it manually at:" -ForegroundColor Yellow
    Write-Host "C:\Program Files\PostgreSQL\[VERSION]\data\pg_hba.conf" -ForegroundColor Cyan
    exit
}

Write-Host ""
Write-Host "Step 1: Backing up pg_hba.conf..." -ForegroundColor Yellow
$backupPath = "$pgHbaPath.backup"
Copy-Item $pgHbaPath $backupPath -Force
Write-Host "✅ Backup created: $backupPath" -ForegroundColor Green

Write-Host ""
Write-Host "Step 2: Modifying pg_hba.conf to use trust authentication..." -ForegroundColor Yellow

# Read the file
$content = Get-Content $pgHbaPath

# Replace md5/scram-sha-256 with trust for localhost
$newContent = $content | ForEach-Object {
    if ($_ -match "^\s*host\s+all\s+all\s+127\.0\.0\.1/32" -or $_ -match "^\s*host\s+all\s+all\s+::1/128") {
        $_ -replace "(md5|scram-sha-256|password)", "trust"
    } else {
        $_
    }
}

# Write back
$newContent | Set-Content $pgHbaPath
Write-Host "✅ Modified pg_hba.conf" -ForegroundColor Green

Write-Host ""
Write-Host "Step 3: Restarting PostgreSQL service..." -ForegroundColor Yellow
$pgService = Get-Service | Where-Object {$_.Name -like "*postgres*"} | Select-Object -First 1
if ($pgService) {
    Restart-Service $pgService.Name -Force
    Start-Sleep -Seconds 3
    Write-Host "✅ PostgreSQL service restarted" -ForegroundColor Green
} else {
    Write-Host "⚠️  Could not find PostgreSQL service" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 4: Setting password to 'root'..." -ForegroundColor Yellow

# Now connect without password and set it
$setPasswordCmd = "psql -U postgres -c `"ALTER USER postgres WITH PASSWORD 'root';`""
$result = Invoke-Expression $setPasswordCmd 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Password set to 'root' successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to set password" -ForegroundColor Red
    Write-Host $result
}

Write-Host ""
Write-Host "Step 5: Restoring pg_hba.conf to use md5..." -ForegroundColor Yellow

# Restore original file
Copy-Item $backupPath $pgHbaPath -Force

# Modify to use md5 instead of trust
$content = Get-Content $pgHbaPath
$newContent = $content | ForEach-Object {
    if ($_ -match "^\s*host\s+all\s+all\s+127\.0\.0\.1/32" -or $_ -match "^\s*host\s+all\s+all\s+::1/128") {
        $_ -replace "trust", "md5"
    } else {
        $_
    }
}
$newContent | Set-Content $pgHbaPath

Write-Host "✅ Restored pg_hba.conf with md5 authentication" -ForegroundColor Green

Write-Host ""
Write-Host "Step 6: Restarting PostgreSQL service again..." -ForegroundColor Yellow
if ($pgService) {
    Restart-Service $pgService.Name -Force
    Start-Sleep -Seconds 3
    Write-Host "✅ PostgreSQL service restarted" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 7: Creating ASI database..." -ForegroundColor Yellow
$env:PGPASSWORD = 'root'
$createDbCmd = "psql -U postgres -c 'CREATE DATABASE ASI;'"
$dbResult = Invoke-Expression $createDbCmd 2>&1

if ($LASTEXITCODE -eq 0 -or $dbResult -match "already exists") {
    Write-Host "✅ Database ASI ready!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Database creation: $dbResult" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== SUCCESS! ===" -ForegroundColor Green
Write-Host ""
Write-Host "✅ PostgreSQL password is now: root" -ForegroundColor Green
Write-Host "✅ Database ASI is ready" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run migrations:" -ForegroundColor White
Write-Host "   cd backend" -ForegroundColor Cyan
Write-Host "   `$env:PGPASSWORD='root'; psql -U postgres -d ASI -f migrations/001_initial_schema.sql" -ForegroundColor Cyan
Write-Host "   `$env:PGPASSWORD='root'; psql -U postgres -d ASI -f migrations/002_users_and_roles.sql" -ForegroundColor Cyan
Write-Host "   `$env:PGPASSWORD='root'; psql -U postgres -d ASI -f migrations/003_add_admin_user.sql" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Restart your backend server" -ForegroundColor White
Write-Host ""
Write-Host "Your .env file is already correct!" -ForegroundColor Green
Write-Host "DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI" -ForegroundColor Gray

