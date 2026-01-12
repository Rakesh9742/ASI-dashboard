# Zoho Authorization Troubleshooting Guide

## Problem: "No Zoho token found for user. Please authorize first."

### Root Cause
After authorizing, tokens are not being saved to the database.

### Solution Steps

#### Step 1: Verify You're Logged In
Make sure you have a valid JWT token from your login session.

#### Step 2: Get Authorization URL (Correct Endpoint)
```bash
GET http://localhost:3000/api/zoho/auth
Headers: Authorization: Bearer <your_jwt_token>
```

**Response:**
```json
{
  "authUrl": "https://accounts.zoho.com/oauth/v2/auth?...",
  "message": "Redirect user to this URL to authorize"
}
```

#### Step 3: Authorize in Browser
1. Copy the `authUrl` from the response
2. Open it in your browser
3. Log in to Zoho and authorize the application
4. Wait for the success page: "✅ Authorization Successful!"

#### Step 4: Verify Tokens Were Saved
```bash
docker exec asi_postgres psql -U postgres -d ASI -c "SELECT user_id, created_at, expires_at FROM zoho_tokens;"
```

If tokens exist, you should see a row with your user_id.

#### Step 5: Check Backend Logs
```bash
docker logs asi_backend --tail 50 | grep -i "token\|callback\|saving"
```

Look for:
- "Token data received"
- "Saving tokens for user X"
- Any error messages

### Common Issues

#### Issue 1: Used `/api/zoho/login-auth` Instead of `/api/zoho/auth`
- **Login flow** (`/api/zoho/login-auth`): For logging in with Zoho, may not save tokens reliably
- **Connect flow** (`/api/zoho/auth`): For connecting Zoho account, always saves tokens

**Fix:** Always use `/api/zoho/auth` with your JWT token.

#### Issue 2: Callback Failed Silently
Check backend logs for errors during callback:
```bash
docker logs asi_backend 2>&1 | Select-String -Pattern "Error|Failed|callback" -CaseSensitive:$false
```

#### Issue 3: User ID Mismatch
The callback uses the `state` parameter as the user ID. Make sure:
- You're logged in as the same user
- The JWT token contains the correct user ID

**Verify your user ID:**
```sql
SELECT id, username, email FROM users WHERE email = 'your_email@example.com';
```

### Manual Token Verification

Check if tokens exist for your user:
```bash
docker exec asi_postgres psql -U postgres -d ASI -c "SELECT u.username, zt.user_id, zt.expires_at FROM users u LEFT JOIN zoho_tokens zt ON u.id = zt.user_id WHERE u.email = 'your_email@example.com';"
```

### Re-authorization
If tokens are missing or expired:
1. Delete existing tokens (if any):
   ```sql
   DELETE FROM zoho_tokens WHERE user_id = YOUR_USER_ID;
   ```
2. Follow Steps 1-3 above to re-authorize

### Testing After Authorization

Once tokens are saved, test the projects endpoint:
```bash
GET http://localhost:3000/api/zoho/projects
Headers: Authorization: Bearer <your_jwt_token>
```

You should get a successful response with your Zoho projects.







