# EDA Output Files - External API Documentation

This document provides detailed information for external developers who need to push EDA output files to the ASI Dashboard server.

## Table of Contents
1. [Overview](#overview)
2. [Authentication](#authentication)
3. [API Endpoint](#api-endpoint)
4. [Request Format](#request-format)
5. [Response Format](#response-format)
6. [File Requirements](#file-requirements)
7. [Examples](#examples)
8. [Error Handling](#error-handling)
9. [Rate Limits & Best Practices](#rate-limits--best-practices)

---

## Overview

The External API allows you to programmatically upload EDA (Electronic Design Automation) output files (CSV or JSON) to the ASI Dashboard server. Files are automatically processed and stored in the database with all Physical Design metrics.

**Base URL**: `https://your-server-domain.com` (or `http://localhost:3000` for development)

**API Endpoint**: `POST /api/eda-files/external/upload`

---

## Authentication

The External API uses **API Key authentication**. You must include a valid API key in your requests.

### Getting an API Key

Contact your system administrator to obtain an API key. The API key will be provided to you and should be kept secure.

### Using the API Key

You can provide the API key in one of two ways:

#### Option 1: HTTP Header (Recommended)
```
X-API-Key: your-api-key-here
```

#### Option 2: Query Parameter
```
?api_key=your-api-key-here
```

**Note**: The header method is recommended for security reasons, as query parameters may be logged in server logs.

---

## API Endpoint

### Upload EDA Output File

**Endpoint**: `POST /api/eda-files/external/upload`

**Description**: Uploads a CSV or JSON file containing EDA output data. The file is automatically processed and stored in the database.

**Authentication**: Required (API Key)

**Content-Type**: `multipart/form-data`

---

## Request Format

### Headers

```
Content-Type: multipart/form-data
X-API-Key: your-api-key-here
```

### Body

The request body must be `multipart/form-data` with a file field named `file`.

| Field Name | Type | Required | Description |
|------------|------|----------|-------------|
| `file` | File | Yes | The EDA output file (CSV or JSON) |

### File Field Details

- **Field name**: Must be exactly `file`
- **File types**: Only `.csv` and `.json` files are accepted
- **File size**: Maximum 100MB per file
- **Encoding**: UTF-8 recommended

---

## Response Format

### Success Response (201 Created)

```json
{
  "success": true,
  "message": "File uploaded and processed successfully",
  "data": {
    "fileId": 123,
    "fileName": "project1_domain1.json",
    "fileSize": 45678,
    "fileType": "json",
    "filePath": "/path/to/stored/file.json",
    "processedAt": "2024-01-15T10:30:00.000Z"
  }
}
```

### Error Responses

#### 400 Bad Request - No File Uploaded
```json
{
  "error": "No file uploaded",
  "message": "Please provide a file in the request. Use multipart/form-data with field name \"file\"."
}
```

#### 400 Bad Request - Invalid File Type
```json
{
  "error": "Invalid file type",
  "message": "Only CSV and JSON files are allowed",
  "received": "txt",
  "allowed": ["csv", "json"]
}
```

#### 401 Unauthorized - Missing API Key
```json
{
  "error": "API key required",
  "message": "Please provide an API key using X-API-Key header or api_key query parameter",
  "example": {
    "header": "X-API-Key: your-api-key-here",
    "query": "?api_key=your-api-key-here"
  }
}
```

#### 401 Unauthorized - Invalid API Key
```json
{
  "error": "Invalid API key",
  "message": "The provided API key is not valid"
}
```

#### 500 Internal Server Error - Processing Failed
```json
{
  "success": false,
  "error": "File processing failed",
  "message": "Project name is required",
  "data": {
    "fileName": "project1_domain1.json",
    "filePath": "/path/to/stored/file.json",
    "fileSize": 45678,
    "fileType": "json",
    "uploadedAt": "2024-01-15T10:30:00.000Z"
  }
}
```

---

## File Requirements

### Supported File Formats

1. **CSV Files** (`.csv`)
   - Must have headers in the first row
   - UTF-8 encoding recommended
   - Required columns: `project`, `block_name`, `experiment`, `rtl_tag`, `stage`
   - See [CSV Format](#csv-format) section for details

2. **JSON Files** (`.json`)
   - Must be valid JSON
   - UTF-8 encoding
   - Can be single object or array of objects
   - For Physical Design files, supports nested `stages` structure
   - See [JSON Format](#json-format) section for details

### Required Fields

The following fields are **required** in your files:

| Field | Description | Example |
|-------|-------------|---------|
| `project` or `project_name` | Project name | `"project1"` |
| `block_name` | Block/design name | `"cpu_core"` |
| `experiment` | Experiment identifier | `"exp_001"` |
| `rtl_tag` | RTL tag/version | `"v1.2.3"` |
| `stage` | Design stage name | `"syn"`, `"place"`, `"route"` |

### Optional Fields

The following fields are optional but recommended:

- `domain` or `domain_name` - Domain name
- `user_name` - User who ran the EDA tool
- `run_directory` - Directory path where the run was executed
- `run_end_time` or `timestamp` - Timestamp of the run
- `area` - Design area
- `inst_count` - Instance count
- `utilization` - Utilization percentage
- `run_status` - Status: `"pass"`, `"fail"`, or `"continue_with_error"`
- `runtime` - Runtime duration
- Timing metrics (WNS, TNS, NVP)
- Constraint metrics
- Power/IR/EM metrics
- Physical verification metrics

---

## CSV Format

### Example CSV File

```csv
project,domain,block_name,experiment,rtl_tag,user_name,stage,area,inst_count,utilization,run_status,runtime
project1,PD,cpu_core,exp_001,v1.2.3,user1,syn,1000000,50000,75.5,pass,3600
project1,PD,cpu_core,exp_001,v1.2.3,user1,place,1000000,50000,75.5,pass,7200
project1,PD,cpu_core,exp_001,v1.2.3,user1,route,1000000,50000,75.5,pass,10800
```

### CSV Column Mapping

The system automatically maps common column name variations:

| Your Column Name | Mapped To |
|-----------------|-----------|
| `project`, `Project`, `Project Name` | `project_name` |
| `domain`, `Domain`, `Domain Name`, `PD` | `domain_name` |
| `block_name`, `block`, `Block Name` | `block_name` |
| `experiment`, `Experiment` | `experiment` |
| `RTL _tag`, `rtl_tag`, `RTL Tag` | `rtl_tag` |
| `stage`, `Stage` | `stage` |

---

## JSON Format

### Single Object Format

```json
{
  "project": "project1",
  "domain": "PD",
  "block_name": "cpu_core",
  "experiment": "exp_001",
  "rtl_tag": "v1.2.3",
  "user_name": "user1",
  "run_directory": "/path/to/run",
  "timestamp": "2024-01-15T10:30:00Z",
  "stage": "syn",
  "area": 1000000,
  "inst_count": 50000,
  "utilization": 75.5,
  "run_status": "pass",
  "runtime": "3600"
}
```

### Array Format

```json
[
  {
    "project": "project1",
    "block_name": "cpu_core",
    "experiment": "exp_001",
    "rtl_tag": "v1.2.3",
    "stage": "syn",
    "area": 1000000
  },
  {
    "project": "project1",
    "block_name": "cpu_core",
    "experiment": "exp_001",
    "rtl_tag": "v1.2.3",
    "stage": "place",
    "area": 1000000
  }
]
```

### Physical Design JSON Format (with nested stages)

For Physical Design files, you can use a nested structure with a `stages` object:

```json
{
  "project": "project1",
  "domain": "PD",
  "block_name": "cpu_core",
  "experiment": "exp_001",
  "rtl_tag": "v1.2.3",
  "user_name": "user1",
  "run_directory": "/path/to/run",
  "last_updated": "2024-01-15T10:30:00Z",
  "stages": {
    "syn": {
      "area": 1000000,
      "inst_count": 50000,
      "utilization": 75.5,
      "run_status": "pass",
      "runtime": "3600",
      "internal_timing_r2r_wns": -0.5,
      "internal_timing_r2r_tns": -100,
      "internal_timing_r2r_nvp": 10
    },
    "place": {
      "area": 1000000,
      "inst_count": 50000,
      "utilization": 75.5,
      "run_status": "pass",
      "runtime": "7200"
    },
    "route": {
      "area": 1000000,
      "inst_count": 50000,
      "utilization": 75.5,
      "run_status": "pass",
      "runtime": "10800"
    }
  }
}
```

When using the nested `stages` format, each stage will be processed as a separate record in the database.

---

## Examples

### cURL Example

```bash
curl -X POST \
  https://your-server-domain.com/api/eda-files/external/upload \
  -H "X-API-Key: your-api-key-here" \
  -F "file=@/path/to/your/file.json"
```

### Python Example

```python
import requests

url = "https://your-server-domain.com/api/eda-files/external/upload"
api_key = "your-api-key-here"
file_path = "/path/to/your/file.json"

headers = {
    "X-API-Key": api_key
}

with open(file_path, 'rb') as f:
    files = {
        'file': (file_path.split('/')[-1], f, 'application/json')
    }
    
    response = requests.post(url, headers=headers, files=files)
    
    if response.status_code == 201:
        print("Success!")
        print(response.json())
    else:
        print(f"Error: {response.status_code}")
        print(response.json())
```

### Python Example with Error Handling

```python
import requests
import sys

def upload_eda_file(api_key, file_path, server_url):
    """Upload EDA output file to server"""
    
    url = f"{server_url}/api/eda-files/external/upload"
    headers = {"X-API-Key": api_key}
    
    try:
        with open(file_path, 'rb') as f:
            files = {'file': (file_path.split('/')[-1], f)}
            response = requests.post(url, headers=headers, files=files, timeout=300)
            
            if response.status_code == 201:
                data = response.json()
                print(f"✅ Success! File ID: {data['data']['fileId']}")
                return True
            else:
                error_data = response.json()
                print(f"❌ Error {response.status_code}: {error_data.get('message', 'Unknown error')}")
                return False
                
    except FileNotFoundError:
        print(f"❌ File not found: {file_path}")
        return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Request failed: {e}")
        return False

# Usage
if __name__ == "__main__":
    API_KEY = "your-api-key-here"
    SERVER_URL = "https://your-server-domain.com"
    FILE_PATH = "/path/to/your/file.json"
    
    upload_eda_file(API_KEY, FILE_PATH, SERVER_URL)
```

### JavaScript/Node.js Example

```javascript
const fs = require('fs');
const FormData = require('form-data');
const axios = require('axios');

async function uploadEdaFile(apiKey, filePath, serverUrl) {
  const url = `${serverUrl}/api/eda-files/external/upload`;
  
  const form = new FormData();
  form.append('file', fs.createReadStream(filePath));
  
  try {
    const response = await axios.post(url, form, {
      headers: {
        ...form.getHeaders(),
        'X-API-Key': apiKey
      },
      maxContentLength: Infinity,
      maxBodyLength: Infinity
    });
    
    if (response.status === 201) {
      console.log('✅ Success!', response.data);
      return response.data;
    }
  } catch (error) {
    if (error.response) {
      console.error('❌ Error:', error.response.status, error.response.data);
    } else {
      console.error('❌ Error:', error.message);
    }
    throw error;
  }
}

// Usage
const API_KEY = 'your-api-key-here';
const SERVER_URL = 'https://your-server-domain.com';
const FILE_PATH = '/path/to/your/file.json';

uploadEdaFile(API_KEY, FILE_PATH, SERVER_URL)
  .then(data => console.log('Upload successful:', data))
  .catch(error => console.error('Upload failed:', error));
```

### PowerShell Example

```powershell
$apiKey = "your-api-key-here"
$serverUrl = "https://your-server-domain.com"
$filePath = "C:\path\to\your\file.json"

$headers = @{
    "X-API-Key" = $apiKey
}

$fileBytes = [System.IO.File]::ReadAllBytes($filePath)
$boundary = [System.Guid]::NewGuid().ToString()
$bodyLines = @(
    "--$boundary",
    "Content-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $filePath -Leaf)`"",
    "Content-Type: application/json",
    "",
    [System.Text.Encoding]::UTF8.GetString($fileBytes),
    "--$boundary--"
) -join "`r`n"

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyLines)

$headers["Content-Type"] = "multipart/form-data; boundary=$boundary"

try {
    $response = Invoke-RestMethod -Uri "$serverUrl/api/eda-files/external/upload" `
        -Method Post `
        -Headers $headers `
        -Body $bodyBytes
    
    Write-Host "✅ Success! File ID: $($response.data.fileId)" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}
```

---

## Error Handling

### Common Errors and Solutions

#### 1. "API key required"
- **Cause**: Missing API key in request
- **Solution**: Include `X-API-Key` header or `api_key` query parameter

#### 2. "Invalid API key"
- **Cause**: API key is incorrect or has been revoked
- **Solution**: Contact administrator to verify/regenerate API key

#### 3. "No file uploaded"
- **Cause**: File field is missing or incorrectly named
- **Solution**: Ensure the form field is named exactly `file`

#### 4. "Invalid file type"
- **Cause**: File is not CSV or JSON
- **Solution**: Convert file to `.csv` or `.json` format

#### 5. "Project name is required"
- **Cause**: File doesn't contain required `project` or `project_name` field
- **Solution**: Add `project` or `project_name` field to your file

#### 6. "Block name is required"
- **Cause**: File doesn't contain required `block_name` field
- **Solution**: Add `block_name` field to your file

#### 7. "Experiment and RTL tag are required"
- **Cause**: Missing `experiment` or `rtl_tag` fields
- **Solution**: Add both `experiment` and `rtl_tag` fields to your file

### Retry Logic

If you receive a `500 Internal Server Error`, you may want to implement retry logic:

```python
import time
import requests

def upload_with_retry(api_key, file_path, server_url, max_retries=3):
    for attempt in range(max_retries):
        try:
            # ... upload code ...
            if response.status_code == 201:
                return response.json()
        except requests.exceptions.RequestException as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt  # Exponential backoff
                print(f"Retrying in {wait_time} seconds...")
                time.sleep(wait_time)
            else:
                raise
```

---

## Rate Limits & Best Practices

### Rate Limits

- **No explicit rate limits** are currently enforced, but please be reasonable
- **Recommended**: Maximum 10 requests per minute per API key
- **Large files**: Files up to 100MB are supported, but processing may take time

### Best Practices

1. **Batch Processing**: If uploading multiple files, add delays between requests (1-2 seconds)
2. **Error Handling**: Always implement proper error handling and retry logic
3. **File Validation**: Validate your files before uploading to avoid processing errors
4. **Logging**: Log all API requests and responses for debugging
5. **API Key Security**: 
   - Never commit API keys to version control
   - Use environment variables or secure key management
   - Rotate API keys periodically
6. **File Naming**: Use descriptive filenames that include project and domain info
7. **Monitoring**: Monitor your uploads and check for processing errors

### File Processing Time

- **Small files** (< 1MB): Usually processed in < 5 seconds
- **Medium files** (1-10MB): Usually processed in 5-30 seconds
- **Large files** (10-100MB): May take 30-120 seconds

Files are processed asynchronously, so the API returns immediately after the file is received. Processing happens in the background.

---

## Support

For issues, questions, or API key requests, please contact your system administrator or the ASI Dashboard support team.

---

## Changelog

### Version 1.0.0 (2024-01-15)
- Initial release of External API
- Support for CSV and JSON file uploads
- API key authentication
- Automatic file processing and database storage

