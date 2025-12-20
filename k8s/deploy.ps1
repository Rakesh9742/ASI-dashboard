# ASI Dashboard Kubernetes Deployment Script (PowerShell)
# This script helps build Docker images and deploy to Kubernetes

param(
    [string]$Registry = "",
    [switch]$Local,
    [string]$Namespace = "asi-dashboard"
)

$ErrorActionPreference = "Stop"

Write-Host "=== ASI Dashboard Kubernetes Deployment ===" -ForegroundColor Green
Write-Host ""

# Build Docker images
Write-Host "Building Docker images..." -ForegroundColor Yellow

# Build backend
Write-Host "Building backend image..." -ForegroundColor Yellow
Set-Location backend
if ($Registry) {
    docker build -t "${Registry}/asi-backend:latest" .
    docker push "${Registry}/asi-backend:latest"
    $BackendImage = "${Registry}/asi-backend:latest"
} else {
    docker build -t "asi-backend:latest" .
    $BackendImage = "asi-backend:latest"
}
Set-Location ..

# Build frontend
Write-Host "Building frontend image..." -ForegroundColor Yellow
Set-Location frontend
if ($Registry) {
    docker build -t "${Registry}/asi-frontend:latest" .
    docker push "${Registry}/asi-frontend:latest"
    $FrontendImage = "${Registry}/asi-frontend:latest"
} else {
    docker build -t "asi-frontend:latest" .
    $FrontendImage = "asi-frontend:latest"
}
Set-Location ..

# Update imagePullPolicy if using local images
if ($Local) {
    Write-Host "Updating deployments for local images..." -ForegroundColor Yellow
    (Get-Content k8s/backend-deployment.yaml) -replace 'imagePullPolicy: IfNotPresent', 'imagePullPolicy: Never' | Set-Content k8s/backend-deployment.yaml
    (Get-Content k8s/frontend-deployment.yaml) -replace 'imagePullPolicy: IfNotPresent', 'imagePullPolicy: Never' | Set-Content k8s/frontend-deployment.yaml
}

# Update image names in deployments
if ($Registry) {
    (Get-Content k8s/backend-deployment.yaml) -replace 'image: asi-backend:latest', "image: $BackendImage" | Set-Content k8s/backend-deployment.yaml
    (Get-Content k8s/frontend-deployment.yaml) -replace 'image: asi-frontend:latest', "image: $FrontendImage" | Set-Content k8s/frontend-deployment.yaml
}

# Deploy to Kubernetes
Write-Host "Deploying to Kubernetes..." -ForegroundColor Yellow
kubectl apply -k k8s/

# Wait for deployments
Write-Host "Waiting for deployments to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=available --timeout=300s deployment/backend -n $Namespace 2>$null
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n $Namespace 2>$null
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n $Namespace 2>$null

# Show status
Write-Host ""
Write-Host "=== Deployment Status ===" -ForegroundColor Green
kubectl get pods -n $Namespace
kubectl get services -n $Namespace

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host "To access the application:"
Write-Host "  Frontend: kubectl port-forward service/frontend 8080:80 -n $Namespace"
Write-Host "  Backend:  kubectl port-forward service/backend 3000:3000 -n $Namespace"

