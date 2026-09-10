# 🚀 API Performance Benchmarking SaaS

> A production-grade, cloud-native platform for load testing any API endpoint with real-time analytics, distributed tracing, and enterprise-level observability.

[![CI/CD Pipeline](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)](https://github.com/Suhani-Srikantaswamy/api-benchmarking-saas/actions)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Ready-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 📚 Quick Links

- 🚀 **[How to Run](#-quick-start)** — Run full stack on Docker Compose
- ☸️ **[Kubernetes Deployment](./k8s/)** — Production-ready K8s manifests
- 🔧 **[Backend Source](./backend/)** — Node.js API + Worker
- 🎨 **[Frontend Source](./frontend/)** — React Dashboard

## ✨ Features

**Core Capabilities**
- 🎯 **Universal API Testing** — Load test any HTTP/HTTPS endpoint with k6 engine
- 📊 **Real-Time Analytics** — Live metrics via Server-Sent Events (SSE)
- 🔄 **Side-by-Side Comparison** — Compare performance across test runs
- 📥 **Multi-Format Export** — Download results as JSON or CSV
- 🔐 **Enterprise Auth** — JWT and API Key authentication with rate limiting
- 🎨 **Modern UI** — Dark-themed React dashboard with responsive charts

**DevOps & Observability**
- 📈 **Prometheus Metrics** — Custom application and system metrics
- 📉 **Grafana Dashboards** — Pre-configured performance visualizations
- 🔍 **Distributed Tracing** — End-to-end request tracing with Jaeger
- 🚨 **Smart Alerting** — AlertManager with 6 production-ready alert rules
- ⚡ **Auto-Scaling** — HPA for API pods, KEDA for queue-based worker scaling

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      🌐 USER BROWSER                            │
│         React 18 + Vite  •  SSE Live Updates                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │ HTTPS / SSE
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│              🔧 BACKEND API (Node.js + Express)                 │
│  ✓ JWT + API Key Auth      ✓ 3-Tier Rate Limiting              │
│  ✓ Input Validation        ✓ Prometheus /metrics               │
│  ✓ OpenTelemetry Tracing   ✓ SSE Event Broadcasting            │
└──────────┬──────────────────────────────────┬───────────────────┘
           │ Enqueue Job                       │ Real-time Notify
           ▼                                   │
┌──────────────────────┐                       │
│   📮 REDIS (BullMQ)  │                       │
│  • Job Queue         │                       │
│  • Auto Retry        │                       │
│  • Concurrency: 3    │                       │
└──────────┬───────────┘                       │
           │ Dequeue Job                       │
           ▼                                   │
┌──────────────────────────────────────────────┴───────────────────┐
│                  ⚙️ WORKER PROCESS (Node.js)                     │
│  1. Consume jobs from Redis (concurrency: 3)                    │
│  2. Spawn k6 as child process (execFile)                        │
│  3. Parse k6 JSON output → calculate metrics                    │
│  4. UPSERT results to PostgreSQL                                │
│  5. Broadcast completion via SSE                                │
└──────────┬───────────────────────────────────────────────────────┘
           │ k6 Load Test (N Virtual Users)
           ▼
┌──────────────────────┐     ┌──────────────────────────────────────┐
│   🎯 TARGET API      │     │   🗄️ POSTGRESQL 15                  │
│  Any HTTP Endpoint   │     │  • benchmark_results table           │
│  GET/POST/PUT/DELETE │     │  • 4 Optimized Indexes               │
│  Custom Headers      │     │  • Connection Pool (max: 20)         │
└──────────────────────┘     └──────────────────────────────────────┘

                    📊 OBSERVABILITY STACK
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Prometheus  │  │   Grafana    │  │    Jaeger    │
│    :9090     │  │    :3001     │  │   :16686     │
│  Metrics     │  │  Dashboards  │  │  Distributed │
│  Scraping    │  │  + Alerts    │  │  Tracing     │
└──────────────┘  └──────────────┘  └──────────────┘

                  ☸️ KUBERNETES DEPLOYMENT
┌─────────────────────────────────────────────────────────────────┐
│  NGINX Ingress → Frontend Service → Frontend Pods               │
│               → Backend Service  → Backend Pods  (HPA)          │
│                                  → Worker Pods   (KEDA)         │
│                                                                  │
│  • KEDA: Queue-based autoscaling (Redis depth)                  │
│  • HPA: CPU-based autoscaling (70% threshold)                   │
│  • PDB: Pod Disruption Budgets for high availability            │
└─────────────────────────────────────────────────────────────────┘
```

### 🎯 Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Separate Worker Process** | k6 is CPU-intensive; isolating it prevents blocking the API event loop |
| **BullMQ + Redis Queue** | Absorbs traffic spikes — 1000 concurrent requests queue instantly, process 3 at a time |
| **SSE over WebSockets** | Unidirectional updates are simpler, work over HTTP/1.1, easier to scale |
| **UPSERT Pattern** | Workers can safely retry failed jobs without creating duplicate records |
| **Multi-Stage Docker Builds** | Reduces image size by 60%, improves security posture |

---

## 🛠️ Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | React 18, Vite, Recharts | Modern SPA with real-time charting |
| **Backend** | Node.js 20, Express | RESTful API with SSE support |
| **Queue** | BullMQ + Redis | Async job processing with retry logic |
| **Load Testing** | k6 | Industry-standard load testing engine |
| **Database** | PostgreSQL 15 | Persistent storage with optimized indexes |
| **Containers** | Docker | Multi-stage builds for security & size |
| **Orchestration** | Kubernetes | Production-grade container orchestration |
| **Autoscaling** | HPA + KEDA | CPU-based & queue-based scaling |
| **CI/CD** | GitHub Actions | Automated testing, building, and deployment |
| **IaC** | Terraform | Infrastructure as Code for AWS EKS |
| **Monitoring** | Prometheus + Grafana | Metrics collection and visualization |
| **Tracing** | OpenTelemetry + Jaeger | Distributed request tracing |
| **Alerting** | AlertManager | Intelligent alert routing and grouping |
| **Security** | Trivy, Network Policies | Vulnerability scanning and network isolation |

---

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- Node.js 20+ (for local development)
- kubectl & Minikube (for Kubernetes deployment)
- Terraform (for infrastructure provisioning)

### Option 1: Docker Compose (Recommended for Development)

Get the entire stack running locally with full deployment experience:

```bash
# Clone the repository
git clone <your-repo-url>
cd api-benchmarking-saas

# Create .env from example
cp docker-compose.env.example .env
# Edit .env and set your own passwords

# Start all services (from WSL/Git Bash on Windows)
docker compose up -d postgres redis
docker compose up -d backend worker frontend prometheus grafana alertmanager jaeger

# Verify deployment
./scripts/health-check.sh --timeout 120
```

> 📌 **On Windows?** Use WSL or Git Bash, not PowerShell, to avoid Bash script line-ending issues.

> 📋 **Run `./scripts/health-check.sh --timeout 120`** to verify all services are up after deployment.

**Access the services:**

| Service | URL | Credentials |
|---------|-----|-------------|
| 🎨 Frontend Dashboard | http://localhost:3000 | — |
| 🔧 Backend API | http://localhost:4000 | API Key: `demo-key-12345` |
| 📊 Prometheus | http://localhost:9090 | — |
| 📈 Grafana | http://localhost:3001 | `admin` / `${GRAFANA_PASSWORD}` (see `.env`) |
| 🚨 AlertManager | http://localhost:9093 | — |
| 🔍 Jaeger UI | http://localhost:16686 | — |

---

### Option 2: Kubernetes (For Production)

Once you have the Docker-based stack working locally, you can deploy to production-grade Kubernetes:

```bash
# 1. Prerequisites: kubectl, a running Kubernetes cluster (EKS, GKE, AKS, etc.)

# 2. Deploy to Kubernetes (requires cluster access and image availability)
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/redis-ha.yaml
kubectl apply -f k8s/worker-deployment.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/keda-scaledobject.yaml
kubectl apply -f k8s/pdb.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/network-policies.yaml

# 3. Verify deployment
kubectl get pods -n benchmark-saas
kubectl logs -f deployment/backend -n benchmark-saas
```

> 📌 **Start with Docker Compose first** to test the stack locally, then scale to Kubernetes when ready for production.

---

### Option 3: Infrastructure as Code (Terraform for AWS EKS)

Provision production infrastructure on AWS:

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply infrastructure changes
terraform apply

# Get kubeconfig for the new cluster
aws eks update-kubeconfig --name benchmark-cluster --region us-east-1
```

**Terraform provisions:**
- EKS cluster with managed node groups
- VPC with public/private subnets
- RDS PostgreSQL instance
- ElastiCache Redis cluster
- Application Load Balancer
- Route53 DNS records
- ACM SSL certificates

> 📌 **For other cloud providers** (GCP, Azure, etc.), adapt the Terraform configs or use their native deployment tools.

---

## 📊 Usage Guide

### Running Load Tests via UI

1. **Navigate to Dashboard**
   ```
   http://localhost:3000
   ```

2. **Configure Test Parameters**
   - **API URL**: Enter any HTTP/HTTPS endpoint (e.g., `https://httpbin.org/get`)
   - **Preset**: Choose load profile
     - 🟢 **Light**: 10 VUs, 30s duration
     - 🟡 **Medium**: 20 VUs, 60s duration
     - 🔴 **Stress**: 50 VUs, 120s duration
   - **Authentication** (optional):
     - Bearer Token
     - API Key
     - Custom JSON headers

3. **Execute & Monitor**
   - Click **Run Load Test**
   - Watch real-time metrics update via SSE
   - View response time, throughput, error rate

4. **Analyze Results**
   - Export as JSON or CSV
   - Compare with previous runs
   - View detailed metrics in Grafana

---

### Running Load Tests via API

**Basic Test:**

```bash
curl -X POST http://localhost:4000/api/benchmark/run \
  -H "X-API-Key: demo-key-12345" \
  -H "Content-Type: application/json" \
  -d '{
    "apiUrl": "https://httpbin.org/get",
    "vus": 10,
    "duration": "10s"
  }'
```

**Response:**
```json
{
  "testId": "test_1234567890",
  "status": "queued",
  "message": "Load test queued successfully"
}
```

**Check Test Status:**

```bash
curl http://localhost:4000/api/benchmark/test_1234567890 \
  -H "X-API-Key: demo-key-12345"
```

**Test with Authentication Headers:**

```bash
curl -X POST http://localhost:4000/api/benchmark/run \
  -H "X-API-Key: demo-key-12345" \
  -H "Content-Type: application/json" \
  -d '{
    "apiUrl": "https://api.github.com/user",
    "vus": 5,
    "duration": "10s",
    "method": "GET",
    "headers": {
      "Authorization": "Bearer YOUR_GITHUB_TOKEN",
      "Accept": "application/vnd.github.v3+json"
    }
  }'
```

**POST Request with Body:**

```bash
curl -X POST http://localhost:4000/api/benchmark/run \
  -H "X-API-Key: demo-key-12345" \
  -H "Content-Type: application/json" \
  -d '{
    "apiUrl": "https://httpbin.org/post",
    "vus": 15,
    "duration": "30s",
    "method": "POST",
    "body": "{\"key\":\"value\"}",
    "headers": {
      "Content-Type": "application/json"
    }
  }'
```

---

### Running k6 Directly

For advanced users who want full control:

```bash
k6 run \
  --env TARGET_URL=https://httpbin.org/get \
  --env VUS=10 \
  --env DURATION=10s \
  backend/k6/load-test.js
```

**Custom k6 script:**

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,
  duration: '30s',
};

export default function () {
  const res = http.get('https://httpbin.org/get');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
```

---

## 🔐 Authentication

The platform supports two authentication methods:

### API Key Authentication

**Header:** `X-API-Key`  
**Demo Key:** `demo-key-12345`

```bash
curl http://localhost:4000/api/benchmark/history \
  -H "X-API-Key: demo-key-12345"
```

### JWT Authentication

**Header:** `Authorization: Bearer <token>`

**Obtain a JWT token:**

```bash
curl -X POST http://localhost:4000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "demo",
    "password": "demo123"
  }'
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": "24h"
}
```

**Use the token:**

```bash
curl http://localhost:4000/api/benchmark/history \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Rate Limiting

