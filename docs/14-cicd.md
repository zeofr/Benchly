# CI/CD Pipeline

## Overview

The GitHub Actions pipeline is defined in `.github/workflows/ci-cd.yml`. It runs on every push to `main`/`develop` and on pull requests targeting `main`. The pipeline has three stages: **CI** (lint + test + build + scan), **Integration** (live API + k6), and **CD** (deploy + push images).

## Triggers

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
```

Concurrent runs on the same branch are automatically cancelled:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Stage 1 — Continuous Integration

### Job 1: `lint-backend`
- Installs backend Node.js dependencies (`npm ci`)
- Runs ESLint on `src/`
- Syntax-checks all `.js` files with `node --check`

### Job 2: `lint-frontend`
- Installs frontend dependencies
- Runs ESLint on `src/`

### Job 3: `test-backend`
- Depends on `lint-backend`
- Runs Jest with coverage (`npm run test:ci`)
- Uploads coverage report as artifact (7-day retention)
- Coverage threshold: 30% lines (see `package.json` Jest config)

### Job 4: `test-frontend`
- Depends on `lint-frontend`
- Runs Vitest (`npm run test:ci`)

### Job 5: `security-scan`
- Runs `npm audit --audit-level=critical` for both backend and frontend (continue-on-error for non-critical)
- Secret detection: greps for GitHub token, OpenAI key, AWS key patterns in source
- Exits `1` if real-looking secrets are found

### Job 6: `build-frontend`
- Depends on `test-frontend`
- Builds Vite production bundle
- Uploads `frontend/dist/` as artifact

### Job 7: `build-backend-image`
- Depends on `test-backend`
- Builds Docker image with k6 installed (`INSTALL_K6=true`)
- Runs **Trivy** vulnerability scan (CRITICAL severity, continue-on-error)
- Saves image as `.tar.gz` artifact

### Job 7b: `build-analytics-image`
- Builds Python FastAPI Docker image
- Runs Trivy scan

### Job 8: `build-frontend-image`
- Depends on `build-frontend`
- Downloads `frontend/dist/` artifact
- Builds Docker image
- Runs Trivy scan
- Saves image as `.tar.gz` artifact

## Stage 2 — Integration Tests

Runs only on `push` events (not PRs).

### Job 9: `integration-test`
- Depends on all build + security jobs
- Spins up **Postgres** and **Redis** as GitHub Actions service containers
- Starts the backend Node.js server in background
- Waits up to 60s for `/health` to return 200
- **API health checks:**
  - `/health` must return 200
  - `/metrics` must return Prometheus text
  - `/api/benchmark` without auth must return 401
  - `/api/benchmark` with `X-API-Key: demo-key-12345` must return 200
- Installs k6 v0.49.0
- Runs `ci-load-test.js` against the live backend
- Uploads k6 results JSON as artifact

### Job 9a: `validate-k8s`
- Runs on every push/PR
- Installs kubectl v1.29.0
- `kubectl apply --dry-run=client` on every file in `k8s/`
- Checks for unresolved placeholder values (`YOUR_DOCKERHUB_USERNAME`, `REPLACE_WITH_BASE64_VALUE`)

### Job 9b: `pr-analytics`
- Runs only on pull requests
- Starts backend + Redis
- Runs k6 quick load test
- Runs `analytics/ingest_k6.py` to process results
- Runs `analytics/check_regression.py` against `analytics/baseline.json`
- Fails the PR if regression is detected

## Stage 3 — Continuous Deployment

Runs only on push to `main`.

### Job 10: `deploy`
- Depends on `integration-test`
- Loads backend + frontend Docker images from artifacts
- Tags as `latest`
- Creates `.env` from GitHub secrets (`POSTGRES_PASSWORD`, `JWT_SECRET`, etc.)
- Runs `docker compose up -d`
- Polls `/health` every 5s for 2 minutes — rolls back (`docker compose down`) if never healthy
- Prints deployment summary (commit SHA, branch, actor, timestamp)

### Job 11: `push-images`
- Depends on `integration-test`
- Skipped gracefully if `DOCKERHUB_USERNAME` secret is not set
- Loads images, logs in to Docker Hub, tags with SHA and `latest`, pushes both tags

## Required GitHub Secrets

| Secret | Used by | Description |
|--------|---------|-------------|
| `POSTGRES_PASSWORD` | deploy | Database password in deployment |
| `JWT_SECRET` | deploy | JWT signing secret in deployment |
| `API_KEYS` | deploy | Comma-separated API keys |
| `GRAFANA_PASSWORD` | deploy | Grafana admin password |
| `DOCKERHUB_USERNAME` | push-images | Docker Hub username (optional) |
| `DOCKERHUB_TOKEN` | push-images | Docker Hub access token (optional) |

## Artifacts produced

| Artifact | Produced by | Retention |
|----------|-------------|-----------|
| `backend-coverage` | test-backend | 7 days |
| `frontend-dist` | build-frontend | 1 day |
| `backend-image` | build-backend-image | 1 day |
| `frontend-image` | build-frontend-image | 1 day |
| `k6-load-test-results` | integration-test | 7 days |

## Pipeline diagram

```
push/PR
  │
  ├── lint-backend ──────────────────────────── test-backend ───┐
  │                                                              ├── build-backend-image ──┐
  ├── lint-frontend ─────────────────────────── test-frontend ──┴── build-frontend ────── build-frontend-image ──┐
  │                                                                                                               │
  ├── security-scan ──────────────────────────────────────────────────────────────────────────────────────────────┤
  │                                                                                                               │
  │                             ┌──────────── integration-test (push only) ◄──────────────────────────────────────┘
  │                             │
  └── validate-k8s (always)    ├── deploy (main only)
                                └── push-images (main + DockerHub secret)
```

## Terraform pipeline (`.github/workflows/terraform.yml`)

A separate workflow handles Terraform plan/apply on infrastructure changes:
- `terraform plan` on PRs that modify `terraform/`
- `terraform apply` on merge to `main` (with explicit approval gate via GitHub environment)
