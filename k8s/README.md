# Kubernetes Deployment Guide for ASI Dashboard

This directory contains Kubernetes manifests for deploying the ASI Dashboard application.

## Prerequisites

1. **Kubernetes cluster** (minikube, kind, or cloud provider)
2. **kubectl** configured to access your cluster
3. **Docker images** built and available (either in a registry or locally)

## Project Structure

```
k8s/
├── namespace.yaml                    # Namespace definition
├── postgres-pvc.yaml                 # Persistent volume for PostgreSQL
├── postgres-configmap.yaml           # PostgreSQL configuration
├── postgres-secret.yaml              # PostgreSQL secrets (password)
├── postgres-init-configmap.yaml      # Database initialization scripts
├── postgres-deployment.yaml          # PostgreSQL deployment
├── postgres-service.yaml             # PostgreSQL service
├── backend-configmap.yaml            # Backend configuration
├── backend-secret.yaml               # Backend secrets (JWT)
├── backend-deployment.yaml           # Backend deployment
├── backend-service.yaml              # Backend service
├── frontend-deployment.yaml          # Frontend deployment
├── frontend-service.yaml             # Frontend service
├── ingress.yaml                      # Ingress for external access
├── kustomization.yaml                # Kustomize configuration
└── README.md                         # This file
```

## Building Docker Images

Before deploying to Kubernetes, you need to build and push your Docker images:

### Option 1: Build and push to a registry

```bash
# Build backend image
cd backend
docker build -t your-registry/asi-backend:latest .
docker push your-registry/asi-backend:latest

# Build frontend image
cd ../frontend
docker build -t your-registry/asi-frontend:latest .
docker push your-registry/asi-frontend:latest
```

### Option 2: Use local images (for minikube/kind)

```bash
# For minikube
eval $(minikube docker-env)
cd backend
docker build -t asi-backend:latest .
cd ../frontend
docker build -t asi-frontend:latest .

# Update imagePullPolicy in deployments to "Never"
```

## Deployment Steps

### 1. Update Configuration

Before deploying, update the following files with your values:

- **postgres-secret.yaml**: Change `POSTGRES_PASSWORD` (default: "root")
- **backend-secret.yaml**: Change `JWT_SECRET` (default: "your-secret-key-change-in-production")
- **backend-deployment.yaml**: Update image name if using a registry
- **frontend-deployment.yaml**: Update image name if using a registry
- **ingress.yaml**: Update hostname to your domain

### 2. Deploy to Kubernetes

#### Option A: Deploy all resources individually

```bash
# Create namespace
kubectl apply -f namespace.yaml

# Deploy PostgreSQL
kubectl apply -f postgres-pvc.yaml
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-secret.yaml
kubectl apply -f postgres-init-configmap.yaml
kubectl apply -f postgres-deployment.yaml
kubectl apply -f postgres-service.yaml

# Deploy Backend
kubectl apply -f backend-configmap.yaml
kubectl apply -f backend-secret.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml

# Deploy Frontend
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml

# Deploy Ingress (optional)
kubectl apply -f ingress.yaml
```

#### Option B: Deploy using Kustomize

```bash
kubectl apply -k .
```

### 3. Verify Deployment

```bash
# Check all pods
kubectl get pods -n asi-dashboard

# Check services
kubectl get services -n asi-dashboard

# Check deployments
kubectl get deployments -n asi-dashboard

# View logs
kubectl logs -f deployment/postgres -n asi-dashboard
kubectl logs -f deployment/backend -n asi-dashboard
kubectl logs -f deployment/frontend -n asi-dashboard
```

### 4. Access the Application

#### Using Port Forwarding (for testing)

```bash
# Forward frontend
kubectl port-forward service/frontend 8080:80 -n asi-dashboard

# Forward backend
kubectl port-forward service/backend 3000:3000 -n asi-dashboard

# Access at http://localhost:8080
```

#### Using Ingress

If you've deployed the Ingress and have an ingress controller:

1. Update `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts` on Windows):
   ```
   <ingress-ip> asi-dashboard.local
   ```

2. Access at `http://asi-dashboard.local`

#### Using LoadBalancer Service

If your cluster supports LoadBalancer services, the frontend service will get an external IP:

```bash
kubectl get service frontend -n asi-dashboard
# Access using the EXTERNAL-IP
```

## Scaling

To scale the application:

```bash
# Scale backend
kubectl scale deployment backend --replicas=3 -n asi-dashboard

# Scale frontend
kubectl scale deployment frontend --replicas=3 -n asi-dashboard
```

## Updating the Application

### Update Backend

```bash
# Build new image
cd backend
docker build -t your-registry/asi-backend:v1.1.0 .

# Push to registry
docker push your-registry/asi-backend:v1.1.0

# Update deployment
kubectl set image deployment/backend backend=your-registry/asi-backend:v1.1.0 -n asi-dashboard
```

### Update Frontend

```bash
# Build new image
cd frontend
docker build -t your-registry/asi-frontend:v1.1.0 .

# Push to registry
docker push your-registry/asi-frontend:v1.1.0

# Update deployment
kubectl set image deployment/frontend frontend=your-registry/asi-frontend:v1.1.0 -n asi-dashboard
```

## Troubleshooting

### Check Pod Status

```bash
kubectl describe pod <pod-name> -n asi-dashboard
```

### Check Logs

```bash
kubectl logs <pod-name> -n asi-dashboard
kubectl logs <pod-name> -n asi-dashboard --previous  # Previous container instance
```

### Database Connection Issues

```bash
# Check PostgreSQL pod
kubectl exec -it deployment/postgres -n asi-dashboard -- psql -U postgres -d ASI

# Test connection from backend pod
kubectl exec -it deployment/backend -n asi-dashboard -- sh
# Inside pod: ping postgres
```

### Delete and Redeploy

```bash
# Delete all resources
kubectl delete -k .

# Or delete namespace (removes everything)
kubectl delete namespace asi-dashboard
```

## Production Considerations

1. **Secrets Management**: Use a proper secrets management system (e.g., Sealed Secrets, External Secrets Operator, or cloud provider secrets)

2. **Resource Limits**: Adjust CPU and memory limits based on your workload

3. **Storage**: Use appropriate storage class for PostgreSQL PVC based on your cluster

4. **Backup**: Set up regular backups for PostgreSQL data

5. **Monitoring**: Add monitoring and logging (Prometheus, Grafana, ELK stack)

6. **SSL/TLS**: Configure SSL certificates for Ingress

7. **High Availability**: Consider using StatefulSet for PostgreSQL in production

8. **Image Registry**: Use a private registry for production images

## Environment Variables

The following environment variables are configurable:

### Backend
- `PORT`: Server port (default: 3000)
- `NODE_ENV`: Environment (production/development)
- `DATABASE_URL`: PostgreSQL connection string
- `JWT_SECRET`: Secret for JWT tokens
- `JWT_EXPIRES_IN`: JWT expiration time

### Frontend
- `API_URL`: Backend API URL

### PostgreSQL
- `POSTGRES_USER`: Database user
- `POSTGRES_PASSWORD`: Database password
- `POSTGRES_DB`: Database name

## Support

For issues or questions, refer to the main project README or create an issue in the repository.

