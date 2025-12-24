# Check Zoho API Response for Projects

This guide shows you how to check the actual API response you're getting from Zoho for your projects.

## API Endpoints

### 1. Get All Zoho Projects (Raw Response)

**Endpoint:** `GET /api/zoho/projects`

**Description:** Returns all projects from Zoho Projects with the complete raw Zoho API response.

**Headers:**
```
Authorization: Bearer <your_token>
```

**Query Parameters:**
- `portalId` (optional) - Specific portal ID to fetch projects from

**Example Request:**
```bash
curl -X GET "http://localhost:3000/api/zoho/projects" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

**With Portal ID:**
```bash
curl -X GET "http://localhost:3000/api/zoho/projects?portalId=123456789" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

**Response Structure:**
```json
{
  "success": true,
  "count": 5,
  "projects": [
    {
      "id": "123456789",
      "name": "Project Name",
      "description": "Project description",
      "status": "active",
      "start_date": "2024-01-01",
      "end_date": "2024-12-31",
      "owner_name": "John Doe",
      "created_time": "2024-01-01T00:00:00+00:00",
      "source": "zoho",
      "raw": {
        // COMPLETE ZOHO API RESPONSE - ALL FIELDS HERE
        "id": "123456789",
        "name": "Project Name",
        "description": "Project description",
        "status": "active",
        "start_date": "2024-01-01",
        "end_date": "2024-12-31",
        "owner_name": "John Doe",
        "owner": "987654321",
        "created_by": "111222333",
        "created_by_name": "Jane Smith",
        "created_time": "2024-01-01T00:00:00+00:00",
        "priority": "High",
        "completion_percentage": 45,
        "work_hours": "120:30",
        "timelog_total": "100:00",
        "billing_type": "Fixed Price",
        "team_name": "Development Team",
        "tags": ["urgent", "client-project"],
        // ... ALL OTHER FIELDS FROM ZOHO API
      }
    }
  ]
}
```

**Key Point:** The `raw` field in each project contains the **complete, unmodified response** from Zoho Projects API with all available fields.

---

### 2. Get Single Zoho Project (Raw Response)

**Endpoint:** `GET /api/zoho/projects/:projectId`

**Description:** Returns a single project from Zoho Projects with the complete raw Zoho API response.

**Headers:**
```
Authorization: Bearer <your_token>
```

**URL Parameters:**
- `projectId` - The Zoho project ID (not prefixed with "zoho_")
  - You can extract this from your Zoho URL: `https://projects.zoho.in/portal/.../projects/173458000001906091/...`
  - The project ID is: `173458000001906091`

**Query Parameters:**
- `portalId` (optional) - Specific portal ID

**Example Request:**
```bash
# Using project ID from your Zoho URL
curl -X GET "http://localhost:3000/api/zoho/projects/173458000001906091" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

**Or with a generic project ID:**
```bash
curl -X GET "http://localhost:3000/api/zoho/projects/123456789" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

**Response Structure:**
```json
{
  "success": true,
  "project": {
    "id": "123456789",
    "name": "Project Name",
    "description": "Project description",
    "status": "active",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "owner_name": "John Doe",
    "created_time": "2024-01-01T00:00:00+00:00",
    "source": "zoho",
    "raw": {
      // COMPLETE ZOHO API RESPONSE - ALL FIELDS HERE
      // Same structure as the "raw" field in the projects list
    }
  }
}
```

---

### 3. Get Projects with Zoho Integration (Combined Response)

**Endpoint:** `GET /api/projects?includeZoho=true`

**Description:** Returns both local and Zoho projects. Zoho projects include a `zoho_data` field with the complete Zoho response.

**Headers:**
```
Authorization: Bearer <your_token>
```

**Example Request:**
```bash
curl -X GET "http://localhost:3000/api/projects?includeZoho=true" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

**Response Structure:**
```json
{
  "local": [...],
  "zoho": [
    {
      "id": "zoho_123456789",
      "name": "Project Name",
      "source": "zoho",
      "zoho_project_id": "123456789",
      "zoho_data": {
        // COMPLETE ZOHO API RESPONSE - ALL FIELDS HERE
        // This is the same as the "raw" field in /api/zoho/projects
      }
    }
  ],
  "all": [...],
  "counts": {
    "local": 5,
    "zoho": 10,
    "total": 15
  }
}
```

**Key Point:** The `zoho_data` field contains the complete Zoho API response, same as the `raw` field in `/api/zoho/projects`.

---

## How to Test

### Option 1: Using cURL

1. **Get your authentication token** (login first):
```bash
curl -X POST "http://localhost:3000/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username": "your_username", "password": "your_password"}'
```

2. **Copy the token** from the response

3. **Call the Zoho projects endpoint**:
```bash
curl -X GET "http://localhost:3000/api/zoho/projects" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  | jq '.'  # Pretty print JSON (optional, requires jq)
```

### Option 2: Using Postman

1. **Create a new GET request**
2. **URL:** `http://localhost:3000/api/zoho/projects`
3. **Headers:**
   - Key: `Authorization`
   - Value: `Bearer YOUR_TOKEN_HERE`