| Tier | Limit | Scope |
|------|-------|-------|
| **General API** | 100 requests / 15 min | Per IP address |
| **Load Tests** | 5 tests / 1 min | Per API key |
| **Authentication** | 10 attempts / 5 min | Per IP address |

> 💡 **Note:** The frontend automatically attaches the demo API key for quick testing.

---

## 📁 Project Structure

```
api-benchmarking-saas/
│
├── 🔧 backend/                      # Node.js + Express API
│   ├── k6/                          # k6 load test scripts
│   │   └── load-test.js             # Configurable k6 test
│   └── src/
│       ├── middleware/              # Express middleware
│       │   ├── auth.js              # JWT + API Key validation
│       │   ├── rateLimiter.js       # 3-tier rate limiting
│       │   └── appMetrics.js        # Prometheus metrics
│       ├── routes/                  # API endpoints
│       │   ├── benchmark.js         # Test execution & results
│       │   ├── auth.js              # Login & token generation
│       │   ├── events.js            # SSE event stream
│       │   └── metrics.js           # Prometheus /metrics
│       ├── db.js                    # PostgreSQL client (pooled)
│       ├── queue.js                 # BullMQ queue setup
│       ├── worker.js                # k6 job processor
│       ├── tracing.js               # OpenTelemetry config
│       ├── logger.js                # Winston logger
│       └── index.js                 # Express app entry
│
├── 🎨 frontend/                     # React 18 + Vite SPA
│   └── src/
│       ├── components/
│       │   ├── BenchmarkForm.jsx    # Test configuration form
│       │   ├── Dashboard.jsx        # Real-time metrics display
│       │   ├── ResultsHistory.jsx   # Test history table
│       │   ├── CompareView.jsx      # Side-by-side comparison
│       │   ├── Toast.jsx            # Notification system
│       │   └── ErrorBoundary.jsx    # Error handling
│       ├── App.jsx                  # Main app component
│       └── main.jsx                 # React entry point
│
├── ☸️ k8s/                          # Kubernetes manifests (16 files)
│   ├── namespace.yaml               # Isolated namespace
│   ├── secrets.yaml                 # Sensitive config (base64)
│   ├── configmap.yaml               # Non-sensitive config
│   ├── postgres-deployment.yaml     # PostgreSQL StatefulSet
│   ├── redis-ha.yaml                # Redis with Sentinel
│   ├── backend-deployment.yaml      # API pods
│   ├── frontend-deployment.yaml     # Frontend pods
│   ├── worker-deployment.yaml       # Worker pods
│   ├── hpa.yaml                     # Horizontal Pod Autoscaler
│   ├── keda-scaledobject.yaml       # Queue-based autoscaling
│   ├── pdb.yaml                     # Pod Disruption Budgets
│   ├── ingress.yaml                 # NGINX Ingress rules
│   ├── network-policies.yaml        # Network isolation
│   ├── cert-manager.yaml            # TLS certificate automation
│   ├── jaeger.yaml                  # Distributed tracing
│   └── secrets-rotation.yaml        # Automated secret rotation
│
├── 🏗️ terraform/                    # Infrastructure as Code
│   ├── main.tf                      # AWS EKS cluster
│   ├── vpc.tf                       # Network configuration
│   ├── rds.tf                       # PostgreSQL RDS
│   ├── elasticache.tf               # Redis cluster
│   ├── variables.tf                 # Input variables
│   └── outputs.tf                   # Output values
│
├── 📊 monitoring/                   # Observability stack
│   ├── prometheus/
│   │   ├── prometheus.yml           # Scrape configs
│   │   └── alerts.yml               # 6 alert rules
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   └── benchmark-dashboard.json
│   │   └── provisioning/            # Auto-provisioning
│   └── alertmanager/
│       └── alertmanager.yml         # Alert routing
│
├── 🔄 .github/workflows/            # CI/CD pipelines
│   └── ci-cd.yml                    # Lint, Test, Build, Deploy
│
├── docker-compose.yml               # Local development stack
└── README.md                        # This file
```

