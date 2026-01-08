# Manual Testing Guide - Replace Stage API

## Endpoint Details

### URL
```
POST http://localhost:3000/api/eda-files/external/replace-stage
```

**For production/server:**
```
POST https://your-server-domain.com/api/eda-files/external/replace-stage
```

---

## Headers

Add these headers to your request:

| Header Name | Value | Required |
|------------|-------|----------|
| `X-API-Key` | `your-api-key-here` | ✅ Yes |
| `Content-Type` | `multipart/form-data` | ⚠️ Usually auto-set by tool |

**Example Headers:**
```
X-API-Key: sitedafilesdata
Content-Type: multipart/form-data
```

---

## Request Body (Form Data)

You need to send **multipart/form-data** with the following fields:

### Required Fields:

| Field Name | Type | Value | Description |
|------------|------|-------|-------------|
| `file` | **File** | Select a CSV or JSON file | The file containing new stage data |
| `project` | Text | `project1` | Project name |
| `block_name` | Text | `cpu_core` | Block name |
| `experiment` | Text | `exp_001` | Experiment name |
| `rtl_tag` | Text | `v1.2.3` | RTL tag |
| `stage_name` | Text | `syn` | Stage name to replace (e.g., syn, place, route) |

---

## Testing with Different Tools

### 1. Using cURL (Command Line)

```bash
curl -X POST \
  "http://localhost:3000/api/eda-files/external/replace-stage" \
  -H "X-API-Key: sitedafilesdata" \
  -F "file=@/path/to/your/stage_data.json" \
  -F "project=project1" \
  -F "block_name=cpu_core" \
  -F "experiment=exp_001" \
  -F "rtl_tag=v1.2.3" \
  -F "stage_name=syn"
```

**Or with query parameters:**
```bash
curl -X POST \
  "http://localhost:3000/api/eda-files/external/replace-stage?project=project1&block_name=cpu_core&experiment=exp_001&rtl_tag=v1.2.3&stage_name=syn" \
  -H "X-API-Key: sitedafilesdata" \
  -F "file=@/path/to/your/stage_data.json"
```

---

### 2. Using Postman

1. **Method**: `POST`
2. **URL**: `http://localhost:3000/api/eda-files/external/replace-stage`
3. **Headers Tab**:
   - Key: `X-API-Key`
   - Value: `sitedafilesdata`
4. **Body Tab**:
   - Select: `form-data`
   - Add fields:
     - `file` (Type: File) - Select your file
     - `project` (Type: Text) - Value: `project1`
     - `block_name` (Type: Text) - Value: `cpu_core`
     - `experiment` (Type: Text) - Value: `exp_001`
     - `rtl_tag` (Type: Text) - Value: `v1.2.3`
     - `stage_name` (Type: Text) - Value: `syn`

---

### 3. Using HTTPie

```bash
http --form POST \
  http://localhost:3000/api/eda-files/external/replace-stage \
  X-API-Key:sitedafilesdata \
  file@/path/to/your/stage_data.json \
  project=project1 \
  block_name=cpu_core \
  experiment=exp_001 \
  rtl_tag=v1.2.3 \
  stage_name=syn
```

---

### 4. Using Python requests

```python
import requests

url = "http://localhost:3000/api/eda-files/external/replace-stage"
api_key = "sitedafilesdata"
file_path = "/path/to/your/stage_data.json"

headers = {
    "X-API-Key": api_key
}

data = {
    "project": "project1",
    "block_name": "cpu_core",
    "experiment": "exp_001",
    "rtl_tag": "v1.2.3",
    "stage_name": "syn"
}

with open(file_path, 'rb') as f:
    files = {
        'file': (file_path.split('/')[-1], f, 'application/json')
    }
    
    response = requests.post(url, headers=headers, files=files, data=data)
    print(response.status_code)
    print(response.json())
```

---

### 5. Using JavaScript/Fetch