4. **Send the request**
5. **View the response** - Look at the `raw` field in each project

### Option 3: Using Browser Console (if frontend is running)

Open browser DevTools Console and run:
```javascript
// First, get your token (you need to be logged in)
const token = localStorage.getItem('auth_token'); // or wherever token is stored

// Then fetch projects
fetch('http://localhost:3000/api/zoho/projects', {
  headers: {
    'Authorization': `Bearer ${token}`
  }
})
.then(res => res.json())
.then(data => {
  console.log('Zoho Projects Response:', data);
  // Look at data.projects[0].raw to see complete Zoho response
  console.log('First Project Raw Data:', data.projects[0]?.raw);
});
```

---

## What to Look For

When you call `/api/zoho/projects`, check:

1. **The `raw` field** - This contains ALL fields returned by Zoho Projects API
2. **Field names** - Note the exact field names (e.g., `work_hours_p`, `timelog_total_t`)
3. **Data types** - Check if values are strings, numbers, arrays, etc.
4. **Nested objects** - Some fields might be objects or arrays
5. **Custom fields** - Any custom fields configured in your Zoho Projects

### Example: Inspecting the Raw Response

```bash
# Get projects and save to file
curl -X GET "http://localhost:3000/api/zoho/projects" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -o zoho_projects.json

# View just the raw data of first project
cat zoho_projects.json | jq '.projects[0].raw'

# List all field names in the raw response
cat zoho_projects.json | jq '.projects[0].raw | keys'

# Get specific field value
cat zoho_projects.json | jq '.projects[0].raw.completion_percentage'
```

---

## Quick Test Script

Create a file `test-zoho-api.js`:

```javascript
const axios = require('axios');

async function testZohoAPI() {
  try {
    // Step 1: Login
    const loginResponse = await axios.post('http://localhost:3000/api/auth/login', {
      username: 'your_username',
      password: 'your_password'
    });
    
    const token = loginResponse.data.token;
    console.log('✅ Logged in, token:', token.substring(0, 20) + '...');
    
    // Step 2: Get Zoho projects
    const projectsResponse = await axios.get('http://localhost:3000/api/zoho/projects', {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });
    
    console.log('\n📊 Zoho Projects Response:');
    console.log('Total projects:', projectsResponse.data.count);
    
    if (projectsResponse.data.projects.length > 0) {
      const firstProject = projectsResponse.data.projects[0];
      console.log('\n🔍 First Project Raw Data (all fields from Zoho):');
      console.log(JSON.stringify(firstProject.raw, null, 2));
      
      console.log('\n📋 All Field Names in Raw Response:');
      console.log(Object.keys(firstProject.raw));
    }
    
  } catch (error) {
    console.error('❌ Error:', error.response?.data || error.message);
  }
}

testZohoAPI();
```

Run it:
```bash
node test-zoho-api.js
```

---

## Troubleshooting

### If you get "Zoho Projects not connected":
1. Make sure you've connected Zoho via `/api/zoho/auth`
2. Check your token status: `GET /api/zoho/status`

### If you get 401 Unauthorized:
1. Make sure your token is valid
2. Try logging in again to get a fresh token

### If you get empty projects array:
1. Check if you have projects in your Zoho Projects portal
2. Verify your Zoho token has the correct scopes
3. Try specifying a `portalId` query parameter

---

## Summary

- **`/api/zoho/projects`** - Best endpoint to see raw Zoho response (check the `raw` field)
- **`/api/zoho/projects/:projectId`** - Get single project with raw data
- **`/api/projects?includeZoho=true`** - Combined local + Zoho projects (check `zoho_data` field)

The `raw` or `zoho_data` field contains the **complete, unmodified response** from Zoho Projects API with all available fields.

