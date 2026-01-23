# Zoho Project Members API - 404 Error

## Issue
Getting `404 Resource Not Found` when trying to fetch project members from Zoho Projects API.

**Endpoint tried**: `/restapi/portal/{portalId}/projects/{projectId}/users/`

## Current Status
- ✅ OAuth scope issue fixed (`ZohoProjects.users.READ` added)
- ✅ User re-authenticated with new scopes
- ❌ API endpoint returns 404

## Possible Causes

1. **Endpoint doesn't exist**: The `/users/` endpoint might not be available in Zoho Projects API
2. **Different API version**: May need to use a different API version or format
3. **Project has no members**: Empty project might return 404
4. **Permission issue**: User might not have permission to view project members

## Solutions Implemented

### 1. Multiple Endpoint Variations
The code now tries:
- `/restapi/portal/{portalId}/projects/{projectId}/users/`
- `/restapi/portal/{portalId}/projects/{projectId}/users`
- `/restapi/portal/{portalId}/projects/{projectId}/members/`
- `/restapi/portal/{portalId}/projects/{projectId}/members`
- `/portal/{portalId}/projects/{projectId}/users/`
- `/portal/{portalId}/projects/{projectId}/users`

### 2. Project Details Fallback
Checks if members are included in project details response.

### 3. Teams API Fallback
Tries to get project teams and extract users from teams.

## Next Steps

### Option 1: Verify API Endpoint
Check Zoho Projects API documentation to confirm the correct endpoint:
- Visit: https://www.zoho.com/projects/help/rest-api/users-api.html
- Or: https://projects.zoho.com/api-docs

### Option 2: Manual Workaround
If the API doesn't support fetching project members:
1. Manually add users to the ASI project
2. Or use Zoho People API to get all employees and filter by project assignment

### Option 3: Check Zoho Project Settings
- Ensure the project has members assigned
- Check if the user has permission to view project members
- Verify the project ID and portal ID are correct

## Testing

After the code update, try syncing again. The logs will show:
- Which endpoints were tried
- If project details contain members
- If teams API contains members
- Detailed error messages

Check backend console for detailed logs showing which approach worked or failed.

