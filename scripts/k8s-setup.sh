#!/usr/bin/env bash
# =============================================================================
# Benchly — Kubernetes Setup Script
# =============================================================================
# Builds images inside Minikube's Docker daemon and applies all manifests.
# Run this once to get the full stack running locally.
#
# Prerequisites:
#   - Minikube installed  (https://minikube.sigs.k8s.io/docs/start/)
#   - kubectl installed
#   - k6 installed        (https://k6.io/docs/get-started/installation/)
#
# Usage:
#   chmod +x scripts/k8s-setup.sh
#   ./scripts/k8s-setup.sh
# =============================================================================

set -euo pipefail

NAMESPACE="benchmark"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ""
echo "============================================="
echo "  Benchly — Kubernetes Setup"
echo "============================================="
echo ""

# ── Step 1: Start Minikube ────────────────────────────────────────────────────
echo "[1/8] Starting Minikube..."
if ! minikube status | grep -q "Running"; then
  # 4 CPU and 6GB RAM gives the HPA room to work
  minikube start --cpus=4 --memory=6144 --driver=docker
else
  echo "      Minikube already running."
fi

# ── Step 2: Enable required addons ───────────────────────────────────────────
echo ""
echo "[2/8] Enabling Minikube addons..."
minikube addons enable metrics-server
minikube addons enable ingress
echo "      metrics-server: enabled"
echo "      ingress: enabled"

# ── Step 3: Point Docker CLI at Minikube's daemon ────────────────────────────
echo ""
echo "[3/8] Configuring Docker to build inside Minikube..."
echo "      Images built here are immediately available to Kubernetes."
eval $(minikube docker-env)

# ── Step 4: Build images ──────────────────────────────────────────────────────
echo ""
echo "[4/8] Building Docker images inside Minikube..."
echo "      Building backend (includes k6, Python analytics)..."
docker build \
  -t benchly-backend:latest \
  -f "$REPO_ROOT/backend/Dockerfile" \
  --build-arg INSTALL_K6=true \
  "$REPO_ROOT"

echo "      Building frontend..."
docker build \
  -t benchly-frontend:latest \
  -f "$REPO_ROOT/frontend/Dockerfile" \
  "$REPO_ROOT/frontend"

echo "      Images built:"
docker images | grep benchly

# ── Step 5: Create namespace ──────────────────────────────────────────────────
echo ""
echo "[5/8] Creating namespace..."
kubectl apply -f "$REPO_ROOT/k8s/namespace.yaml"

# ── Step 6: Apply secrets and config ─────────────────────────────────────────
echo ""
echo "[6/8] Applying secrets and ConfigMap..."
kubectl apply -f "$REPO_ROOT/k8s/secrets.yaml"
kubectl apply -f "$REPO_ROOT/k8s/configmap.yaml"

# ── Step 7: Deploy infrastructure (order matters — DB before API) ─────────────
echo ""
echo "[7/8] Deploying services..."

echo "      PostgreSQL..."
kubectl apply -f "$REPO_ROOT/k8s/postgres-deployment.yaml"

echo "      Redis..."
kubectl apply -f "$REPO_ROOT/k8s/redis-deployment.yaml"

echo "      Jaeger..."
kubectl apply -f "$REPO_ROOT/k8s/jaeger.yaml"

echo "      Waiting for PostgreSQL to be ready (up to 90s)..."
kubectl wait --for=condition=ready pod \
  -l app=postgres \
  -n "$NAMESPACE" \
  --timeout=90s

echo "      Waiting for Redis to be ready (up to 60s)..."
kubectl wait --for=condition=ready pod \
  -l app=redis \
  -n "$NAMESPACE" \
  --timeout=60s

echo "      Backend API (2 replicas)..."
kubectl apply -f "$REPO_ROOT/k8s/backend-deployment.yaml"

echo "      Worker..."
kubectl apply -f "$REPO_ROOT/k8s/worker-deployment.yaml"

echo "      Frontend..."
kubectl apply -f "$REPO_ROOT/k8s/frontend-deployment.yaml"

echo "      HPA (requires metrics-server)..."
kubectl apply -f "$REPO_ROOT/k8s/hpa.yaml"

echo "      Prometheus..."
kubectl apply -f "$REPO_ROOT/k8s/prometheus.yaml"

echo "      Grafana..."
kubectl apply -f "$REPO_ROOT/k8s/grafana.yaml"

# ── Step 8: Wait and verify ───────────────────────────────────────────────────
echo ""
echo "[8/8] Waiting for all deployments to be ready (up to 3 minutes)..."

kubectl wait --for=condition=available deployment/backend   -n "$NAMESPACE" --timeout=180s
kubectl wait --for=condition=available deployment/frontend  -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=available deployment/worker    -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=available deployment/prometheus -n "$NAMESPACE" --timeout=120s
kubectl wait --for=condition=available deployment/grafana   -n "$NAMESPACE" --timeout=120s

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo "  Setup Complete!"
echo "============================================="
echo ""
kubectl get pods      -n "$NAMESPACE"
echo ""
kubectl get services  -n "$NAMESPACE"
echo ""
kubectl get hpa       -n "$NAMESPACE"
echo ""

MINIKUBE_IP=$(minikube ip)
echo "Access URLs:"
echo "  Frontend:   http://$MINIKUBE_IP:30080"
echo "  Prometheus: http://$MINIKUBE_IP:30090"
echo "  Grafana:    http://$MINIKUBE_IP:30300  (admin / admin)"
echo ""
echo "For Jaeger tracing UI:"
echo "  kubectl port-forward svc/jaeger 16686:16686 -n benchmark"
echo "  Then open: http://localhost:16686"
echo ""
echo "Next step — run the spike test:"
echo "  ./scripts/k8s-demo.sh"
echo ""
