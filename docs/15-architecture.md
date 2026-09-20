# System Architecture

## Overview

Benchly is a **SaaS load testing platform** built as a set of loosely-coupled microservices. Users submit a URL and test parameters through the frontend; the backend queues the job; the worker runs k6 against the target API; results are persisted, analysed, and streamed back to the UI in real time.

## Service map

```
                        ┌─────────────────────────────────────────────────────┐
                        │                 Browser / User                       │
                        └─────────────────────┬───────────────────────────────┘
                                              │ HTTP + SSE
                        ┌─────────────────────▼───────────────────────────────┐
                        │            Frontend (React + Vite)                   │
                        │              nginx · port 3000/8080                  │
                        └──────────────────┬──────────────────────────────────┘
                                           │ REST API + SSE
                        ┌──────────────────▼──────────────────────────────────┐
                        │          Backend API (Express.js)                    │
                        │     /auth  /api/benchmark  /api/events  /metrics     │
                        │                port 4000                             │
                        └───┬──────────────┬──────────────┬────────────────────┘
                            │ enqueue      │ persist      │ OTel spans
               ┌────────────▼───┐    ┌────▼────┐   ┌────▼─────────┐
               │   Redis 7      │    │Postgres │   │  Jaeger       │
               │  BullMQ queue  │    │   15    │   │  port 16686   │
               │   port 6379    │    │port 5432│   └──────────────┘
               └────────┬───────┘    └────▲────┘
                        │ dequeue         │ save results
               ┌────────▼────────────────┴───────────────────────────────────┐
               │              Worker (Node.js — worker.js)                    │
               │         BullMQ consumer · concurrency 3                      │
               └────────────────┬────────────────────┬────────────────────────┘
                                │ execFile k6         │ POST /analyse
               ┌────────────────▼───────┐    ┌────────▼──────────────────────┐
               │   k6 subprocess        │    │  Analytics (FastAPI + Pandas)  │
               │   load-test.js         │    │  diagnosis + HPA reco          │
               │   writes /tmp JSON     │    │  port 8001                     │
               └────────────────────────┘    └────────────────────────────────┘

Monitoring (all services emit metrics to Prometheus):
  Backend ──────────────────────────────────────────┐
  Analytics ────────────────────────────────────────┤
                                              ┌─────▼──────────────┐
                                              │  Prometheus         │
                                              │   port 9090         │
                                              └──┬──────────────────┘
                                                 │ alerts
                                          ┌──────▼──────────────┐
                                          │  Alertmanager        │
                                          │   port 9093          │
                                          └─────────────────────┘
                                                 │ data source
                                          ┌──────▼──────────────┐
                                          │     Grafana          │
                                          │   port 3001          │
                                          └─────────────────────┘
```

## Data flow — submitting a benchmark

```
1. User fills BenchmarkForm and clicks "Run Load Test"
2. Frontend → POST /api/benchmark/run { apiUrl, vus, duration, headers, method }
3. Backend authenticates request (JWT or API key)
4. Backend validates input (express-validator)
5. Backend → db.createPendingBenchmark(testId) → Postgres
6. Backend → enqueueLoadTest(job) → Redis (BullMQ)
7. Backend → returns 202 { testId, status: 'pending' }
8. Frontend opens EventSource /api/events/:testId (SSE)

9. Worker dequeues job from Redis
10. Worker → db.updateBenchmarkStatus(testId, 'running') → Postgres
11. Worker → execFile('k6', [...], env) — k6 hits the target API
12. k6 writes results to /tmp/k6-result-<testId>.json
13. Worker parses JSON output → metrics object
14. Worker → db.saveBenchmark({ ...metrics, status: 'completed' }) → Postgres
15. Worker → notifyClients(testId, metrics) → SSE push to frontend

16. Worker → POST analytics:8001/analyse { ...metrics } [async]
17. Analytics normalises payload, runs Pandas analysis, returns diagnosis + HPA
18. Worker → db.saveBenchmark({ nl_analysis }) → Postgres
19. Worker → notifyClients(testId, { ...metrics, analysis }) → SSE push

20. Frontend receives SSE event → updates Dashboard with live results
21. User sees avg/p95/p99 response times, RPS, error rate, and AI diagnosis
```

## Data flow — viewing history

```
1. User clicks "History" tab
2. Frontend → GET /api/benchmark (with X-API-Key header)
3. Backend → db.getAllBenchmarks(50) → SELECT * FROM benchmark_results ORDER BY created_at DESC
4. Backend returns JSON array
5. Frontend renders table with all past runs
```

## Port reference

| Service | Host Port | Container Port | Protocol |
|---------|-----------|----------------|----------|
| Frontend (nginx) | 3000 | 8080 | HTTP |
| Backend API | 4000 | 4000 | HTTP |
| Analytics | 8001 | 8001 | HTTP |
| Prometheus | 9090 | 9090 | HTTP |
| Grafana | 3001 | 3000 | HTTP |
| Alertmanager | 9093 | 9093 | HTTP |
| Jaeger UI | 16686 | 16686 | HTTP |
| Jaeger OTLP HTTP | 4318 | 4318 | HTTP |
| Jaeger OTLP gRPC | 4317 | 4317 | gRPC |
| Postgres | 5432 | 5432 | TCP |
| Redis | 6379 | 6379 | TCP |

## Network

All services communicate over the `benchmark-network` Docker bridge network (service name = hostname). In Kubernetes, services are addressed by their `ClusterIP` service name within the `benchmark` namespace.

## Technology choices

| Decision | Choice | Why |
|----------|--------|-----|
| Frontend | React + Vite | Fast dev experience, Recharts for data viz |
| Backend | Express.js | Lightweight, well-understood, rich ecosystem |
| Job queue | BullMQ + Redis | Reliable, retries, concurrency control |
| Load engine | k6 | Scriptable, low overhead, good k8s integration |
| Analysis | FastAPI + Pandas | Python data science ecosystem for metrics analysis |
| Database | PostgreSQL | ACID, good for structured result history |
| Observability | Prometheus + Grafana | Industry standard, integrates with k6 and OTel |
| Tracing | OpenTelemetry + Jaeger | Vendor-neutral, auto-instruments Node.js libs |
| Container orchestration | Kubernetes + Helm | Production-grade scaling, HPA support |
| IaC | Terraform | Declarative, reproducible, supports both local and cloud |
| CI/CD | GitHub Actions | Integrated with repo, matrix jobs, secret management |
