# Zoho Projects Integration Setup Guide

This guide explains how to set up and use the Zoho Projects integration in the ASI Dashboard.

## Overview

The integration allows you to:
- Connect your Zoho Projects account via OAuth 2.0
- Fetch projects from Zoho Projects
- Display Zoho projects alongside local projects in the application
- Automatically refresh access tokens

## Prerequisites

1. **Zoho Projects Account** - You need an active Zoho Projects account
2. **Zoho API Credentials** - Client ID and Client Secret (already in `.env`)
3. **Database Migration** - Run the migration to create necessary tables

## Setup Steps

### Step 1: Install Dependencies

```bash
cd backend
npm install
```

This will install `axios` which is required for making HTTP requests to Zoho API.

### Step 2: Run Database Migration

```bash
# Using psql
psql -U postgres -d ASI -f migrations/007_create_zoho_integration.sql

# Or if using Docker
docker exec -i asi_postgres psql -U postgres -d ASI < migrations/007_create_zoho_integration.sql
```

This creates:
- `zoho_tokens` table - Stores OAuth tokens per user
- `zoho_projects_mapping` table - Maps Zoho projects to local projects (optional)

### Step 3: Configure Zoho API URL

Update `backend/.env` with the correct Zoho API URL based on your data center:

```env
# For US data center (default)
ZOHO_API_URL=https://projectsapi.zoho.com
ZOHO_AUTH_URL=https://accounts.zoho.com

# For EU data center
# ZOHO_API_URL=https://projectsapi.zoho.eu
# ZOHO_AUTH_URL=https://accounts.zoho.eu

# For India data center
# ZOHO_API_URL=https://projectsapi.zoho.in
# ZOHO_AUTH_URL=https://accounts.zoho.in

# For Australia data center
# ZOHO_API_URL=https://projectsapi.zoho.com.au
# ZOHO_AUTH_URL=https://accounts.zoho.com.au
```

### Step 4: Verify Zoho Credentials

Make sure your `.env` file has:
```env
ZOHO_CLIENT_ID=your_client_id
ZOHO_CLIENT_SECRET=your_client_secret
ZOHO_REDIRECT_URI=http://localhost:3000/api/zoho/callback
```

**Important**: The redirect URI must match exactly what you configured in your Zoho application settings.

## Usage

### 1. Connect Zoho Projects Account

**Get Authorization URL:**
```bash
GET /api/zoho/auth
Authorization: Bearer <your_jwt_token>
```

Response:
```json
{
  "authUrl": "https://accounts.zoho.com/oauth/v2/auth?...",
  "message": "Redirect user to this URL to authorize"
}
```

**User Flow:**
1. Frontend calls `/api/zoho/auth` to get the authorization URL
2. User is redirected to Zoho authorization page
3. User authorizes the application
4. Zoho redirects to `/api/zoho/callback?code=...&state=<userId>`
5. Backend exchanges code for tokens and stores them
6. User sees success message

### 2. Check Connection Status

```bash
GET /api/zoho/status
Authorization: Bearer <your_jwt_token>
```

Response:
```json
{
  "connected": true,
  "message": "Zoho Projects is connected"
}
```

### 3. Get Zoho Portals (Workspaces)

```bash
GET /api/zoho/portals
Authorization: Bearer <your_jwt_token>
```

Response:
```json
[
  {
    "id": "123456789",
    "name": "My Workspace",
    ...
  }
]
```

### 4. Get Zoho Projects

**Get all projects:**
```bash
GET /api/zoho/projects
Authorization: Bearer <your_jwt_token>
```

**Get projects from specific portal:**
```bash
GET /api/zoho/projects?portalId=123456789
Authorization: Bearer <your_jwt_token>
```

Response:
```json
{
  "success": true,
  "count": 5,
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
      "raw": { /* full project data */ }
    }
  ]
}
```

### 5. Get Combined Projects (Local + Zoho)

**Get all projects including Zoho:**
```bash
GET /api/projects?includeZoho=true
Authorization: Bearer <your_jwt_token>
```

**With specific portal:**
```bash
GET /api/projects?includeZoho=true&portalId=123456789
Authorization: Bearer <your_jwt_token>
```

