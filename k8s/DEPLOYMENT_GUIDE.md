# Complete Kubernetes Deployment Guide - ASI Dashboard

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Initial Setup](#initial-setup)
5. [Deployment Process](#deployment-process)
6. [Issues Encountered and Solutions](#issues-encountered-and-solutions)
7. [Accessing the Application](#accessing-the-application)
8. [Verification and Monitoring](#verification-and-monitoring)
9. [Troubleshooting](#troubleshooting)
10. [Maintenance and Updates](#maintenance-and-updates)
11. [Making Changes to the Application](#making-changes-to-the-application)
12. [Production Deployment Guide](#production-deployment-guide)

---

## Overview

This document provides a complete guide on how we established Kubernetes for the ASI Dashboard application and achieved a fully running application. The ASI Dashboard is a full-stack application consisting of:

- **Frontend**: Flutter web application served via Nginx
- **Backend**: Node.js/Express API server
- **Database**: PostgreSQL 15

All components are containerized using Docker and orchestrated using Kubernetes on Minikube.

---

## Architecture

### Application Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (Minikube)             │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              Namespace: asi-dashboard                   │ │
│  │                                                         │ │
│  │  ┌──────────────┐    ┌──────────────┐   ┌──────────┐ │ │
│  │  │   Frontend   │───▶│   Backend    │──▶│ Postgres │ │ │
│  │  │  (Nginx)     │    │  (Node.js)   │   │   15     │ │ │
│  │  │   Port 80    │    │  Port 3000   │   │ Port 5432│ │ │
│  │  │  2 replicas  │    │  2 replicas  │   │1 replica │ │ │
│  │  └──────────────┘    └──────────────┘   └──────────┘ │ │
│  │       │                    │                  │        │ │
│  │       └────────────────────┴──────────────────┘        │ │
│  │                        │                                │ │
│  │                  ┌─────▼─────┐                         │ │
│  │                  │  Ingress  │                         │ │
│  │                  │ Controller │                         │ │
│  │                  └────────────┘                         │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Kubernetes Resources

| Resource Type | Name | Purpose |
|--------------|------|---------|
| **Namespace** | `asi-dashboard` | Isolates application resources |
| **ConfigMap** | `backend-config` | Backend configuration (non-sensitive) |
| **ConfigMap** | `postgres-config` | PostgreSQL configuration |
| **ConfigMap** | `postgres-init-scripts` | Database initialization scripts |
| **Secret** | `backend-secret` | JWT secret and sensitive backend data |
| **Secret** | `postgres-secret` | Database password |
| **PersistentVolumeClaim** | `postgres-pvc` | Database storage |
| **Deployment** | `frontend` | Frontend application (2 replicas) |
| **Deployment** | `backend` | Backend API (2 replicas) |
| **Deployment** | `postgres` | PostgreSQL database (1 replica) |
| **Service** | `frontend` | LoadBalancer for frontend access |
| **Service** | `backend` | ClusterIP for internal backend access |
| **Service** | `postgres` | ClusterIP for database access |
| **Ingress** | `asi-dashboard-ingress` | External routing configuration |

---

## Prerequisites

### Required Software

1. **Docker Desktop** (or Docker Engine)
   - Version: 20.10 or later
   - Used for building container images

2. **Minikube**
   - Version: 1.37.0 or later
   - Local Kubernetes cluster

3. **kubectl**
   - Kubernetes command-line tool
   - Configured to connect to minikube

4. **PowerShell** (Windows) or **Bash** (Linux/Mac)
   - For running deployment scripts

### System Requirements

- **CPU**: Minimum 2 cores (4+ recommended)
- **RAM**: Minimum 4GB (8GB+ recommended)
- **Disk**: At least 20GB free space
- **OS**: Windows 10/11, Linux, or macOS

### Verification

Check that all prerequisites are installed:

```powershell
# Check Docker
docker --version
docker info

# Check Minikube
minikube version

# Check kubectl
kubectl version --client

# Check Kubernetes cluster
kubectl cluster-info
```

---

## Initial Setup

### Step 1: Install Minikube

**Windows (using Chocolatey):**
```powershell
choco install minikube
```

**Windows (Manual):**
1. Download from: https://minikube.sigs.k8s.io/docs/start/
2. Add to PATH

**Linux/Mac:**
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

### Step 2: Start Minikube Cluster

```powershell
# Start minikube with recommended settings
minikube start --driver=docker --memory=4096 --cpus=2

# Verify cluster is running
minikube status
kubectl get nodes
```

**Expected Output:**
```
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

### Step 3: Verify Kubernetes Connection

```powershell
# Check cluster info
kubectl cluster-info

# List contexts
kubectl config get-contexts

# Set minikube as current context (if needed)
kubectl config use-context minikube
```

### Step 4: Enable Required Addons (Optional)

```powershell
# Enable ingress controller (for production-like setup)
minikube addons enable ingress

# Enable metrics server (for resource monitoring)
minikube addons enable metrics-server
```

---

## Deployment Process

### Step 1: Build Docker Images

The deployment script automatically builds Docker images, but here's the manual process:

#### Build Backend Image

```powershell
cd backend
docker build -t asi-backend:latest .
cd ..
```

**Backend Dockerfile Structure:**
- Base: `node:18-alpine`
- Installs dependencies: `npm install`
- Builds application: `npm run build`
- Runs: `node dist/index.js`

#### Build Frontend Image

```powershell
cd frontend
docker build -t asi-frontend:latest .
cd ..
```

**Frontend Dockerfile Structure:**
- Stage 1: Build Flutter web app using `ubuntu:22.04`
- Stage 2: Serve with `nginx:alpine`
- Multi-stage build for optimized image size

### Step 2: Load Images into Minikube

**Critical Step**: Minikube uses its own Docker daemon, so images built on the host must be loaded into minikube.

```powershell
# Load backend image
minikube image load asi-backend:latest

# Load frontend image
minikube image load asi-frontend:latest

# Verify images are loaded
minikube image ls | Select-String "asi-"
```

### Step 3: Configure Kubernetes Manifests

The application uses Kustomize for resource management. Key configuration files:

#### Namespace (`namespace.yaml`)
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: asi-dashboard
```

#### Backend Configuration (`backend-configmap.yaml`)
- PORT: 3000
- NODE_ENV: production
- DATABASE_URL: postgresql://postgres:password@postgres:5432/ASI
- JWT_EXPIRES_IN: 24h

#### Backend Secrets (`backend-secret.yaml`)
- JWT_SECRET: (change in production!)

#### PostgreSQL Configuration (`postgres-configmap.yaml`)
- POSTGRES_DB: ASI
- POSTGRES_USER: postgres

#### PostgreSQL Secrets (`postgres-secret.yaml`)
- POSTGRES_PASSWORD: (change in production!)

### Step 4: Deploy Using Automated Script

**PowerShell (Windows):**
```powershell
.\k8s\deploy.ps1 -Local
```

**What the script does:**
1. ✅ Builds backend Docker image
2. ✅ Builds frontend Docker image
3. ✅ Updates deployment YAMLs for local images
4. ✅ Loads images into minikube (if using minikube)
5. ✅ Checks Kubernetes connection
6. ✅ Deploys all resources using `kubectl apply -k k8s/`
7. ✅ Waits for deployments to be ready
8. ✅ Shows deployment status

**Bash (Linux/Mac):**
```bash
./k8s/deploy.sh --local
```

### Step 5: Manual Deployment (Alternative)

If you prefer manual deployment:

```powershell
# Navigate to k8s directory
cd k8s

# Deploy all resources using Kustomize
kubectl apply -k .

# Or deploy individually
kubectl apply -f namespace.yaml
kubectl apply -f postgres-pvc.yaml
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-secret.yaml
kubectl apply -f postgres-init-configmap.yaml
kubectl apply -f postgres-deployment.yaml
kubectl apply -f postgres-service.yaml
kubectl apply -f backend-configmap.yaml
kubectl apply -f backend-secret.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml
kubectl apply -f ingress.yaml
```

### Step 6: Verify Deployment

```powershell
# Check all pods are running
kubectl get pods -n asi-dashboard

# Expected output:
# NAME                        READY   STATUS    RESTARTS   AGE
# backend-xxx                  1/1     Running   0         2m
# frontend-xxx                 1/1     Running   0         2m
# postgres-xxx                 1/1     Running   0         2m

# Check services
kubectl get services -n asi-dashboard

# Check deployments
kubectl get deployments -n asi-dashboard
```

---

## Issues Encountered and Solutions

### Issue 1: Kubernetes Connection Failed

**Problem:**
```
Unable to connect to the server: dial tcp 127.0.0.1:52751: 
connectex: No connection could be made because the target machine 
actively refused it.
```

**Root Cause:**
- Minikube cluster was partially stopped (kubelet and apiserver stopped)
- Kubeconfig was pointing to a stale endpoint

**Solution:**
```powershell
# Update minikube context
minikube update-context

# Start minikube cluster
minikube start

# Verify connection
kubectl cluster-info
```

**Prevention:**
The deployment script now includes diagnostic checks that detect this issue and provide specific fix instructions.

### Issue 2: ErrImageNeverPull - Images Not Found

**Problem:**
```
Error: ErrImageNeverPull
Container image "asi-backend:latest" is not present with pull policy of Never
```

**Root Cause:**
- Images were built on host Docker daemon
- Minikube has its own separate Docker daemon
- With `imagePullPolicy: Never`, Kubernetes doesn't pull from registry
- Images weren't available in minikube's Docker environment

**Solution:**
```powershell
# Load images into minikube
minikube image load asi-backend:latest
minikube image load asi-frontend:latest

# Restart pods to pick up images
kubectl delete pods -n asi-dashboard -l app=backend
kubectl delete pods -n asi-dashboard -l app=frontend
```

**Prevention:**
The deployment script now automatically loads images into minikube when using the `-Local` flag.

### Issue 3: Deployment Timeout

**Problem:**
```
error: timed out waiting for the condition on deployments/backend
```

**Root Cause:**
- Pods couldn't start due to missing images (Issue 2)
- Health checks failing
- Resource constraints

**Solution:**
1. Check pod status: `kubectl get pods -n asi-dashboard`
2. Check pod events: `kubectl describe pod <pod-name> -n asi-dashboard`
3. Check logs: `kubectl logs <pod-name> -n asi-dashboard`
4. Fix underlying issue (usually image loading)
5. Script will retry automatically

### Issue 4: Database Connection Issues

**Problem:**
Backend can't connect to PostgreSQL.

**Solution:**
```powershell
# Check PostgreSQL is running
kubectl get pods -n asi-dashboard -l app=postgres

# Check PostgreSQL logs
kubectl logs -f deployment/postgres -n asi-dashboard

# Test connection from backend pod
kubectl exec -it deployment/backend -n asi-dashboard -- sh
# Inside pod: ping postgres
# Inside pod: nc -zv postgres 5432

# Verify DATABASE_URL in backend config
kubectl get configmap backend-config -n asi-dashboard -o yaml
```

**Common Fixes:**
- Ensure PostgreSQL pod is running
- Verify DATABASE_URL format: `postgresql://user:password@postgres:5432/dbname`
- Check network policies (if any)
- Verify service name matches: `postgres`

### Issue 5: Frontend Can't Reach Backend

**Problem:**
Frontend makes API calls but gets connection errors.

**Solution:**
```powershell
# Verify backend service exists
kubectl get service backend -n asi-dashboard

# Test from frontend pod
kubectl exec -it deployment/frontend -n asi-dashboard -- sh
# Inside pod: wget -O- http://backend:3000/health

# Check backend API_URL configuration in frontend
kubectl get configmap frontend-config -n asi-dashboard -o yaml
```

**Common Fixes:**
- Use service name for internal communication: `http://backend:3000`
- For external access, use port-forward or ingress
- Verify CORS settings in backend

---

## Accessing the Application

### Method 1: Port Forwarding (Recommended for Development)

**Frontend:**
```powershell
# Terminal 1
kubectl port-forward service/frontend 8080:80 -n asi-dashboard

# Access at: http://localhost:8080
```

**Backend API:**
```powershell
# Terminal 2
kubectl port-forward service/backend 3000:3000 -n asi-dashboard

# Access at: http://localhost:3000
# Health check: http://localhost:3000/health
```

### Method 2: Minikube Service

**Frontend:**
```powershell
# Opens in default browser automatically
minikube service frontend -n asi-dashboard

# Or get URL only
minikube service frontend -n asi-dashboard --url
```

**Backend:**
```powershell
# Note: Backend is ClusterIP, so port-forward is needed
kubectl port-forward service/backend 3000:3000 -n asi-dashboard
```

### Method 3: Minikube Tunnel (For LoadBalancer)

```powershell
# Start tunnel in separate terminal (keeps running)
minikube tunnel

# In another terminal, check service external IP
kubectl get services -n asi-dashboard

# Access using the EXTERNAL-IP shown
```

### Method 4: Ingress (Production-like)

**Prerequisites:**
```powershell
# Enable ingress addon
minikube addons enable ingress

# Wait for ingress controller
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

**Get Ingress IP:**
```powershell
kubectl get ingress -n asi-dashboard
```

**Configure Hosts File:**
Add to `C:\Windows\System32\drivers\etc\hosts` (Windows) or `/etc/hosts` (Linux/Mac):
```
<ingress-ip> asi-dashboard.local
```

**Access:**
- Frontend: `http://asi-dashboard.local`
- Backend API: `http://asi-dashboard.local/api`

---

## Verification and Monitoring

### Check Pod Status

```powershell
# All pods
kubectl get pods -n asi-dashboard

# Detailed pod information
kubectl describe pod <pod-name> -n asi-dashboard

# Pod logs
kubectl logs -f deployment/backend -n asi-dashboard
kubectl logs -f deployment/frontend -n asi-dashboard
kubectl logs -f deployment/postgres -n asi-dashboard
```

### Check Service Endpoints

```powershell
# Verify services have endpoints
kubectl get endpoints -n asi-dashboard

# Expected: Each service should have pod IPs listed
```

### Check Resource Usage

```powershell
# Pod resource usage
kubectl top pods -n asi-dashboard

# Node resource usage
kubectl top nodes
```

### Health Checks

```powershell
# Backend health endpoint
kubectl port-forward service/backend 3000:3000 -n asi-dashboard
# Then: curl http://localhost:3000/health

# Or from inside cluster
kubectl run -it --rm curl-test --image=curlimages/curl --restart=Never -- \
  curl http://backend.asi-dashboard.svc.cluster.local:3000/health
```

### Database Verification

```powershell
# Connect to PostgreSQL
kubectl exec -it deployment/postgres -n asi-dashboard -- psql -U postgres -d ASI

# Inside psql:
# \dt          # List tables
# \d+ <table>  # Describe table
# SELECT * FROM <table> LIMIT 10;
```

---

## Troubleshooting

### Pods Not Starting

```powershell
# Check pod status
kubectl get pods -n asi-dashboard

# Check pod events
kubectl describe pod <pod-name> -n asi-dashboard

# Check logs
kubectl logs <pod-name> -n asi-dashboard

# Common issues:
# - ImagePullBackOff: Image not found or pull policy issue
# - CrashLoopBackOff: Application crashing, check logs
# - Pending: Resource constraints or scheduling issues
```

### Services Not Accessible

```powershell
# Check service endpoints
kubectl get endpoints -n asi-dashboard

# If no endpoints, pods aren't matching service selector
kubectl get pods -n asi-dashboard --show-labels

# Verify service selector matches pod labels
kubectl get service backend -n asi-dashboard -o yaml
kubectl get pods -n asi-dashboard -l app=backend
```

### Database Connection Issues

```powershell
# Check PostgreSQL is running
kubectl get pods -n asi-dashboard -l app=postgres

# Check PostgreSQL logs
kubectl logs deployment/postgres -n asi-dashboard

# Test network connectivity
kubectl exec -it deployment/backend -n asi-dashboard -- \
  nc -zv postgres 5432

# Verify DATABASE_URL
kubectl get configmap backend-config -n asi-dashboard -o yaml
```

### Image Issues

```powershell
# List images in minikube
minikube image ls

# Load image into minikube
minikube image load <image-name>

# Check image pull policy
kubectl get deployment backend -n asi-dashboard -o yaml | grep imagePullPolicy
```

### Network Issues

```powershell
# Check DNS resolution
kubectl run -it --rm dns-test --image=busybox --restart=Never -- \
  nslookup postgres.asi-dashboard.svc.cluster.local

# Test service connectivity
kubectl run -it --rm curl-test --image=curlimages/curl --restart=Never -- \
  curl http://backend.asi-dashboard.svc.cluster.local:3000/health
```

### Complete Reset

If everything is broken:

```powershell
# Delete all resources
kubectl delete namespace asi-dashboard

# Or delete specific resources
kubectl delete -k k8s/

# Rebuild and redeploy
.\k8s\deploy.ps1 -Local
```

---

## Maintenance and Updates

### Updating the Application

#### Update Backend

```powershell
# 1. Make code changes
# 2. Rebuild image
cd backend
docker build -t asi-backend:latest .
cd ..

# 3. Load into minikube
minikube image load asi-backend:latest

# 4. Restart deployment
kubectl rollout restart deployment/backend -n asi-dashboard

# 5. Monitor rollout
kubectl rollout status deployment/backend -n asi-dashboard
```

#### Update Frontend

```powershell
# 1. Make code changes
# 2. Rebuild image
cd frontend
docker build -t asi-frontend:latest .
cd ..

# 3. Load into minikube
minikube image load asi-frontend:latest

# 4. Restart deployment
kubectl rollout restart deployment/frontend -n asi-dashboard

# 5. Monitor rollout
kubectl rollout status deployment/frontend -n asi-dashboard
```

### Scaling Applications

```powershell
# Scale backend
kubectl scale deployment/backend --replicas=3 -n asi-dashboard

# Scale frontend
kubectl scale deployment/frontend --replicas=3 -n asi-dashboard

# Verify scaling
kubectl get pods -n asi-dashboard
```

### Database Backup

```powershell
# Create backup
kubectl exec deployment/postgres -n asi-dashboard -- \
  pg_dump -U postgres ASI > backup.sql

# Or using port-forward
kubectl port-forward service/postgres 5432:5432 -n asi-dashboard
# Then use pg_dump from local machine
```

### Database Restore

```powershell
# Copy backup to pod
kubectl cp backup.sql asi-dashboard/<postgres-pod-name>:/tmp/backup.sql

# Restore
kubectl exec deployment/postgres -n asi-dashboard -- \
  psql -U postgres -d ASI < /tmp/backup.sql
```

### Viewing Logs

```powershell
# All logs
kubectl logs -f deployment/backend -n asi-dashboard

# Specific pod
kubectl logs -f <pod-name> -n asi-dashboard

# Previous container instance (if crashed)
kubectl logs <pod-name> -n asi-dashboard --previous

# All pods with label
kubectl logs -f -l app=backend -n asi-dashboard
```

### Resource Monitoring

```powershell
# Pod resource usage
kubectl top pods -n asi-dashboard

# Node resource usage
kubectl top nodes

# Detailed resource requests/limits
kubectl describe pod <pod-name> -n asi-dashboard | grep -A 5 "Limits\|Requests"
```

### Making Changes to the Application

#### Development Workflow

**1. Code Changes**

```powershell
# Make your code changes in the respective directories
# - backend/ for API changes
# - frontend/ for UI changes
```

**2. Testing Changes Locally (Before Deployment)**

```powershell
# Test backend locally
cd backend
npm install
npm run dev
# Test at http://localhost:3000

# Test frontend locally
cd frontend
flutter run -d chrome
# Test in browser
```

**3. Build and Deploy Changes**

**Option A: Using Deployment Script (Recommended)**

```powershell
# Rebuild and redeploy everything
.\k8s\deploy.ps1 -Local

# Or with no cache (for clean builds)
.\k8s\deploy.ps1 -Local -NoCache
```

**Option B: Manual Update Process**

```powershell
# Step 1: Build new image
cd backend
docker build -t asi-backend:latest .
cd ..

# Step 2: Load into minikube
minikube image load asi-backend:latest

# Step 3: Update deployment (triggers rolling update)
kubectl rollout restart deployment/backend -n asi-dashboard

# Step 4: Monitor the rollout
kubectl rollout status deployment/backend -n asi-dashboard

# Step 5: Verify changes
kubectl logs -f deployment/backend -n asi-dashboard
```

**4. Rollback if Needed**

```powershell
# Check rollout history
kubectl rollout history deployment/backend -n asi-dashboard

# Rollback to previous version
kubectl rollout undo deployment/backend -n asi-dashboard

# Rollback to specific revision
kubectl rollout undo deployment/backend --to-revision=2 -n asi-dashboard
```

#### Configuration Changes

**Update Environment Variables:**

```powershell
# Edit ConfigMap
kubectl edit configmap backend-config -n asi-dashboard

# Or update from file
kubectl apply -f k8s/backend-configmap.yaml

# Restart pods to pick up changes
kubectl rollout restart deployment/backend -n asi-dashboard
```

**Update Secrets:**

```powershell
# Edit secret (base64 encoded)
kubectl edit secret backend-secret -n asi-dashboard

# Or update from file
kubectl apply -f k8s/backend-secret.yaml

# Restart pods
kubectl rollout restart deployment/backend -n asi-dashboard
```

**Update Database Configuration:**

```powershell
# Edit PostgreSQL config
kubectl edit configmap postgres-config -n asi-dashboard

# Restart PostgreSQL (WARNING: May cause downtime)
kubectl rollout restart deployment/postgres -n asi-dashboard
```

#### Database Schema Changes

```powershell
# 1. Connect to database
kubectl exec -it deployment/postgres -n asi-dashboard -- psql -U postgres -d ASI

# 2. Run migration scripts
# Inside psql:
\i /docker-entrypoint-initdb.d/migration.sql

# Or copy migration file to pod
kubectl cp migrations/001_add_table.sql asi-dashboard/<postgres-pod>:/tmp/migration.sql
kubectl exec deployment/postgres -n asi-dashboard -- psql -U postgres -d ASI -f /tmp/migration.sql
```

#### Frontend Configuration Changes

```powershell
# Update API endpoint in frontend
# Edit frontend code to change API_URL
# Rebuild and redeploy
cd frontend
docker build -t asi-frontend:latest .
cd ..
minikube image load asi-frontend:latest
kubectl rollout restart deployment/frontend -n asi-dashboard
```

#### Resource Changes (CPU/Memory)

```powershell
# Edit deployment
kubectl edit deployment backend -n asi-dashboard

# Or update from file
kubectl apply -f k8s/backend-deployment.yaml

# Changes apply automatically (rolling update)
```

#### Replica Count Changes

```powershell
# Scale up
kubectl scale deployment/backend --replicas=5 -n asi-dashboard

# Scale down
kubectl scale deployment/backend --replicas=2 -n asi-dashboard

# Or edit deployment
kubectl edit deployment backend -n asi-dashboard
# Change: replicas: 5
```

---

## Production Deployment Guide

### Overview

This section covers all the changes and considerations needed when moving from development (Minikube) to production (Cloud Kubernetes).

### Key Differences: Development vs Production

| Aspect | Development (Minikube) | Production |
|--------|----------------------|-----------|
| **Image Registry** | Local Docker daemon | Container registry (Docker Hub, ECR, GCR, ACR) |
| **Image Pull Policy** | `Never` (local images) | `Always` or `IfNotPresent` |
| **Secrets Management** | Plain YAML files | External secrets manager (Vault, AWS Secrets Manager) |
| **SSL/TLS** | HTTP only | HTTPS with certificates |
| **Ingress** | Optional | Required with SSL |
| **Resource Limits** | Minimal | Production-grade |
| **Replicas** | 1-2 | 3+ for high availability |
| **Storage** | Local storage | Cloud storage (EBS, Azure Disk, GCE Persistent Disk) |
| **Monitoring** | Basic | Full observability stack |
| **Backup** | Manual | Automated backups |
| **Network Policies** | None | Strict network policies |
| **RBAC** | Permissive | Role-based access control |

### Step-by-Step Production Migration

#### Step 1: Set Up Container Registry

**Docker Hub:**
```powershell
# Login
docker login

# Build and tag
docker build -t yourusername/asi-backend:v1.0.0 ./backend
docker build -t yourusername/asi-frontend:v1.0.0 ./frontend

# Push
docker push yourusername/asi-backend:v1.0.0
docker push yourusername/asi-frontend:v1.0.0
```

**AWS ECR:**
```powershell
# Get login token
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Create repositories
aws ecr create-repository --repository-name asi-backend
aws ecr create-repository --repository-name asi-frontend

# Build and push
docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/asi-backend:v1.0.0 ./backend
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/asi-backend:v1.0.0
```

**Azure Container Registry:**
```powershell
# Login
az acr login --name <registry-name>

# Build and push
az acr build --registry <registry-name> --image asi-backend:v1.0.0 ./backend
az acr build --registry <registry-name> --image asi-frontend:v1.0.0 ./frontend
```

**Google Container Registry:**
```powershell
# Configure Docker
gcloud auth configure-docker

# Build and push
docker build -t gcr.io/<project-id>/asi-backend:v1.0.0 ./backend
docker push gcr.io/<project-id>/asi-backend:v1.0.0
```

#### Step 2: Update Deployment Manifests

**1. Update Image References**

Edit `backend-deployment.yaml`:
```yaml
spec:
  template:
    spec:
      containers:
      - name: backend
        image: your-registry/asi-backend:v1.0.0  # Changed from asi-backend:latest
        imagePullPolicy: Always  # Changed from Never
```

Edit `frontend-deployment.yaml`:
```yaml
spec:
  template:
    spec:
      containers:
      - name: frontend
        image: your-registry/asi-frontend:v1.0.0  # Changed from asi-frontend:latest
        imagePullPolicy: Always  # Changed from Never
```

**2. Update Replica Counts**

Edit `backend-deployment.yaml`:
```yaml
spec:
  replicas: 3  # Changed from 2 for high availability
```

Edit `frontend-deployment.yaml`:
```yaml
spec:
  replicas: 3  # Changed from 2 for high availability
```

**3. Update Resource Limits**

Edit `backend-deployment.yaml`:
```yaml
resources:
  requests:
    memory: "512Mi"  # Increased from 256Mi
    cpu: "500m"       # Increased from 250m
  limits:
    memory: "1Gi"     # Increased from 512Mi
    cpu: "1000m"      # Increased from 500m
```

**4. Add Resource Quotas**

Create `resource-quota.yaml`:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: asi-dashboard-quota
  namespace: asi-dashboard
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "10"
    services.loadbalancers: "2"
```

#### Step 3: Update Secrets Management

**Option A: Use External Secrets Operator**

Install External Secrets Operator:
```powershell
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/charts/external-secrets/templates/crds/secretstore.yaml
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/charts/external-secrets/templates/crds/externalsecret.yaml
```

Create SecretStore:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: asi-dashboard
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
```

Create ExternalSecret:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: backend-secret
  namespace: asi-dashboard
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: backend-secret
    creationPolicy: Owner
  data:
  - secretKey: JWT_SECRET
    remoteRef:
      key: asi-dashboard/jwt-secret
```

**Option B: Use Kubernetes Secrets with Sealed Secrets**

Install Sealed Secrets:
```powershell
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
```

Create sealed secret:
```powershell
kubectl create secret generic backend-secret \
  --from-literal=JWT_SECRET=your-secret \
  --dry-run=client -o yaml | kubeseal -o yaml > backend-sealed-secret.yaml
```

#### Step 4: Configure Production-Grade Storage

**AWS EKS - EBS Storage:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: asi-dashboard
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3  # AWS EBS gp3
  resources:
    requests:
      storage: 100Gi  # Increased from default
```

**Azure AKS - Azure Disk:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: asi-dashboard
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: managed-premium  # Azure Premium SSD
  resources:
    requests:
      storage: 100Gi
```

**GKE - Persistent Disk:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: asi-dashboard
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard-rwo  # GCE Persistent Disk
  resources:
    requests:
      storage: 100Gi
```

#### Step 5: Set Up Ingress with SSL/TLS

**Install Ingress Controller:**

**NGINX Ingress:**
```powershell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

**Update Ingress Configuration:**

Edit `ingress.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: asi-dashboard-ingress
  namespace: asi-dashboard
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # For Let's Encrypt
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - asi-dashboard.yourdomain.com
    secretName: asi-dashboard-tls
  rules:
  - host: asi-dashboard.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 3000
```

**Set Up SSL Certificate with Cert-Manager:**

Install Cert-Manager:
```powershell
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

Create ClusterIssuer:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

#### Step 6: Update Service Types

**Frontend Service:**

Edit `frontend-service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: asi-dashboard
spec:
  type: ClusterIP  # Changed from LoadBalancer (use Ingress instead)
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    app: frontend
```

**Backend Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: asi-dashboard
spec:
  type: ClusterIP  # Keep as ClusterIP (internal only)
  ports:
  - port: 3000
    targetPort: 3000
    protocol: TCP
  selector:
    app: backend
```

#### Step 7: Add Network Policies

Create `network-policy.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-network-policy
  namespace: asi-dashboard
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: asi-dashboard
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 3000
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  - to: []  # Allow DNS
    ports:
    - protocol: UDP
      port: 53
```

#### Step 8: Set Up Monitoring

**Install Prometheus and Grafana:**

```powershell
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Install Grafana
# (Included in kube-prometheus-stack)
```

**Add ServiceMonitor for Backend:**

Create `backend-servicemonitor.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-metrics
  namespace: asi-dashboard
spec:
  selector:
    matchLabels:
      app: backend
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

#### Step 9: Set Up Logging

**Install ELK Stack or Loki:**

**Loki (Lightweight):**
```powershell
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace logging --create-namespace
```

**Add logging annotations to deployments:**
```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "3000"
    prometheus.io/path: "/metrics"
```

#### Step 10: Configure Database Backups

**Automated Backup Job:**

Create `postgres-backup-cronjob.yaml`:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: asi-dashboard
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15-alpine
            command:
            - /bin/sh
            - -c
            - |
              pg_dump -h postgres -U postgres ASI > /backup/backup-$(date +%Y%m%d-%H%M%S).sql
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

#### Step 11: Update Deployment Script for Production

Create `deploy-production.ps1`:
```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$Registry,
    
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [string]$Namespace = "asi-dashboard"
)

# Build and push images
Write-Host "Building and pushing images..." -ForegroundColor Yellow

# Backend
Set-Location backend
docker build -t "${Registry}/asi-backend:${Version}" .
docker push "${Registry}/asi-backend:${Version}"
docker tag "${Registry}/asi-backend:${Version}" "${Registry}/asi-backend:latest"
docker push "${Registry}/asi-backend:latest"
Set-Location ..

# Frontend
Set-Location frontend
docker build -t "${Registry}/asi-frontend:${Version}" .
docker push "${Registry}/asi-frontend:${Version}"
docker tag "${Registry}/asi-frontend:${Version}" "${Registry}/asi-frontend:latest"
docker push "${Registry}/asi-frontend:latest"
Set-Location ..

# Update image tags in deployments
(Get-Content k8s/backend-deployment.yaml) -replace 'image: .*', "image: ${Registry}/asi-backend:${Version}" | Set-Content k8s/backend-deployment.yaml
(Get-Content k8s/frontend-deployment.yaml) -replace 'image: .*', "image: ${Registry}/asi-frontend:${Version}" | Set-Content k8s/frontend-deployment.yaml

# Deploy
kubectl apply -k k8s/

Write-Host "Deployment complete!" -ForegroundColor Green
```

**Usage:**
```powershell
.\k8s\deploy-production.ps1 -Registry "your-registry" -Version "v1.0.0"
```

#### Step 12: Set Up Horizontal Pod Autoscaling

Create `backend-hpa.yaml`:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
  namespace: asi-dashboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

#### Step 13: Configure Pod Disruption Budget

Create `backend-pdb.yaml`:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
  namespace: asi-dashboard
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: backend
```

### Production Checklist

Before going to production, ensure:

- [ ] **Images pushed to container registry**
- [ ] **Image tags use version numbers (not `latest`)**
- [ ] **ImagePullPolicy set to `Always` or `IfNotPresent`**
- [ ] **Secrets stored in external secrets manager**
- [ ] **SSL/TLS certificates configured**
- [ ] **Ingress controller installed and configured**
- [ ] **Resource limits appropriate for production load**
- [ ] **Replica counts set for high availability (3+)**
- [ ] **Persistent storage configured with appropriate size**
- [ ] **Backup strategy implemented**
- [ ] **Monitoring and alerting set up**
- [ ] **Logging aggregation configured**
- [ ] **Network policies implemented**
- [ ] **RBAC configured with least privilege**
- [ ] **Health checks configured**
- [ ] **Readiness and liveness probes tuned**
- [ ] **Horizontal Pod Autoscaling configured**
- [ ] **Pod Disruption Budgets set**
- [ ] **Resource quotas defined**
- [ ] **CI/CD pipeline configured**
- [ ] **Disaster recovery plan documented**
- [ ] **Security scanning enabled**
- [ ] **Compliance requirements met**

### Production Deployment Command

```powershell
# Deploy to production
.\k8s\deploy-production.ps1 -Registry "your-registry" -Version "v1.0.0"

# Or using Kustomize with overlays
kubectl apply -k k8s/overlays/production/
```

### Post-Deployment Verification

```powershell
# Check all pods are running
kubectl get pods -n asi-dashboard

# Check services
kubectl get services -n asi-dashboard

# Check ingress
kubectl get ingress -n asi-dashboard

# Test endpoints
curl https://asi-dashboard.yourdomain.com/health
curl https://asi-dashboard.yourdomain.com/api/health

# Check metrics
kubectl top pods -n asi-dashboard

# Verify SSL certificate
openssl s_client -connect asi-dashboard.yourdomain.com:443 -servername asi-dashboard.yourdomain.com
```

---

## Summary

### What We Achieved

✅ **Established Kubernetes Cluster**
- Set up Minikube on local machine
- Configured kubectl to connect to cluster
- Enabled necessary addons

✅ **Containerized Application**
- Built Docker images for frontend, backend, and database
- Optimized images using multi-stage builds
- Configured proper image pull policies

✅ **Deployed to Kubernetes**
- Created namespace for isolation
- Deployed PostgreSQL with persistent storage
- Deployed backend API with 2 replicas
- Deployed frontend with 2 replicas
- Configured services for networking
- Set up ingress for external access

✅ **Resolved Critical Issues**
- Fixed Kubernetes connection problems
- Resolved image loading issues for minikube
- Fixed deployment timeouts
- Established proper networking between services

✅ **Application Access**
- Multiple access methods (port-forward, minikube service, ingress)
- Health checks and monitoring
- Logging and debugging capabilities

### Key Learnings

1. **Minikube uses separate Docker daemon** - Images must be explicitly loaded
2. **Health checks are critical** - Ensure applications have proper health endpoints
3. **Service discovery** - Use service names for internal communication
4. **Configuration management** - Use ConfigMaps and Secrets appropriately
5. **Persistent storage** - PVCs are needed for database data persistence

### Production Migration Summary

**Quick Reference: Changes Required for Production**

| Component | Development | Production | Action Required |
|----------|------------|------------|----------------|
| **Image Registry** | Local Docker | Container Registry | Push images to registry |
| **Image Tag** | `latest` | Version tags (`v1.0.0`) | Use semantic versioning |
| **Image Pull Policy** | `Never` | `Always` | Update deployment YAMLs |
| **Replicas** | 1-2 | 3+ | Update replica counts |
| **Resource Limits** | Minimal | Production-grade | Increase CPU/memory |
| **Secrets** | Plain YAML | External Secrets | Migrate to secrets manager |
| **SSL/TLS** | HTTP | HTTPS | Install cert-manager, configure TLS |
| **Ingress** | Optional | Required | Install ingress controller |
| **Storage** | Local | Cloud storage | Update storage class |
| **Monitoring** | None | Full stack | Install Prometheus/Grafana |
| **Logging** | kubectl logs | Aggregated | Set up ELK/Loki |
| **Backups** | Manual | Automated | Create CronJob |
| **Network** | Open | Secured | Add network policies |
| **Access Control** | Permissive | RBAC | Configure roles |
| **Autoscaling** | None | HPA | Create HPA resources |
| **Service Type** | LoadBalancer | ClusterIP + Ingress | Update service types |

**Migration Steps:**
1. Set up container registry → Push images
2. Update deployment manifests → Change image references
3. Configure secrets management → External secrets
4. Set up ingress with SSL → Install cert-manager
5. Update resource limits → Production values
6. Increase replicas → High availability
7. Set up monitoring → Prometheus/Grafana
8. Configure backups → Automated CronJob
9. Add network policies → Security
10. Test and verify → Production readiness

### Next Steps

- [ ] Set up CI/CD pipeline for automated deployments
- [ ] Configure monitoring (Prometheus, Grafana)
- [ ] Set up logging aggregation (ELK stack)
- [ ] Implement backup strategy for database
- [ ] Configure SSL/TLS certificates
- [ ] Set up horizontal pod autoscaling
- [ ] Configure resource quotas and limits
- [ ] Implement network policies for security

---

## Quick Reference Commands

```powershell
# Deployment
.\k8s\deploy.ps1 -Local

# Status
kubectl get all -n asi-dashboard

# Logs
kubectl logs -f deployment/backend -n asi-dashboard
kubectl logs -f deployment/frontend -n asi-dashboard

# Access
kubectl port-forward service/frontend 8080:80 -n asi-dashboard
kubectl port-forward service/backend 3000:3000 -n asi-dashboard

# Restart
kubectl rollout restart deployment/backend -n asi-dashboard

# Scale
kubectl scale deployment/backend --replicas=3 -n asi-dashboard

# Delete
kubectl delete namespace asi-dashboard
```

---

**Document Version:** 1.0  
**Last Updated:** December 2024  
**Maintained By:** ASI Dashboard Team

