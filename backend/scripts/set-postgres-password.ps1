# Script to set PostgreSQL password to 'root'
# Run this as Administrator

Write-Host "Setting PostgreSQL password to 'root'..." -ForegroundColor Yellow
Write-Host ""

# Try to connect and set password
$env:PGPASSWORD = ''
$result = psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'root';" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Password set successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your .env file should now work with:" -ForegroundColor Cyan
    Write-Host "DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI" -ForegroundColor White
} else {
    Write-Host "❌ Failed to set password. Error:" -ForegroundColor Red
    Write-Host $result
    Write-Host ""
    Write-Host "Try running this script as Administrator, or:" -ForegroundColor Yellow
    Write-Host "1. Connect manually: psql -U postgres" -ForegroundColor Cyan
    Write-Host "2. Run: ALTER USER postgres WITH PASSWORD 'root';" -ForegroundColor Cyan
}

