```javascript
const formData = new FormData();
const fileInput = document.querySelector('input[type="file"]');

formData.append('file', fileInput.files[0]);
formData.append('project', 'project1');
formData.append('block_name', 'cpu_core');
formData.append('experiment', 'exp_001');
formData.append('rtl_tag', 'v1.2.3');
formData.append('stage_name', 'syn');

fetch('http://localhost:3000/api/eda-files/external/replace-stage', {
  method: 'POST',
  headers: {
    'X-API-Key': 'sitedafilesdata'
  },
  body: formData
})
.then(response => response.json())
.then(data => console.log(data))
.catch(error => console.error('Error:', error));
```

---

## Example File Format

### JSON File Example (`stage_data.json`):

```json
{
  "project": "project1",
  "block_name": "cpu_core",
  "experiment": "exp_001",
  "rtl_tag": "v1.2.3",
  "stage": "syn",
  "run_status": "pass",
  "runtime": "3600",
  "area": "1000000",
  "inst_count": "50000",
  "utilization": "75.5",
  "log_errors": "0",
  "log_warnings": "5",
  "internal_timing_r2r_wns": "-0.5",
  "internal_timing_r2r_tns": "-100",
  "internal_timing_r2r_nvp": "10"
}
```

### CSV File Example (`stage_data.csv`):

```csv
project,block_name,experiment,rtl_tag,stage,run_status,runtime,area,inst_count,utilization,log_errors,log_warnings,internal_timing_r2r_wns,internal_timing_r2r_tns,internal_timing_r2r_nvp
project1,cpu_core,exp_001,v1.2.3,syn,pass,3600,1000000,50000,75.5,0,5,-0.5,-100,10
```

---

## Expected Response

### Success Response (200 OK):

```json
{
  "success": true,
  "message": "Stage deleted and replaced successfully",
  "data": {
    "project": "project1",
    "block_name": "cpu_core",
    "experiment": "exp_001",
    "rtl_tag": "v1.2.3",
    "stage_name": "syn",
    "old_stage_id": 123,
    "new_stage_id": 456,
    "file_name": "stage_data.json",
    "replaced_at": "2024-01-15T10:30:00.000Z"
  }
}
```

### Error Responses:

#### 400 Bad Request - Missing Parameters:
```json
{
  "error": "Missing required parameters",
  "message": "Please provide: project, block_name, experiment, rtl_tag, and stage_name",
  "required": ["project", "block_name", "experiment", "rtl_tag", "stage_name"]
}
```

#### 400 Bad Request - No File:
```json
{
  "error": "No file uploaded",
  "message": "Please provide a file in the request. Use multipart/form-data with field name \"file\"."
}
```

#### 401 Unauthorized - Invalid API Key:
```json
{
  "error": "Invalid API key",
  "message": "The provided API key is not valid"
}
```

#### 404 Not Found - Stage Not Found:
```json
{
  "error": "Stage not found",
  "message": "Stage \"syn\" not found in the specified run"
}
```

#### 500 Internal Server Error:
```json
{
  "success": false,
  "error": "Stage replacement failed",
  "message": "Error details here"
}
```

---

## Quick Test Checklist

- [ ] Set correct URL (localhost:3000 or your server)
- [ ] Add `X-API-Key` header with valid API key
- [ ] Select a file (CSV or JSON) for the `file` field
- [ ] Add `project` form field
- [ ] Add `block_name` form field
- [ ] Add `experiment` form field
- [ ] Add `rtl_tag` form field
- [ ] Add `stage_name` form field
- [ ] Ensure the stage exists in the database before testing
- [ ] Check response status code (should be 200)
- [ ] Verify response contains `success: true`

---

## Troubleshooting

1. **"No file uploaded"**: Make sure you're using `multipart/form-data` and the file field is named `file`
2. **"Missing required parameters"**: Check that all 5 parameters (project, block_name, experiment, rtl_tag, stage_name) are provided
3. **"Stage not found"**: Verify the stage exists in the database with the exact identifiers you provided
4. **"Invalid API key"**: Check your API key in the `.env` file (EDA_API_KEYS) and ensure it matches
5. **Connection refused**: Make sure your server is running on the correct port

---

## Notes

- The uploaded file is automatically deleted after processing
- The API uses a database transaction - if anything fails, all changes are rolled back
- File must be CSV or JSON format
- Maximum file size: 100MB
- The stage must already exist in the database to be replaced

