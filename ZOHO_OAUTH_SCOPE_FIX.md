# Zoho OAuth Scope Fix for Project Members Sync

## Issue
Getting `403 Invalid OAuth scope` error when trying to sync project members.

## Solution
Added `ZohoProjects.users.READ` scope to the OAuth authorization request.

## Action Required: Re-authenticate

Since OAuth scopes are granted when the user first authorizes the application, you need to **re-authenticate** to get a new token with the updated scopes.

### Steps to Re-authenticate:

1. **Disconnect existing Zoho connection:**
   - Go to Zoho Integration settings in the app
   - Click "Disconnect" to remove the old token

2. **Re-connect with new scopes:**
   - Click "Connect Zoho" or "Login with Zoho"
   - Authorize the application again
   - The new token will include the `ZohoProjects.users.READ` scope

3. **Verify the sync works:**
   - Try syncing project members again
   - It should now work without the OAuth scope error

## Updated Scopes

The OAuth request now includes:
- `AaaServer.profile.read`
- `profile`
- `email`
- `ZohoProjects.projects.READ`
- `ZohoProjects.portals.READ`
- `ZohoProjects.tasks.READ`
- `ZohoProjects.tasklists.READ`
- **`ZohoProjects.users.READ`** ← NEW (for accessing project members)
- `ZOHOPEOPLE.forms.ALL`
- `ZOHOPEOPLE.employee.ALL`

## Note

If you're using Zoho OAuth login (not just integration), you'll also need to re-login through Zoho to get the updated scopes.