---

## 🔄 CI/CD Pipeline

Automated workflows powered by GitHub Actions:

### Pipeline Stages

```
┌──────────────────┐     ┌─────────────────┐     ┌──────────────────┐
│   Validate & Test│ --> │    Build Images │ --> │   Deploy & Verify │
│                  │     │                 │     │                   │
│ • ESLint         │     │ • Docker Build  │     │ • Docker Compose  │
│ • Vitest         │     │ • Frontend Build│     │ • Health Checks   │
│ • Jest           │     │ • Image Tag     │     │ • Integration Test│
│ • npm audit      │     │ • Push to Hub   │     │ • k6 Load Test    │
│ • Security Scan  │     │ • Artifact Save │     │ • Artifact Upload │
└──────────────────┘     └─────────────────┘     └──────────────────┘
```

### Workflow File

The CI/CD pipeline is defined in [`.github/workflows/ci-cd.yml`](./.github/workflows/ci-cd.yml).

**Pipeline runs on:**
- Every push to `main`
- Every pull request
- Manual trigger via `workflow_dispatch`

### Workflow Features

- ✅ **Automated Testing** — Unit, integration, and E2E tests
- 🔒 **Security Scanning** — Trivy for CVE detection (fails on CRITICAL)
- 🐳 **Multi-Stage Builds** — Optimized Docker images
- 📦 **Artifact Caching** — Faster builds with layer caching
- 🔄 **Auto Rollback** — Reverts on deployment failure
- 📊 **Deployment Metrics** — Success rate, duration tracking
- 🔔 **Slack Notifications** — Build status alerts

