# Benchly

API performance benchmarking platform. Submit any HTTP endpoint, run k6 load tests on demand, and get back structured latency, throughput, and error-rate data with automated analysis.

[![CI](https://github.com/zeofr/Benchly/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/zeofr/Benchly/actions/workflows/ci-cd.yml)

---

## Overview

Benchly runs k6 load tests against any HTTP/HTTPS endpoint and surfaces the results through a React dashboard. Tests are queued via BullMQ so the API stays responsive under concurrent requests. A FastAPI analytics service processes each run with Pandas, flags bottlenecks, and recommends replica counts. The full stack ships with Prometheus, Grafana, and Jaeger, and deploys to Kubernetes with HPA configured for CPU-based autoscaling.

**Stack**

| Layer | Technology |
|---|---|
| API | Node.js, Express |
| Analytics | Python, FastAPI, Pandas |
| Queue | Redis, BullMQ |
| Load testing | k6 |
| Database | PostgreSQL 15 |
| Frontend | React 18, Recharts |
| Observability | Prometheus, Grafana, Jaeger |
| Orchestration | Kubernetes, HPA |
| IaC | Terraform (Kubernetes provider, EKS reference) |
| CI/CD | GitHub Actions, Trivy |

---

## Running locally

**Prerequisites:** Docker, Docker Compose

```bash
cp docker-compose.env.example .env
# set passwords in .env

docker compose up -d
```

| Service | URL | Auth |
|---|---|---|
| Frontend | http://localhost:3000 | — |
| Backend API | http://localhost:4000 | `X-API-Key: demo-key-12345` |
| Analytics API | http://localhost:8001/docs | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3001 | `admin` / see `.env` |
| Jaeger | http://localhost:16686 | — |

---

## Kubernetes (Minikube)

```bash
# Build images inside Minikube and deploy the full stack
chmod +x scripts/k8s-setup.sh && ./scripts/k8s-setup.sh

# Run the HPA scaling demo
./scripts/k8s-demo.sh
```

Windows:
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\k8s-setup.ps1
```

See [KUBERNETES_DEMO.md](./KUBERNETES_DEMO.md) for the full walkthrough including HPA verification, Prometheus queries, and Grafana dashboard usage.

---

## API

**Run a test**
```bash
curl -X POST http://localhost:4000/api/benchmark/run \
  -H "X-API-Key: demo-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"apiUrl": "https://httpbin.org/get", "vus": 10, "duration": "30s"}'
```

**Check result**
```bash
curl http://localhost:4000/api/benchmark/{testId} \
  -H "X-API-Key: demo-key-12345"
```

**Get analysis from the analytics service directly**
```bash
curl -X POST http://localhost:8001/analyse \
  -H "Content-Type: application/json" \
  -d '{"avg_response_time": 120, "p95_latency_ms": 340, "requests_per_sec": 85, "error_rate_pct": 0.5}'
```

---

## Architecture

```
Browser
  └── React frontend (nginx:8080)
        └── Express API (:4000)
              ├── BullMQ → Redis → Worker → k6
              │                        └── FastAPI analytics (:8001)
              ├── PostgreSQL (:5432)
              └── /metrics → Prometheus → Grafana
```

**Key decisions**

- Worker runs k6 as a subprocess, isolated from the API process so load tests don't block request handling
- FastAPI handles the analytics workload where Python/Pandas is the natural fit; Express calls it over HTTP after each test
- SSE rather than WebSockets for real-time updates — simpler, stateless, works over HTTP/1.1
- HPA scales backend pods on CPU; the analytics service is stateless and scales independently

---

## CI/CD

Every push runs: lint → unit tests → Docker builds → Trivy CVE scan → k8s manifest validation → integration test with k6.

Deployment to a live Kubernetes cluster requires `KUBE_CONFIG` in GitHub secrets. The pipeline currently deploys via `docker compose up` on the CI runner. See `.github/workflows/ci-cd.yml` for the full job graph.

Optional secrets for Docker Hub publishing:

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Image registry |
| `DOCKERHUB_TOKEN` | Registry auth |
| `POSTGRES_PASSWORD` | DB password |
| `JWT_SECRET` | Token signing |

---

## Project structure

```
Benchly/
├── backend/          Express API, BullMQ worker, k6 scripts
├── frontend/         React dashboard
├── analytics/        FastAPI analytics service (Pandas)
├── k8s/              Kubernetes manifests
├── terraform/        IaC — Minikube provider + EKS reference
├── monitoring/       Prometheus config, Grafana dashboards, AlertManager
├── scripts/          Setup and demo scripts
└── .github/          CI/CD workflows
```

---

## License

MIT
