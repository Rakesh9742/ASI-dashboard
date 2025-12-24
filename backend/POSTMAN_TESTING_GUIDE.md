# Postman Testing Guide - Zoho Projects Integration API

This guide will help you test all Zoho Projects integration endpoints using Postman.

## Prerequisites

1. **Backend server running**
   ```powershell
   cd backend
   npm run dev
   ```
   Server should be running on `http://localhost:3000`

2. **Valid JWT Token**
   - You need to authenticate first to get a JWT token
   - Use the login endpoint to get your token

3. **Postman installed**
   - Download from: https://www.postman.com/downloads/

## Step 1: Get Authentication Token

Before testing Zoho endpoints, you need to authenticate.

### Request: Login

**Method:** `POST`  
**URL:** `http://localhost:3000/api/auth/login`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "username": "admin",
  "password": "admin123"
}
```

**Expected Response (200 OK):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 1,
    "username": "admin",
    "email": "admin@example.com",
    "role": "admin"
  }
}
```

**Action:** Copy the `token` value - you'll need it for all subsequent requests.

---

## Step 2: Set Up Postman Environment (Recommended)

1. Click **Environments** in Postman
2. Click **+** to create new environment
3. Name it: `ASI Dashboard Local`
4. Add variables:
   - `base_url`: `http://localhost:3000`
   - `token`: (paste your token here)
5. Save and select this environment

Now you can use `{{base_url}}` and `{{token}}` in your requests.

---

## Step 3: Test Zoho Integration Endpoints

### Test 1: Check Zoho Connection Status

**Purpose:** Check if user has connected Zoho Projects account

**Method:** `GET`  
**URL:** `{{base_url}}/api/zoho/status`

**Headers:**
```
Authorization: Bearer {{token}}
```

**Expected Response (200 OK) - Not Connected:**
```json
{
  "connected": false,
  "message": "Zoho Projects is not connected"
}
```

**Expected Response (200 OK) - Connected:**
```json
{
  "connected": true,
  "message": "Zoho Projects is connected"
}
```

**What to Check:**
- ✅ Status code is 200
- ✅ Response shows connection status
- ✅ If `connected: false`, you need to authorize first

---

### Test 2: Get Zoho Authorization URL

**Purpose:** Get the OAuth URL to start authorization flow

**Method:** `GET`  
**URL:** `{{base_url}}/api/zoho/auth`

**Headers:**
```
Authorization: Bearer {{token}}
```

**Expected Response (200 OK):**
```json
{
  "authUrl": "https://accounts.zoho.com/oauth/v2/auth?client_id=...&redirect_uri=...&response_type=code&scope=...",
  "message": "Redirect user to this URL to authorize"
}
```

**What to Check:**
- ✅ Status code is 200
- ✅ `authUrl` is present and is a valid URL
- ✅ URL contains your client_id
- ✅ URL contains redirect_uri matching your .env

**Action:** 
1. Copy the `authUrl`
2. Open it in a browser
3. Authorize the application
4. You'll be redirected to the callback URL

---

### Test 3: Verify OAuth Callback (Browser Test)

**Purpose:** This endpoint is called by Zoho after authorization

**Method:** `GET`  
**URL:** `http://localhost:3000/api/zoho/callback?code=AUTHORIZATION_CODE&state=USER_ID`

**Note:** This is typically called by Zoho in a browser, not directly in Postman. But you can test it manually.

**What to Check:**
- ✅ After authorizing in browser, you should see a success page
- ✅ If error, check the error message

**Common Issues:**
- ❌ "State parameter missing" - Make sure you're calling `/api/zoho/auth` first
- ❌ "Authorization code not provided" - Check the callback URL has `code` parameter
- ❌ "Failed to exchange code for token" - Check client ID/secret in .env

---

### Test 4: Check Connection Status Again

**Purpose:** Verify tokens were saved after authorization

**Method:** `GET`  
**URL:** `{{base_url}}/api/zoho/status`

**Headers:**
```
Authorization: Bearer {{token}}
```

**Expected Response (200 OK) - After Authorization:**
```json
{
  "connected": true,
  "message": "Zoho Projects is connected"
}
```

**What to Check:**
- ✅ `connected` is now `true`
- ✅ Status code is 200

---

### Test 5: Get Zoho Portals (Workspaces)

**Purpose:** Fetch all portals/workspaces from Zoho Projects

**Method:** `GET`  
**URL:** `{{base_url}}/api/zoho/portals`

**Headers:**
```
Authorization: Bearer {{token}}
```

**Expected Response (200 OK):**
```json
[
  {
    "id": "123456789",
    "name": "My Workspace",
    "id_string": "123456789",
    "role": "owner",
    ...
  }
]
```

**What to Check:**
- ✅ Status code is 200
- ✅ Returns array of portals
- ✅ Each portal has `id` and `name`
- ✅ If empty array `[]`, you need to create a portal in Zoho Projects first

**Error Response (500) - Not Connected:**
```json
{
  "error": "No Zoho token found for user. Please authorize first."
}
```

**Error Response (500) - Token Expired:**
```json
{
  "error": "Failed to refresh token: ..."
}
```

