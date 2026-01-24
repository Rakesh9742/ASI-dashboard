# Quick Start Guide - ASI Dashboard Kubernetes Deployment

## 🚀 Fast Deployment (5 Minutes)

### Prerequisites Check
```powershell
docker --version
minikube version
kubectl version --client
```

### Step 1: Start Minikube
```powershell
minikube start
minikube status
```

### Step 2: Deploy Application
```powershell
.\k8s\deploy.ps1 -Local
```

### Step 3: Access Application
```powershell
# Frontend (Terminal 1)
kubectl port-forward service/frontend 8080:80 -n asi-dashboard
# Open: http://localhost:8080

# Backend (Terminal 2)
kubectl port-forward service/backend 3000:3000 -n asi-dashboard
# Open: http://localhost:3000
```

## ✅ Verify Everything Works

```powershell
# Check pods
kubectl get pods -n asi-dashboard

# Check services
kubectl get services -n asi-dashboard

# Check logs
kubectl logs deployment/backend -n asi-dashboard
```

## 🔧 Common Issues

### Issue: Can't connect to Kubernetes
```powershell
minikube update-context
minikube start
```

### Issue: Images not found
```powershell
minikube image load asi-backend:latest
minikube image load asi-frontend:latest
```

### Issue: Pods not starting
```powershell
kubectl describe pod <pod-name> -n asi-dashboard
kubectl logs <pod-name> -n asi-dashboard
```

## 📚 Full Documentation

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for complete documentation.




























