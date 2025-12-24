# How to Update Backend in Docker/Kubernetes

This guide shows you how to stop, rebuild, and deploy backend changes when using Docker and Kubernetes (Minikube).

## Quick Steps Summary

1. **Rebuild Docker image** with your changes
2. **Load image into Minikube** (if using minikube)
3. **Restart backend pods** to use new image

---

## Method 1: Using Deployment Script (Easiest)

### Update Backend Only

```powershell
# From project root
.\k8s\deploy.ps1 -Local
```

This will:
- ✅ Build new backend Docker image
- ✅ Load it into minikube
- ✅ Update deployments
- ✅ Restart pods automatically

---

## Method 2: Manual Step-by-Step

### Step 1: Rebuild Docker Image

```powershell
# Navigate to backend directory
cd backend

# Build new Docker image (includes your Zoho changes)
docker build -t asi-backend:latest .

# Go back to root
cd ..
```

**What this does:**
- Copies all your code (including new Zoho files)
- Installs dependencies (including axios)
- Builds TypeScript
- Creates new Docker image

### Step 2: Load Image into Minikube

**Important:** Minikube uses its own Docker daemon, so you must load the image.

```powershell
# Load the new backend image into minikube
minikube image load asi-backend:latest
```

**Verify it's loaded:**
```powershell
minikube image ls | Select-String "asi-backend"
```

### Step 3: Restart Backend Pods

**Option A: Rolling Restart (Recommended)**
```powershell
# This triggers a rolling update with zero downtime
kubectl rollout restart deployment/backend -n asi-dashboard

# Wait for rollout to complete
kubectl rollout status deployment/backend -n asi-dashboard
```

**Option B: Delete Pods (Faster, but brief downtime)**
```powershell
# Delete all backend pods (they will recreate automatically)
kubectl delete pods -n asi-dashboard -l app=backend

# Watch pods restart
kubectl get pods -n asi-dashboard -l app=backend -w
```

**Option C: Scale Down/Up**
```powershell
# Scale down to 0
kubectl scale deployment/backend --replicas=0 -n asi-dashboard

# Wait a moment
Start-Sleep -Seconds 5

# Scale back up
kubectl scale deployment/backend --replicas=2 -n asi-dashboard
```

### Step 4: Verify New Version is Running

```powershell
# Check pod status
kubectl get pods -n asi-dashboard -l app=backend

# Check logs to see if new code is running
kubectl logs -f deployment/backend -n asi-dashboard

# Test the new endpoint
kubectl port-forward service/backend 3000:3000 -n asi-dashboard
# Then test: GET http://localhost:3000/api/zoho/status
```

---

## Method 3: Complete Rebuild (No Cache)

If you want to ensure everything is fresh:

```powershell
# Build with no cache
cd backend
docker build --no-cache -t asi-backend:latest .
cd ..

# Load into minikube
minikube image load asi-backend:latest

# Restart deployment
kubectl rollout restart deployment/backend -n asi-dashboard
```

---

## Complete Update Script

Create a file `update-backend.ps1` in project root:

```powershell
# Update Backend in Kubernetes
Write-Host "=== Updating Backend in Kubernetes ===" -ForegroundColor Green

# Step 1: Build image
Write-Host "`n1. Building Docker image..." -ForegroundColor Yellow
Set-Location backend
docker build -t asi-backend:latest .
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Build failed!" -ForegroundColor Red
    Set-Location ..
    exit 1
}
Set-Location ..

# Step 2: Load into minikube
Write-Host "`n2. Loading image into minikube..." -ForegroundColor Yellow
minikube image load asi-backend:latest
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to load image!" -ForegroundColor Red
    exit 1
}

# Step 3: Restart deployment
Write-Host "`n3. Restarting backend deployment..." -ForegroundColor Yellow
kubectl rollout restart deployment/backend -n asi-dashboard

# Step 4: Wait for rollout
Write-Host "`n4. Waiting for rollout to complete..." -ForegroundColor Yellow
kubectl rollout status deployment/backend -n asi-dashboard

# Step 5: Verify
Write-Host "`n5. Verifying deployment..." -ForegroundColor Yellow
kubectl get pods -n asi-dashboard -l app=backend

