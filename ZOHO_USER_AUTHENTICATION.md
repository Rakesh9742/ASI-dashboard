# Zoho User Authentication Guide

## How Authentication Works for Zoho Users

### First Time Login (Zoho OAuth)
1. Click **"Login with Zoho"** button
2. Complete Zoho OAuth in the popup window
3. Your account is automatically created in the system
4. You're logged in and redirected to the dashboard

### Subsequent Logins

#### Option 1: Stay Logged In (Recommended) ✅
- **Your JWT token lasts 7 days**
- **Token is saved in browser storage**
- **You stay logged in even after closing the browser**
- **No need to re-authenticate for 7 days**

#### Option 2: Use Zoho OAuth Again
- If your token expires (after 7 days), click **"Login with Zoho"** again
- Quick and secure - just one click!

#### Option 3: Set a Password (Optional)
If you want to login with username/password instead:

1. **After logging in with Zoho**, go to your profile settings
2. **Set a password** using the "Set Password" option
3. **Future logins**: You can use either:
   - Username/Password (traditional login)
   - Zoho OAuth (one-click login)

### Important Notes

⚠️ **Zoho users cannot use username/password login until they set a password**

- When a Zoho user is created, they don't have a password set
- If you try to login with username/password before setting one, you'll see:
  ```
  "This account uses Zoho OAuth login. Please use 'Login with Zoho' button instead"
  ```

### Setting Your Password

**API Endpoint:** `POST /api/auth/set-password`

**Request:**
```json
{
  "password": "your-secure-password"
}
```

**Requirements:**
- Must be authenticated (logged in)
- Password must be at least 6 characters
- Can only be set once (for Zoho OAuth users)

**After setting password:**
- You can login with username/password
- You can still use Zoho OAuth (both methods work)

### Changing Your Password

**API Endpoint:** `POST /api/auth/change-password`

**Request:**
```json
{
  "currentPassword": "old-password",
  "newPassword": "new-secure-password"
}
```

**Note:** Zoho OAuth users who haven't set a password can skip `currentPassword` (it's ignored).

## Summary

| Scenario | Action Required |
|----------|----------------|
| **First login** | Use "Login with Zoho" button |
| **Next 7 days** | Already logged in, no action needed |
| **After 7 days** | Use "Login with Zoho" button again |
| **Want username/password** | Set password in profile settings first |
| **Password set** | Can use either login method |

## Your Username

When you login with Zoho, your username is automatically generated as:
- **Format:** `{email_prefix}_zoho`
- **Example:** If your email is `john.doe@company.com`, your username is `john.doe_zoho`

You can use either:
- Your **email address** OR
- Your **username** (`{email_prefix}_zoho`)

Both work for login!




