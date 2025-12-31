# Replace Stage API - Interactive PowerShell Script
# This script helps you replace a stage by uploading a file

# Default values (can be overridden)
$script:BASE_URL = if ($env:BASE_URL) { $env:BASE_URL } else { "http://localhost:3000" }
$script:API_KEY = if ($env:API_KEY) { $env:API_KEY } else { "sitedafilesdata" }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Replace Stage API - Interactive Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to prompt for input with default value
function Get-InputWithDefault {
    param(
        [string]$Prompt,
        [string]$DefaultValue,
        [string]$Required = $false
    )
    
    if ($DefaultValue) {
        $input = Read-Host "$Prompt [$DefaultValue]"
        if ([string]::IsNullOrWhiteSpace($input)) {
            $input = $DefaultValue
        }
    } else {
        $input = Read-Host "$Prompt"
    }
    
    if ($Required -and [string]::IsNullOrWhiteSpace($input)) {
        Write-Host "Error: This field is required!" -ForegroundColor Red
        exit 1
    }
    
    return $input
}

# Function to validate file exists
function Test-FileValid {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "Error: File not found: $FilePath" -ForegroundColor Red
        exit 1
    }
    
    $ext = [System.IO.Path]::GetExtension($FilePath).TrimStart('.')
    $ext = $ext.ToLower()
    
    if ($ext -ne "csv" -and $ext -ne "json") {
        Write-Host "Error: File must be CSV or JSON format. Got: .$ext" -ForegroundColor Red
        exit 1
    }
}

# Get inputs from user
Write-Host "Enter the following information:" -ForegroundColor Yellow
Write-Host ""

# Base URL (should be just the base, e.g., http://localhost:3000)
$BASE_URL = Get-InputWithDefault -Prompt "Base URL (e.g., http://localhost:3000)" -DefaultValue $script:BASE_URL

# API Key
$API_KEY = Get-InputWithDefault -Prompt "API Key" -DefaultValue $script:API_KEY -Required $true

# Project name
$PROJECT_NAME = Get-InputWithDefault -Prompt "Project Name" -DefaultValue "project1" -Required $true

# Block name
$BLOCK_NAME = Get-InputWithDefault -Prompt "Block Name" -DefaultValue "cpu_core" -Required $true

# Experiment
$EXPERIMENT = Get-InputWithDefault -Prompt "Experiment" -DefaultValue "exp_001" -Required $true

# RTL Tag
$RTL_TAG = Get-InputWithDefault -Prompt "RTL Tag" -DefaultValue "v1.2.3" -Required $true

# Stage name
$STAGE_NAME = Get-InputWithDefault -Prompt "Stage Name (e.g., syn, place, route)" -DefaultValue "syn" -Required $true

# File path
Write-Host ""
$FILE_PATH = Read-Host "File Path (CSV or JSON)"
if ([string]::IsNullOrWhiteSpace($FILE_PATH)) {
    Write-Host "Error: File path is required!" -ForegroundColor Red
    exit 1
}
Test-FileValid -FilePath $FILE_PATH

# Confirm before sending
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  Confirmation" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Base URL:    " -NoNewline
Write-Host $BASE_URL -ForegroundColor Green
Write-Host "API Key:     " -NoNewline
Write-Host "$($API_KEY.Substring(0, [Math]::Min(10, $API_KEY.Length)))..." -ForegroundColor Green
Write-Host "Project:     " -NoNewline
Write-Host $PROJECT_NAME -ForegroundColor Green
Write-Host "Block:       " -NoNewline
Write-Host $BLOCK_NAME -ForegroundColor Green
Write-Host "Experiment:  " -NoNewline
Write-Host $EXPERIMENT -ForegroundColor Green
Write-Host "RTL Tag:     " -NoNewline
Write-Host $RTL_TAG -ForegroundColor Green
Write-Host "Stage:       " -NoNewline
Write-Host $STAGE_NAME -ForegroundColor Green
Write-Host "File:        " -NoNewline
Write-Host $FILE_PATH -ForegroundColor Green
Write-Host ""

$CONFIRM = Read-Host "Proceed with replacing the stage? (y/N)"
if ($CONFIRM -notmatch "^[Yy]$") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

# Make API call
Write-Host ""
Write-Host "Sending request to API..." -ForegroundColor Cyan
Write-Host ""