### Optional GitHub Secrets

For Docker Hub publishing and advanced deployments, configure these in your repository settings:

| Secret | Description | Optional | Example |
|--------|-------------|----------|----------|
| `DOCKERHUB_USERNAME` | Docker Hub username | ✅ Yes | `myusername` |
| `DOCKERHUB_TOKEN` | Docker Hub access token | ✅ Yes | `dckr_pat_...` |
| `POSTGRES_PASSWORD` | PostgreSQL password | ✅ Yes | `secure_password` |
| `JWT_SECRET` | JWT signing secret | ✅ Yes | `random_string_256bit` |
| `GRAFANA_PASSWORD` | Grafana admin password | ✅ Yes | `secure_password` |
| `API_KEYS` | Backend API keys | ✅ Yes | `prod-key-12345` |

> 📌 **Local deployment** uses `.env` file. Secrets are only needed if you want to publish Docker images to a registry or deploy to production.

---

## 📊 Monitoring & Observability

### Prometheus Metrics

**Access:** http://localhost:9090

**Custom Metrics Exposed:**

| Metric | Type | Description |
|--------|------|-------------|
| `http_requests_total` | Counter | Total HTTP requests by method, route, status |
| `http_request_duration_ms` | Histogram | Request latency distribution |
| `benchmark_tests_total` | Counter | Total load tests executed |
| `benchmark_test_duration_seconds` | Histogram | Test execution time |
| `queue_jobs_active` | Gauge | Active jobs in Redis queue |
| `queue_jobs_waiting` | Gauge | Pending jobs in queue |
| `nodejs_eventloop_lag_seconds` | Gauge | Event loop lag (performance indicator) |

