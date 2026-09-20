# Benchly — Kubernetes Demo Guide

Complete reference for running the Kubernetes deployment locally with Minikube.

---

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
- [k6](https://k6.io/docs/get-started/installation/) installed locally

---

## STEP 14 — Complete Demo Workflow (Interview Commands)

### 1. Start the cluster

```bash
minikube start --cpus=4 --memory=6144 --driver=docker
minikube addons enable metrics-server
minikube addons enable ingress
```

Why `--cpus=4 --memory=6144`: The HPA needs real CPU headroom to trigger. With too few resources, pods get throttled and scaling never fires.

Why `metrics-server`: Without it, HPA cannot query CPU metrics and stays permanently at `<unknown>`.

---

### 2. Build images inside Minikube

```bash
# Point your Docker CLI at Minikube's internal daemon
eval $(minikube docker-env)         # Linux/Mac
# OR on Windows PowerShell:
& minikube -p minikube docker-env | Invoke-Expression

# Build both images — they are now available to Kubernetes without a registry
docker build -t benchly-backend:latest -f backend/Dockerfile --build-arg INSTALL_K6=true .
docker build -t benchly-frontend:latest -f frontend/Dockerfile ./frontend

# Verify images exist inside Minikube
docker images | grep benchly
```

**Why `eval $(minikube docker-env)`**: Minikube runs its own Docker daemon inside a VM. When you build an image there, Kubernetes can pull it with `imagePullPolicy: Never` — no Docker Hub account needed.

---

### 3. Apply Kubernetes manifests

```bash
# Namespace first — everything else goes inside it
kubectl apply -f k8s/namespace.yaml

# Config and secrets
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/configmap.yaml

# Infrastructure (order matters: DB before API)
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/redis-deployment.yaml
kubectl apply -f k8s/jaeger.yaml

# Wait for DB to be ready before deploying the API
kubectl wait --for=condition=ready pod -l app=postgres -n benchmark --timeout=90s
kubectl wait --for=condition=ready pod -l app=redis    -n benchmark --timeout=60s

# Application layer
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml

# Autoscaling
kubectl apply -f k8s/hpa.yaml

# Observability
kubectl apply -f k8s/prometheus.yaml
kubectl apply -f k8s/grafana.yaml
```

Or use the setup script which does all of this:
```bash
chmod +x scripts/k8s-setup.sh && ./scripts/k8s-setup.sh
```

---

### 4. Verify pods are running

```bash
kubectl get nodes
kubectl get pods        -n benchmark
kubectl get deployments -n benchmark
kubectl get services    -n benchmark
kubectl get hpa         -n benchmark
```

Expected output — all pods should show `Running` or `1/1`:
```
NAME                          READY   STATUS    RESTARTS   AGE
backend-xxx-yyy               1/1     Running   0          2m
backend-zzz-www               1/1     Running   0          2m
frontend-xxx-yyy              1/1     Running   0          2m
postgres-xxx-yyy              1/1     Running   0          3m
redis-xxx-yyy                 1/1     Running   0          3m
worker-xxx-yyy                1/1     Running   0          2m
prometheus-xxx-yyy            1/1     Running   0          2m
grafana-xxx-yyy               1/1     Running   0          2m
jaeger-xxx-yyy                1/1     Running   0          3m
```

---

### 5. Open Grafana

```bash
MINIKUBE_IP=$(minikube ip)
echo "Grafana: http://$MINIKUBE_IP:30300"
open "http://$MINIKUBE_IP:30300"    # macOS
# OR on Windows:
start "http://$MINIKUBE_IP:30300"
```

Login: `admin` / `admin`

Navigate to: **Dashboards → Benchly → Benchly — API Performance**

You should see live data in:
- HTTP Request Rate
- p95 Latency
- CPU Utilization per Pod

---

### 6. Run the smoke test first

```bash
MINIKUBE_IP=$(minikube ip)
k6 run --env BASE_URL=http://$MINIKUBE_IP:30080 --env API_KEY=demo-key-12345 backend/k6/smoke-test.js
```

This uses 1 VU for 30 seconds. If this fails, debug before running the spike.

---

### 7. Start the k6 spike test

In terminal 1 — watch HPA:
```bash
watch -n 3 kubectl get hpa -n benchmark
```

In terminal 2 — run the spike:
```bash
MINIKUBE_IP=$(minikube ip)
k6 run \
  --env BASE_URL=http://$MINIKUBE_IP:30080 \
  --env API_KEY=demo-key-12345 \
  backend/k6/spike-test.js
```

The spike test runs for ~4 minutes total.

---

### 8. Watch HPA scale replicas

In the `watch` terminal you will see something like:

```
NAME          REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
backend-hpa   Deployment/backend   8%/70%    2         5         2          5m
backend-hpa   Deployment/backend   67%/70%   2         5         2          7m
backend-hpa   Deployment/backend   84%/70%   2         5         3          8m   ← scaling!
backend-hpa   Deployment/backend   91%/70%   2         5         4          9m
backend-hpa   Deployment/backend   87%/70%   2         5         5          10m  ← at max
```

```bash
# Also watch pods being created in real time
kubectl get pods -n benchmark -l app=backend --watch
```

---

### 9. Observe metrics in Prometheus and Grafana

**Prometheus** — `http://$MINIKUBE_IP:30090`

Useful queries:
```promql
# Request rate
rate(http_requests_total[1m])

# p95 latency
histogram_quantile(0.95, sum(rate(http_request_duration_ms_bucket[1m])) by (le))

# HPA current replicas
kube_horizontalpodautoscaler_status_current_replicas{namespace="benchmark"}

# CPU by pod
rate(process_cpu_seconds_total[1m]) * 100
```

**Grafana** — `http://$MINIKUBE_IP:30300`

Open the **Benchly — API Performance** dashboard. During the spike you will see:
- Request Rate: spike upward
- p95 Latency: increases as pods are still ramping up
- CPU Utilization: crosses the 70% threshold
- Backend Pod Count: 2 → 3 → 4 → 5

---

### 10. Stop load and observe scale-down

When k6 finishes, the HPA enters a **5-minute scale-down stabilization window**.

```bash
# Continue watching — replicas will decrease slowly
watch -n 10 kubectl get hpa -n benchmark

# After ~5 minutes:
# backend-hpa   Deployment/backend   12%/70%   2   5   4   15m
# backend-hpa   Deployment/backend   8%/70%    2   5   3   16m
# backend-hpa   Deployment/backend   6%/70%    2   5   2   22m  ← back to min
```

This cooldown is intentional — it prevents rapid replica thrashing when load briefly dips.

---

## STEP 4 — Container Image Strategy

**Minikube with `eval $(minikube docker-env)`** is used instead of kind.

Comparison:

| Approach | How it works | Tradeoff |
|---|---|---|
| `eval $(minikube docker-env)` | Redirects `docker build` into Minikube's internal daemon | Images are immediately available — no push/load step needed |
| `kind load docker-image` | Build locally, then copy image tarball into kind nodes | Two-step process, but works without eval |
| Docker Hub push/pull | Build locally, push to registry, k8s pulls | Requires account; `imagePullPolicy: Always` — adds internet dependency |

The Minikube approach is the simplest for local development. The manifests use `imagePullPolicy: Never` to enforce that Kubernetes never tries to pull from a registry.

---

## STEP 10 — Database Architecture

**PostgreSQL** is used (not SQLite). This is confirmed by `backend/src/db.js` using the `pg` npm package with a connection pool.

**Multiple replicas + PostgreSQL**: This is safe because all backend pods connect to the same PostgreSQL Service (ClusterIP). Each pod establishes its own connection pool but they all read/write to the same shared database. This is standard horizontal scaling for stateless API servers with a shared database.

PostgreSQL itself runs as 1 replica with a PersistentVolumeClaim. In production you would use:
- Amazon RDS (managed PostgreSQL with automated backups and read replicas)
- or a StatefulSet with proper leader election

For local demo, a single Deployment with a PVC is correct.

---

## STEP 6 — How HPA Works in This Project

```
k6 generates 30-50 VUs of traffic
         ↓
Backend pods processing HTTP requests → CPU rises
         ↓
kubelet reports CPU metrics every 15s to Metrics Server
         ↓
HPA queries Metrics Server every 15s
         ↓
HPA calculates: desired = ceil(current × actual_cpu / target_cpu)
Example:  ceil(2 × 84% / 70%) = ceil(2.4) = 3 replicas
         ↓
HPA updates the Deployment's .spec.replicas from 2 to 3
         ↓
Deployment creates a new Pod
         ↓
Pod runs initContainers (wait for postgres/redis)
         ↓
Pod starts backend, passes readinessProbe (/health)
         ↓
Service includes new Pod in its endpoint list
         ↓
kube-proxy updates iptables rules on every Node
         ↓
Traffic is distributed across 3 Pods
```

**Critical distinction — Prometheus vs Metrics Server**:

| | Metrics Server | Prometheus |
|---|---|---|
| Purpose | HPA CPU/memory scaling | Application metrics, alerting, dashboards |
| Data source | kubelet (node-level resource data) | Application `/metrics` endpoint |
| Retention | Live only (no history) | Configurable (24h in this setup) |
| Queries | `kubectl top pods` | PromQL (rich query language) |
| Used by HPA? | **Yes** | No (not in this setup) |

The HPA in this project uses CPU metrics from the Metrics Server, NOT from Prometheus. Prometheus is for observability dashboards and alerts, not for driving autoscaling decisions.

---

## STEP 7 — Prometheus and Grafana Architecture

```
Express.js backend
  ↓ prom-client library
  ↓ exposes /metrics (Prometheus text format)
  ↓
Prometheus (pod annotation discovery)
  ↓ scrapes all backend pods every 10s
  ↓ stores time-series data
  ↓
Grafana
  ↓ queries Prometheus via PromQL
  ↓ renders dashboards
  ↓
Grafana panels show:
  - RPS, error rate, latency (from /metrics)
  - CPU per pod (from process_cpu_seconds_total)
  - Pod count (from kube_pod_info — requires kube-state-metrics for full detail)
```

**Pod-level vs aggregate metrics**: The Prometheus config uses both a static target (the backend Service, aggregate) and pod annotation discovery. The pod discovery scrapes each backend pod individually, so you can see metrics broken down by pod in Grafana — useful for seeing which pod is under load before HPA fully balances.

---

## STEP 11 — Terraform Honest Assessment

Terraform **exists** in this repository (`terraform/main.tf`). What it actually does:

- Targets a **local Minikube cluster** via the Kubernetes provider (`~/.kube/config`)
- Manages: Namespace, Secrets, PostgreSQL, Redis, Backend, Frontend, Worker deployments, PodDisruptionBudgets
- Requires `dockerhub_username` variable (expects images on Docker Hub)
- `aws-eks.tf` is **fully commented out** — it provisions nothing in AWS

**The honest position for interview**: "I have Terraform configuration that manages the same Kubernetes resources as the `kubectl apply` manifests, targeting a local Minikube cluster. The Terraform code demonstrates infrastructure-as-code principles — declarative state, plan/apply workflow, and secrets management. The AWS EKS configuration exists in the codebase as a reference implementation showing how this would expand to a production cloud cluster."

**For actual local use**: The `kubectl apply` approach in the `k8s/` directory is simpler and does not require `dockerhub_username`. The Terraform approach would additionally require either pushing images to Docker Hub or modifying the `dockerhub_username` variable to use the local image name and adding `imagePullPolicy: Never` to the Terraform HCL.

---

## STEP 12 — CI/CD Pipeline Overview

What the existing GitHub Actions pipeline does:

```
Code push to main/develop
         ↓
[Lint Backend]  [Lint Frontend]
         ↓
[Backend Tests + Coverage]  [Frontend Tests]
         ↓
[Security Scan: npm audit + secret detection]
         ↓
[Build Backend Docker Image]  [Build Frontend Docker Image]
         ↓
[Trivy scan — block on CRITICAL CVEs]
         ↓
[k8s Manifest Validation — dry-run kubectl apply]   ← NEW
         ↓
[Integration Test: starts backend + postgres + redis, runs k6 CI load test]
         ↓
[Deploy: docker compose up (local CI runner)]
```

**Important distinction**: The CI/CD pipeline currently deploys via `docker compose up` on the CI runner. It does NOT deploy to a Kubernetes cluster. For that to work in CI, you would need:
- A Kubernetes cluster accessible from GitHub Actions (e.g., a cloud cluster with `KUBE_CONFIG` secret)
- Or a self-hosted runner with Minikube

The manifest validation step (`validate-k8s`) was added to catch YAML errors in CI without needing a live cluster.

---

## Troubleshooting

### HPA shows `<unknown>` for targets

```bash
# Check metrics-server is running
kubectl get pods -n kube-system | grep metrics-server

# If not running:
minikube addons enable metrics-server

# Wait 60s then check
kubectl top pods -n benchmark
kubectl get hpa -n benchmark
```

### Pod stuck in `Pending`

```bash
kubectl describe pod <pod-name> -n benchmark
# Look for: Insufficient CPU/memory → increase minikube --memory
# Or: ImagePullBackOff → check imagePullPolicy: Never and that image exists
docker images | grep benchly   # run with eval $(minikube docker-env) active
```

### Backend pod `CrashLoopBackOff`

```bash
kubectl logs <backend-pod-name> -n benchmark
# Common causes:
# - postgres not ready yet (initContainers should prevent this, but check)
# - DB_PASSWORD wrong in secrets
# - Port conflict
```

### HPA not scaling despite high load

```bash
# 1. Check metrics are available
kubectl top pods -n benchmark -l app=backend

# 2. Check HPA events
kubectl describe hpa backend-hpa -n benchmark

# 3. Confirm resource requests are set in the Deployment
# HPA calculates % based on REQUEST, not limit.
# If requests are too high (e.g., 1000m), 70% = 700m — k6 may not reach this.
kubectl get deployment backend -n benchmark -o yaml | grep -A4 resources
```

### Grafana shows "No data"

```bash
# Check Prometheus is actually scraping the backend
curl http://$(minikube ip):30090/api/v1/targets

# The benchmark-backend target should show state: up
# If state: down, check the service DNS resolves:
kubectl exec -it $(kubectl get pod -l app=prometheus -n benchmark -o name | head -1) \
  -n benchmark -- wget -qO- http://backend.benchmark.svc.cluster.local:4000/metrics | head -5
```

---

## Cleanup

```bash
# Delete everything in the benchmark namespace
kubectl delete namespace benchmark

# Stop Minikube (keeps the VM)
minikube stop

# Delete Minikube entirely (frees all disk space)
minikube delete
```
