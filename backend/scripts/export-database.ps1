# Script to export PostgreSQL database
# Supports both Docker and local PostgreSQL instances

param(
    [string]$OutputPath = "",
    [string]$Format = "plain",  # plain, custom, tar, directory
    [switch]$DataOnly = $false,
    [switch]$SchemaOnly = $false,
    [switch]$Docker = $false,
    [switch]$Local = $false
)

Write-Host "=== PostgreSQL Database Export ===" -ForegroundColor Yellow
Write-Host ""

# Database configuration
$DB_NAME = "asi"  # Note: PostgreSQL converts unquoted names to lowercase
$DB_USER = "postgres"
$DB_PASSWORD = "root"
$DB_HOST = "localhost"
$DB_PORT = "5432"
$DOCKER_CONTAINER = "asi_postgres"

# Determine if using Docker or local PostgreSQL
$useDocker = $false

if ($Docker) {
    $useDocker = $true
} elseif ($Local) {
    $useDocker = $false
} else {
    # Auto-detect: Check if Docker container is running
    $containerStatus = docker ps --filter "name=$DOCKER_CONTAINER" --format "{{.Status}}" 2>$null
    if ($containerStatus -and $containerStatus -match "Up") {
        Write-Host "✅ Docker container '$DOCKER_CONTAINER' is running" -ForegroundColor Green
        $useDocker = $true
    } else {
        Write-Host "⚠️  Docker container not found, using local PostgreSQL" -ForegroundColor Yellow
        $useDocker = $false
    }
}

Write-Host ""
Write-Host "Export Configuration:" -ForegroundColor Cyan
Write-Host "  Database: $DB_NAME" -ForegroundColor Gray
Write-Host "  User: $DB_USER" -ForegroundColor Gray
Write-Host "  Host: $DB_HOST" -ForegroundColor Gray
Write-Host "  Port: $DB_PORT" -ForegroundColor Gray
Write-Host "  Source: $(if ($useDocker) { "Docker Container" } else { "Local PostgreSQL" })" -ForegroundColor Gray
Write-Host "  Format: $Format" -ForegroundColor Gray
Write-Host ""

# Generate output filename if not provided
if ([string]::IsNullOrEmpty($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $extension = switch ($Format) {
        "plain" { "sql" }
        "custom" { "dump" }
        "tar" { "tar" }
        "directory" { "dir" }
        default { "sql" }
    }
    $OutputPath = "ASI_backup_$timestamp.$extension"
}

# Ensure output directory exists
$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "✅ Created output directory: $outputDir" -ForegroundColor Green
}

# Build pg_dump command
$dumpOptions = @()

if ($DataOnly) {
    $dumpOptions += "--data-only"
    Write-Host "  Mode: Data only" -ForegroundColor Gray
}

if ($SchemaOnly) {
    $dumpOptions += "--schema-only"
    Write-Host "  Mode: Schema only" -ForegroundColor Gray
}

# Format-specific options
switch ($Format) {
    "custom" {
        $dumpOptions += "--format=custom"
        $dumpOptions += "--compress=9"
    }
    "tar" {
        $dumpOptions += "--format=tar"
    }
    "directory" {
        $dumpOptions += "--format=directory"
        $dumpOptions += "--compress=9"
    }
    default {
        $dumpOptions += "--format=plain"
    }
}

# Additional useful options
$dumpOptions += "--verbose"
$dumpOptions += "--no-owner"
$dumpOptions += "--no-privileges"

# Build the full command
if ($useDocker) {
    # Export from Docker container
    Write-Host "Exporting from Docker container..." -ForegroundColor Yellow
    
    $dockerCmd = "docker exec -i $DOCKER_CONTAINER pg_dump"
    $dockerCmd += " -U $DB_USER"
    $dockerCmd += " -d $DB_NAME"
    $dockerCmd += " " + ($dumpOptions -join " ")
    
    Write-Host "Running: $dockerCmd" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Set password via environment variable in Docker
        $env:PGPASSWORD = $DB_PASSWORD
        docker exec -e PGPASSWORD=$DB_PASSWORD $DOCKER_CONTAINER pg_dump -U $DB_USER -d $DB_NAME $dumpOptions | Out-File -FilePath $OutputPath -Encoding UTF8
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Database exported successfully!" -ForegroundColor Green
        } else {
            Write-Host "❌ Export failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "❌ Error during export: $_" -ForegroundColor Red
        exit 1
    }
} else {
    # Export from local PostgreSQL
    Write-Host "Exporting from local PostgreSQL..." -ForegroundColor Yellow
    
    # Check if pg_dump is available
    $pgDumpPath = Get-Command pg_dump -ErrorAction SilentlyContinue
    if (-not $pgDumpPath) {
        Write-Host "❌ pg_dump not found in PATH" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure PostgreSQL client tools are installed and in your PATH." -ForegroundColor Yellow
        Write-Host "Or use Docker export by running: .\export-database.ps1 -Docker" -ForegroundColor Yellow
        exit 1
    }
    
    $localCmd = "pg_dump"
    $localCmd += " -h $DB_HOST"
    $localCmd += " -p $DB_PORT"
    $localCmd += " -U $DB_USER"
    $localCmd += " -d $DB_NAME"
    $localCmd += " " + ($dumpOptions -join " ")
    $localCmd += " -f `"$OutputPath`""
    
    Write-Host "Running: $localCmd" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $env:PGPASSWORD = $DB_PASSWORD
        & pg_dump -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME $dumpOptions -f $OutputPath
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Database exported successfully!" -ForegroundColor Green
        } else {
            Write-Host "❌ Export failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "❌ Error during export: $_" -ForegroundColor Red
        exit 1
    }
}

# Display file information
Write-Host ""
Write-Host "=== Export Complete ===" -ForegroundColor Green
Write-Host "Output file: $OutputPath" -ForegroundColor Cyan

if (Test-Path $OutputPath) {
    $fileInfo = Get-Item $OutputPath
    $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
    Write-Host "File size: $fileSize MB" -ForegroundColor Gray
    Write-Host "Created: $($fileInfo.CreationTime)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "To restore this backup, use:" -ForegroundColor Yellow
if ($useDocker) {
    Write-Host "  docker exec -i $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME < $OutputPath" -ForegroundColor White
} else {
    Write-Host "  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f $OutputPath" -ForegroundColor White
}
Write-Host ""