**Example PromQL Queries:**

```promql
# Request rate (requests per second)
rate(http_requests_total[5m])

# 95th percentile response time
histogram_quantile(0.95, rate(http_request_duration_ms_bucket[5m]))

# Error rate percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# Queue depth over time
queue_jobs_waiting + queue_jobs_active
```

---

### Grafana Dashboards

**Access:** http://localhost:3001 (admin / password from `.env` GRAFANA_PASSWORD)

**Pre-configured Dashboard Panels:**

1. **System Overview**
   - Request rate, error rate, latency
   - Active connections, queue depth
   - CPU and memory usage

2. **Load Test Metrics**
   - Tests per hour
   - Average test duration
   - Success vs failure rate

3. **Database Performance**
   - Query duration
   - Connection pool utilization
   - Slow query log

4. **Infrastructure Health**
   - Pod status and restarts
   - Node resource utilization
   - Network I/O

**Import Custom Dashboards:**
```bash
# Dashboard JSON located at:
monitoring/grafana/dashboards/benchmark-dashboard.json
```

---

### Jaeger Distributed Tracing

**Access:** http://localhost:16686

**Trace Spans Captured:**

- HTTP request lifecycle
- Database queries
- Redis operations
- k6 process execution
- External API calls

**How to Use:**

1. Select service: `benchmark-backend`
2. Choose operation: `POST /api/benchmark/run`
3. Click **Find Traces**
4. Analyze span timeline and dependencies

**Trace Context Propagation:**
- Uses W3C Trace Context standard
- Automatic correlation across services
- Custom tags for test_id, api_url, vus

---

### AlertManager

**Access:** http://localhost:9093

**Configured Alerts:**

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| **HighCPUUsage** | CPU > 80% for 5m | Warning | Scale up pods |
| **HighMemoryUsage** | Memory > 85% for 5m | Warning | Investigate memory leaks |
| **HighErrorRate** | Error rate > 5% for 2m | Critical | Page on-call engineer |
| **HighLatency** | P95 latency > 2s for 5m | Warning | Check database performance |
| **BackendDown** | No metrics for 1m | Critical | Immediate investigation |
| **EventLoopLag** | Lag > 100ms for 3m | Warning | Check blocking operations |

**Alert Routing:**
- Critical → PagerDuty + Slack
- Warning → Slack only
- Grouping by `alertname` and `severity`
- 5-minute grouping window

---

### Logging

**Structured JSON Logging with Winston:**

```json
{
  "timestamp": "2026-05-04T10:30:45.123Z",
  "level": "info",
  "message": "Load test completed",
  "testId": "test_1234567890",
  "duration": 30,
  "vus": 10,
  "requestCount": 1500,
  "errorRate": 0.02
}
```

**Log Levels:**
- `error` — Application errors, exceptions
- `warn` — Degraded performance, rate limits
- `info` — Test execution, API requests
- `debug` — Detailed execution flow (dev only)

**View Logs:**

```bash
# Docker Compose
docker compose logs -f backend

# Kubernetes
kubectl logs -f deployment/backend -n benchmark-saas

# Tail last 100 lines
kubectl logs --tail=100 deployment/backend -n benchmark-saas
```

---

## 🔒 Security

### Authentication & Authorization

| Feature | Implementation |
|---------|---------------|
| **Authentication** | JWT (HS256) + API Key |
| **Token Expiry** | 24 hours (configurable) |
| **Password Hashing** | bcrypt (10 rounds) |
| **API Key Storage** | Environment variables |
| **CORS** | Configured for specific origins |

### Rate Limiting

**Implementation:** `express-rate-limit` with Redis store

