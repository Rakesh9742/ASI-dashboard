# Session Expiration & Logout

## 1. When you close the app without logging out (coming back later)

### What happens on reopen

1. **Auth state is restored from device**
   - On app start, `AuthNotifier` runs `_loadAuthState()` and reads **token** and **user** from **SharedPreferences** (saved at login).
   - If both exist, it sets `isAuthenticated: true` with that token and user.
   - **AuthWrapper** sees `isAuthenticated: true` and shows **MainNavigationScreen** (main app), not the login screen.
   - So when you come back, you are shown as **still logged in** and go straight into the app; you do **not** have to log in again unless the token is no longer valid.

2. **JWT (app session)**
   - The app does **not** check with the server that the token is still valid on startup. It only uses what is in SharedPreferences.
   - If the JWT has **expired** while the app was closed (e.g. after 7 days if `JWT_EXPIRES_IN=7d`), the **next API call** that uses that token will get **401** from the backend (e.g. “Token expired”).
   - Today the app does **not** globally handle 401 by clearing auth and sending you to login. The failing request will throw and you may see an error message; you need to use **Logout** (or clear app data) and then log in again to get a new token.

3. **Zoho**
   - Zoho tokens are stored in the **backend** (`zoho_tokens` table), not in the app. Closing the app does not remove them.
   - When you come back and the app calls any Zoho API, the backend uses `getValidAccessToken(userId)`: if the access token is expired or expiring soon (< 5 min), it **refreshes** using the refresh token and saves the new access token. So Zoho continues to work after you reopen the app, as long as the refresh token is still valid.

4. **SSH**
   - The SSH connection is maintained by the **backend**. When you closed the app, the connection may have stayed open or been closed by the server (e.g. timeout).
   - When you come back and use something that needs SSH (e.g. run command, terminal), the backend will **reconnect** if needed (`getSSHConnection(userId)`). So SSH is re-established on demand; no special action needed from you.

**Summary:** Closing the app without logging out is supported. When you come back, the app restores your session from SharedPreferences and you are taken straight into the app. Zoho is refreshed on the backend when needed; SSH is reconnected on demand. If your JWT has expired, the next API call will get 401 and you need to log out and log in again to get a new token.

---

## 2. Zoho session expiration

### Where Zoho tokens live
- Stored in DB: `zoho_tokens` (per user: `access_token`, `refresh_token`, `expires_at`).
- **Access token** expires (e.g. ~1 hour). **Refresh token** is long-lived until revoked.

### How expiration is handled (backend)

1. **When any Zoho API is called**  
   Backend uses `zoho.service.getValidAccessToken(userId)`:
   - Reads `access_token`, `refresh_token`, `expires_at` from `zoho_tokens`.
   - If **expires_at is in less than 5 minutes**, it **refreshes** using the refresh token (Zoho OAuth `refresh_token` grant), then updates `zoho_tokens` with the new access token and expiry.
   - Returns the (possibly refreshed) access token.

2. **“Is Zoho connected?” checks**  
   Backend uses `zoho.service.hasValidToken(userId)`:
   - Returns true only if a row exists and `expires_at > now`.
   - Does **not** try to refresh. So if the access token is already expired but the refresh token is still valid, `hasValidToken` can be false until the next call that uses `getValidAccessToken` (which will refresh).

3. **If refresh fails**  
   - Refresh can fail (e.g. refresh token revoked/expired).  
   - `getValidAccessToken` throws (e.g. “refresh token may be invalid or expired. Please re-authorize”).  
   - API returns 500; user must use “Login with Zoho” again to get new tokens.

**Summary:** Zoho “session” is kept valid by **refreshing the access token** when it’s about to expire (< 5 min). No separate “Zoho session expiration” event is emitted; expiration is handled inside Zoho API calls.

---

## 3. Application logout

### Frontend (Flutter)

- **Logout action** (e.g. Logout in main nav) calls `AuthNotifier.logout()` (`auth_provider.dart`).
- **In `logout()`:**
  1. **SSH:** `ApiService.disconnectSSH(token)` is called so the backend closes the SSH connection and any terminal sessions for that user.
  2. **Zoho:** `ApiService.disconnectZoho(token)` is called so the backend removes Zoho tokens from `zoho_tokens` for that user (all roles). Errors are ignored so logout always completes.
  3. **Local auth state:** Token and user are removed from `SharedPreferences` (`_tokenKey`, `_userKey`).
  4. **State:** `AuthState` is set to `isAuthenticated: false`.

So:
- **Session** = JWT in app (and optionally Zoho tokens in DB).
- **Logout** = clear JWT and user from app + disconnect SSH + remove Zoho tokens from DB. Next login is fresh (no Zoho until user connects again).

### Backend

- **JWT:** Stateless. There is no “logout” endpoint that invalidates the token; logout is done by the client discarding the token.
- **JWT expiration:** Configured by `JWT_EXPIRES_IN` (e.g. `7d`). If the client sends an expired JWT, `auth.middleware` returns **401** with `error: 'Token expired'`.
- **Zoho:**  
  - **POST /api/zoho/disconnect** (authenticated): calls `zoho.service.revokeTokens(userId)`, which **deletes** the row in `zoho_tokens` for that user.  
  - This is called automatically on app logout (all roles) so the user gets a fresh state on next login. It is also used when the user explicitly “disconnects” Zoho in the UI.
