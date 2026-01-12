# Zoho Redirect URI Fix

## Problem
The redirect URI in the authorization URL (`http://13.204.252.101:3000/api/zoho/callback`) must match **EXACTLY** what's registered in your Zoho application settings.

If they don't match, Zoho will reject the callback and tokens won't be saved.

## Solution

### Step 1: Check Your Zoho Application Settings

1. Go to [Zoho Developer Console](https://api-console.zoho.com/)
2. Select your application
3. Check the **Redirect URI** field
4. Note the exact URL (e.g., `http://localhost:3000/api/zoho/callback` or `http://13.204.252.101:3000/api/zoho/callback`)

### Step 2: Set ZOHO_REDIRECT_URI to Match

**Option A: If Zoho has `http://localhost:3000/api/zoho/callback`**

Create a `.env` file in the project root:
```bash
ZOHO_REDIRECT_URI=http://localhost:3000/api/zoho/callback
```

**Option B: If Zoho has `http://13.204.252.101:3000/api/zoho/callback`**

Create a `.env` file in the project root:
```bash
ZOHO_REDIRECT_URI=http://13.204.252.101:3000/api/zoho/callback
```

### Step 3: Update Zoho Application Settings (If Needed)

If your Zoho application doesn't have the correct redirect URI:

1. Go to [Zoho Developer Console](https://api-console.zoho.com/)
2. Select your application
3. Click **Edit** or **Settings**
4. Add/Update the **Redirect URI** to: `http://13.204.252.101:3000/api/zoho/callback`
5. Save changes

### Step 4: Restart Backend

```bash
docker-compose restart backend
```

### Step 5: Verify

1. Check backend logs:
```bash
docker logs asi_backend | grep "redirectUri"
```

Should show the redirect URI you set.

2. Get new auth URL:
```bash
GET http://localhost:3000/api/zoho/auth
Authorization: Bearer <your_jwt_token>
```

3. Check the `redirect_uri` parameter in the `authUrl` - it should match what's in Zoho.

4. Re-authorize and check if tokens are saved:
```bash
docker exec asi_postgres psql -U postgres -d ASI -c "SELECT user_id, created_at FROM zoho_tokens;"
```

## Important Notes

- The redirect URI must match **EXACTLY** (including http/https, port, path)
- Zoho is case-sensitive for redirect URIs
- If using localhost, make sure Zoho can reach it (may need to use public IP for production)
- After changing redirect URI in Zoho, wait a few minutes for changes to propagate







