# Test Zoho Endpoints After Backend Update

## ✅ Backend Status

Your backend has been restarted and is running:
- ✅ New pods created and running
- ✅ Port forwarding active on port 3000
- ✅ Deployment successfully rolled out

## 🧪 Test Zoho Endpoints in Postman

### Step 1: Get Your JWT Token

**Request:**
```
POST http://localhost:3000/api/auth/login
Content-Type: application/json

Body:
{
  "username": "admin",
  "password": "admin123"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {...}
}
```

**Copy the `token` value!**

---

### Step 2: Test Zoho Status Endpoint

**Request:**
```
GET http://localhost:3000/api/zoho/status
Authorization: Bearer YOUR_TOKEN_HERE
```

**Expected Response (Not Connected):**
```json
{
  "connected": false,
  "message": "Zoho Projects is not connected"
}
```

**Expected Response (Connected):**
```json
{
  "connected": true,
  "message": "Zoho Projects is connected"
}
```

**✅ If you get this response, the endpoint is working!**

---

### Step 3: Test Get Auth URL

**Request:**
```
GET http://localhost:3000/api/zoho/auth
Authorization: Bearer YOUR_TOKEN_HERE
```

**Expected Response:**
```json
{
  "authUrl": "https://accounts.zoho.com/oauth/v2/auth?client_id=...",
  "message": "Redirect user to this URL to authorize"
}
```

**✅ If you get this response, the endpoint is working!**

---

### Step 4: Test Get Projects (After Authorization)

**Request:**
```
GET http://localhost:3000/api/zoho/projects
Authorization: Bearer YOUR_TOKEN_HERE
```

**Expected Response (Not Connected):**
```json
{
  "success": false,
  "error": "No Zoho token found for user. Please authorize first."
}
```

**Expected Response (Connected):**
```json
{
  "success": true,
  "count": 3,
  "projects": [...]
}
```

---

## 🔍 Troubleshooting

### Error: "Cannot GET /api/zoho/status"

**Possible causes:**
1. Backend pods not restarted with new image
2. Image doesn't have new Zoho files
3. Routes not registered

**Fix:**
```powershell
# Rebuild and reload
cd backend
docker build -t asi-backend:latest .
cd ..
minikube image load asi-backend:latest
kubectl rollout restart deployment/backend -n asi-dashboard
```

### Error: 401 Unauthorized

**Fix:**
- Make sure you're including the Authorization header
- Verify token is valid (not expired)
- Login again to get a fresh token

### Error: 500 Internal Server Error

**Check logs:**
```powershell
kubectl logs -f deployment/backend -n asi-dashboard
```

**Common issues:**
- Missing axios package (check Dockerfile installs it)
- Database connection issues
- Missing environment variables

### Error: Module not found

**Fix:**
- Rebuild image with `--no-cache`:
  ```powershell
  docker build --no-cache -t asi-backend:latest .
  minikube image load asi-backend:latest
  kubectl rollout restart deployment/backend -n asi-dashboard
  ```

---

## ✅ Success Checklist

- [ ] Backend pods are running
- [ ] Port forwarding is active
- [ ] Can login and get token
- [ ] `/api/zoho/status` returns response (not error)
- [ ] `/api/zoho/auth` returns auth URL
- [ ] No errors in backend logs

---

## 📝 Quick Test Commands

**Check if endpoint exists:**
```powershell
# In Postman or browser (with token)
curl http://localhost:3000/api/zoho/status -H "Authorization: Bearer YOUR_TOKEN"
```

**Check backend logs:**
```powershell
kubectl logs -f deployment/backend -n asi-dashboard
```

**Check pod status:**
```powershell
kubectl get pods -n asi-dashboard -l app=backend
```

**Check if new code is in pod:**
```powershell
kubectl exec -it deployment/backend -n asi-dashboard -- ls -la /app/src/routes/ | grep zoho
```

---

## 🎯 Next Steps

1. ✅ Test `/api/zoho/status` - Should work now
2. ✅ Test `/api/zoho/auth` - Should return auth URL
3. ✅ Authorize Zoho account (use auth URL)
4. ✅ Test `/api/zoho/projects` - Should return projects
5. ✅ Test `/api/projects?includeZoho=true` - Should return combined projects

Your Zoho integration is now live! 🎉

