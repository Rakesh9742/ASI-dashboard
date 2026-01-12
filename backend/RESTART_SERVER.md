# How to Restart Backend Server After Adding Zoho Integration

## Problem
You're getting `Cannot GET /api/zoho/auth` error even though login works. This means the server needs to be restarted or rebuilt to load the new Zoho routes.

## Solution

### Option 1: If Running in Development Mode (npm run dev)

**The server should auto-reload, but if it doesn't:**

1. **Stop the server** (Press `Ctrl+C` in the terminal)

2. **Restart it:**
   ```powershell
   cd backend
   npm run dev
   ```

3. **Verify it's running:**
   - Check console for: `🚀 ASI Dashboard API server running on port 3000`
   - No errors about missing modules

### Option 2: If Running in Production Mode (npm start)

**You need to rebuild TypeScript first:**

1. **Stop the server** (Press `Ctrl+C`)

2. **Build TypeScript:**
   ```powershell
   cd backend
   npm run build
   ```

3. **Start the server:**
   ```powershell
   npm start
   ```

### Option 3: Quick Fix - Install Dependencies First

**If you haven't installed axios yet:**

1. **Install dependencies:**
   ```powershell
   cd backend
   npm install
   ```

2. **Then restart:**
   ```powershell
   # For development
   npm run dev
   
   # OR for production
   npm run build
   npm start
   ```

## Verify It's Working

After restarting, test in Postman:

1. **Check health endpoint:**
   ```
   GET http://localhost:3000/health
   ```
   Should return: `{"status":"ok",...}`

2. **Check Zoho status:**
   ```
   GET http://localhost:3000/api/zoho/status
   Headers: Authorization: Bearer YOUR_TOKEN
   ```
   Should return: `{"connected":false,...}` (not an error)

## Common Issues

### Issue: Module not found error
**Error:** `Cannot find module 'axios'`

**Fix:**
```powershell
cd backend
npm install
npm run dev
```

### Issue: TypeScript compilation errors
**Error:** Type errors in console

**Fix:**
```powershell
cd backend
npm run build
# Check for errors, fix them, then:
npm start
```

### Issue: Port already in use
**Error:** `Port 3000 is already in use`

**Fix:**
1. Find and kill the process:
   ```powershell
   # Windows
   netstat -ano | findstr :3000
   taskkill /PID <PID> /F
   ```
2. Or change port in `.env`:
   ```
   PORT=3001
   ```

## Quick Checklist

- [ ] Installed dependencies: `npm install`
- [ ] Server is running: Check console
- [ ] No TypeScript errors: Check build output
- [ ] Routes are registered: Check `index.ts` has zoho routes
- [ ] Test endpoint works: `GET /api/zoho/status`

## Still Not Working?

1. **Check if files exist:**
   ```powershell
   Test-Path "src\routes\zoho.routes.ts"
   Test-Path "src\services\zoho.service.ts"
   ```
   Both should return `True`

2. **Check server logs:**
   - Look for import errors
   - Look for route registration messages
   - Check for TypeScript compilation errors

3. **Verify index.ts:**
   - Should have: `import zohoRoutes from './routes/zoho.routes';`
   - Should have: `app.use('/api/zoho', zohoRoutes);`

4. **Try hard restart:**
   ```powershell
   # Stop server
   # Delete node_modules and reinstall
   Remove-Item -Recurse -Force node_modules
   npm install
   npm run dev
   ```