| Endpoint | Limit | Window |
|----------|-------|--------|
| `/api/benchmark/run` | 5 requests | 1 minute |
| `/auth/login` | 10 requests | 5 minutes |
| All other endpoints | 100 requests | 15 minutes |

### Container Security

**Multi-Stage Docker Builds:**
```dockerfile
# Build stage (large)
FROM node:20-alpine AS builder
# ... build steps ...

# Production stage (minimal)
FROM node:20-alpine
USER node  # Non-root user
COPY --from=builder --chown=node:node /app /app
```

**Security Features:**
- ✅ Non-root user execution
- ✅ Minimal base images (Alpine Linux)
- ✅ No unnecessary packages
- ✅ Read-only root filesystem (where possible)
- ✅ Dropped capabilities

### Vulnerability Scanning

**Trivy Integration:**

```bash
# Scan Docker images
trivy image benchmark-backend:latest

# Scan in CI/CD (fails on CRITICAL)
trivy image --severity CRITICAL --exit-code 1 benchmark-backend:latest
```

**Scan Results:**
- Automated scanning on every build
- Blocks deployment if CRITICAL CVEs found
- Weekly scheduled scans for deployed images

### Kubernetes Security

**Network Policies:**

```yaml
# Default deny all ingress/egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**Explicit Allow Rules:**
- Backend → PostgreSQL (port 5432)
- Backend → Redis (port 6379)
- Worker → Redis (port 6379)
- Frontend → Backend (port 4000)
- Ingress → Frontend (port 80)

**Pod Security Standards:**
- Restricted security context
- No privileged containers
- Read-only root filesystem
- Run as non-root user
- Drop all capabilities

### Secrets Management

**Kubernetes Secrets:**

```bash
# Create secrets from literals
kubectl create secret generic db-credentials \
  --from-literal=username=postgres \
  --from-literal=password=secure_password \
  -n benchmark-saas

# Create from file
kubectl create secret generic jwt-secret \
  --from-file=jwt-secret=./jwt.key \
  -n benchmark-saas
```

**Best Practices:**
- ✅ Secrets stored in etcd (encrypted at rest)
- ✅ Mounted as volumes (not environment variables)
- ✅ Automated rotation every 90 days
- ✅ Separate secrets per environment
- ✅ Never committed to Git

### TLS/SSL

**cert-manager Integration:**

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: benchmark-tls
spec:
  secretName: benchmark-tls-secret
  issuer: letsencrypt-prod
  dnsNames:
  - benchmark.example.com
```

**Features:**
- Automatic certificate provisioning
- Auto-renewal before expiry
- Let's Encrypt integration
- TLS 1.2+ only

### Input Validation

**Request Validation:**

```javascript
// URL validation
const urlRegex = /^https?:\/\/.+/;
if (!urlRegex.test(apiUrl)) {
  throw new Error('Invalid URL format');
}

// VUs validation
if (vus < 1 || vus > 100) {
  throw new Error('VUs must be between 1 and 100');
}

// Duration validation
if (!duration.match(/^\d+[smh]$/)) {
  throw new Error('Invalid duration format');
}
```

**Sanitization:**
- SQL injection prevention (parameterized queries)
- XSS protection (Content Security Policy)
- Command injection prevention (no shell execution)

### Security Headers

```javascript
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
}));
```

---

## ⚙️ Configuration

### Environment Variables

**Project Configuration:**

Copy `docker-compose.env.example` to `.env` in the project root:

```bash
# PostgreSQL
POSTGRES_PASSWORD=change-this-db-password

# Grafana
GRAFANA_PASSWORD=change-this-grafana-password

# Backend JWT
JWT_SECRET=change-this-jwt-secret

# API Keys
API_KEYS=demo-key-12345

# Optional: Demo credentials
DEMO_ADMIN_PASSWORD=change-this-admin-password
DEMO_USER_PASSWORD=change-this-user-password

# Optional: AI integration
OPENAI_API_KEY=
```

### Kubernetes ConfigMap

**Non-sensitive configuration:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: benchmark-saas
data:
  PORT: "4000"
  NODE_ENV: "production"
  DB_HOST: "postgres-service"
  DB_PORT: "5432"
  DB_NAME: "benchmarkdb"
  REDIS_HOST: "redis-service"
  REDIS_PORT: "6379"
  LOG_LEVEL: "info"
  WORKER_CONCURRENCY: "3"
```

### Kubernetes Secrets

**Sensitive configuration:**

```bash
# Create secrets
kubectl create secret generic backend-secrets \
  --from-literal=DB_PASSWORD='secure_password' \
  --from-literal=JWT_SECRET='random_256_bit_string' \
  --from-literal=API_KEYS='prod-key-12345' \
  -n benchmark-saas