Write-Host "`n✅ Backend update complete!" -ForegroundColor Green
```

**Usage:**
```powershell
.\update-backend.ps1
```

---

## Troubleshooting

### Issue: Pods Still Using Old Image

**Check current image:**
```powershell
kubectl describe pod -n asi-dashboard -l app=backend | Select-String "Image:"
```

**Force pull:**
```powershell
# Delete pods to force recreation
kubectl delete pods -n asi-dashboard -l app=backend

# Or update deployment to force pull
kubectl set image deployment/backend backend=asi-backend:latest -n asi-dashboard
kubectl rollout restart deployment/backend -n asi-dashboard
```

### Issue: Image Not Found in Minikube

**Verify image is loaded:**
```powershell
minikube image ls | Select-String "asi-backend"
```

**If not found, reload:**
```powershell
minikube image load asi-backend:latest
```

### Issue: Pods Crash After Update

**Check logs:**
```powershell
kubectl logs -n asi-dashboard -l app=backend --tail=50
```

**Check pod events:**
```powershell
kubectl describe pod -n asi-dashboard -l app=backend
```

**Common causes:**
- Missing dependencies (run `npm install` before building)
- TypeScript errors (check build output)
- Missing environment variables
- Database connection issues

### Issue: Changes Not Reflected

**Verify new code is in image:**
```powershell
# Check if new files are in the image
docker run --rm asi-backend:latest ls -la /app/src/routes/ | Select-String "zoho"
```

**If files missing:**
- Check Dockerfile copies all files
- Rebuild with `--no-cache`
- Verify you're in the correct directory when building

---

## Quick Reference Commands

### Build and Deploy
```powershell
# Quick update
cd backend && docker build -t asi-backend:latest . && cd ..
minikube image load asi-backend:latest
kubectl rollout restart deployment/backend -n asi-dashboard
```

### Check Status
```powershell
# Pod status
kubectl get pods -n asi-dashboard -l app=backend

# Deployment status
kubectl get deployment backend -n asi-dashboard

# Rollout status
kubectl rollout status deployment/backend -n asi-dashboard
```

### View Logs
```powershell
# All backend logs
kubectl logs -f deployment/backend -n asi-dashboard

# Specific pod
kubectl logs -f <pod-name> -n asi-dashboard

# Previous crashed pod
kubectl logs <pod-name> -n asi-dashboard --previous
```

### Restart Options
```powershell
# Rolling restart (recommended)
kubectl rollout restart deployment/backend -n asi-dashboard

# Delete pods (faster)
kubectl delete pods -n asi-dashboard -l app=backend

# Scale down/up
kubectl scale deployment/backend --replicas=0 -n asi-dashboard
kubectl scale deployment/backend --replicas=2 -n asi-dashboard
```

---

## What Happens During Update

1. **Docker Build:**
   - Copies all source files (including new Zoho files)
   - Installs npm packages (including axios)
   - Compiles TypeScript to JavaScript
   - Creates new image layer

2. **Minikube Load:**
   - Transfers image from host Docker to minikube Docker
   - Makes image available to Kubernetes

3. **Pod Restart:**
   - Kubernetes detects new image
   - Creates new pods with new image
   - Terminates old pods
   - New pods start with updated code

4. **Verification:**
   - New pods become ready
   - Traffic routes to new pods
   - Old pods terminate

---

## Best Practices

1. **Always test locally first** before deploying to Kubernetes
2. **Use rolling restart** to avoid downtime
3. **Check logs** after deployment to verify it's working
4. **Keep image tags** for rollback (use version tags in production)
5. **Monitor deployment** during rollout

---

## For Production

In production, use version tags instead of `latest`:

```powershell
# Build with version
docker build -t asi-backend:v1.1.0 .

# Update deployment
kubectl set image deployment/backend backend=asi-backend:v1.1.0 -n asi-dashboard

# Rollback if needed
kubectl rollout undo deployment/backend -n asi-dashboard
```

---

## Summary

**To update backend with Zoho changes:**

```powershell
# 1. Build
cd backend
docker build -t asi-backend:latest .
cd ..

# 2. Load into minikube
minikube image load asi-backend:latest

# 3. Restart
kubectl rollout restart deployment/backend -n asi-dashboard

# 4. Verify
kubectl get pods -n asi-dashboard -l app=backend
kubectl logs -f deployment/backend -n asi-dashboard
```

That's it! Your new Zoho integration endpoints will be available.

