# How to Access Your ASI Dashboard Application

## Method 1: Using Minikube Service (Easiest for Frontend)

```powershell
# Access frontend (opens in browser automatically)
minikube service frontend -n asi-dashboard

# Or get the URL without opening browser
minikube service frontend -n asi-dashboard --url
```

## Method 2: Using Port Forwarding (Recommended for Development)

### Access Frontend:
```powershell
# In one terminal - Forward frontend to localhost:8080
kubectl port-forward service/frontend 8080:80 -n asi-dashboard

# Then open browser to: http://localhost:8080
```

### Access Backend:
```powershell
# In another terminal - Forward backend to localhost:3000
kubectl port-forward service/backend 3000:3000 -n asi-dashboard

# API will be available at: http://localhost:3000
```

### Access Both at Once:
```powershell
# Forward both services in one command
kubectl port-forward service/frontend 8080:80 -n asi-dashboard &
kubectl port-forward service/backend 3000:3000 -n asi-dashboard
```

## Method 3: Using Minikube Tunnel (For LoadBalancer Services)

```powershell
# Start tunnel in a separate terminal (keeps running)
minikube tunnel

# Then access frontend at the EXTERNAL-IP shown by:
kubectl get services -n asi-dashboard
```

## Method 4: Using Ingress (Requires Ingress Controller)

If you have an ingress controller installed:

1. Enable ingress addon in minikube:
```powershell
minikube addons enable ingress
```

2. Add to your hosts file (`C:\Windows\System32\drivers\etc\hosts`):
```
127.0.0.1 asi-dashboard.local
```

3. Get the ingress IP:
```powershell
kubectl get ingress -n asi-dashboard
```

4. Access at: `http://asi-dashboard.local`

## Quick Status Check

```powershell
# Check if pods are running
kubectl get pods -n asi-dashboard

# Check services
kubectl get services -n asi-dashboard

# Check ingress
kubectl get ingress -n asi-dashboard
```

## Troubleshooting

If you can't access the application:

1. **Check pod status:**
   ```powershell
   kubectl get pods -n asi-dashboard
   kubectl describe pod <pod-name> -n asi-dashboard
   ```

2. **Check service endpoints:**
   ```powershell
   kubectl get endpoints -n asi-dashboard
   ```

3. **Check logs:**
   ```powershell
   kubectl logs -f deployment/frontend -n asi-dashboard
   kubectl logs -f deployment/backend -n asi-dashboard
   ```

4. **Test from inside cluster:**
   ```powershell
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://frontend.asi-dashboard.svc.cluster.local
   ```

