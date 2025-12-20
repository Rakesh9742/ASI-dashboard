# ASI Dashboard Kubernetes Deployment Script (PowerShell)
# This script helps build Docker images and deploy to Kubernetes

param(
    [string]$Registry = "",
    [switch]$Local,
    [switch]$NoCache,
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
try {
    $buildArgs = if ($NoCache) { "--no-cache" } else { "" }
    if ($Registry) {
        docker build $buildArgs -t "${Registry}/asi-backend:latest" .
        if ($LASTEXITCODE -ne 0) { throw "Backend build failed" }
        docker push "${Registry}/asi-backend:latest"
        if ($LASTEXITCODE -ne 0) { throw "Backend push failed" }
        $BackendImage = "${Registry}/asi-backend:latest"
    } else {
        docker build $buildArgs -t "asi-backend:latest" .
        if ($LASTEXITCODE -ne 0) { throw "Backend build failed" }
        $BackendImage = "asi-backend:latest"
    }
} catch {
    Write-Host "ERROR: Backend build failed: $_" -ForegroundColor Red
    Set-Location ..
    exit 1
}
Set-Location ..

# Build frontend
Write-Host "Building frontend image..." -ForegroundColor Yellow
Set-Location frontend
try {
    $buildArgs = if ($NoCache) { "--no-cache" } else { "" }
    if ($Registry) {
        docker build $buildArgs -t "${Registry}/asi-frontend:latest" .
        if ($LASTEXITCODE -ne 0) { throw "Frontend build failed" }
        docker push "${Registry}/asi-frontend:latest"
        if ($LASTEXITCODE -ne 0) { throw "Frontend push failed" }
        $FrontendImage = "${Registry}/asi-frontend:latest"
    } else {
        docker build $buildArgs -t "asi-frontend:latest" .
        if ($LASTEXITCODE -ne 0) { throw "Frontend build failed" }
        $FrontendImage = "asi-frontend:latest"
    }
} catch {
    Write-Host "ERROR: Frontend build failed: $_" -ForegroundColor Red
    Set-Location ..
    exit 1
}
Set-Location ..

# Update imagePullPolicy if using local images
if ($Local) {
    Write-Host "Updating deployments for local images..." -ForegroundColor Yellow
    (Get-Content k8s/backend-deployment.yaml) -replace 'imagePullPolicy: IfNotPresent', 'imagePullPolicy: Never' | Set-Content k8s/backend-deployment.yaml
    (Get-Content k8s/frontend-deployment.yaml) -replace 'imagePullPolicy: IfNotPresent', 'imagePullPolicy: Never' | Set-Content k8s/frontend-deployment.yaml
    
    # Load images into minikube if using minikube
    $currentContext = kubectl config current-context 2>&1
    if ($currentContext -like "*minikube*") {
        Write-Host "Loading images into minikube..." -ForegroundColor Yellow
        Write-Host "  Loading backend image..." -ForegroundColor Cyan
        minikube image load "asi-backend:latest" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARNING: Failed to load backend image into minikube" -ForegroundColor Yellow
        } else {
            Write-Host "  ✓ Backend image loaded" -ForegroundColor Green
        }
        
        Write-Host "  Loading frontend image..." -ForegroundColor Cyan
        minikube image load "asi-frontend:latest" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARNING: Failed to load frontend image into minikube" -ForegroundColor Yellow
        } else {
            Write-Host "  ✓ Frontend image loaded" -ForegroundColor Green
        }
    }
}

# Update image names in deployments
if ($Registry) {
    (Get-Content k8s/backend-deployment.yaml) -replace 'image: asi-backend:latest', "image: $BackendImage" | Set-Content k8s/backend-deployment.yaml
    (Get-Content k8s/frontend-deployment.yaml) -replace 'image: asi-frontend:latest', "image: $FrontendImage" | Set-Content k8s/frontend-deployment.yaml
}

# Check if Kubernetes is available
Write-Host "Checking Kubernetes connection..." -ForegroundColor Yellow
try {
    $null = kubectl cluster-info --request-timeout=5s 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes cluster is not accessible"
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Kubernetes cluster is not accessible!" -ForegroundColor Red
    Write-Host ""
    
    # Diagnostic information
    Write-Host "=== Diagnostic Information ===" -ForegroundColor Yellow
    $currentContext = kubectl config current-context 2>&1
    Write-Host "Current kubectl context: $currentContext" -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "Available contexts:" -ForegroundColor Cyan
    kubectl config get-contexts 2>&1 | Out-Host
    
    Write-Host ""
    Write-Host "=== Troubleshooting Steps ===" -ForegroundColor Yellow
    
    # Check if minikube is being used
    if ($currentContext -like "*minikube*") {
        Write-Host "1. Minikube detected. Checking status..." -ForegroundColor Cyan
        $minikubeStatus = minikube status 2>&1
        Write-Host $minikubeStatus
        
        if ($minikubeStatus -like "*Stopped*" -or $minikubeStatus -like "*Misconfigured*") {
            Write-Host ""
            Write-Host "   Fix: Run the following commands:" -ForegroundColor Yellow
            Write-Host "     minikube update-context" -ForegroundColor White
            Write-Host "     minikube start" -ForegroundColor White
        }
    }
    
    # Check if docker-desktop is available
    $dockerContext = kubectl config get-contexts 2>&1 | Select-String "docker-desktop"
    if ($dockerContext) {
        Write-Host ""
        Write-Host "2. Docker Desktop Kubernetes detected." -ForegroundColor Cyan
        Write-Host "   To use Docker Desktop Kubernetes:" -ForegroundColor Yellow
        Write-Host "     kubectl config use-context docker-desktop" -ForegroundColor White
        Write-Host "   Make sure Kubernetes is enabled in Docker Desktop settings." -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "3. General checks:" -ForegroundColor Cyan
    Write-Host "   - Ensure your Kubernetes cluster is running" -ForegroundColor White
    Write-Host "   - Verify kubectl is properly configured" -ForegroundColor White
    Write-Host "   - Check if Docker Desktop is running (if using docker-desktop context)" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Skipping deployment. Please fix the Kubernetes connection and try again." -ForegroundColor Red
    exit 1
}

# Deploy to Kubernetes
Write-Host "Deploying to Kubernetes..." -ForegroundColor Yellow
try {
    kubectl apply -k k8s/ --validate=false
    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes deployment failed"
    }
} catch {
    Write-Host "ERROR: Kubernetes deployment failed: $_" -ForegroundColor Red
    exit 1
}

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

