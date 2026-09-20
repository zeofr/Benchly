# =============================================================================
# Benchly — Kubernetes Setup Script (PowerShell for Windows)
# =============================================================================
# Windows equivalent of k8s-setup.sh
# Prerequisites: Minikube, kubectl, Docker Desktop (or Docker CE)
#
# Usage:
#   Set-ExecutionPolicy -Scope Process Bypass
#   .\scripts\k8s-setup.ps1
# =============================================================================

$ErrorActionPreference = "Stop"
$NAMESPACE = "benchmark"
$REPO_ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Benchly — Kubernetes Setup (Windows)"      -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Start Minikube
Write-Host "[1/8] Starting Minikube..." -ForegroundColor Yellow
$status = minikube status 2>&1
if ($status -notmatch "Running") {
    minikube start --cpus=4 --memory=6144 --driver=docker
} else {
    Write-Host "      Minikube already running."
}

# Step 2: Enable addons
Write-Host ""
Write-Host "[2/8] Enabling Minikube addons..." -ForegroundColor Yellow
minikube addons enable metrics-server
minikube addons enable ingress
Write-Host "      metrics-server and ingress enabled."

# Step 3: Configure Docker to use Minikube's daemon
Write-Host ""
Write-Host "[3/8] Configuring Docker environment for Minikube..." -ForegroundColor Yellow
Write-Host "      Run this in your terminal before building:"
Write-Host "      & minikube -p minikube docker-env | Invoke-Expression" -ForegroundColor Green
Write-Host ""
& minikube -p minikube docker-env | Invoke-Expression

# Step 4: Build images
Write-Host ""
Write-Host "[4/8] Building Docker images inside Minikube..." -ForegroundColor Yellow
Write-Host "      Building backend..."
docker build `
    -t benchly-backend:latest `
    -f "$REPO_ROOT\backend\Dockerfile" `
    --build-arg INSTALL_K6=true `
    "$REPO_ROOT"

Write-Host "      Building frontend..."
docker build `
    -t benchly-frontend:latest `
    -f "$REPO_ROOT\frontend\Dockerfile" `
    "$REPO_ROOT\frontend"

Write-Host "      Building analytics (FastAPI)..."
docker build `
    -t benchly-analytics:latest `
    "$REPO_ROOT\analytics"

Write-Host "      Images built:"
docker images | Select-String "benchly"

# Step 5: Create namespace
Write-Host ""
Write-Host "[5/8] Creating namespace..." -ForegroundColor Yellow
kubectl apply -f "$REPO_ROOT\k8s\namespace.yaml"

# Step 6: Secrets and config
Write-Host ""
Write-Host "[6/8] Applying secrets and ConfigMap..." -ForegroundColor Yellow
kubectl apply -f "$REPO_ROOT\k8s\secrets.yaml"
kubectl apply -f "$REPO_ROOT\k8s\configmap.yaml"

# Step 7: Deploy
Write-Host ""
Write-Host "[7/8] Deploying services..." -ForegroundColor Yellow

kubectl apply -f "$REPO_ROOT\k8s\postgres-deployment.yaml"
kubectl apply -f "$REPO_ROOT\k8s\redis-deployment.yaml"
kubectl apply -f "$REPO_ROOT\k8s\jaeger.yaml"

Write-Host "      Waiting for PostgreSQL..."
kubectl wait --for=condition=ready pod -l app=postgres -n $NAMESPACE --timeout=90s

Write-Host "      Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app=redis -n $NAMESPACE --timeout=60s

kubectl apply -f "$REPO_ROOT\k8s\backend-deployment.yaml"
kubectl apply -f "$REPO_ROOT\k8s\worker-deployment.yaml"
kubectl apply -f "$REPO_ROOT\k8s\analytics-deployment.yaml"
kubectl apply -f "$REPO_ROOT\k8s\frontend-deployment.yaml"
kubectl apply -f "$REPO_ROOT\k8s\hpa.yaml"
kubectl apply -f "$REPO_ROOT\k8s\prometheus.yaml"
kubectl apply -f "$REPO_ROOT\k8s\grafana.yaml"

# Step 8: Verify
Write-Host ""
Write-Host "[8/8] Waiting for deployments to be ready..." -ForegroundColor Yellow

kubectl wait --for=condition=available deployment/backend    -n $NAMESPACE --timeout=180s
kubectl wait --for=condition=available deployment/frontend   -n $NAMESPACE --timeout=120s
kubectl wait --for=condition=available deployment/prometheus -n $NAMESPACE --timeout=120s
kubectl wait --for=condition=available deployment/grafana    -n $NAMESPACE --timeout=120s

$MINIKUBE_IP = minikube ip

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
kubectl get pods     -n $NAMESPACE
Write-Host ""
kubectl get services -n $NAMESPACE
Write-Host ""
kubectl get hpa      -n $NAMESPACE
Write-Host ""
Write-Host "Access URLs:" -ForegroundColor Cyan
Write-Host "  Frontend:   http://$MINIKUBE_IP`:30080"
Write-Host "  Prometheus: http://$MINIKUBE_IP`:30090"
Write-Host "  Grafana:    http://$MINIKUBE_IP`:30300  (admin / admin)"
Write-Host ""