---

### Test 6: Get All Zoho Projects

**Purpose:** Fetch all projects from Zoho Projects

**Method:** `GET`  
**URL:** `{{base_url}}/api/zoho/projects`

**Headers:**
```
Authorization: Bearer {{token}}
```

**Query Parameters (Optional):**
- `portalId`: Specific portal ID (if you have multiple portals)

**Example with portal:**
```
{{base_url}}/api/zoho/projects?portalId=123456789
```

**Expected Response (200 OK):**
```json
{
  "success": true,
  "count": 3,
  "projects": [
    {
      "id": "987654321",
      "name": "Project Name",
      "description": "Project description",
      "status": "active",
      "start_date": "2024-01-01",
      "end_date": "2024-12-31",
      "owner_name": "John Doe",
      "created_time": "2024-01-01T00:00:00Z",
      "source": "zoho",
      "raw": {
        // Full project data from Zoho
      }
    }
  ]
}
```

**What to Check:**
- ✅ Status code is 200
- ✅ `success` is `true`
- ✅ `count` matches number of projects
- ✅ Each project has required fields: `id`, `name`, `source`
- ✅ Projects array is not null

**Empty Response (No Projects):**
```json
{
  "success": true,
  "count": 0,
  "projects": []
}
```

**Error Response (500):**
```json
{
  "success": false,
  "error": "Failed to fetch projects: ..."
}
```

---

### Test 7: Get Single Zoho Project

**Purpose:** Get details of a specific project

**Method:** `GET`  
**URL:** `{{base_url}}/api/zoho/projects/:projectId`

**Example:**
```
{{base_url}}/api/zoho/projects/987654321?portalId=123456789
```

**Headers:**
```
Authorization: Bearer {{token}}
```

**Query Parameters (Optional):**
- `portalId`: Portal ID containing the project

**Expected Response (200 OK):**
```json
{
  "success": true,
  "project": {
    "id": "987654321",
    "name": "Project Name",
    "description": "Full project description",
    "status": "active",
    "start_date": "2024-01-01",
    "end_date": "2024-12-31",
    "owner_name": "John Doe",
    "created_time": "2024-01-01T00:00:00Z",
    "source": "zoho",
    "raw": {
      // Full project data
    }
  }
}
```

**What to Check:**
- ✅ Status code is 200
- ✅ `success` is `true`
- ✅ Project object contains all fields
- ✅ `id` matches the projectId in URL

**Error Response (404/500):**
```json
{
  "success": false,
  "error": "Failed to fetch project: Project not found"
}
```

---

### Test 8: Get Combined Projects (Local + Zoho)

**Purpose:** Get both local and Zoho projects together

**Method:** `GET`  
**URL:** `{{base_url}}/api/projects?includeZoho=true`

**Headers:**
```
Authorization: Bearer {{token}}
```

**Query Parameters:**
- `includeZoho`: `true` or `1` (required to include Zoho projects)
- `portalId`: (optional) Specific Zoho portal ID

**Expected Response (200 OK):**
```json
{
  "local": [
    {
      "id": 1,
      "name": "Local Project",
      "client": "Client Name",
      "technology_node": "Node.js",
      "start_date": "2024-01-01",
      "target_date": "2024-12-31",
      "plan": "Project plan",
      "created_at": "2024-01-01T00:00:00Z",
      "domains": [...],
      "source": "local"
    }
  ],
  "zoho": [
    {
      "id": "zoho_987654321",
      "name": "Zoho Project",
      "client": "Owner Name",
      "technology_node": null,
      "start_date": "2024-01-01",
      "target_date": "2024-12-31",
      "plan": "Description",
      "created_at": "2024-01-01T00:00:00Z",
      "domains": [],
      "source": "zoho",
      "zoho_project_id": "987654321",
      "zoho_data": {...}
    }
  ],
  "all": [
    // Combined array of local + zoho projects
  ],
  "counts": {
    "local": 5,
    "zoho": 3,
    "total": 8
  }
}
```

**What to Check:**
- ✅ Status code is 200
- ✅ `local` array contains local projects
- ✅ `zoho` array contains Zoho projects (if connected)
- ✅ `all` array combines both
- ✅ `counts` shows correct numbers
- ✅ Each project has `source` field (`local` or `zoho`)

**Response if Zoho Not Connected:**
```json
{
  "local": [...],
  "zoho": [],
  "all": [...],
  "counts": {
    "local": 5,
    "zoho": 0,
    "total": 5
  },
  "message": "Zoho Projects not connected. Use /api/zoho/auth to connect."
}
```

---

### Test 9: Disconnect Zoho

**Purpose:** Remove Zoho connection and tokens

**Method:** `POST`  
**URL:** `{{base_url}}/api/zoho/disconnect`

**Headers:**
```
Authorization: Bearer {{token}}
```

**Expected Response (200 OK):**
```json
{
  "success": true,
  "message": "Zoho Projects disconnected successfully"
}
```

**What to Check:**
- ✅ Status code is 200
- ✅ `success` is `true`
- ✅ After disconnecting, `/api/zoho/status` should return `connected: false`

