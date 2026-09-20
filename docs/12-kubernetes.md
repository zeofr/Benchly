# Kubernetes Manifests

## Overview

The `k8s/` directory contains all Kubernetes manifests for running Benchly on a local Minikube cluster (or any Kubernetes cluster). Everything lives in the `benchmark` namespace.

## Manifest files

```
k8s/
├── namespace.yaml           # benchmark namespace
├── configmap.yaml           # non-sensitive backend config
├── secrets.yaml             # DB credentials, JWT secret, API keys
├── postgres-deployment.yaml # PostgreSQL Deployment + Service
├── redis-deployment.yaml    # Redis Deployment + Service
├── backend-deployment.yaml  # Backend API Deployment + Service
├── worker-deployment.yaml   # Worker Deployment
├── frontend-deployment.yaml # Frontend nginx Deployment + Service
├── analytics-deployment.yaml# FastAPI analytics Deployment + Service
├── hpa.yaml                 # HorizontalPodAutoscaler for backend
├── ingress.yaml             # Ingress for external access
├── prometheus.yaml          # Prometheus Deployment + ConfigMap + Service
├── grafana.yaml             # Grafana Deployment + Service
└── jaeger.yaml              # Jaeger Deployment + Service
```

## Applying to a cluster

```bash
# Start Minikube
minikube start --cpus=4 --memory=8192

# Build images inside Minikube's Docker daemon
eval $(minikube docker-env)
docker build -t benchly-backend:latest  -f backend/Dockerfile   . --build-arg INSTALL_K6=true
docker build -t benchly-frontend:latest -f frontend/Dockerfile  ./frontend
docker build -t benchly-analytics:latest                        ./analytics

# Apply all manifests in order
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/redis-deployment.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/analytics-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/prometheus.yaml
kubectl apply -f k8s/grafana.yaml
kubectl apply -f k8s/jaeger.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/ingress.yaml
```

Or use the setup script:
```bash
bash scripts/k8s-setup.sh
```

## Namespace (`namespace.yaml`)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: benchmark
  labels:
    app: api-benchmark-saas
```

All resources are created in the `benchmark` namespace.

## Secrets (`secrets.yaml`)

Base64-encoded values. Template (replace before applying):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: benchmark
type: Opaque
data:
  DB_NAME:     YmVuY2htYXJrZGI=         # benchmarkdb
  DB_USER:     cG9zdGdyZXM=             # postgres
  DB_PASSWORD: REPLACE_WITH_BASE64_VALUE
  JWT_SECRET:  REPLACE_WITH_BASE64_VALUE
  API_KEYS:    REPLACE_WITH_BASE64_VALUE
```

Encode a value: `echo -n 'mypassword' | base64`

## ConfigMap (`configmap.yaml`)

Non-sensitive backend config:

```yaml
data:
  PORT:                       "4000"
  NODE_ENV:                   "production"
  DB_HOST:                    "postgres"
  DB_PORT:                    "5432"
  REDIS_HOST:                 "redis"
  REDIS_PORT:                 "6379"
  LOG_LEVEL:                  "info"
  OTEL_ENABLED:               "true"
  OTEL_SERVICE_NAME:          "benchmark-backend"
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://jaeger:4318/v1/traces"
```

## Backend Deployment (`backend-deployment.yaml`)

Key features:
- 2 initial replicas
- `imagePullPolicy: Never` — uses locally-built image
- Init containers wait for Postgres and Redis to be ready before the pod starts
- All env vars from ConfigMap + Secret
- Resource requests: 100m CPU, 128Mi memory; limits: 500m CPU, 256Mi memory
- Prometheus annotations: `prometheus.io/scrape: "true"` on pod
- Readiness probe: `GET /health` after 15s, every 10s
- Liveness probe: `GET /health` after 30s, every 30s

## HPA (`hpa.yaml`)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
  namespace: benchmark
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30      # react to load quickly
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300     # wait 5 min before scaling down
```

Prerequisite: `minikube addons enable metrics-server`

### How HPA works in this setup

- Each backend pod requests 100m CPU
- HPA target = 70% of 100m = 70m per pod
- At 2 pods: total capacity = 200m, threshold = 140m
- If actual usage = 160m → `ceil(2 × 160/140)` = 3 replicas

## Ingress (`ingress.yaml`)

Routes external traffic:
- `/` → frontend service (port 8080)
- `/api/` → backend service (port 4000)
- `/auth/` → backend service (port 4000)
- `/metrics` → backend service (port 4000)

Requires nginx ingress controller:
```bash
minikube addons enable ingress
```

## Worker Deployment (`worker-deployment.yaml`)

Same image as the backend, but `command: ["node", "src/worker.js"]`. Higher resource limits (512Mi memory, 1000m CPU) because it runs k6 subprocesses.

## Useful commands

```bash
# Watch all pods
kubectl get pods -n benchmark -w

# Check HPA status
kubectl get hpa -n benchmark

# Scale backend manually
kubectl scale deployment backend -n benchmark --replicas=3

# View backend logs
kubectl logs -n benchmark deployment/backend -f

# View worker logs
kubectl logs -n benchmark deployment/worker -f

# Port-forward services for local access
kubectl port-forward -n benchmark svc/frontend  3000:8080
kubectl port-forward -n benchmark svc/backend   4000:4000
kubectl port-forward -n benchmark svc/grafana   3001:3000
kubectl port-forward -n benchmark svc/jaeger    16686:16686
kubectl port-forward -n benchmark svc/prometheus 9090:9090

# Delete everything
kubectl delete namespace benchmark
```