# Verify secrets
kubectl get secrets -n benchmark-saas
kubectl describe secret backend-secrets -n benchmark-saas
```

### Load Test Presets

**Customize in frontend:**

```javascript
// frontend/src/components/BenchmarkForm.jsx
const PRESETS = {
  light: { vus: 10, duration: '30s', label: 'Light' },
  medium: { vus: 20, duration: '60s', label: 'Medium' },
  stress: { vus: 50, duration: '120s', label: 'Stress' },
  spike: { vus: 100, duration: '30s', label: 'Spike' },
  soak: { vus: 15, duration: '600s', label: 'Soak' },
};
```

### Database Configuration

**PostgreSQL Tuning:**

```sql
-- Connection pooling
max_connections = 100
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB

-- Performance
random_page_cost = 1.1
effective_io_concurrency = 200
```

**Indexes:**

```sql
CREATE INDEX idx_test_id ON benchmark_results(test_id);
CREATE INDEX idx_timestamp ON benchmark_results(created_at DESC);
CREATE INDEX idx_status ON benchmark_results(status);
CREATE INDEX idx_api_url ON benchmark_results(api_url);
```

---

---

## 🐛 Troubleshooting

### Common Issues

**Issue: Backend fails to connect to PostgreSQL**

```bash
# Check if PostgreSQL is running
docker compose ps postgres

# View PostgreSQL logs
docker compose logs postgres

# Test connection manually
docker compose exec postgres psql -U postgres -d benchmarkdb -c "SELECT 1;"

# Solution: Ensure DB_HOST matches service name in docker-compose.yml
```

**Issue: Worker not processing jobs**

```bash
# Check worker logs
docker compose logs worker

# Verify Redis connection
docker compose exec redis redis-cli PING

# Check queue status
docker compose exec redis redis-cli LLEN bull:benchmark:wait

# Solution: Restart worker service
docker compose restart worker
```

**Issue: Frontend can't reach backend API**

```bash
# Check backend health
curl http://localhost:4000/health

# Verify CORS configuration
# backend/src/index.js should include frontend origin

# Solution: Update CORS_ORIGIN environment variable
```

**Issue: k6 not found in worker**

```bash
# Verify k6 installation in Docker image
docker compose exec worker which k6

# Solution: Rebuild worker image
docker compose build worker
```

**Issue: High memory usage**

```bash
# Check container memory
docker stats

# Analyze Node.js heap
docker compose exec backend node --expose-gc --inspect=0.0.0.0:9229 src/index.js

# Solution: Increase container memory limits or optimize queries
```

### Kubernetes Troubleshooting

**Pod not starting:**

```bash
# Check pod status
kubectl get pods -n benchmark-saas

# View pod events
kubectl describe pod <pod-name> -n benchmark-saas

# Check logs
kubectl logs <pod-name> -n benchmark-saas

# Common causes:
# - Image pull errors (check imagePullSecrets)
# - Resource limits too low
# - Missing ConfigMap or Secret
```

**Service not accessible:**

```bash
# Check service endpoints
kubectl get endpoints -n benchmark-saas

# Test service internally
kubectl run -it --rm debug --image=alpine --restart=Never -n benchmark-saas -- sh
# Inside pod: wget -O- http://backend-service:4000/health

# Check Ingress
kubectl describe ingress -n benchmark-saas
```

**Database connection issues:**

```bash
# Check PostgreSQL pod
kubectl logs -f statefulset/postgres -n benchmark-saas

# Verify secrets
kubectl get secret db-credentials -n benchmark-saas -o yaml

# Test connection from backend pod
kubectl exec -it deployment/backend -n benchmark-saas -- sh
# Inside pod: nc -zv postgres-service 5432
```

### Performance Issues

**Slow API responses:**

1. Check Prometheus metrics for bottlenecks
2. Review Jaeger traces for slow spans
3. Analyze database query performance
4. Check Redis connection pool

**Queue backlog:**

```bash
# Check queue depth
docker compose exec redis redis-cli LLEN bull:benchmark:wait

# Increase worker concurrency
# Edit backend/.env: WORKER_CONCURRENCY=5

