# Postman Testing Guide - External API

## Quick Setup

### 1. Create New Request

1. Open Postman
2. Click **New** → **HTTP Request**
3. Set method to **POST**

### 2. Enter URL

```
http://localhost:3000/api/eda-files/external/upload
```

Or for production:
```
https://your-server-domain.com/api/eda-files/external/upload
```

### 3. Configure Headers

Go to **Headers** tab and add:

| Key | Value |
|-----|-------|
| `X-API-Key` | `your-api-key-here` |

**Note**: Replace `your-api-key-here` with an actual API key from your `EDA_API_KEYS` environment variable.

### 4. Configure Body

1. Go to **Body** tab
2. Select **form-data** (NOT raw or x-www-form-urlencoded)
3. Add a new key-value pair:
   - **Key**: `file` (make sure it's exactly "file")
   - **Type**: Change from "Text" to **"File"** (dropdown on the right)
   - **Value**: Click **Select Files** and choose your CSV or JSON file

### 5. Send Request

Click **Send** button.

---

## Complete Postman Configuration

### Request Details

**Method**: `POST`

**URL**: 
```
http://localhost:3000/api/eda-files/external/upload
```

**Headers**:
```
X-API-Key: your-api-key-here
```

**Body Type**: `form-data`

**Body Fields**:
- Key: `file` (Type: File)
- Value: [Select your file]

---

## Example Test Files

### Example JSON File (test-file.json)

Create a file named `test-file.json` with this content:

```json
{
  "project": "test_project",
  "domain": "PD",
  "block_name": "test_block",
  "experiment": "exp_001",
  "rtl_tag": "v1.0.0",
  "user_name": "test_user",
  "run_directory": "/test/run",
  "timestamp": "2024-01-15T10:30:00Z",
  "stages": {
    "syn": {
      "area": 1000000,
      "inst_count": 50000,
      "utilization": 75.5,
      "run_status": "pass",
      "runtime": "3600",
      "internal_timing_r2r_wns": -0.5,
      "internal_timing_r2r_tns": -100,
      "internal_timing_r2r_nvp": 10,
      "log_errors": 0,
      "log_warnings": 5,
      "log_critical": 0
    },
    "place": {
      "area": 1000000,
      "inst_count": 50000,
      "utilization": 75.5,
      "run_status": "pass",
      "runtime": "7200",
      "internal_timing_r2r_wns": -0.3,
      "internal_timing_r2r_tns": -50,
      "internal_timing_r2r_nvp": 5
    }
  }
}
```

### Example CSV File (test-file.csv)

Create a file named `test-file.csv` with this content:

```csv
project,domain,block_name,experiment,rtl_tag,user_name,stage,area,inst_count,utilization,run_status,runtime
test_project,PD,test_block,exp_001,v1.0.0,test_user,syn,1000000,50000,75.5,pass,3600
test_project,PD,test_block,exp_001,v1.0.0,test_user,place,1000000,50000,75.5,pass,7200
test_project,PD,test_block,exp_001,v1.0.0,test_user,route,1000000,50000,75.5,pass,10800
```

---

## Step-by-Step Postman Setup

### Step 1: Create Request

1. Click **New** → **HTTP Request**
2. Name it: `Upload EDA File - External API`

### Step 2: Set Method and URL

- **Method**: Select `POST` from dropdown
- **URL**: Enter `http://localhost:3000/api/eda-files/external/upload`

### Step 3: Add Headers

1. Click **Headers** tab
2. Click **Add Header**
3. Key: `X-API-Key`
4. Value: `your-api-key-here` (replace with actual key)

**Important**: Postman may auto-add `Content-Type: multipart/form-data` - that's correct, don't remove it.

### Step 4: Configure Body

1. Click **Body** tab
2. Select **form-data** radio button
3. In the key-value table:
   - **Key**: Type `file`
   - **Type**: Click dropdown next to key, select **File** (not Text)
   - **Value**: Click **Select Files** button, choose your test file

### Step 5: Send Request

Click the blue **Send** button.

---

## Expected Responses

### Success Response (201 Created)

```json
{
  "success": true,
  "message": "File uploaded and processed successfully",
  "data": {
    "fileId": 123,
    "fileName": "test-file.json",
    "fileSize": 1234,
    "fileType": "json",
    "filePath": "/path/to/stored/file.json",
    "processedAt": "2024-01-15T10:30:00.000Z"
  }
}
```

### Error: Missing API Key (401)

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

### Error: Invalid API Key (401)

```json
{
  "error": "Invalid API key",
  "message": "The provided API key is not valid"
}
```

### Error: No File (400)

```json
{
  "error": "No file uploaded",
  "message": "Please provide a file in the request. Use multipart/form-data with field name \"file\"."
}
```

### Error: Invalid File Type (400)

```json
{
  "error": "Invalid file type",
  "message": "Only CSV and JSON files are allowed",
  "received": "txt",
  "allowed": ["csv", "json"]
}
```

---

## Postman Collection JSON

You can import this collection directly into Postman:

```json
{
  "info": {
    "name": "ASI Dashboard - External API",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Upload EDA File - External API",
      "request": {
        "method": "POST",
        "header": [
          {
            "key": "X-API-Key",
            "value": "{{api_key}}",
            "type": "text"
          }
        ],
        "body": {
          "mode": "formdata",
          "formdata": [
            {
              "key": "file",
              "type": "file",
              "src": []
            }
          ]
        },
        "url": {
          "raw": "{{base_url}}/api/eda-files/external/upload",
          "host": ["{{base_url}}"],
          "path": ["api", "eda-files", "external", "upload"]
        }
      }
    }
  ],
  "variable": [
    {
      "key": "base_url",
      "value": "http://localhost:3000",
      "type": "string"
    },
    {
      "key": "api_key",
      "value": "your-api-key-here",
      "type": "string"
    }
  ]
}
```

### How to Import Collection

1. Open Postman
2. Click **Import** button (top left)
3. Click **Raw text** tab
4. Paste the JSON above
5. Click **Import**
6. Update variables:
   - Click on collection name
   - Go to **Variables** tab
   - Update `base_url` and `api_key` values

---

## Testing Checklist

- [ ] Server is running on port 3000
- [ ] API key is configured in `.env` file (`EDA_API_KEYS`)
- [ ] API key is added to Postman headers
- [ ] Request method is `POST`
- [ ] URL is correct: `/api/eda-files/external/upload`
- [ ] Body type is `form-data`
- [ ] File field name is exactly `file` (lowercase)
- [ ] File type is set to "File" (not "Text")
- [ ] Test file is a valid CSV or JSON file
- [ ] Test file contains required fields (project, block_name, experiment, rtl_tag, stage)

---

## Troubleshooting

### "API key required" Error

**Problem**: API key not sent or header name is wrong.

**Solution**:
- Check header name is exactly `X-API-Key` (case-sensitive)
- Verify API key value is correct
- Make sure API key is in your `.env` file

### "No file uploaded" Error

**Problem**: File field is missing or incorrectly named.

**Solution**:
- Check body type is `form-data` (not raw or x-www-form-urlencoded)
- Verify field name is exactly `file` (lowercase, no spaces)
- Make sure file type is set to "File" (not "Text")

### "Invalid file type" Error

**Problem**: File is not CSV or JSON.

**Solution**:
- Use `.csv` or `.json` file extension
- Check file content is valid CSV/JSON

### Connection Refused

**Problem**: Server is not running.

**Solution**:
- Start backend server: `cd backend && npm run dev`
- Check server is running on correct port
- Verify URL is correct

---

## Quick Test Script

Save this as `test-upload.json` and import to Postman:

```json
{
  "name": "Test Upload",
  "request": {
    "method": "POST",
    "header": [
      {
        "key": "X-API-Key",
        "value": "test-key-123"
      }
    ],
    "body": {
      "mode": "formdata",
      "formdata": [
        {
          "key": "file",
          "type": "file",
          "src": "C:/path/to/your/test-file.json"
        }
      ]
    },
    "url": {
      "raw": "http://localhost:3000/api/eda-files/external/upload",
      "protocol": "http",
      "host": ["localhost"],
      "port": "3000",
      "path": ["api", "eda-files", "external", "upload"]
    }
  }
}
```

---

## Environment Variables in Postman

Create a Postman environment for easier testing:

1. Click **Environments** (left sidebar)
2. Click **+** to create new environment
3. Add variables:
   - `base_url`: `http://localhost:3000`
   - `api_key`: `your-api-key-here`
4. Use in requests: `{{base_url}}` and `{{api_key}}`

---

## Screenshots Guide

### Correct Postman Configuration

**Headers Tab:**
```
X-API-Key: your-api-key-here
```

**Body Tab:**
- Select: `form-data`
- Key: `file`
- Type: `File` (dropdown)
- Value: [Select Files button]

---

## Next Steps

After successful test:
1. Share API key with developers
2. Share `EXTERNAL_API_DOCUMENTATION.md` with them
3. Monitor API usage
4. Set up proper API keys for production