Response:
```json
{
  "local": [
    {
      "id": 1,
      "name": "Local Project",
      "source": "local",
      ...
    }
  ],
  "zoho": [
    {
      "id": "zoho_987654321",
      "name": "Zoho Project",
      "source": "zoho",
      "zoho_project_id": "987654321",
      ...
    }
  ],
  "all": [ /* combined array */ ],
  "counts": {
    "local": 10,
    "zoho": 5,
    "total": 15
  }
}
```

### 6. Get Single Zoho Project

```bash
GET /api/zoho/projects/:projectId?portalId=123456789
Authorization: Bearer <your_jwt_token>
```

### 7. Disconnect Zoho

```bash
POST /api/zoho/disconnect
Authorization: Bearer <your_jwt_token>
```

## API Endpoints Summary

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| GET | `/api/zoho/auth` | Get OAuth authorization URL | Yes |
| GET | `/api/zoho/callback` | OAuth callback (called by Zoho) | No |
| GET | `/api/zoho/status` | Check connection status | Yes |
| GET | `/api/zoho/portals` | Get all portals/workspaces | Yes |
| GET | `/api/zoho/projects` | Get all Zoho projects | Yes |
| GET | `/api/zoho/projects/:projectId` | Get single Zoho project | Yes |
| POST | `/api/zoho/disconnect` | Disconnect Zoho account | Yes |
| GET | `/api/projects?includeZoho=true` | Get combined projects | Yes |

## Token Management

The integration automatically:
- ✅ Stores access and refresh tokens securely in the database
- ✅ Refreshes tokens when they're about to expire (5 minutes before)
- ✅ Handles token expiration gracefully
- ✅ Associates tokens with specific users

## Error Handling

Common errors and solutions:

### "No Zoho token found"
- **Cause**: User hasn't authorized Zoho Projects yet
- **Solution**: Call `/api/zoho/auth` to start authorization

### "Token expired"
- **Cause**: Refresh token is invalid or expired
- **Solution**: User needs to re-authorize via `/api/zoho/auth`

### "No portals found"
- **Cause**: User doesn't have any portals in Zoho Projects
- **Solution**: Create a portal/workspace in Zoho Projects first

### "Failed to fetch projects"
- **Cause**: API error, invalid portal ID, or permissions issue
- **Solution**: Check Zoho API credentials, portal ID, and user permissions

## Frontend Integration Example

```typescript
// 1. Get authorization URL
const response = await fetch('/api/zoho/auth', {
  headers: { 'Authorization': `Bearer ${token}` }
});
const { authUrl } = await response.json();

// 2. Open authorization window
const authWindow = window.open(authUrl, 'Zoho Auth', 'width=600,height=700');

// 3. Listen for callback (poll or use postMessage)
// After authorization, fetch projects
const projectsResponse = await fetch('/api/projects?includeZoho=true', {
  headers: { 'Authorization': `Bearer ${token}` }
});
const { local, zoho, all } = await projectsResponse.json();
```

## Security Notes

1. **Tokens are stored per user** - Each user has their own Zoho connection
2. **Tokens are encrypted in database** - Consider encrypting sensitive fields
3. **HTTPS required in production** - OAuth requires HTTPS for redirect URI
4. **Token refresh is automatic** - No manual intervention needed

## Troubleshooting

### Authorization fails
- Check redirect URI matches exactly in Zoho app settings
- Verify client ID and secret are correct
- Check that the redirect URI uses HTTPS in production

### Can't fetch projects
- Verify user has access to portals in Zoho Projects
- Check API URL matches your data center
- Verify token hasn't expired (check `/api/zoho/status`)

### Token refresh fails
- User may need to re-authorize
- Check refresh token is still valid in Zoho
- Verify client credentials are correct

## Next Steps

- [ ] Add project synchronization (sync Zoho projects to local database)
- [ ] Add webhook support for real-time updates
- [ ] Add support for creating projects in Zoho from the app
- [ ] Add support for updating project status
- [ ] Add project mapping UI

## Support

For Zoho API documentation:
- https://www.zoho.com/projects/api/

For issues with this integration:
- Check backend logs for detailed error messages
- Verify all environment variables are set correctly
- Ensure database migration has been run