# Scale workers in Kubernetes
kubectl scale deployment worker --replicas=5 -n benchmark-saas
```

---

## ⚡ Performance Tuning

### Backend Optimization

**Connection Pooling:**

```javascript
// backend/src/db.js
const pool = new Pool({
  max: 20,              // Maximum connections
  min: 2,               // Minimum connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

**Redis Optimization:**

```javascript
// backend/src/queue.js
const queue = new Queue('benchmark', {
  connection: {
    host: process.env.REDIS_HOST,
    port: process.env.REDIS_PORT,
    maxRetriesPerRequest: 3,
    enableReadyCheck: true,
    enableOfflineQueue: false,
  },
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 2000,
    },
    removeOnComplete: 100,  // Keep last 100 completed jobs
    removeOnFail: 50,       // Keep last 50 failed jobs
  },
});
```

### Database Optimization

**Query Optimization:**

```sql
-- Use EXPLAIN ANALYZE to identify slow queries
EXPLAIN ANALYZE SELECT * FROM benchmark_results WHERE test_id = 'test_123';

-- Add covering indexes
CREATE INDEX idx_test_results ON benchmark_results(test_id, status, created_at);

-- Vacuum regularly
VACUUM ANALYZE benchmark_results;
```

**Connection Pooling:**

```yaml
# k8s/postgres-deployment.yaml
env:
- name: POSTGRES_MAX_CONNECTIONS
  value: "200"
- name: POSTGRES_SHARED_BUFFERS
  value: "256MB"
```

### Kubernetes Scaling

**Horizontal Pod Autoscaler:**

```yaml
# k8s/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**KEDA Queue-Based Scaling:**

```yaml
# k8s/keda-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: worker-scaler
spec:
  scaleTargetRef:
    name: worker
  minReplicaCount: 1
  maxReplicaCount: 20
  triggers:
  - type: redis
    metadata:
      address: redis-service:6379
      listName: bull:benchmark:wait
      listLength: "5"  # Scale up when queue > 5
```

### Load Testing Best Practices

**Gradual Ramp-Up:**

```javascript
// backend/k6/load-test.js
export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp up to 10 VUs
    { duration: '5m', target: 10 },   // Stay at 10 VUs
    { duration: '2m', target: 50 },   // Ramp up to 50 VUs
    { duration: '5m', target: 50 },   // Stay at 50 VUs
    { duration: '2m', target: 0 },    // Ramp down
  ],
};
```

**Resource Limits:**

```yaml
# k8s/backend-deployment.yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

---

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### Development Setup

```bash
# Fork and clone the repository
git clone https://github.com/Suhani-Srikantaswamy/api-benchmarking-saas.git
cd api-benchmarking-saas

# Install dependencies
cd backend && npm install
cd ../frontend && npm install

# Start development environment
docker compose up -d postgres redis
cd backend && npm run dev
cd frontend && npm run dev
```

### Code Style

- **JavaScript:** ESLint + Prettier
- **Commits:** Conventional Commits format
- **Branches:** `feature/`, `bugfix/`, `hotfix/` prefixes

**Example commit:**
```bash
git commit -m "feat(backend): add support for custom k6 scripts"
git commit -m "fix(frontend): resolve SSE reconnection issue"
git commit -m "docs(readme): update deployment instructions"
```

### Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write clean, documented code
   - Add tests for new features
   - Update documentation

3. **Test your changes**
   ```bash
   npm run test
   npm run lint
   ```

4. **Submit PR**
   - Clear description of changes
   - Link related issues
   - Include screenshots for UI changes

5. **Code Review**
   - Address reviewer feedback
   - Ensure CI/CD passes
   - Squash commits if requested

### Testing Guidelines

**Backend Tests:**
```bash
cd backend
npm run test              # Run all tests
npm run test:unit         # Unit tests only
npm run test:integration  # Integration tests
npm run test:coverage     # Coverage report
```

**Frontend Tests:**
```bash
cd frontend
npm run test              # Run all tests
npm run test:watch        # Watch mode
npm run test:coverage     # Coverage report
```

### Documentation

- Update README.md for new features
- Add JSDoc comments for functions
- Update API documentation
- Include examples for new endpoints

---

## 📄 License

This project is licensed under the **MIT License**.

```
MIT License

Copyright (c) 2026 API Benchmarking SaaS

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🙏 Acknowledgments

- **[k6](https://k6.io/)** — Modern load testing tool
- **[BullMQ](https://docs.bullmq.io/)** — Premium queue package for Node.js
- **[Prometheus](https://prometheus.io/)** — Monitoring and alerting toolkit
- **[Grafana](https://grafana.com/)** — Observability platform
- **[Jaeger](https://www.jaegertracing.io/)** — Distributed tracing system
- **[Kubernetes](https://kubernetes.io/)** — Container orchestration
- **[Terraform](https://www.terraform.io/)** — Infrastructure as Code

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/Suhani-Srikantaswamy/api-benchmarking-saas/issues)
- **Discussions:** [GitHub Discussions](https://github.com/Suhani-Srikantaswamy/api-benchmarking-saas/discussions)

---

<div align="center">

**Built with ❤️ for the DevOps community**

⭐ Star this repo if you find it useful!

</div>
