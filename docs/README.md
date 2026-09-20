# Benchly — Documentation Index

Welcome to the Benchly docs folder. Each file covers one service or layer in detail.

| File | What it covers |
|------|----------------|
| [01-frontend.md](./01-frontend.md) | React SPA — UI, components, API client |
| [02-backend.md](./02-backend.md) | Express.js API — routes, auth, queue, tracing |
| [03-worker.md](./03-worker.md) | BullMQ worker — k6 execution and result parsing |
| [04-analytics.md](./04-analytics.md) | FastAPI + Pandas — diagnosis and HPA recommendation |
| [05-postgres.md](./05-postgres.md) | PostgreSQL — schema, queries, connection pool |
| [06-redis.md](./06-redis.md) | Redis — queue persistence, BullMQ config |
| [07-prometheus.md](./07-prometheus.md) | Prometheus — scrape config, alert rules |
| [08-grafana.md](./08-grafana.md) | Grafana — dashboards and provisioning |
| [09-alertmanager.md](./09-alertmanager.md) | Alertmanager — routing and notification config |
| [10-jaeger.md](./10-jaeger.md) | Jaeger — distributed tracing, OpenTelemetry |
| [11-k6-scripts.md](./11-k6-scripts.md) | k6 load test scripts — smoke, load, spike, CI |
| [12-kubernetes.md](./12-kubernetes.md) | Kubernetes manifests — deployments, HPA, ingress |
| [13-terraform.md](./13-terraform.md) | Terraform — local Minikube & AWS EKS config |
| [14-cicd.md](./14-cicd.md) | GitHub Actions CI/CD — pipeline stages and jobs |
| [15-architecture.md](./15-architecture.md) | System architecture — data flow and service map |

## Quick start

```bash
# Start the entire stack locally
docker compose up -d

# URLs
Frontend   → http://localhost:3000
Backend    → http://localhost:4000
Grafana    → http://localhost:3001   (admin / admin)
Prometheus → http://localhost:9090
Jaeger     → http://localhost:16686
Analytics  → http://localhost:8001
```

## Default credentials

| Service | Username | Password |
|---------|----------|----------|
| Benchly app | admin | admin123 |
| Benchly app | demo | demo123 |
| Grafana | admin | admin |