---

## Complete Testing Workflow

### Workflow 1: First Time Setup

1. ✅ **Login** → Get JWT token
2. ✅ **Check Status** → Should be `connected: false`
3. ✅ **Get Auth URL** → Copy the URL
4. ✅ **Authorize in Browser** → Open URL, authorize
5. ✅ **Check Status Again** → Should be `connected: true`
6. ✅ **Get Portals** → Verify portals exist
7. ✅ **Get Projects** → Fetch Zoho projects
8. ✅ **Get Combined Projects** → See local + Zoho together

### Workflow 2: Regular Usage

1. ✅ **Get Combined Projects** → `GET /api/projects?includeZoho=true`
2. ✅ **Get Single Zoho Project** → `GET /api/zoho/projects/:id`

### Workflow 3: Troubleshooting

1. ✅ **Check Status** → Verify connection
2. ✅ **Get Portals** → Check if portals accessible
3. ✅ **Get Projects** → Test API access
4. ✅ **If errors** → Check error messages

---

## Postman Collection Setup

### Create a Collection

1. Click **Collections** → **+ New Collection**
2. Name it: `ASI Dashboard - Zoho Integration`
3. Add all the requests above as items

### Add Pre-request Script (Auto Token)

Add this to collection's **Pre-request Script** tab:

```javascript
// Auto-set token from environment
if (pm.environment.get("token")) {
    pm.request.headers.add({
        key: "Authorization",
        value: "Bearer " + pm.environment.get("token")
    });
}
```

### Add Tests (Auto Validation)

Add tests to each request:

**For Status Endpoint:**
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Response has connected field", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('connected');
});
```

**For Projects Endpoint:**
```javascript
pm.test("Status code is 200", function () {
    pm.response.to.have.status(200);
});

pm.test("Response has success field", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('success');
    pm.expect(jsonData.success).to.be.true;
});

pm.test("Response has projects array", function () {
    var jsonData = pm.response.json();
    pm.expect(jsonData).to.have.property('projects');
    pm.expect(jsonData.projects).to.be.an('array');
});
```

---

## Common Issues & Solutions

### Issue 1: 401 Unauthorized

**Error:**
```json
{
  "error": "Unauthorized"
}
```

**Solutions:**
- ✅ Check token is set in Authorization header
- ✅ Verify token format: `Bearer <token>`
- ✅ Token might be expired - login again
- ✅ Check token in environment variable

### Issue 2: 500 Internal Server Error

**Error:**
```json
{
  "error": "No Zoho token found for user. Please authorize first."
}
```

**Solutions:**
- ✅ Call `/api/zoho/auth` first
- ✅ Complete OAuth flow in browser
- ✅ Check database has tokens: `SELECT * FROM zoho_tokens WHERE user_id = 1;`

### Issue 3: Token Expired

**Error:**
```json
{
  "error": "Failed to refresh token: ..."
}
```

**Solutions:**
- ✅ Re-authorize: Call `/api/zoho/auth` again
- ✅ Check refresh token in database
- ✅ Verify client credentials in .env

### Issue 4: No Portals Found

**Error:**
```json
{
  "error": "No portals found. Please create a portal in Zoho Projects first."
}
```

**Solutions:**
- ✅ Create a portal/workspace in Zoho Projects web interface
- ✅ Verify you have access to portals
- ✅ Check Zoho account permissions

### Issue 5: Empty Projects Array

**Response:**
```json
{
  "success": true,
  "count": 0,
  "projects": []
}
```

**Solutions:**
- ✅ This is normal if you have no projects in Zoho
- ✅ Create a project in Zoho Projects first
- ✅ Verify you're using the correct portal ID

---

## Response Validation Checklist

For each successful request, verify:

- [ ] Status code is 200 (or expected code)
- [ ] Response is valid JSON
- [ ] Required fields are present
- [ ] Data types are correct (arrays, objects, strings)
- [ ] No error messages
- [ ] Timestamps are in correct format
- [ ] IDs are present and valid
- [ ] Source field indicates correct origin (`local` or `zoho`)

---

## Quick Test Commands

### Using cURL (Alternative to Postman)

**Check Status:**
```bash
curl -X GET "http://localhost:3000/api/zoho/status" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Get Auth URL:**
```bash
curl -X GET "http://localhost:3000/api/zoho/auth" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Get Projects:**
```bash
curl -X GET "http://localhost:3000/api/zoho/projects" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Get Combined Projects:**
```bash
curl -X GET "http://localhost:3000/api/projects?includeZoho=true" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## Next Steps After Testing

1. ✅ Verify all endpoints work correctly
2. ✅ Test error scenarios
3. ✅ Verify token refresh works
4. ✅ Test with multiple users
5. ✅ Integrate with frontend
6. ✅ Test in production environment

---

## Support

If you encounter issues:
1. Check backend console logs
2. Verify database tables exist
3. Check .env configuration
4. Verify Zoho credentials
5. Check network connectivity
6. Review error messages in responses

For more details, see: `ZOHO_INTEGRATION_SETUP.md`

