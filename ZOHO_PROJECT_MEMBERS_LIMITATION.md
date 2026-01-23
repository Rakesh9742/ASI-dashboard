# Zoho Projects API - Project Members Limitation

## Issue Summary

The Zoho Projects API does **not support** fetching project members directly for this account. All attempted endpoints return errors:

- `/restapi/portal/{portalId}/projects/{projectId}/users/` → 404 Not Found
- `/restapi/portal/{portalId}/projects/{projectId}/users` → 400 "Given URL is wrong"
- `/restapi/portal/{portalId}/projects/{projectId}/people/` → 400 "Given URL is wrong"
- `/restapi/portal/{portalId}/projects/{projectId}/members/` → 400 "Given URL is wrong"
- `/restapi/portal/{portalId}/projects/{projectId}/usergroups/` → 404 Not Found
- `/restapi/portal/{portalId}/users/` → "Unauthorized Access"

## Root Cause

This appears to be a limitation of the Zoho Projects API v3 for this account type or subscription level. The API documentation may mention these endpoints, but they are not available for all accounts.

## Alternative Solutions

### Option 1: Extract Members from Tasks (Implemented)
- Fetch all tasks for the project
- Extract unique assignees/owners from tasks
- This gives us users who are actually working on the project

### Option 2: Manual Entry
- Allow admins to manually add project members via the UI
- Store the mapping in the `user_projects` table

### Option 3: Use Zoho People API (If Available)
- If you have Zoho People integration, fetch employees from there
- Match employees to projects manually or via some mapping

### Option 4: Project Details with Parameters
- Try fetching project details with query parameters like `?include=users,members`
- This might return member information if the API supports it

## Current Implementation Status

The code now tries:
1. ✅ Multiple endpoint variations (all fail)
2. ✅ Usergroups/teams endpoint (fails)
3. ✅ Project details with parameters (to be tested)
4. ✅ Extract members from tasks (to be tested)
5. ❌ Portal users endpoint (Unauthorized - needs different scope)

## Next Steps

1. **Test task-based extraction**: The code will now try to get tasks and extract assignees
2. **Check Zoho API documentation**: Verify if there's a different API version or endpoint format
3. **Consider manual entry**: If automatic sync isn't possible, provide a UI for manual member assignment
4. **Check subscription level**: Some Zoho Projects API features may require a higher subscription tier

## Recommendation

Since automatic sync isn't working, we should:
1. Implement task-based member extraction (already added)
2. Provide a manual "Add Member" feature in the UI
3. Allow admins to manually assign users to projects with roles

