#!/bin/bash

# ASI Dashboard Kubernetes Deployment Script
# This script helps build Docker images and deploy to Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="asi-dashboard"
REGISTRY=""  # Set your registry here, e.g., "docker.io/username" or "gcr.io/project-id"
USE_LOCAL_IMAGES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --registry)
      REGISTRY="$2"
      shift 2
      ;;
    --local)
      USE_LOCAL_IMAGES=true
      shift
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--registry REGISTRY] [--local] [--namespace NAMESPACE]"
      exit 1
      ;;
  esac
done

echo -e "${GREEN}=== ASI Dashboard Kubernetes Deployment ===${NC}\n"

# Build Docker images
echo -e "${YELLOW}Building Docker images...${NC}"

# Build backend
echo -e "${YELLOW}Building backend image...${NC}"
cd backend
if [ -n "$REGISTRY" ]; then
  docker build -t ${REGISTRY}/asi-backend:latest .
  docker push ${REGISTRY}/asi-backend:latest
  BACKEND_IMAGE="${REGISTRY}/asi-backend:latest"
else
  docker build -t asi-backend:latest .
  BACKEND_IMAGE="asi-backend:latest"
fi
cd ..

# Build frontend
echo -e "${YELLOW}Building frontend image...${NC}"
cd frontend
if [ -n "$REGISTRY" ]; then
  docker build -t ${REGISTRY}/asi-frontend:latest .
  docker push ${REGISTRY}/asi-frontend:latest
  FRONTEND_IMAGE="${REGISTRY}/asi-frontend:latest"
else
  docker build -t asi-frontend:latest .
  FRONTEND_IMAGE="asi-frontend:latest"
fi
cd ..

# Update imagePullPolicy if using local images
if [ "$USE_LOCAL_IMAGES" = true ]; then
  echo -e "${YELLOW}Updating deployments for local images...${NC}"
  sed -i.bak 's/imagePullPolicy: IfNotPresent/imagePullPolicy: Never/g' k8s/backend-deployment.yaml
  sed -i.bak 's/imagePullPolicy: IfNotPresent/imagePullPolicy: Never/g' k8s/frontend-deployment.yaml
fi

# Update image names in deployments
if [ -n "$REGISTRY" ]; then
  sed -i.bak "s|image: asi-backend:latest|image: ${BACKEND_IMAGE}|g" k8s/backend-deployment.yaml
  sed -i.bak "s|image: asi-frontend:latest|image: ${FRONTEND_IMAGE}|g" k8s/frontend-deployment.yaml
fi

# Deploy to Kubernetes
echo -e "${YELLOW}Deploying to Kubernetes...${NC}"
kubectl apply -k k8s/

# Wait for deployments
echo -e "${YELLOW}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/backend -n $NAMESPACE || true
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n $NAMESPACE || true
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n $NAMESPACE || true

# Show status
echo -e "\n${GREEN}=== Deployment Status ===${NC}"
kubectl get pods -n $NAMESPACE
kubectl get services -n $NAMESPACE

echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
echo -e "To access the application:"
echo -e "  Frontend: kubectl port-forward service/frontend 8080:80 -n $NAMESPACE"
echo -e "  Backend:  kubectl port-forward service/backend 3000:3000 -n $NAMESPACE"

# Cleanup backup files
rm -f k8s/*.bak

