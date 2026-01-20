# Script to restore data from backup file, handling conflicts
# This extracts only COPY/INSERT statements and runs them with conflict handling

param(
    [string]$BackupFile = "ASI_backup_20260120_203444.sql",
    [switch]$SkipErrors = $true
)

Write-Host "=== Restore Data from Backup ===" -ForegroundColor Yellow
Write-Host ""

# Database configuration
$DB_NAME = "asi"
$DB_USER = "postgres"
$DB_PASSWORD = "root"
$DB_HOST = "localhost"
$DB_PORT = "5432"

if (-not (Test-Path $BackupFile)) {
    Write-Host "❌ Backup file not found: $BackupFile" -ForegroundColor Red
    exit 1
}

Write-Host "Reading backup file: $BackupFile" -ForegroundColor Cyan
Write-Host ""

# Read the backup file
$content = Get-Content $BackupFile -Raw

# Extract COPY statements (data insertion)
$copyPattern = '(?s)(COPY\s+public\.\w+\s+\([^)]+\)\s+FROM\s+stdin;.*?\\\.)'
$copyMatches = [regex]::Matches($content, $copyPattern)

Write-Host "Found $($copyMatches.Count) COPY statements" -ForegroundColor Green
Write-Host ""

# Process each COPY statement
$successCount = 0
$errorCount = 0
$skippedCount = 0

foreach ($match in $copyMatches) {
    $copyStatement = $match.Value
    
    # Extract table name
    if ($copyStatement -match 'COPY\s+public\.(\w+)\s+') {
        $tableName = $matches[1]
        
        Write-Host "Processing table: $tableName" -ForegroundColor Cyan -NoNewline
        
        # Convert COPY to INSERT with ON CONFLICT handling
        # This is a simplified approach - for production, you'd want more sophisticated parsing
        try {
            # For now, we'll use a simpler approach: try to insert and catch errors
            $env:PGPASSWORD = $DB_PASSWORD
            
            # Extract the data lines (between FROM stdin; and \.)
            if ($copyStatement -match 'FROM stdin;(.*?)\\\.') {
                $dataLines = $matches[1].Trim()
                
                if ($dataLines) {
                    # Convert COPY format to INSERT statements
                    # Get column names
                    if ($copyStatement -match 'COPY\s+public\.\w+\s+\(([^)]+)\)') {
                        $columns = $matches[1] -split ',' | ForEach-Object { $_.Trim() }
                        
                        # Process each data line
                        $dataLinesArray = $dataLines -split "`n" | Where-Object { $_.Trim() -ne '' }
                        
                        foreach ($line in $dataLinesArray) {
                            # Parse tab-separated values
                            $values = $line -split "`t"
                            
                            # Build INSERT with ON CONFLICT DO NOTHING
                            $valuesStr = ($values | ForEach-Object { 
                                if ($_ -eq '\N' -or $_ -eq '') { 'NULL' }
                                else { "'" + ($_ -replace "'", "''") + "'" }
                            }) -join ', '
                            
                            $insertSQL = "INSERT INTO $tableName ($($columns -join ', ')) VALUES ($valuesStr) ON CONFLICT DO NOTHING;"
                            
                            try {
                                $result = $env:PGPASSWORD = $DB_PASSWORD; psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c $insertSQL 2>&1
                                if ($LASTEXITCODE -eq 0) {
                                    $successCount++
                                } else {
                                    if ($SkipErrors) {
                                        $skippedCount++
                                    } else {
                                        $errorCount++
                                        Write-Host "  ⚠️  Error: $result" -ForegroundColor Yellow
                                    }
                                }
                            } catch {
                                if ($SkipErrors) {
                                    $skippedCount++
                                } else {
                                    $errorCount++
                                }
                            }
                        }
                    }
                }
            }
            
            Write-Host " ✅" -ForegroundColor Green
        } catch {
            Write-Host " ❌ Error: $_" -ForegroundColor Red
            $errorCount++
        }
    }
}

Write-Host ""
Write-Host "=== Restore Complete ===" -ForegroundColor Green
Write-Host "  Success: $successCount" -ForegroundColor Green
Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
Write-Host "  Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