try {
    # Check if curl is available (simpler and more reliable)
    $curlAvailable = Get-Command curl.exe -ErrorAction SilentlyContinue
    
    if ($curlAvailable) {
        # Use curl for multipart/form-data (most reliable)
        Write-Host "Using curl for file upload..." -ForegroundColor Cyan
        
        # Check if BASE_URL already contains the full path
        if ($BASE_URL -match "/api/eda-files/external/replace-stage$") {
            $uri = $BASE_URL
        } else {
            $uri = "$BASE_URL/api/eda-files/external/replace-stage"
        }
        
        $curlArgs = @(
            "-X", "POST",
            "-H", "X-API-Key: $API_KEY",
            "-F", "file=@`"$FILE_PATH`"",
            "-F", "project=$PROJECT_NAME",
            "-F", "block_name=$BLOCK_NAME",
            "-F", "experiment=$EXPERIMENT",
            "-F", "rtl_tag=$RTL_TAG",
            "-F", "stage_name=$STAGE_NAME",
            "-s", "-w", "`n%{http_code}",
            $uri
        )
        
        $output = & curl.exe $curlArgs
        $httpCode = ($output | Select-Object -Last 1).Trim()
        $body = ($output | Select-Object -SkipLast 1) -join "`n"
        
        # Create a response-like object for compatibility
        $response = New-Object PSObject -Property @{
            StatusCode = [int]$httpCode
            Content = $body
        }
    } else {
        # Fallback: Use .NET HttpClient for PowerShell 5.1
        Write-Host "Using .NET HttpClient for file upload..." -ForegroundColor Cyan
        
        Add-Type -AssemblyName System.Net.Http
        
        # Check if BASE_URL already contains the full path
        if ($BASE_URL -match "/api/eda-files/external/replace-stage$") {
            $uriString = $BASE_URL
        } else {
            $uriString = "$BASE_URL/api/eda-files/external/replace-stage"
        }
        $uri = New-Object System.Uri($uriString)
        $client = New-Object System.Net.Http.HttpClient
        $client.DefaultRequestHeaders.Add("X-API-Key", $API_KEY)
        
        $content = New-Object System.Net.Http.MultipartFormDataContent
        
        # Add file
        $fileStream = [System.IO.File]::OpenRead($FILE_PATH)
        $fileName = [System.IO.Path]::GetFileName($FILE_PATH)
        $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
        $fileContent.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream")
        $content.Add($fileContent, "file", $fileName)
        
        # Add form fields
        $content.Add((New-Object System.Net.Http.StringContent($PROJECT_NAME)), "project")
        $content.Add((New-Object System.Net.Http.StringContent($BLOCK_NAME)), "block_name")
        $content.Add((New-Object System.Net.Http.StringContent($EXPERIMENT)), "experiment")
        $content.Add((New-Object System.Net.Http.StringContent($RTL_TAG)), "rtl_tag")
        $content.Add((New-Object System.Net.Http.StringContent($STAGE_NAME)), "stage_name")
        
        # Make request
        $response = $client.PostAsync($uri, $content).Result
        $httpCode = [int]$response.StatusCode
        $body = $response.Content.ReadAsStringAsync().Result
        
        $fileStream.Close()
        $client.Dispose()
        
        # Create a response-like object for compatibility
        $response = New-Object PSObject -Property @{
            StatusCode = $httpCode
            Content = $body
        }
    }
    
    $httpCode = $response.StatusCode
    $body = $response.Content
    
    # Display results
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Response" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($httpCode -eq 200) {
        Write-Host "[SUCCESS] HTTP $httpCode" -ForegroundColor Green
        Write-Host ""
        
        try {
            $json = $body | ConvertFrom-Json
            $json | ConvertTo-Json -Depth 10 | Write-Host
            
            if ($json.data) {
                Write-Host ""
                Write-Host "Stage replaced successfully!" -ForegroundColor Green
                Write-Host "  Old Stage ID: $($json.data.old_stage_id)"
                Write-Host "  New Stage ID: $($json.data.new_stage_id)"
            }
        } catch {
            Write-Host $body
        }
    } elseif ($httpCode -eq 400) {
        Write-Host "[ERROR] Bad Request (HTTP $httpCode)" -ForegroundColor Red
        Write-Host ""
        try {
            $json = $body | ConvertFrom-Json
            $json | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Host $body
        }
    } elseif ($httpCode -eq 401) {
        Write-Host "[ERROR] Unauthorized (HTTP $httpCode)" -ForegroundColor Red
        Write-Host "Invalid API key!" -ForegroundColor Red
        Write-Host ""
        try {
            $json = $body | ConvertFrom-Json
            $json | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Host $body
        }
    } elseif ($httpCode -eq 404) {
        Write-Host "[ERROR] Not Found (HTTP $httpCode)" -ForegroundColor Red
        Write-Host "Stage, project, block, or run not found!" -ForegroundColor Red
        Write-Host ""
        try {
            $json = $body | ConvertFrom-Json
            $json | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Host $body
        }
    } elseif ($httpCode -eq 500) {
        Write-Host "[ERROR] Server Error (HTTP $httpCode)" -ForegroundColor Red
        Write-Host ""
        try {
            $json = $body | ConvertFrom-Json
            $json | ConvertTo-Json -Depth 10 | Write-Host
        } catch {
            Write-Host $body
        }
    } else {
        Write-Host "[WARNING] Unexpected response (HTTP $httpCode)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host $body
    }
    
    Write-Host ""
    
    # Exit with appropriate code
    if ($httpCode -eq 200) {
        exit 0
    } else {
        exit 1
    }
    
} catch {
    Write-Host ""
    Write-Host "Error making request:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "HTTP Status: $statusCode" -ForegroundColor Red
        
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
            
            Write-Host ""
            Write-Host "Response body:" -ForegroundColor Yellow
            try {
                $json = $responseBody | ConvertFrom-Json
                $json | ConvertTo-Json -Depth 10 | Write-Host
            } catch {
                Write-Host $responseBody
            }
        } catch {
            # Could not read response body
        }
    }
    
    exit 1
}

